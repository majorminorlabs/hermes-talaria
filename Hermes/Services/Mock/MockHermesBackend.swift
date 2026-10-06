import Foundation

/// An in-memory simulation of `hermes-mobile-bridge` plus the Hermes host
/// behind it. Conforms to every service protocol so the whole app runs
/// without the Studio. State changes go through the same ordered
/// `HermesEvent` log the real bridge will provide.
final class MockHermesBackend {
    let simulation: SimulationControls
    let eventLog = MockEventLog()

    var hosts: [String: Host]
    var hostStatuses: [String: HostStatus]
    var conversations: [String: Conversation]
    var messages: [String: [Message]]
    var runs: [String: Run]
    var approvals: [String: ApprovalRequest]
    var profiles: [String: Profile]
    var tasks: [String: HermesTask]
    var routines: [String: Routine]
    var memoryEntries: [MemoryEntry]
    var skillList: [Skill]
    var toolList: [ToolInfo]
    var mcpList: [MCPServer]
    var integrationList: [Integration]
    var logEntries: [LogEntry]

    var savedCaptures: [UUID: CaptureRecord] = [:]
    var createdCommands: [UUID: Conversation] = [:]
    var sentCommands: [UUID: Run] = [:]

    var activeHostID = MockID.studio
    /// Developer override for the Studio's connection state.
    var forcedConnection: ConnectionState?

    // Run engine state
    var drivers: [String: Task<Void, Never>] = [:]
    var approvalWaiters: [String: CheckedContinuation<ApprovalDecision, Never>] = [:]
    var steeringNotes: [String: [String]] = [:]
    private var didStart = false

    init(fixtures: MockFixtures = .standard(), simulation: SimulationControls = SimulationControls()) {
        self.simulation = simulation
        hosts = Dictionary(uniqueKeysWithValues: fixtures.hosts.map { ($0.id, $0) })
        hostStatuses = fixtures.hostStatuses
        conversations = Dictionary(uniqueKeysWithValues: fixtures.conversations.map { ($0.id, $0) })
        messages = fixtures.messages
        runs = Dictionary(uniqueKeysWithValues: fixtures.runs.map { ($0.id, $0) })
        approvals = Dictionary(uniqueKeysWithValues: fixtures.approvals.map { ($0.id, $0) })
        profiles = Dictionary(uniqueKeysWithValues: fixtures.profiles.map { ($0.id, $0) })
        tasks = Dictionary(uniqueKeysWithValues: fixtures.tasks.map { ($0.id, $0) })
        routines = Dictionary(uniqueKeysWithValues: fixtures.routines.map { ($0.id, $0) })
        memoryEntries = fixtures.memory
        skillList = fixtures.skills
        toolList = fixtures.tools
        mcpList = fixtures.mcpServers
        integrationList = fixtures.integrations
        logEntries = fixtures.logs
        simulation.onCapabilitiesChanged = { [weak self] in
            guard let self else { return }
            self.publishHostStatus(self.activeHostID)
        }
    }

    /// Resume the fixture runs that are mid-flight so the app feels live.
    func startSimulation() {
        guard !didStart else { return }
        didStart = true
        drive(runID: "r-bench", messageID: "m-bench-live", script: MockScripts.benchContinuation)
        drive(runID: "r-arxiv", messageID: "m-arxiv-live", script: MockScripts.arxivContinuation)
        drive(runID: "r-ios", messageID: "m-ios-live", script: [
            .awaitApproval(id: "a-rm", approved: MockScripts.iosApproved, denied: MockScripts.iosDenied),
        ])
        drive(runID: "r-notes", messageID: "m-notes-live", script: [
            .awaitApproval(id: "a-index", approved: MockScripts.notesApproved, denied: MockScripts.notesDenied),
        ])
    }

    func publish(_ event: HermesEvent) {
        eventLog.publish(event)
    }

    // MARK: Request simulation

    /// Wraps every request: latency, reachability, capability and failure injection.
    func perform<T>(_ capability: HermesCapability? = nil, _ work: () throws -> T) async throws -> T {
        let delay = simulation.latency.seconds
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try ensureReachable()
        if let capability, !supports(capability) {
            throw HermesError.unsupported(capability)
        }
        if simulation.failRequests { throw HermesError.timeout }
        return try work()
    }

