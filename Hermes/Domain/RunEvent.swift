import Foundation

/// A human-readable entry in a run's timeline. Hosts emit richer raw events;
/// the client layer maps them into these.
nonisolated struct RunEvent: Identifiable, Hashable, Codable, Sendable {
    let id: String
    /// Monotonic per-run ordering assigned by the bridge. Used to merge
    /// replayed and live events without duplicates or reordering.
    var sequence: Int
    var timestamp: Date
    var kind: RunEventKind
    var title: String
    var detail: String?
    var status: StepStatus
    var toolKind: ToolKind?
    var duration: TimeInterval?

    init(id: String = UUID().uuidString, sequence: Int = 0, timestamp: Date = .now, kind: RunEventKind, title: String,
         detail: String? = nil, status: StepStatus = .done, toolKind: ToolKind? = nil,
         duration: TimeInterval? = nil) {
        self.id = id
        self.sequence = sequence
        self.timestamp = timestamp
        self.kind = kind
        self.title = title
        self.detail = detail
        self.status = status
        self.toolKind = toolKind
        self.duration = duration
    }
}

nonisolated enum RunEventKind: String, Codable, Sendable {
    case started
    case modelSelected
    case thinking
    case tool
    /// A step Hermes has announced but not started (e.g. "Preparing response").
    case planned
    case approvalRequested
    case approvalResolved
    case steering
    case output
    case completed
    case failed
    case cancelled
    case connectionLost
    case connectionRestored

    /// Whether this event belongs in the live ✓ ● ○ checklist.
    var isStep: Bool {
        switch self {
        case .tool, .planned, .approvalRequested: true
        default: false
        }
    }
}

nonisolated enum StepStatus: String, Codable, Sendable {
    case pending, active, done, failed, skipped
}

/// High-level tool families, used for grouping and iconography.
nonisolated enum ToolKind: String, Codable, Sendable, CaseIterable {
    case terminal, files, browser, web, code, memory, skills, delegate, mcp, vision, image, messaging, schedule, other

    var label: String {
        switch self {
        case .terminal: "Terminal"
        case .files: "Files"
        case .browser: "Browser"
        case .web: "Web"
        case .code: "Code"
        case .memory: "Memory"
        case .skills: "Skills"
        case .delegate: "Subagent"
        case .mcp: "MCP"
        case .vision: "Vision"
        case .image: "Image"
        case .messaging: "Messaging"
        case .schedule: "Schedule"
        case .other: "Tool"
        }
    }

    var symbol: String {
        switch self {
        case .terminal: "terminal"
        case .files: "doc.text"
        case .browser: "safari"
        case .web: "magnifyingglass"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .memory: "brain"
        case .skills: "book.closed"
        case .delegate: "person.2.badge.gearshape"
        case .mcp: "point.3.connected.trianglepath.dotted"
        case .vision: "eye"
        case .image: "photo"
        case .messaging: "paperplane"
        case .schedule: "calendar.badge.clock"
        case .other: "wrench.and.screwdriver"
        }
    }
}

/// A tool invocation as recorded in the conversation transcript.
nonisolated struct ToolCall: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var kind: ToolKind
    /// Underlying tool name (e.g. `terminal`, `read_file`). Shown only in details.
    var name: String
    /// Human summary, e.g. "Ran python analyze.py".
    var summary: String
    var input: String?
    var output: String?
    var status: ToolCallStatus
    var duration: TimeInterval?
    var targets: [String]

    init(id: String = UUID().uuidString, kind: ToolKind, name: String, summary: String,
         input: String? = nil, output: String? = nil, status: ToolCallStatus = .completed,
         duration: TimeInterval? = nil, targets: [String] = []) {
        self.id = id
        self.kind = kind
        self.name = name
        self.summary = summary
        self.input = input
        self.output = output
        self.status = status
        self.duration = duration
        self.targets = targets
    }
}

nonisolated enum ToolCallStatus: String, Codable, Sendable {
    case running, completed, failed, denied

    var label: String {
        switch self {
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .denied: "Denied"
        }
    }
}
