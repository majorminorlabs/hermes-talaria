import Foundation

// MARK: - Memory

nonisolated struct MemoryEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var content: String
    var scope: MemoryScope
    var profileID: String?
    var source: MemorySource
    var sourceTitle: String?
    var conversationID: String?
    var createdAt: Date
    var updatedAt: Date
    var tags: [String]

    var title: String {
        content.split(separator: "\n").first.map(String.init) ?? content
    }
}

nonisolated enum MemoryScope: String, Codable, Sendable, CaseIterable, Identifiable {
    /// What Hermes has learned about its environment and work.
    case agent
    /// What Hermes knows about the user.
    case user

    var id: String { rawValue }

    var label: String {
        switch self {
        case .agent: "Agent"
        case .user: "User profile"
        }
    }
}

nonisolated enum MemorySource: String, Codable, Sendable {
    case conversation, routine, manual, skill

    var label: String {
        switch self {
        case .conversation: "Conversation"
        case .routine: "Routine"
        case .manual: "Added manually"
        case .skill: "Skill"
        }
    }

    var symbol: String {
        switch self {
        case .conversation: "bubble.left"
        case .routine: "calendar.badge.clock"
        case .manual: "pencil"
        case .skill: "book.closed"
        }
    }
}

// MARK: - Skills

nonisolated struct Skill: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var summary: String
    var category: String
    var isEnabled: Bool
    var version: String?
    var origin: SkillOrigin
    var usageCount: Int
    var lastUsedAt: Date?
    var instructionsPreview: String
    var requiredToolsets: [String]
}

nonisolated enum SkillOrigin: String, Codable, Sendable {
    case bundled, hub, local, agentCreated

    var label: String {
        switch self {
        case .bundled: "Bundled"
        case .hub: "Skills Hub"
        case .local: "Local"
        case .agentCreated: "Created by Hermes"
        }
    }
}

// MARK: - Tools & MCP

nonisolated struct ToolInfo: Identifiable, Hashable, Codable, Sendable {
    var id: String { name }
    var name: String
    var toolset: String
    var summary: String
    var availability: ToolAvailability
}

nonisolated enum ToolAvailability: Hashable, Codable, Sendable {
    case available
    case needsSetup(String)
    case unavailable(String)

    var isAvailable: Bool { self == .available }

    var label: String {
        switch self {
        case .available: "Available"
        case .needsSetup: "Needs setup"
        case .unavailable: "Unavailable"
        }
    }

    var reason: String? {
        switch self {
        case .available: nil
        case .needsSetup(let reason), .unavailable(let reason): reason
        }
    }
}

nonisolated struct MCPServer: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var transport: MCPTransport
    var endpoint: String
    var status: MCPStatus
    var errorMessage: String?
    var toolNames: [String]
    var lastConnectedAt: Date?

    var toolCount: Int { toolNames.count }
}

nonisolated enum MCPTransport: String, Codable, Sendable {
    case stdio, http

    var label: String { self == .stdio ? "stdio" : "HTTP" }
}

nonisolated enum MCPStatus: String, Codable, Sendable {
    case connected, connecting, disconnected, error

    var label: String {
        switch self {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnected: "Disconnected"
        case .error: "Error"
        }
    }
}

// MARK: - Integrations

nonisolated struct Integration: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var platform: IntegrationPlatform
    var status: IntegrationStatus
    var detail: String?
    var lastActivity: Date?
}

nonisolated enum IntegrationPlatform: String, Codable, Sendable, CaseIterable {
    case telegram, discord, slack, whatsapp, signal, email, homeAssistant

    var label: String {
        switch self {
        case .telegram: "Telegram"
        case .discord: "Discord"
        case .slack: "Slack"
        case .whatsapp: "WhatsApp"
        case .signal: "Signal"
        case .email: "Email"
        case .homeAssistant: "Home Assistant"
        }
    }

    var symbol: String {
        switch self {
        case .telegram: "paperplane"
        case .discord: "gamecontroller"
        case .slack: "number"
        case .whatsapp: "phone.bubble"
        case .signal: "lock.shield"
        case .email: "envelope"
        case .homeAssistant: "house"
        }
    }
}

nonisolated enum IntegrationStatus: String, Codable, Sendable {
    case connected, disconnected, error, notConfigured

    var label: String {
        switch self {
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .error: "Error"
        case .notConfigured: "Not configured"
        }
    }
}
