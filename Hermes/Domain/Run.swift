import Foundation

/// One execution of Hermes. A conversation turn, a routine firing or a task
/// step each produce a run. Runs are owned by the host and keep a stable ID
/// across phone reconnects; backgrounding the app never stops a run.
nonisolated struct Run: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var title: String
    var profileID: String?
    var conversationID: String?
    var taskID: String?
    var routineID: String?
    var hostID: String
    var trigger: RunTrigger
    var state: RunState
    var startedAt: Date
    var endedAt: Date?
    /// Short human description of what Hermes is doing right now.
    var currentAction: String?
    var events: [RunEvent]
    var model: ModelRef?
    var reasoning: ReasoningLevel?
    var project: ProjectContext?
    var usage: TokenUsage?
    var pendingApprovalID: String?
    var failureReason: String?
    var resultSummary: String?
    var stopSupported: Bool? = nil
    var steerSupported: Bool? = nil
    var retrySupported: Bool? = nil

    var canStop: Bool { stopSupported ?? state.canStop }
    var canSteer: Bool { steerSupported ?? state.canSteer }
    var canRetry: Bool { state != .unknown && (retrySupported ?? state.canRetry) }

    /// Highest event sequence seen. Updates with a lower value are stale.
    var lastSequence: Int { events.last?.sequence ?? 0 }

    /// Appends an event with the next sequence number.
    mutating func append(_ event: RunEvent) {
        var event = event
        event.sequence = lastSequence + 1
        events.append(event)
    }

    /// Events rendered as the live checklist (✓ ● ○): finished and active
    /// steps in order, then announced-but-pending ones. Steering
    /// instructions appear inline.
    var steps: [RunEvent] {
        let visible = events.filter { $0.kind.isStep || ($0.kind == .steering && $0.detail != nil) }
        return visible.filter { $0.status != .pending } + visible.filter { $0.status == .pending }
    }

    var activeStep: RunEvent? { steps.first { $0.status == .active } }

    func elapsed(at now: Date = .now) -> TimeInterval {
        (endedAt ?? now).timeIntervalSince(startedAt)
    }

    var toolEvents: [RunEvent] { events.filter { $0.kind == .tool } }

    /// What to present when the phone may not be seeing live state: an
    /// active run seen over a degraded connection is shown as disconnected.
    func displayState(isLive: Bool) -> RunState {
        isLive || !state.isActive ? state : .disconnected
    }

    /// Tool usage counts for the details sheet.
    var toolsUsed: [(ToolKind, Int)] {
        let counts = Dictionary(grouping: toolEvents.compactMap(\.toolKind), by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}

nonisolated enum RunTrigger: String, Codable, Sendable {
    case chat, routine, task, external

    var label: String {
        switch self {
        case .chat: "Conversation"
        case .routine: "Routine"
        case .task: "Task"
        case .external: "External"
        }
    }
}

nonisolated enum RunState: String, Codable, Sendable, CaseIterable {
    case queued
    case running
    case waitingForApproval
    case waitingForInput
    /// A steering instruction was sent and hasn't been picked up yet.
    case steeringPending
    case stopping
    case completed
    case failed
    case cancelled
    /// The phone lost contact; the run may still be executing on the host.
    case disconnected
    /// The bridge cannot establish the outcome; never treat this as offline or retryable.
    case unknown

    var isActive: Bool {
        switch self {
        case .queued, .running, .waitingForApproval, .waitingForInput, .steeringPending, .stopping, .disconnected: true
        case .completed, .failed, .cancelled, .unknown: false
        }
    }

    var isTerminal: Bool { self == .completed || self == .failed || self == .cancelled }

    var needsUser: Bool { self == .waitingForApproval || self == .waitingForInput }

    var canStop: Bool {
        switch self {
        case .queued, .running, .waitingForApproval, .waitingForInput, .steeringPending: true
        default: false
        }
    }

    var canSteer: Bool { self == .running || self == .steeringPending }

    var canRetry: Bool { self == .failed || self == .cancelled }

    var label: String {
        switch self {
        case .queued: "Starting"
        case .running: "Working"
        case .waitingForApproval: "Needs you on Mac"
        case .waitingForInput: "Needs you"
        case .steeringPending: "Working · instruction sent"
        case .stopping: "Stopping"
        case .completed: "Done"
        case .failed: "Failed"
        case .cancelled: "Stopped"
        case .disconnected: "Last known: working"
        case .unknown: "Outcome unknown"
        }
    }

    var shortLabel: String {
        switch self {
        case .waitingForApproval: "Approval"
        case .waitingForInput: "Input"
        case .steeringPending: "Steering"
        default: label
        }
    }

    var symbol: String {
        switch self {
        case .queued: "clock"
        case .running: "circle.dotted"
        case .waitingForApproval: "hand.raised.fill"
        case .waitingForInput: "questionmark.bubble.fill"
        case .steeringPending: "arrow.turn.down.right"
        case .stopping: "stop.circle"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "minus.circle.fill"
        case .disconnected: "wifi.slash"
        case .unknown: "questionmark.circle"
        }
    }
}

/// Outcome of a finished run, used for history and routine results.
nonisolated enum RunOutcome: String, Codable, Sendable, CaseIterable, Identifiable {
    case succeeded, failed, cancelled

    var id: String { rawValue }

    init?(_ state: RunState) {
        switch state {
        case .completed: self = .succeeded
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .succeeded: "Completed"
        case .failed: "Failed"
        case .cancelled: "Stopped"
        }
    }

    var symbol: String {
        switch self {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "minus.circle.fill"
        }
    }
}
