import Foundation

/// Persistent identity normalized from profiles or Hermes Desktop Bot Mode.
nonisolated struct Profile: Identifiable, Hashable, Codable, Sendable {
    static let defaultID = "default"

    let id: String
    var name: String
    var role: String
    var summary: String
    var tint: ProfileTint
    var model: ModelRef
    var status: ProfileStatus
    var hostID: String
    var isDefault: Bool
    var skillIDs: [String]
    var toolsets: [String]
    var mcpServerIDs: [String]
    /// Configuration metadata. Any of these may be absent if the host doesn't expose them.
    var memorySummary: String?
    var memoryEntryCount: Int?
    var soulSummary: String?
    var configPath: String?
    var currentRunID: String?
    var isBotMode: Bool? = nil
    var canonicalChatAvailable: Bool? = nil
    var lastActiveAt: Date? = nil
    var activitySummary: String? = nil
    var avatarData: String? = nil
    var routinesMetadata: [String]? = nil
    var pluginsMetadata: [String]? = nil
    var modelAvailable: Bool? = nil
    var soul: String? = nil
    var editableFields: Set<String>? = nil
    /// Native Hermes profile name (`research-orchestrator`). Seeds the
    /// Desktop-matching identity hue when no avatar image is available.
    var profileKey: String? = nil
    /// The Studio has an avatar asset (Desktop's rendered bot face) for this bot.
    var hasAvatar: Bool? = nil

    var initials: String { String(name.prefix(1)).uppercased() }
}

nonisolated enum ProfileStatus: String, Codable, Sendable {
    case working, idle, needsAttention, unavailable, unknown

    var label: String {
        switch self {
        case .working: "Working"
        case .idle: "Idle"
        case .needsAttention: "Needs attention"
        case .unavailable: "Unavailable"
        case .unknown: "Status unobserved"
        }
    }
}

/// Muted identity colors. Deliberately few and desaturated.
nonisolated enum ProfileTint: String, Codable, Sendable, CaseIterable {
    case slate, teal, indigo, amber, rose, olive
}
