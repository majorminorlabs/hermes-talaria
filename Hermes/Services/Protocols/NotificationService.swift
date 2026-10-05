import Foundation
import UserNotifications

/// Something worth interrupting the user for. Deliberately excludes tool
/// calls and routine progress.
nonisolated enum HermesNotification: Hashable, Sendable {
    case approvalRequired(ApprovalRequest, profileName: String?)
    case runCompleted(Run, profileName: String?)
    case runFailed(Run, profileName: String?)
    case taskBlocked(HermesTask)
    case routineResult(Run, routineName: String)

    var category: NotificationCategory {
        switch self {
        case .approvalRequired: .approvals
        case .runCompleted: .completions
        case .runFailed: .failures
        case .taskBlocked: .blockedTasks
        case .routineResult: .routineResults
        }
    }

    var title: String {
        switch self {
        case .approvalRequired(_, let profile): "\(profile ?? "Hermes") needs approval"
        case .runCompleted(let run, let profile): "\(profile ?? "Hermes") finished \(run.title)"
        case .runFailed(let run, let profile): "\(profile ?? "Hermes") failed: \(run.title)"
        case .taskBlocked(let task): "Task blocked: \(task.title)"
        case .routineResult(_, let name): "\(name) finished"
        }
    }

    var body: String {
        switch self {
        case .approvalRequired(let request, _): request.payload
        case .runCompleted(let run, _): run.resultSummary ?? "Completed"
        case .runFailed(let run, _): run.failureReason ?? "The run failed."
        case .taskBlocked(let task): task.blockReason ?? "Waiting on a dependency."
        case .routineResult(let run, _): run.resultSummary ?? run.title
        }
    }

    var identifier: String {
        switch self {
        case .approvalRequired(let request, _): "approval-\(request.id)"
        case .runCompleted(let run, _), .runFailed(let run, _), .routineResult(let run, _): "run-\(run.id)"
        case .taskBlocked(let task): "task-\(task.id)"
        }
    }
}

nonisolated enum NotificationCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case approvals, failures, blockedTasks, completions, routineResults

    var id: String { rawValue }

    var label: String {
        switch self {
        case .approvals: "Approval required"
        case .failures: "Run failed"
        case .blockedTasks: "Task blocked"
        case .completions: "Run completed"
        case .routineResults: "Routine results"
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .approvals, .failures, .blockedTasks: true
        case .completions, .routineResults: false
        }
    }
}

/// Decides which state transitions become notifications.
nonisolated enum NotificationPolicy {
    static func notification(previous: Run?, current: Run, profileName: String?, routineName: String?) -> HermesNotification? {
        guard previous?.state != current.state else { return nil }
        switch current.state {
        case .completed:
            if let routineName { return .routineResult(current, routineName: routineName) }
            return .runCompleted(current, profileName: profileName)
        case .failed:
            return .runFailed(current, profileName: profileName)
        default:
            return nil
        }
    }

    static func notification(previous: HermesTask?, current: HermesTask) -> HermesNotification? {
        guard current.status == .blocked, previous?.status != .blocked, previous != nil else { return nil }
        return .taskBlocked(current)
    }
}

/// Delivers notifications to the user. Remote push from the Studio is a
/// future integration point; this local implementation covers the case where
/// the app is alive in the background.
protocol NotificationService: AnyObject, Sendable {
    func requestAuthorization() async -> Bool
    func deliver(_ notification: HermesNotification)
}

final class LocalNotificationService: NotificationService {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    func deliver(_ notification: HermesNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.threadIdentifier = notification.category.rawValue
        content.sound = notification.category == .approvals ? .default : nil
        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
