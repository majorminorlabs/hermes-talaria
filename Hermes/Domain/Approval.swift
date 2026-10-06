import Foundation

/// Hermes is paused and asking before doing something risky.
///
/// Not every approval can be resolved from the phone: the bridge may be
/// unable to target a specific pending request safely. `availability` says
/// what the phone is allowed to do; the UI must never show an active Approve
/// button unless the request is actionable.
nonisolated struct ApprovalRequest: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var runID: String
    var conversationID: String?
    var profileID: String?
    var kind: ApprovalKind
    /// One-line description, e.g. "Delete generated cache file".
    var summary: String
    var command: String?
    var workingDirectory: String?
    var paths: [String]
    /// Unified diff for file modifications.
    var diff: String?
    /// Why Hermes flagged this (pattern match, policy, …).
    var reason: String?
    var risk: ApprovalRisk
    var requestedAt: Date
    var expiresAt: Date?
    var availability: ApprovalAvailability
    var allowsSessionApproval: Bool
    var clarificationQuestion: String? = nil
    var clarificationChoices: [String]? = nil

    var recommendedChoice: String? = nil
    var onTimeout: String? = nil

    var isClarification: Bool { clarificationQuestion != nil }

    var headline: String {
        switch kind {
        case .command: "Hermes wants to run"
        case .fileWrite: "Hermes wants to modify"
        case .fileDelete: "Hermes wants to delete"
        case .network: "Hermes wants to connect to"
        case .tool: "Hermes wants to use"
        }
    }

    /// The primary payload shown in monospace.
    var payload: String {
        if let command { return command }
        return paths.joined(separator: "\n")
    }

    /// Availability after applying expiry and host capability.
    func effectiveAvailability(remoteApprovalsSupported: Bool, now: Date = .now) -> ApprovalAvailability {
        if let expiresAt, expiresAt <= now { return .expired }
        guard remoteApprovalsSupported || isClarification else {
            return .unavailableRemotely("This host doesn't support approving actions from the phone.")
        }
        return availability
    }
}

nonisolated enum ApprovalAvailability: Hashable, Codable, Sendable {
    /// The bridge can target this exact request; Approve/Deny are safe.
    case actionable
    /// Must be resolved on the host (terminal or desktop client).
    case unavailableRemotely(String?)
    /// The bridge can't be sure which pending request a decision would hit.
    case ambiguous(String?)
    case expired

    var isActionable: Bool { self == .actionable }

    var title: String {
        switch self {
        case .actionable: "Approval required"
        case .unavailableRemotely, .ambiguous: "Approve on your Mac"
        case .expired: "Approval expired"
        }
    }

    var explanation: String? {
        switch self {
        case .actionable:
            nil
        case .unavailableRemotely(let reason):
            reason ?? "This action can't be approved from the phone. Resolve it in Hermes on your Mac, or stop the run."
        case .ambiguous(let reason):
            reason ?? "Hermes can't safely target this approval from the phone. Resolve it on your Mac, or stop the run."
        case .expired:
            "Hermes stopped waiting for a decision. It may have continued without this step."
        }
    }
}

nonisolated enum ApprovalKind: String, Codable, Sendable {
    case command, fileWrite, fileDelete, network, tool

    var label: String {
        switch self {
        case .command: "Terminal command"
        case .fileWrite: "File change"
        case .fileDelete: "File deletion"
        case .network: "Network access"
        case .tool: "Tool use"
        }
    }

    var symbol: String {
        switch self {
        case .command: "terminal"
        case .fileWrite: "doc.badge.ellipsis"
        case .fileDelete: "trash"
        case .network: "network"
        case .tool: "wrench.and.screwdriver"
        }
    }
}

nonisolated enum ApprovalRisk: String, Codable, Sendable {
    case low, moderate, high

    var label: String {
        switch self {
        case .low: "Low risk"
        case .moderate: "Moderate risk"
        case .high: "High risk"
        }
    }
}

nonisolated enum ApprovalDecision: String, Codable, Sendable {
    case approveOnce
    case approveForSession
    case deny

    var isApproval: Bool { self != .deny }
}