    func supports(_ capability: HermesCapability) -> Bool {
        currentStatus(for: activeHostID).capabilities.contains(capability)
    }

    func ensureReachable() throws {
        switch currentStatus(for: activeHostID).connection {
        case .connected: return
        case .hermesOffline: throw HermesError.hermesOffline
        case .authenticationRequired: throw HermesError.unauthorized
        case .connecting, .reconnecting, .bridgeOffline: throw HermesError.bridgeUnreachable
        }
    }

    func list<T>(_ values: [T]) -> [T] {
        simulation.emptyData ? [] : values
    }

    // MARK: Host status

    func currentStatus(for hostID: String) -> HostStatus {
        var status = hostStatuses[hostID] ?? .unknown(hostID)
        if hostID == MockID.studio, let forcedConnection {
            status.connection = forcedConnection
            if forcedConnection == .hermesOffline { status.hermesState = .stopped }
        }
        status.activeRunCount = simulation.emptyData ? 0 : runs.values.filter { $0.hostID == hostID && $0.state.isActive }.count
        status.capabilities.subtract(simulation.disabledCapabilities)
        if status.connection.isConnected { status.lastSeen = .now }
        return status
    }

    func publishHostStatus(_ hostID: String) {
        publish(.hostStatus(currentStatus(for: hostID)))
    }

    /// Developer control: force the Studio into a connection state.
    func simulateConnection(_ state: ConnectionState?) {
        forcedConnection = state
        if let state { log(state.isConnected ? .info : .warning, .connection, "Simulated connection state: \(state.label)") }
        publishHostStatus(MockID.studio)
        if case .reconnecting = state {
            Task {
                try? await Task.sleep(for: .seconds(3))
                if case .reconnecting = self.forcedConnection {
                    self.forcedConnection = nil
                    self.log(.info, .connection, "Reconnected to Mac Studio")
                    self.publishHostStatus(MockID.studio)
                }
            }
        }
    }

    // MARK: Mutation + publishing

    func upsert(_ run: Run) {
        let previous = runs[run.id]
        runs[run.id] = run
        publish(.runUpserted(run))
        if previous?.state.isActive != run.state.isActive { publishHostStatus(run.hostID) }
        if let profileID = run.profileID { refreshProfileStatus(profileID) }
    }

    func upsert(_ message: Message) {
        var list = messages[message.conversationID, default: []]
        if let index = list.firstIndex(where: { $0.id == message.id }) {
            list[index] = message
        } else {
            list.append(message)
        }
        messages[message.conversationID] = list
        publish(.messageUpserted(message))
    }

    func upsert(_ conversation: Conversation) {
        conversations[conversation.id] = conversation
        publish(.conversationUpserted(conversation))
    }

    func upsert(_ task: HermesTask) {
        let previous = tasks[task.id]
        tasks[task.id] = task
        publish(.taskUpserted(task))
        if previous?.status != task.status, let profileID = task.assigneeProfileID { refreshProfileStatus(profileID) }
    }

    func upsert(_ routine: Routine) {
        routines[routine.id] = routine
        publish(.routineUpserted(routine))
    }

    func upsert(_ profile: Profile) {
        profiles[profile.id] = profile
        publish(.profileUpserted(profile))
    }

    func upsert(_ approval: ApprovalRequest) {
        approvals[approval.id] = approval
        publish(.approvalUpserted(approval))
    }

    func refreshProfileStatus(_ profileID: String) {
        guard var profile = profiles[profileID] else { return }
        let active = runs.values.filter { $0.profileID == profileID && $0.state.isActive }.sorted { $0.startedAt > $1.startedAt }
        let status: ProfileStatus = active.contains { $0.state.needsUser } ? .needsAttention : (active.isEmpty ? .idle : .working)
        let current = active.first { $0.state.needsUser }?.id ?? active.first?.id
        guard profile.status != status || profile.currentRunID != current else { return }
        profile.status = status
        profile.currentRunID = current
        upsert(profile)
    }

