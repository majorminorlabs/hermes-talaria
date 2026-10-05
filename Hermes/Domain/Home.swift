import Foundation

/// The aggregated Home response produced by the bridge. Home renders this
/// directly rather than assembling state from individual services.
nonisolated struct HomeSummary: Hashable, Codable, Sendable {
    var host: HostStatus
    var activeRuns: [Run]
    var attention: [AttentionItem]
    var recentRuns: [Run]
    var upcoming: [Routine]
    var generatedAt: Date
}

/// Something that genuinely needs the user.
nonisolated struct AttentionItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var kind: AttentionKind
    var title: String
    var detail: String?
    var date: Date
    var profileID: String?
    var runID: String?
    var approvalID: String?
    var taskID: String?
}

nonisolated enum AttentionKind: String, Codable, Sendable {
    case approval, failedRun, blockedTask, hostIssue, authentication

    var symbol: String {
        switch self {
        case .approval: "hand.raised.fill"
        case .failedRun: "xmark.octagon.fill"
        case .blockedTask: "exclamationmark.octagon.fill"
        case .hostIssue: "wifi.exclamationmark"
        case .authentication: "lock.fill"
        }
    }

    var label: String {
        switch self {
        case .approval: "Approval"
        case .failedRun: "Failed"
        case .blockedTask: "Blocked"
        case .hostIssue: "Connection"
        case .authentication: "Sign-in"
        }
    }
}
