import Foundation

// MARK: - Usage

nonisolated enum UsagePeriod: String, Codable, Sendable, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: "24 Hours"
        case .week: "7 Days"
        case .month: "30 Days"
        }
    }
}

/// Token and run counts as reported by the host. No pricing is derived.
nonisolated struct UsageReport: Hashable, Codable, Sendable {
    var period: UsagePeriod
    var totals: TokenUsage
    var runCount: Int
    var models: [ModelUsage]
    var daily: [DailyUsage]
    var sessionCount: Int? = nil
}

nonisolated struct ModelUsage: Identifiable, Hashable, Codable, Sendable {
    var id: String { model.id }
    var model: ModelRef
    var usage: TokenUsage
    var runCount: Int
    var sessionCount: Int? = nil
}

nonisolated struct DailyUsage: Identifiable, Hashable, Codable, Sendable {
    var id: Date { date }
    var date: Date
    var tokens: Int
    var runs: Int
    var sessionCount: Int? = nil
}

// MARK: - Logs

nonisolated struct LogEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var timestamp: Date
    var level: LogLevel
    var category: LogCategory
    var message: String
    var detail: String?
    var runID: String?

    var exportLine: String {
        let time = timestamp.formatted(.iso8601)
        var line = "\(time) [\(level.rawValue.uppercased())] [\(category.rawValue)] \(message)"
        if let detail { line += "\n    \(detail.replacingOccurrences(of: "\n", with: "\n    "))" }
        return line
    }
}

nonisolated enum LogLevel: String, Codable, Sendable, CaseIterable, Identifiable, Comparable {
    case debug, info, warning, error

    var id: String { rawValue }

    private var rank: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .warning: 2
        case .error: 3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    var label: String {
        switch self {
        case .debug: "Debug"
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        }
    }

    var symbol: String {
        switch self {
        case .debug: "ant"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}

nonisolated enum LogCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case connection, run, approval, routine, integration, app

    var id: String { rawValue }

    var label: String {
        switch self {
        case .connection: "Connection"
        case .run: "Runs"
        case .approval: "Approvals"
        case .routine: "Routines"
        case .integration: "Integrations"
        case .app: "App"
        }
    }
}
