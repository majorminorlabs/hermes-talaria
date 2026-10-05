import Foundation

/// Durable work tracked by Hermes (multi-agent kanban). A task may produce
/// several runs over its lifetime. Named `HermesTask` to avoid clashing with
/// Swift's `Task`.
nonisolated struct HermesTask: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var title: String
    var summary: String
    var status: TaskStatus
    var assigneeProfileID: String?
    var priority: TaskPriority
    var hostID: String
    var project: ProjectContext?
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var dependencyIDs: [String]
    var blockReason: String?
    var runIDs: [String]
    var conversationID: String?
    var activity: [TaskActivity]
    var sourceState: String? = nil
    var supportedTransitions: [TaskStatus]? = nil
    var boardID: String? = nil

    var availableTransitions: [TaskStatus] { supportedTransitions ?? TaskStatus.allCases.filter { $0 != status } }

    var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (completedAt ?? .now).timeIntervalSince(startedAt)
    }

    var latestActivity: TaskActivity? { activity.max { $0.date < $1.date } }
}

nonisolated enum TaskStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case ready, inProgress, blocked, completed, failed, cancelled, triage, todo, scheduled, review, archived

    var id: String { rawValue }

    /// Columns shown on the kanban surface.
    static let board: [TaskStatus] = [.ready, .inProgress, .blocked, .completed]

    var label: String {
        switch self {
        case .triage: "Triage"
        case .todo: "To Do"
        case .scheduled: "Scheduled"
        case .review: "Review"
        case .archived: "Archived"
        case .ready: "Ready"
        case .inProgress: "In Progress"
        case .blocked: "Blocked"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    var symbol: String {
        switch self {
        case .triage, .todo: "tray"
        case .scheduled: "clock"
        case .review: "eye"
        case .archived: "archivebox"
        case .ready: "circle"
        case .inProgress: "circle.dotted.circle"
        case .blocked: "exclamationmark.octagon"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "minus.circle"
        }
    }

    /// Failed and cancelled tasks live in the Completed column/history.
    var boardColumn: TaskStatus {
        switch self {
        case .failed, .cancelled, .archived: .completed
        case .triage, .todo, .scheduled: .ready
        case .review: .inProgress
        default: self
        }
    }
}

nonisolated enum TaskPriority: Int, Codable, Sendable, Comparable, CaseIterable {
    case low = 0, normal = 1, high = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }
}

nonisolated struct TaskActivity: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var date: Date
    var text: String
    var profileID: String?
    var symbol: String
}

/// Input for creating a task from the phone.
nonisolated struct TaskDraft: Hashable, Sendable {
    var title: String = ""
    var summary: String = ""
    var assigneeProfileID: String?
    var priority: TaskPriority = .normal
    var project: ProjectContext?
}
