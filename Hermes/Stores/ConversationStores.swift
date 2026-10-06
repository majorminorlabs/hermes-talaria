import Foundation

/// The conversation list plus loaded transcripts, kept current by the
/// app-wide event loop.
@Observable
final class ConversationListStore {
    private let client: HermesClient
    private let cache: SnapshotCache

    private(set) var conversations: [String: Conversation] = [:]
    private(set) var transcripts: [String: [Message]] = [:]
    private(set) var phase: LoadPhase = .idle
    private(set) var updatedAt: Date?

    init(client: HermesClient, cache: SnapshotCache) {
        self.client = client
        self.cache = cache
        if let snapshot = cache.load([Conversation].self, key: .conversations) {
            conversations = Dictionary(snapshot.value.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            updatedAt = snapshot.savedAt
        }
        if let snapshot = cache.load([String: [Message]].self, key: .transcripts) {
            transcripts = snapshot.value
        }
        if let state = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value {
            conversations = Dictionary(state.conversations.map { ($0.id,$0) }, uniquingKeysWith: { $1 })
            transcripts = state.transcripts
        }

    }

    func restoreScopedCache() {
        let state = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value
        let rows = state?.conversations ?? cache.load([Conversation].self, key: .conversations)?.value ?? []
        conversations = Dictionary(rows.map { ($0.id,$0) }, uniquingKeysWith: { $1 })
        transcripts = state?.transcripts ?? cache.load([String:[Message]].self, key: .transcripts)?.value ?? [:]
        phase = .idle
    }

    var sorted: [Conversation] {
        conversations.values.sorted { $0.lastActivity > $1.lastActivity }
    }

    func conversation(_ id: String?) -> Conversation? { id.flatMap { conversations[$0] } }

    func conversations(forProfile id: String) -> [Conversation] {
        sorted.filter { $0.profileID == id }
    }

    /// Grouped for the list: Pinned, then by recency.
    func sections(matching query: String) -> [ConversationSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matches = sorted.filter {
            trimmed.isEmpty
                || $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.preview.localizedCaseInsensitiveContains(trimmed)
                || ($0.project?.name.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
        var sections: [ConversationSection] = []
        let pinned = matches.filter(\.isPinned)
        if !pinned.isEmpty && trimmed.isEmpty { sections.append(ConversationSection(title: "Pinned", conversations: pinned)) }
        let rest = trimmed.isEmpty ? matches.filter { !$0.isPinned } : matches
        let calendar = Calendar.current
        let buckets: [(String, (Date) -> Bool)] = [
            ("Today", { calendar.isDateInToday($0) }),
            ("Yesterday", { calendar.isDateInYesterday($0) }),
            ("Previous 7 Days", { $0 > Date.now.addingTimeInterval(-7 * 86_400) }),
            ("Older", { _ in true }),
        ]
        var remaining = rest
        for (title, predicate) in buckets {
            let bucket = remaining.filter { predicate($0.lastActivity) }
            remaining.removeAll { predicate($0.lastActivity) }
            if !bucket.isEmpty { sections.append(ConversationSection(title: title, conversations: bucket)) }
        }
        return sections
    }

    // MARK: Loading

    func refresh() async {
        phase = .loading
        do {
            let list = try await client.conversations.listConversations()
            conversations = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            updatedAt = .now
            phase = .loaded
            cache.save(list, key: .conversations)
        } catch {
            if let error = HermesError.from(error) { phase = .failed(error) }
        }
    }

    func loadTranscript(_ conversationID: String) async throws {
        let started = Date.now
        let fetched = try await client.conversations.messages(conversationID: conversationID)
        // Keep messages that arrived over the event stream mid-fetch, but drop
        // anything older that the host no longer has (stale cache).
        let fetchedIDs = Set(fetched.map(\.id))
        let extra = (transcripts[conversationID] ?? []).filter {
            !fetchedIDs.contains($0.id) && $0.createdAt >= started.addingTimeInterval(-5)
        }
        transcripts[conversationID] = (fetched + extra).sorted { $0.createdAt < $1.createdAt }
        persistTranscripts()
    }

    /// Keeps the most recently active transcripts for offline reading.
    private func persistTranscripts() {
        let recent = sorted.prefix(12).map(\.id).filter { transcripts[$0] != nil }
        let subset = Dictionary(uniqueKeysWithValues: recent.compactMap { id in transcripts[id].map { (id, $0) } })
        cache.save(subset, key: .transcripts)
    }

    func apply(_ event: HermesEvent) {
        switch event {
        case .conversationUpserted(let conversation):
            conversations[conversation.id] = conversation
        case .conversationRemoved(let id):
            conversations[id] = nil
            transcripts[id] = nil
        case .transcriptReplaced(let id, let messages):
            transcripts[id] = messages
        case .messageUpserted(let message):
            guard transcripts[message.conversationID] != nil else { return }
            var list = transcripts[message.conversationID] ?? []
            if let index = list.firstIndex(where: { $0.id == message.id }) {
                list[index] = message
            } else {
                list.append(message)
            }
            transcripts[message.conversationID] = list
        default:
            break
        }
    }

    // MARK: Actions

    func create(configuration: RunConfiguration) async throws -> Conversation {
        let conversation = try await client.conversations.createConversation(configuration: configuration)
        conversations[conversation.id] = conversation
        transcripts[conversation.id] = []
        return conversation
    }

    func rename(_ id: String, to title: String) async throws {
        try await client.conversations.renameConversation(id: id, title: title)
    }

    func delete(_ id: String) async throws {
        try await client.conversations.deleteConversation(id: id)
    }

    func setArchived(_ archived: Bool, _ id: String) async throws {
        try await client.conversations.setArchived(archived, conversationID: id)
        if var c = conversations[id] { c.isArchived = archived; conversations[id] = c }
    }

    func setPinned(_ pinned: Bool, _ id: String) async throws {
        try await client.conversations.setPinned(pinned, conversationID: id)
    }

    func send(_ message: OutgoingMessage, conversationID: String, configuration: RunConfiguration) async throws {
        try await client.conversations.send(message, conversationID: conversationID, configuration: configuration)
    }
}

struct ConversationSection: Identifiable {
    var id: String { title }
    var title: String
    var conversations: [Conversation]
}

/// State for one open conversation (new or existing).
@Observable
final class ConversationModel {
    private let list: ConversationListStore
    private let activity: ActivityStore
    private let connection: ConnectionStore
    private let drafts: DraftStore

    private(set) var conversationID: String?
    private(set) var phase: LoadPhase = .idle
    private(set) var isSending = false
    var configuration: RunConfiguration
    var attachments: [FileAttachment] = []
    var draft: String {
        didSet { drafts.setDraft(draft, for: conversationID ?? "new") }
    }

    init(conversationID: String?, profileID: String?, list: ConversationListStore, activity: ActivityStore,
         connection: ConnectionStore, drafts: DraftStore, preferences: AppPreferences) {
        self.conversationID = conversationID
        self.list = list
        self.activity = activity
        self.connection = connection
        self.drafts = drafts
        let existing = list.conversation(conversationID)
        configuration = RunConfiguration(
            profileID: existing?.profileID ?? profileID ?? preferences.defaultProfileID ?? Profile.defaultID,
            model: existing?.model, reasoning: preferences.defaultReasoning,
            hostID: connection.activeHostID, project: existing?.project)
        draft = drafts.draft(for: conversationID ?? "new")
    }

    var conversation: Conversation? { list.conversation(conversationID) }

    var messages: [Message] { conversationID.flatMap { list.transcripts[$0] } ?? [] }

    var activeRun: Run? {
        if let run = activity.run(conversation?.activeRunID), run.state.isActive { return run }
        return activity.activeRuns.first { $0.conversationID == conversationID && conversationID != nil }
    }

    var pendingApproval: ApprovalRequest? {
        activeRun.flatMap { activity.pendingApproval(for: $0) }
    }

    var composerMode: ComposerMode {
        if conversationID != nil && activity.runs.values.contains(where: { $0.conversationID == conversationID && $0.state == .unknown }) { return .busy }
        guard let run = activeRun else { return .send }
        if let approval = pendingApproval, approval.isClarification, approval.availability.isActionable, (approval.expiresAt ?? .distantPast) > .now { return .clarify }
        if run.canSteer && connection.supports(.steering) { return .steer }
        return .busy
    }

    var canSend: Bool {
        let hasContent = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
        let botChatWritable = conversation?.isBotChat != true || connection.supports(.botChat)
        return conversation?.readOnly != true && botChatWritable && hasContent && !isSending && connection.canControlChat && connection.connection.isConnected && composerMode != .busy
    }

    func load() async {
        guard let conversationID else { phase = .loaded; return }
        if list.transcripts[conversationID] == nil { phase = .loading }
        do {
            try await list.loadTranscript(conversationID)
            phase = .loaded
        } catch {
            if let error = HermesError.from(error) { phase = .failed(error) }
        }
    }

    /// Sends the composer contents: a new message, or a steering
    /// instruction when a run is active.
    func submit() async throws {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        isSending = true
        defer { isSending = false }

        if composerMode == .clarify, let approval = pendingApproval {
            try await activity.answerClarification(approval.id, answer: text)
            draft = ""
            return
        }

        if composerMode == .steer, let run = activeRun {
            try await activity.steer(run.id, instruction: text)
            draft = ""
            return
        }

        let id: String
        if let conversationID {
            id = conversationID
        } else {
            let created = try await list.create(configuration: configuration)
            drafts.setDraft("", for: "new")
            conversationID = created.id
            id = created.id
        }
        let outgoing = OutgoingMessage(text: text, attachments: attachments)
        try await list.send(outgoing, conversationID: id, configuration: configuration)
        draft = ""
        attachments = []
    }

    func steer(_ instruction: String) async throws {
        guard let run = activeRun else { return }
        try await activity.steer(run.id, instruction: instruction)
    }

    func stop() async throws {
        guard let run = activeRun else { return }
        try await activity.stop(run.id)
    }
}

enum ComposerMode: Equatable {
    case send
    case clarify
    /// A run is active and accepts instructions.
    case steer
    /// A run is active and can't take input (waiting for approval, stopping…).
    case busy
}