    func log(_ level: LogLevel, _ category: LogCategory, _ message: String, detail: String? = nil, runID: String? = nil) {
        let entry = LogEntry(id: UUID().uuidString, timestamp: .now, level: level, category: category,
                             message: message, detail: detail, runID: runID)
        logEntries.insert(entry, at: 0)
        publish(.log(entry))
    }

    func profileName(_ id: String?) -> String {
        id.flatMap { profiles[$0]?.name } ?? "Hermes"
    }
}

// MARK: - HermesEventStream

extension MockHermesBackend: HermesEventStream {
    func subscribe(after cursor: EventCursor?) -> AsyncStream<HermesEventEnvelope> {
        eventLog.subscribe(after: cursor, replayEnabled: supports(.runReplay))
    }
}

// MARK: - HostService

extension MockHermesBackend: HostService {
    func connect(to host: Host) async {
        activeHostID = host.id
        if hosts[host.id] == nil {
            hosts[host.id] = host
            hostStatuses[host.id] = .unknown(host.id)
        }
        var connecting = currentStatus(for: host.id)
        connecting.connection = .connecting
        publish(.hostStatus(connecting))
        try? await Task.sleep(for: .seconds(host.id == MockID.studio ? 0.6 : 1.4))
        let status = currentStatus(for: host.id)
        log(status.connection.isConnected ? .info : .warning, .connection,
            status.connection.isConnected ? "Connected to \(host.name) bridge (\(status.latencyMilliseconds ?? 0) ms)" : "\(host.name): \(status.connection.label)")
        publish(.hostStatus(status))
    }

    func disconnect(hostID: String) async {}

    func status(hostID: String) async throws -> HostStatus {
        try await Task.sleep(for: .seconds(simulation.latency.seconds))
        return currentStatus(for: hostID)
    }

    func runOptions(hostID: String) async throws -> RunOptions {
        try await perform {
            RunOptions(models: MockModels.all, reasoningLevels: ReasoningLevel.allCases, projects: MockProjects.all)
        }
    }
}

// MARK: - HomeService

extension MockHermesBackend: HomeService {
    /// Simulates the bridge's server-side aggregation.
    func homeSummary() async throws -> HomeSummary {
        try await perform {
            let all = list(Array(runs.values))
            let active = all.filter(\.state.isActive).sorted { $0.startedAt > $1.startedAt }
            let recent = all.filter(\.state.isTerminal)
                .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
                .prefix(6)

            var attention: [AttentionItem] = list(Array(approvals.values)).map { approval in
                AttentionItem(id: "attn-\(approval.id)", kind: .approval,
                              title: "\(profileName(approval.profileID)) needs approval",
                              detail: approval.payload, date: approval.requestedAt, profileID: approval.profileID,
                              runID: approval.runID, approvalID: approval.id, taskID: nil)
            }
            let dayAgo = Date.now.addingTimeInterval(-86_400)
            attention += all.filter { $0.state == .failed && ($0.endedAt ?? .distantPast) > dayAgo }.map { run in
                AttentionItem(id: "attn-\(run.id)", kind: .failedRun, title: "\(run.title) failed",
                              detail: run.failureReason, date: run.endedAt ?? run.startedAt, profileID: run.profileID,
                              runID: run.id, approvalID: nil, taskID: run.taskID)
            }
            attention += list(Array(tasks.values)).filter { $0.status == .blocked }.map { task in
                AttentionItem(id: "attn-\(task.id)", kind: .blockedTask, title: "\(task.title) is blocked",
                              detail: task.blockReason, date: task.updatedAt, profileID: task.assigneeProfileID,
                              runID: nil, approvalID: nil, taskID: task.id)
            }
            let upcoming = list(Array(routines.values))
                .filter { $0.isEnabled && $0.nextRunAt != nil }
                .sorted { ($0.nextRunAt ?? .distantFuture) < ($1.nextRunAt ?? .distantFuture) }
                .prefix(4)
            return HomeSummary(host: currentStatus(for: activeHostID), activeRuns: active,
                               attention: attention.sorted { $0.date > $1.date }, recentRuns: Array(recent),
                               upcoming: Array(upcoming), generatedAt: .now)
        }
    }
}
