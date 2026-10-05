import Foundation

/// Scheduled Hermes work (cron job).
nonisolated struct Routine: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var prompt: String
    var schedule: RoutineSchedule
    var nextRunAt: Date?
    var profileID: String?
    var isEnabled: Bool
    var lastResult: RoutineResult?
    /// Where results are delivered, e.g. "Telegram · Home".
    var delivery: String?
    var hostID: String
    var skillIDs: [String]
}

nonisolated struct RoutineSchedule: Hashable, Codable, Sendable {
    /// The host's expression, e.g. `0 7 * * 1-5` or `every 2h`.
    var expression: String
    /// Human description, e.g. "Weekdays at 7:00 AM".
    var summary: String
}

nonisolated struct RoutineResult: Hashable, Codable, Sendable {
    var outcome: RunOutcome
    var date: Date
    var runID: String?
    var summary: String?
}

/// Editable fields for a routine.
nonisolated struct RoutineDraft: Hashable, Sendable {
    var name: String
    var prompt: String
    var scheduleExpression: String
    var profileID: String?
    var delivery: String?

    init(_ routine: Routine) {
        name = routine.name
        prompt = routine.prompt
        scheduleExpression = routine.schedule.expression
        profileID = routine.profileID
        delivery = routine.delivery
    }
}
