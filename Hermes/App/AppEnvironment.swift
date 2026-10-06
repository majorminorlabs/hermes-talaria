import SwiftUI

/// Composition root. Owns the client, the stores and the single app-wide
/// event subscription that keeps every store current.
@Observable
final class AppEnvironment {
    let client: HermesClient
    /// Present only when running against the simulator; drives Settings › Simulation.
    let simulator: MockHermesBackend?
    let preferences: AppPreferences
    let router = AppRouter()
    let toasts = ToastCenter()
    let cache: SnapshotCache
    let drafts: DraftStore

    let connection: ConnectionStore
    let home: HomeStore
    let activity: ActivityStore
    let conversations: ConversationListStore
    let profiles: ProfileStore
    let tasks: TaskStore
    let routines: RoutineStore
    let work: WorkItemStore
    let needsYou: NeedsYouStore
    let seen: SeenStore
    let snoozes: SnoozeStore
    let outbox: OutboxStore
    let voice = VoiceSession()
    let agentModels: AgentModelStore

    var isInBackground = false

    @ObservationIgnored private let notifier: any NotificationService
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var lastCursor: EventCursor?
    @ObservationIgnored private var streamEnded = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var subscriptionID = UUID()

    init(client: HermesClient, simulator: MockHermesBackend?, preferences: AppPreferences, cache: SnapshotCache,
         savedHosts: SavedHostStore, drafts: DraftStore, notifier: any NotificationService, defaultHosts: [Host]) {
        self.client = client
        self.simulator = simulator
        self.preferences = preferences
        self.cache = cache
        self.drafts = drafts
        self.notifier = notifier
        agentModels = AgentModelStore(defaults: preferences.defaults)
        let queueBase = cache.queueDirectory
        outbox = OutboxStore(directory: queueBase)
        connection = ConnectionStore(client: client, savedHosts: savedHosts, cache: cache, defaultHosts: defaultHosts)
        home = HomeStore(client: client, cache: cache)
        activity = ActivityStore(client: client, cache: cache)
        conversations = ConversationListStore(client: client, cache: cache)
        profiles = ProfileStore(client: client, cache: cache)
        tasks = TaskStore(client: client, cache: cache)
        routines = RoutineStore(client: client, cache: cache)
        seen = SeenStore(defaults: preferences.defaults)
        snoozes = SnoozeStore(defaults: preferences.defaults)
        needsYou = NeedsYouStore(activity: activity, tasks: tasks, home: home, routines: routines, connection: connection, snoozes: snoozes, outbox: outbox)
        work = WorkItemStore(conversations: conversations, activity: activity, tasks: tasks, needs: needsYou, seen: seen, connection: connection)
        lastCursor = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value.cursor ?? cache.load(EventCursor.self, key: .eventCursor)?.value
        if simulator == nil {
            connection.onHostSwitch = { [weak self] in
                guard let self else { return }
                eventTask?.cancel()
                cache.scope(to: connection.activeHostID)
                home.restoreScopedCache(); activity.restoreScopedCache(); conversations.restoreScopedCache()
                profiles.restoreScopedCache(); tasks.restoreScopedCache(); routines.restoreScopedCache()
                lastCursor = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value.cursor
                startEventLoop()
            }
        }
    }

    /// Where a mock environment keeps local state.
    enum MockStorage {
        /// The app's real preferences and caches.
        case standard
        /// Throwaway storage (previews).
        case ephemeral
        /// A named sandbox that survives relaunches (UI tests exercising cached state).
        case named(String, reset: Bool)
    }

