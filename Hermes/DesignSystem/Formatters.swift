import Foundation

enum Format {
    /// Compact elapsed time: "42s", "3m 42s", "12m", "1h 05m", "3d 4h".
    static func elapsed(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<600: return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h \(String(format: "%02d", (seconds % 3600) / 60))m"
        default: return "\(seconds / 86_400)d \((seconds % 86_400) / 3600)h"
        }
    }

    /// "now", "4m ago", "2h ago", "Yesterday", "3d ago".
    static func relative(_ date: Date, now: Date = .now) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 0 { return future(date, now: now) }
        switch interval {
        case ..<60: return "now"
        case ..<3600: return "\(Int(interval / 60))m ago"
        case ..<86_400: return "\(Int(interval / 3600))h ago"
        default:
            if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
            return "\(Int(interval / 86_400))d ago"
        }
    }

    /// "updated just now", "updated 4m ago".
    static func updated(_ date: Date, now: Date = .now) -> String {
        let relative = relative(date, now: now)
        return relative == "now" ? "updated just now" : "updated \(relative)"
    }

    /// "in 47m", "in 3h", "Tomorrow 7:00 AM", "Sun 6:00 PM".
    static func future(_ date: Date, now: Date = .now) -> String {
        let interval = date.timeIntervalSince(now)
        let calendar = Calendar.current
        switch interval {
        case ..<60: return "now"
        case ..<3600: return "in \(Int(interval / 60))m"
        case ..<(6 * 3600): return "in \(Int(interval / 3600))h \(Int(interval.truncatingRemainder(dividingBy: 3600) / 60))m"
        default:
            let time = date.formatted(date: .omitted, time: .shortened)
            if calendar.isDateInToday(date) { return "Today \(time)" }
            if calendar.isDateInTomorrow(date) { return "Tomorrow \(time)" }
            return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
        }
    }

    /// Messages-style list timestamp.
    static func listTimestamp(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            if now.timeIntervalSince(date) < 60 { return "now" }
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if now.timeIntervalSince(date) < 6 * 86_400 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    /// 38_210 → "38.2k", 1_204_000 → "1.2M".
    static func tokens(_ count: Int) -> String {
        switch count {
        case ..<1000: return "\(count)"
        case ..<1_000_000:
            let value = Double(count) / 1000
            return value >= 100 ? "\(Int(value))k" : String(format: "%.1fk", value)
        default:
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Commit hashes shorten to 7 characters like git; versions stay as-is.
    static func version(_ raw: String) -> String {
        let isHash = raw.count >= 12 && raw.allSatisfy(\.isHexDigit)
        return isHash ? String(raw.prefix(7)) : raw
    }

    /// "Active now", "Active 53m ago", "Active yesterday".
    static func lastActive(_ date: Date, now: Date = .now) -> String {
        let relative = relative(date, now: now)
        switch relative {
        case "now": return "Active now"
        case "Yesterday": return "Active yesterday"
        default: return "Active \(relative)"
        }
    }

    static func uptime(_ interval: TimeInterval) -> String {
        let days = Int(interval / 86_400)
        let hours = Int(interval.truncatingRemainder(dividingBy: 86_400) / 3600)
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h"
    }
}
