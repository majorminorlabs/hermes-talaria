import Foundation

/// Hermes profiles (shown as "bots").
@Observable
final class ProfileStore {
    private let client: HermesClient
    private let cache: SnapshotCache
    private var refreshGeneration = UUID()

    private(set) var profiles: [String: Profile] = [:]
    private(set) var phase: LoadPhase = .idle

    init(client: HermesClient, cache: SnapshotCache) {
        self.client = client
        self.cache = cache
        if let snapshot = cache.load([Profile].self, key: .profiles) {
            profiles = Dictionary(snapshot.value.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        }
        if let state = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value {
            profiles = Dictionary(state.profiles.map { ($0.id,$0) }, uniquingKeysWith: { $1 })
        }

    }

    func restoreScopedCache() {
        refreshGeneration = UUID()
        let state = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value
        let rows = state?.profiles ?? cache.load([Profile].self, key: .profiles)?.value ?? []
        profiles = Dictionary(rows.map { ($0.id,$0) }, uniquingKeysWith: { $1 })
        phase = .idle
    }

    var sorted: [Profile] {
        profiles.values.sorted { ($0.isDefault ? 0 : 1, $0.name) < ($1.isDefault ? 0 : 1, $1.name) }
    }

    /// Non-default profiles, presented as bots.
    var bots: [Profile] { sorted.filter { $0.isBotMode == true || !$0.isDefault } }

    func profile(_ id: String?) -> Profile? { id.flatMap { profiles[$0] } }

    /// Who to show for a session or run. Sessions on the default Hermes
    /// profile resolve to the default bot in Bot Mode (whose IDs are opaque),
    /// so they wear its face instead of a generic monogram. Presentation only.
    func identity(_ id: String?) -> Profile? {
        if let exact = profile(id) { return exact }
        if let id { let native = profiles.values.filter { $0.profileKey == id }; if native.count == 1 { return native.first } }
        guard id == nil || id == Profile.defaultID else { return nil }
        return profiles.values.first { $0.isDefault }
    }

    func name(_ id: String?) -> String { identity(id)?.name ?? "Hermes" }

    private var avatarAttempts = Set<String>()

    /// Fetches detail once per session for bots whose Studio avatar (the
    /// Desktop face) isn't loaded yet; `refresh` then keeps it. Uses the
    /// existing bot detail read; no new bridge surface.
    func loadMissingAvatars() async {
        let missing = profiles.values.filter {
            $0.isBotMode == true && $0.hasAvatar == true && $0.avatarData == nil && !avatarAttempts.contains($0.id)
        }
        guard !missing.isEmpty else { return }
        // The audited detail read also loads profile-scoped metadata on Hermes.
        // Avoid a roster-sized burst competing with interactive bot operations.
        for bot in missing.sorted(by: { $0.name < $1.name }) {
            guard !Task.isCancelled else { break }
            avatarAttempts.insert(bot.id)
            await loadProfile(bot.id)
            if Task.isCancelled {
                avatarAttempts.remove(bot.id)
                break
            }
        }
        cache.save(sorted, key: .profiles)
    }

    func refresh() async {
        let generation = UUID(); refreshGeneration = generation
        phase = .loading
        do {
            let list = try await client.profiles.listProfiles().map { summary in
                guard summary.isBotMode == true, let detail = profiles[summary.id] else { return summary }
                var value = summary
                value.skillIDs = detail.skillIDs; value.toolsets = detail.toolsets; value.mcpServerIDs = detail.mcpServerIDs
                value.soulSummary = detail.soulSummary; value.memorySummary = detail.memorySummary
                value.soul = detail.soul; value.editableFields = detail.editableFields
                value.avatarData = detail.avatarData; value.routinesMetadata = detail.routinesMetadata; value.pluginsMetadata = detail.pluginsMetadata
                return value
            }
            guard generation == refreshGeneration else { return }
            profiles = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            phase = .loaded
            cache.save(list, key: .profiles)
        } catch {
            guard generation == refreshGeneration else { return }
            if let error = HermesError.from(error) { phase = .failed(error) }
        }
    }

    func apply(_ event: HermesEvent) {
        if case .profileUpserted(let profile) = event { profiles[profile.id] = profile }
    }

    func loadProfile(_ id: String) async {
        do { profiles[id] = try await client.profiles.profile(id: id) }
        catch HermesError.notFound { profiles[id] = nil }
        catch { /* Preserve last observed detail during a transient disconnect. */ }
    }

    func create(_ draft: BotDraft) async throws -> Profile {
        let bot = try await client.profiles.createBot(draft)
        // Creation already returns Hermes's confirmed detail. Preserve it if
        // the subsequent roster/detail refresh is unavailable or incomplete.
        profiles[bot.id] = bot
        await refresh(); await loadProfile(bot.id)
        return profiles[bot.id] ?? bot
    }
    func duplicate(_ id: String) async throws {
        _ = try await client.profiles.duplicateBot(id:id); await refresh()
    }
    func hide(_ id: String) async throws {
        try await client.profiles.hideBot(id: id); await refresh()
    }
    func update(_ id: String, changes: ProfileChanges) async throws {
        let updated = try await client.profiles.updateProfile(id: id, changes: changes)
        profiles[updated.id] = updated
        await refresh(); await loadProfile(updated.id)
    }
}

/// Kanban tasks.
@Observable
final class TaskStore {
    private let client: HermesClient
    private let cache: SnapshotCache

