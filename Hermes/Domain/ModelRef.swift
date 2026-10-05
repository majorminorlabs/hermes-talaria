import Foundation

/// A model as Hermes reports it. `id` is whatever identifier the host uses.
nonisolated struct ModelRef: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var displayName: String
    var provider: String
    var supportsReasoning: Bool? = nil

    var label: String { displayName }
    var detailedLabel: String { "\(displayName) · \(provider)" }
}

nonisolated enum ReasoningLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    case off, low, medium, high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

/// Working directory / repository context for a run or conversation.
nonisolated struct ProjectContext: Identifiable, Hashable, Codable, Sendable {
    var id: String { path }
    var name: String
    var path: String
}

/// Settings applied to the next run started from a conversation.
nonisolated struct RunConfiguration: Hashable, Codable, Sendable {
    var profileID: String
    var model: ModelRef?
    var reasoning: ReasoningLevel
    var hostID: String
    var project: ProjectContext?

    init(profileID: String = Profile.defaultID, model: ModelRef? = nil, reasoning: ReasoningLevel = .medium,
         hostID: String, project: ProjectContext? = nil) {
        self.profileID = profileID
        self.model = model
        self.reasoning = reasoning
        self.hostID = hostID
        self.project = project
    }
}

nonisolated struct TokenUsage: Hashable, Codable, Sendable {
    var input: Int
    var output: Int
    var cached: Int = 0
    var reasoning: Int = 0
    var reportedTotal: Int? = nil
    var cacheWritten: Int? = nil

    var total: Int { reportedTotal ?? (input + output + reasoning) }
}