    /// The app wired to the in-memory simulator.
    static func mock(fixtures: MockFixtures = .standard(), storage: MockStorage = .standard) -> AppEnvironment {
        let backend = MockHermesBackend(fixtures: fixtures)
        let defaults: UserDefaults
        let cacheDirectory: URL?
        switch storage {
        case .standard:
            defaults = .standard
            cacheDirectory = nil
        case .ephemeral:
            defaults = UserDefaults(suiteName: "preview-\(UUID().uuidString)")!
            cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        case .named(let name, let reset):
            if reset { UserDefaults().removePersistentDomain(forName: name) }
            defaults = UserDefaults(suiteName: name)!
            cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            if reset { try? FileManager.default.removeItem(at: cacheDirectory!) }
        }
        return AppEnvironment(
            client: .mock(backend), simulator: backend, preferences: AppPreferences(defaults: defaults),
            cache: SnapshotCache(directory: cacheDirectory), savedHosts: SavedHostStore(defaults: defaults),
            drafts: DraftStore(defaults: defaults), notifier: LocalNotificationService(),
            defaultHosts: fixtures.hosts)
    }

    static func live() -> AppEnvironment {
        let saved = SavedHostStore()
        let client = BridgeHermesClient()
        let hostID = saved.activeHostID ?? saved.load().first?.id ?? "unpaired"
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BridgeCache", isDirectory: true)
        let cache = SnapshotCache(directory: base); cache.scope(to: hostID)
        return AppEnvironment(client: client.client, simulator: nil, preferences: AppPreferences(),
            cache: cache, savedHosts: saved, drafts: DraftStore(),
            notifier: LocalNotificationService(), defaultHosts: [])
    }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        applySimulationLaunchArguments()
        simulator?.startSimulation()
        startEventLoop()
        await connection.connect()
    }

    /// `-simulate bridgeOffline|hermesOffline|authRequired|reconnecting` and
    /// `-emptyData` put the simulator into a state at launch (UI tests, QA).
    private func applySimulationLaunchArguments() {
        guard let simulator else { return }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "emptyData") { simulator.simulation.emptyData = true }
        let speed = defaults.double(forKey: "runSpeed")
        if speed > 0 { simulator.simulation.runSpeed = speed }
        switch defaults.string(forKey: "simulate") {
        case "bridgeOffline": simulator.forcedConnection = .bridgeOffline
        case "hermesOffline": simulator.forcedConnection = .hermesOffline
        case "authRequired": simulator.forcedConnection = .authenticationRequired
        case "reconnecting": simulator.forcedConnection = .reconnecting(attempt: 2)
        default: break
        }
    }

    func refreshAll() async {
        async let home: Void = home.refresh()
        async let activity: Void = activity.refresh()
        async let conversations: Void = conversations.refresh()
        async let profiles: Void = refreshIfSupported(.profiles) { await self.profiles.refresh() }
        async let tasks: Void = refreshIfSupported(.kanban) { await self.tasks.refresh() }
        async let routines: Void = refreshIfSupported(.cron) { await self.routines.refresh() }
        _ = await (home, activity, conversations, profiles, tasks, routines)
        work.seedSeen()
        await outbox.syncCaptures(environment: self)
    }

    private func refreshIfSupported(_ capability: HermesCapability, _ refresh: () async -> Void) async {
        if connection.supports(capability) { await refresh() }
    }

    // MARK: Events

    private func startEventLoop() {
        eventTask?.cancel()
        let subscription = UUID(); subscriptionID = subscription
        let expectedHost = connection.activeHostID
        let stream = client.events.subscribe(after: lastCursor)
        eventTask = Task {
            for await envelope in stream {
                await self.handle(envelope, expectedHostID: expectedHost, subscription: subscription)
            }
            // The transport dropped. Resubscribe from `lastCursor` once the
            // bridge is reachable again so missed events are replayed.
            self.streamEnded = true
        }
    }

    /// Applies an entire source event and durably commits state BEFORE advancing
    /// the network cursor. Synthetic host/action updates have no new cursor.
    func handle(_ envelope: HermesEventEnvelope, expectedHostID: String? = nil, subscription: UUID? = nil) async {
        let expectedHost = expectedHostID ?? connection.activeHostID
        func isCurrent() -> Bool { !Task.isCancelled && expectedHost == connection.activeHostID && (subscription == nil || subscription == subscriptionID) }
        guard isCurrent() else { return }
        if case .resyncRequired = envelope.event {
            repeat {
                if !isCurrent() { return }
                await refreshAll()
                guard isCurrent() else { return }
                if home.phase == .loaded && activity.phase == .loaded && conversations.phase == .loaded { break }
                try? await Task.sleep(for: .seconds(2))
            } while !Task.isCancelled
            for id in conversations.transcripts.keys { try? await conversations.loadTranscript(id) }
        } else {
            applyEvent(envelope.event)
        }
        guard isCurrent(), !envelope.cursor.value.isEmpty else { return }
        // Simulation retains its original independent fixture caches. Its early
        // synthetic events are not canonical bridge snapshot checkpoints.
        if client.events is MockHermesBackend {
            lastCursor = envelope.cursor
            cache.save(envelope.cursor, key: .eventCursor)
            await client.events.acknowledge(envelope.cursor)
            return
        }
        let state = AppliedBridgeState(cursor: envelope.cursor, hostID: connection.activeHostID,
            home: home.summary, runs: activity.activeRuns + Array(activity.finishedRuns.prefix(60)), approvals: Array(activity.approvals.values),
            conversations: Array(conversations.sorted.prefix(100)), transcripts: checkpointTranscripts,
            profiles: profiles.sorted, tasks: Array(tasks.tasks.values), routines: routines.sorted)
        do {
            try cache.commit(state)
            lastCursor = envelope.cursor
            cache.save(envelope.cursor, key: .eventCursor)
            await client.events.acknowledge(envelope.cursor)
        } catch {
            toasts.show("Could not save replay state. Free device storage before reconnecting.", symbol: "exclamationmark.triangle")
            eventTask?.cancel()
        }
    }

    private var checkpointTranscripts: [String:[Message]] {
        let activeIDs = activity.activeRuns.compactMap(\.conversationID)
        let ids = Set(activeIDs + conversations.sorted.prefix(12).map(\.id))
        return conversations.transcripts.filter { ids.contains($0.key) }
    }

    private func applyEvent(_ event: HermesEvent) {
        if case .batch(let events) = event { for item in events { applyEvent(item) }; return }
        let wasConnected = connection.connection.isConnected
        notifyIfNeeded(event)
        connection.apply(event); home.apply(event); activity.apply(event); conversations.apply(event)
        profiles.apply(event); tasks.apply(event); routines.apply(event)
        if case .hostStatus(let status) = event, status.hostID == connection.activeHostID,
           !wasConnected && status.connection.isConnected {
            Task { await refreshAll(); await connection.loadRunOptions() }
        }
    }

    // MARK: Notifications

    private func notifyIfNeeded(_ event: HermesEvent) {
        guard isInBackground, preferences.notificationsEnabled else { return }
        let notification: HermesNotification?
        switch event {
        case .runUpserted(let run):
            notification = NotificationPolicy.notification(
                previous: activity.run(run.id), current: run, profileName: profiles.profile(run.profileID)?.name,
                routineName: routines.routine(run.routineID)?.name)
        case .approvalUpserted(let approval) where activity.approval(approval.id) == nil:
            notification = .approvalRequired(approval, profileName: profiles.profile(approval.profileID)?.name)
        case .taskUpserted(let task):
            notification = NotificationPolicy.notification(previous: tasks.task(task.id), current: task)
        default:
            notification = nil
        }
        if let notification, preferences.isEnabled(notification.category) {
            notifier.deliver(notification)
        }
    }

    func requestNotificationPermission() async -> Bool {
        await notifier.requestAuthorization()
    }

    // MARK: Factories

    func makeConversationModel(conversationID: String?, profileID: String?) -> ConversationModel {
        ConversationModel(conversationID: conversationID, profileID: profileID, list: conversations, activity: activity,
                          connection: connection, drafts: drafts, preferences: preferences)
    }

    /// Clears cached snapshots and local acknowledgements.
    func clearLocalCache() {
        cache.clear()
        preferences.resetLocalState()
    }
}