    private(set) var tasks: [String: HermesTask] = [:]
    private(set) var phase: LoadPhase = .idle

    init(client: HermesClient, cache: SnapshotCache) {
        self.client = client
        self.cache = cache
        if let snapshot = cache.load([HermesTask].self, key: .tasks) {
            tasks = Dictionary(snapshot.value.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        }
        if let state = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value {
            tasks = Dictionary(state.tasks.map { ($0.id,$0) }, uniquingKeysWith: { $1 })
        }

    }

    func restoreScopedCache() {
        let state = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value
        let rows = state?.tasks ?? cache.load([HermesTask].self, key: .tasks)?.value ?? []
        tasks = Dictionary(rows.map { ($0.id,$0) }, uniquingKeysWith: { $1 })
        phase = .idle
    }

    func task(_ id: String?) -> HermesTask? { id.flatMap { tasks[$0] } }

    /// Tasks for a board column, highest priority and most recent first.
    func tasks(in column: TaskStatus) -> [HermesTask] {
        tasks.values
            .filter { $0.status.boardColumn == column }
            .sorted { ($0.priority, $0.updatedAt) > ($1.priority, $1.updatedAt) }
    }

    func tasks(forProfile id: String) -> [HermesTask] {
        tasks.values.filter { $0.assigneeProfileID == id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func refresh() async {
        phase = .loading
        do {
            let list = try await client.tasks.listTasks()
            tasks = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            phase = .loaded
            cache.save(list, key: .tasks)
        } catch {
            if let error = HermesError.from(error) { phase = .failed(error) }
        }
    }

    func apply(_ event: HermesEvent) {
        if case .taskUpserted(let task) = event { tasks[task.id] = task }
    }

    @discardableResult
    func create(_ draft: TaskDraft) async throws -> HermesTask {
        let task = try await client.tasks.createTask(draft)
        tasks[task.id] = task
        return task
    }

    func setStatus(_ status: TaskStatus, for id: String) async throws {
        try await client.tasks.setStatus(status, taskID: id)
    }

    func start(_ id: String) async throws {
        try await client.tasks.startTask(id: id)
    }
}

/// Scheduled routines (cron).
@Observable
final class RoutineStore {
    private let client: HermesClient
    private let cache: SnapshotCache

    private(set) var routines: [String: Routine] = [:]
    private(set) var phase: LoadPhase = .idle

    init(client: HermesClient, cache: SnapshotCache) {
        self.client = client
        self.cache = cache
        if let snapshot = cache.load([Routine].self, key: .routines) {
            routines = Dictionary(snapshot.value.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        }
        if let state = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value {
            routines = Dictionary(state.routines.map { ($0.id,$0) }, uniquingKeysWith: { $1 })
        }

    }

    /// Enabled routines by next run, then paused ones.
    func restoreScopedCache() {
        let state = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value
        let rows = state?.routines ?? cache.load([Routine].self, key: .routines)?.value ?? []
        routines = Dictionary(rows.map { ($0.id,$0) }, uniquingKeysWith: { $1 })
        phase = .idle
    }

    var sorted: [Routine] {
        routines.values.sorted { lhs, rhs in
            if lhs.isEnabled != rhs.isEnabled { return lhs.isEnabled }
            return (lhs.nextRunAt ?? .distantFuture) < (rhs.nextRunAt ?? .distantFuture)
        }
    }

    func routine(_ id: String?) -> Routine? { id.flatMap { routines[$0] } }

    func routines(forProfile id: String) -> [Routine] { sorted.filter { $0.profileID == id } }

    func refresh() async {
        phase = .loading
        do {
            let list = try await client.schedules.listRoutines()
            routines = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            phase = .loaded
            cache.save(list, key: .routines)
        } catch {
            if let error = HermesError.from(error) { phase = .failed(error) }
        }
    }

    func apply(_ event: HermesEvent) {
        switch event {
        case .routineUpserted(let routine): routines[routine.id] = routine
        case .routineRemoved(let id): routines[id] = nil
        default: break
        }
    }

    func setEnabled(_ enabled: Bool, for id: String) async throws {
        routines[id]?.isEnabled = enabled
        do {
            try await client.schedules.setEnabled(enabled, routineID: id)
        } catch {
            routines[id]?.isEnabled = !enabled
            throw error
        }
    }

    func runNow(_ id: String) async throws {
        try await client.schedules.runNow(routineID: id)
    }

    func update(_ id: String, draft: RoutineDraft) async throws {
        try await client.schedules.updateRoutine(id: id, draft: draft)
    }

    func delete(_ id: String) async throws {
        try await client.schedules.deleteRoutine(id: id)
        routines[id] = nil
    }
}
