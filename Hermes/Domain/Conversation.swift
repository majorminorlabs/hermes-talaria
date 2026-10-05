import Foundation

/// A persistent human ↔ Hermes thread (a Hermes session).
nonisolated struct Conversation: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var title: String
    /// Every Hermes session belongs to a profile; `Profile.defaultID` for the default one.
    var profileID: String
    var hostID: String
    var source: ConversationSource
    var createdAt: Date
    var lastActivity: Date
    var preview: String
    var project: ProjectContext?
    var model: ModelRef?
    var activeRunID: String?
    var isPinned: Bool
    var messageCount: Int
    var readOnly: Bool? = nil
    /// Canonical Bot Chat metadata. `profileID` remains the opaque mobile bot ID;
    /// the native profile name is retained separately for profile-scoped reads.
    var isBotChat: Bool? = nil
    var botID: String? = nil
    var botProfileID: String? = nil

    var usesDefaultProfile: Bool { profileID == Profile.defaultID }
}

/// Where the session originated. Hermes sessions can start outside the app.
nonisolated enum ConversationSource: String, Codable, Sendable {
    case app, cli, telegram, discord, slack, routine, api

    var label: String {
        switch self {
        case .app: "iPhone"
        case .cli: "Terminal"
        case .telegram: "Telegram"
        case .discord: "Discord"
        case .slack: "Slack"
        case .routine: "Routine"
        case .api: "API"
        }
    }

    var symbol: String? {
        switch self {
        case .app: nil
        case .cli: "terminal"
        case .telegram: "paperplane"
        case .discord, .slack: "number"
        case .routine: "calendar.badge.clock"
        case .api: "network"
        }
    }
}

nonisolated struct Message: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var conversationID: String
    var role: MessageRole
    var createdAt: Date
    var parts: [MessagePart]
    var runID: String?
    var status: MessageStatus
    /// A user instruction delivered to an already-running run.
    var isSteering: Bool

    init(id: String = UUID().uuidString, conversationID: String, role: MessageRole,
         createdAt: Date = .now, parts: [MessagePart], runID: String? = nil, status: MessageStatus = .sent,
         isSteering: Bool = false) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.createdAt = createdAt
        self.parts = parts
        self.runID = runID
        self.status = status
        self.isSteering = isSteering
    }

    /// Concatenated markdown, for copy/share and previews.
    var plainText: String {
        parts.compactMap {
            if case .markdown(let text) = $0 { return text }
            return nil
        }.joined(separator: "\n\n")
    }

    var toolCalls: [ToolCall] {
        parts.flatMap { part -> [ToolCall] in
            if case .tools(let calls) = part { return calls }
            return []
        }
    }
}

nonisolated enum MessageRole: String, Codable, Sendable {
    case user, assistant, system
}

nonisolated enum MessageStatus: String, Codable, Sendable {
    case sending, sent, streaming, failed
}

nonisolated enum MessagePart: Hashable, Codable, Sendable {
    case markdown(String)
    case tools([ToolCall])
    case image(ImageAttachment)
    case file(FileAttachment)
    case error(MessageError)
    case event(SystemEvent)
}

nonisolated struct ImageAttachment: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var source: ImageSource
    var aspectRatio: Double
    var caption: String?
}

nonisolated enum ImageSource: Hashable, Codable, Sendable {
    /// Image bundled with the app (mock data).
    case asset(String)
    case remote(URL)
    case data(Data)
}

nonisolated struct FileAttachment: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var byteCount: Int
    var fileExtension: String
    var path: String?

    /// Composer-only bytes are excluded from persisted transcripts and caches.
    var data: Data? = nil
    var contentType: String? = nil
    enum CodingKeys: String, CodingKey { case id, name, byteCount, fileExtension, path, contentType }

    var symbol: String {
        switch fileExtension.lowercased() {
        case "csv", "xlsx", "tsv": "tablecells"
        case "pdf": "doc.richtext"
        case "png", "jpg", "jpeg", "heic": "photo"
        case "zip", "tar", "gz": "doc.zipper"
        case "swift", "py", "js", "ts", "sh", "rs", "go": "chevron.left.forwardslash.chevron.right"
        case "md", "txt": "doc.plaintext"
        default: "doc"
        }
    }
}

nonisolated struct MessageError: Hashable, Codable, Sendable {
    var title: String
    var detail: String?
    var isRetryable: Bool
}

nonisolated struct SystemEvent: Hashable, Codable, Sendable {
    var symbol: String
    var text: String
}
