import Foundation

/// Connection management and host-level status. Saved host definitions are
/// local state (`SavedHostStore`); this service only talks to bridges.
protocol HostService: AnyObject, Sendable {
    /// Establish (or re-establish) the session with a host's bridge. Status
    /// changes are published as `HermesEvent.hostStatus`.
    func connect(to host: Host) async
    func disconnect(hostID: String) async
    func status(hostID: String) async throws -> HostStatus
    /// Models, reasoning levels and recent projects offered for new runs.
    func runOptions(hostID: String) async throws -> RunOptions
}

/// The bridge's aggregated Home/status response.
protocol HomeService: AnyObject, Sendable {
    func homeSummary() async throws -> HomeSummary
}

protocol ConversationService: AnyObject, Sendable {
    func searchConversations(_ query: String) async throws -> [Conversation]
    func listConversations() async throws -> [Conversation]
    func messages(conversationID: String) async throws -> [Message]
    func createConversation(configuration: RunConfiguration) async throws -> Conversation
    func createConversation(configuration: RunConfiguration, commandID: UUID) async throws -> Conversation
    func commandObservation(_ id: UUID, creating: Bool) async throws -> CommandObservation
    func setArchived(_ archived: Bool, conversationID: String) async throws
    func send(_ message: OutgoingMessage, conversationID: String, configuration: RunConfiguration, commandID: UUID) async throws -> Run
    func renameConversation(id: String, title: String) async throws
    func deleteConversation(id: String) async throws
    func setPinned(_ pinned: Bool, conversationID: String) async throws
    /// Sends a user message and starts a run. Messages and run progress
    /// arrive through the event stream.
    @discardableResult
    func send(_ message: OutgoingMessage, conversationID: String, configuration: RunConfiguration) async throws -> Run
}

/// What the composer submits.
nonisolated struct OutgoingMessage: Hashable, Sendable {
    var text: String
    var attachments: [FileAttachment] = []
}

protocol RunService: AnyObject, Sendable {
    /// Active runs plus recent history.
    func listRuns() async throws -> [Run]
    func pendingApprovals() async throws -> [ApprovalRequest]
    /// Cooperative stop: Hermes finishes the current step, then halts.
    func stop(runID: String) async throws
    /// Deliver an instruction to an already-running run.
    func steer(runID: String, instruction: String) async throws
    @discardableResult
    func retry(runID: String) async throws -> Run
    /// Only valid for approvals whose availability is `.actionable`.
    func resolveApproval(id: String, decision: ApprovalDecision) async throws
    func answerClarification(id: String, answer: String) async throws
    func run(id: String) async throws -> Run
}

/// Hermes profiles, presented as "bots" in the UI.
protocol ProfileService: AnyObject, Sendable {
    func listProfiles() async throws -> [Profile]
    func profile(id: String) async throws -> Profile
    func canonicalConversation(profileID: String) async throws -> Conversation?
    func updateProfile(id: String, changes: ProfileChanges) async throws -> Profile
    func createBot(_ draft: BotDraft) async throws -> Profile
    func botInventory(profileID: String?) async throws -> BotInventory
    func hideBot(id: String) async throws
    func duplicateBot(id: String) async throws -> Profile
}

extension ProfileService {
    func canonicalConversation(profileID: String) async throws -> Conversation? { nil }
    func createBot(_ draft: BotDraft) async throws -> Profile { throw HermesError.unsupported(.botCreate) }
    func botInventory(profileID: String?) async throws -> BotInventory { throw HermesError.unsupported(.botInventory) }
    func hideBot(id: String) async throws { throw HermesError.unsupported(.botHide) }
    func duplicateBot(id: String) async throws -> Profile { throw HermesError.unsupported(.botDuplicate) }
}

/// Editable profile fields. Deliberately small for V1.
nonisolated struct ProfileChanges: Hashable, Sendable {
    var model: ModelRef?
    var confirmExpensiveModel: Bool? = nil
    var name: String? = nil
    var description: String? = nil
    var soul: String? = nil
    var mcpServerIDs: [String]? = nil
    var enabledSkillIDs: [String]?
    var toolsets: [String]?
}

protocol TaskService: AnyObject, Sendable {
    func listTasks() async throws -> [HermesTask]
    @discardableResult
    func createTask(_ draft: TaskDraft) async throws -> HermesTask
    func review(taskID: String, status: TaskStatus, summary: String) async throws
    func setStatus(_ status: TaskStatus, taskID: String) async throws
    /// Dispatch a ready or blocked task to its assignee.
    func startTask(id: String) async throws
}

protocol ScheduleService: AnyObject, Sendable {
    func listRoutines() async throws -> [Routine]
    func setEnabled(_ enabled: Bool, routineID: String) async throws
    func runNow(routineID: String) async throws
    func updateRoutine(id: String, draft: RoutineDraft) async throws
    func deleteRoutine(id: String) async throws
}

protocol MemoryService: AnyObject, Sendable {
    func listMemory(scope: MemoryScope?, query: String) async throws -> [MemoryEntry]
    func deleteMemory(id: String) async throws
}

protocol SkillService: AnyObject, Sendable {
    func listSkills() async throws -> [Skill]
    func setEnabled(_ enabled: Bool, skillID: String) async throws
}

protocol ToolService: AnyObject, Sendable {
    func listTools() async throws -> [ToolInfo]
    func listMCPServers() async throws -> [MCPServer]
}

protocol IntegrationService: AnyObject, Sendable {
    func listIntegrations() async throws -> [Integration]
}

protocol UsageService: AnyObject, Sendable {
    func usage(period: UsagePeriod) async throws -> UsageReport
}

protocol LogService: AnyObject, Sendable {
    func recentLogs(limit: Int) async throws -> [LogEntry]
}

// Bridge-only exact input; mock runs do not produce clarification requests.
extension RunService {
    func answerClarification(id: String, answer: String) async throws { throw HermesError.rejected("No fresh clarification is available") }
    func run(id: String) async throws -> Run {
        guard let value = try await listRuns().first(where: { $0.id == id }) else { throw HermesError.notFound }
        return value
    }
}

protocol ArtifactService: AnyObject, Sendable {
    func artifacts(conversationID: String) async throws -> [FileAttachment]
    func downloadArtifact(id: String) async throws -> URL
}

extension ProfileService {
    func profile(id: String) async throws -> Profile {
        guard let value = try await listProfiles().first(where: { $0.id == id }) else { throw HermesError.notFound }
        return value
    }
}

extension ConversationService {
    func searchConversations(_ query: String) async throws -> [Conversation] { try await listConversations().filter { $0.title.localizedCaseInsensitiveContains(query) || $0.preview.localizedCaseInsensitiveContains(query) } }
    func commandObservation(_ id: UUID, creating: Bool) async throws -> CommandObservation { .pending }
    func createConversation(configuration: RunConfiguration, commandID: UUID) async throws -> Conversation { try await createConversation(configuration: configuration) }
    func send(_ message: OutgoingMessage, conversationID: String, configuration: RunConfiguration, commandID: UUID) async throws -> Run { try await send(message, conversationID: conversationID, configuration: configuration) }
    func setArchived(_ archived: Bool, conversationID: String) async throws { throw HermesError.unsupported(.sessions) }
}

extension TaskService {
    func review(taskID: String, status: TaskStatus, summary: String) async throws {
        guard summary.isEmpty else { throw HermesError.rejected("This host does not support review notes") }
        try await setStatus(status, taskID: taskID)
    }
}
