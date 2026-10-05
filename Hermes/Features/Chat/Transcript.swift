import Foundation

/// What the conversation renders. Hermes persists each tool request and each
/// tool result as its own history row, so two tool calls arrive as four
/// assistant messages. Runs of tool-only messages fold into one group, and a
/// request and its result (same call ID) merge into one call. Presentation
/// only; messages themselves are untouched.
nonisolated enum TranscriptItem: Identifiable, Hashable, Sendable {
    case message(Message)
    case tools(id: String, calls: [ToolCall])

    var id: String {
        switch self {
        case .message(let message): message.id
        case .tools(let id, _): id
        }
    }

    static func build(_ messages: [Message]) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        var pending: [ToolCall] = []
        var groupID: String?

        func flush() {
            if let id = groupID, !pending.isEmpty { items.append(.tools(id: "tools-\(id)", calls: merge(pending))) }
            pending = []
            groupID = nil
        }

        for message in messages {
            // Only persisted history rows fold. A message tied to a run is that
            // run's live bubble: it must keep rendering its live block and approvals.
            if message.isToolOnly && message.runID == nil {
                if groupID == nil { groupID = message.id }
                pending += message.toolCalls
            } else {
                flush()
                items.append(.message(message))
            }
        }
        flush()
        return items
    }

    /// Request + result rows for one call become a single call carrying both.
    static func merge(_ calls: [ToolCall]) -> [ToolCall] {
        var order: [String] = []
        var merged: [String: ToolCall] = [:]
        for call in calls {
            guard var existing = merged[call.id] else {
                order.append(call.id)
                merged[call.id] = call
                continue
            }
            existing.input = existing.input ?? call.input
            existing.output = call.output ?? existing.output
            existing.duration = existing.duration ?? call.duration
            existing.targets = existing.targets.isEmpty ? call.targets : existing.targets
            if existing.status != .failed && existing.status != .denied { existing.status = call.status }
            merged[call.id] = existing
        }
        return order.compactMap { merged[$0] }
    }
}

extension Message {
    /// An assistant row with tool activity and nothing to read.
    nonisolated var isToolOnly: Bool {
        role == .assistant && !parts.isEmpty && parts.allSatisfy {
            if case .tools(let calls) = $0 { return !calls.isEmpty }
            return false
        }
    }
}
