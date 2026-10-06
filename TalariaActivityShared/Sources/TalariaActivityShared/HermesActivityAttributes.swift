import ActivityKit
import Foundation

public struct HermesActivityAttributes: ActivityAttributes, Sendable {
    public struct Run: Codable, Hashable, Identifiable, Sendable {
        public enum State: String, Codable, Sendable { case running, needsInput, blocked, done }
        public var id: String
        public var title: String
        public var botName: String
        public var botColor: String
        public var state: State
        public var step: Int?
        public var totalSteps: Int?
        public var threadID: String?
        public init(id: String, title: String, botName: String, botColor: String, state: State, step: Int? = nil, totalSteps: Int? = nil, threadID: String? = nil) {
            self.id = id; self.title = title; self.botName = botName; self.botColor = botColor; self.state = state; self.step = step; self.totalSteps = totalSteps; self.threadID = threadID
        }
        public var detail: String {
            switch state {
            case .needsInput: return "Needs you"
            case .blocked: return "Blocked"
            case .done: return "Done"
            case .running:
                if let step, let totalSteps, totalSteps > 0 { return "step \(step)/\(totalSteps)" }
                return "Running"
            }
        }
        public var url: URL {
            guard state == .needsInput, let threadID else { return ContentState.threadsURL }
            return URL(string: "talaria://thread/\(threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? threadID)") ?? ContentState.threadsURL
        }
    }
    public struct ContentState: Codable, Hashable, Sendable {
        public var runs: [Run]
        public var updatedAt: Date
        public init(runs: [Run], updatedAt: Date = .now) { self.runs = runs; self.updatedAt = updatedAt }
        public var activeRuns: [Run] { runs.filter { $0.state != .done } }
        public var activeCount: Int { activeRuns.count }
        public var worstState: Run.State {
            if activeRuns.contains(where: { $0.state == .blocked }) { return .blocked }
            if activeRuns.contains(where: { $0.state == .needsInput }) { return .needsInput }
            return activeCount == 0 ? .done : .running
        }
        public var label: String {
            switch worstState { case .running: "Running"; case .needsInput: "Needs you"; case .blocked: "Blocked"; case .done: "All done" }
        }
        public var displayRuns: [Run] {
            let urgent = activeRuns.filter { $0.state == .needsInput || $0.state == .blocked }
            return Array((urgent + activeRuns.filter { $0.state == .running }).prefix(3))
        }
        public static let threadsURL = URL(string: "talaria://threads")!
    }
    public var isDemo: Bool
    public init(isDemo: Bool = false) { self.isDemo = isDemo }
}

public enum HermesActivityFixtures {
    public static let offsets: [TimeInterval] = [0, 3, 7, 12, 16, 19]
    public static func frame(_ index: Int, at date: Date = .now) -> HermesActivityAttributes.ContentState {
        var runs = [HermesActivityAttributes.Run(id: "demo-coder", title: "Fix RosterPath deploy", botName: "Coder", botColor: "6366F1", state: index == 5 ? .done : .running, step: min(index + 1, 5), totalSteps: 5)]
        if index >= 1 { runs.append(.init(id: "demo-research", title: "Eval sweep", botName: "Researcher", botColor: "A855F7", state: index >= 4 ? .done : .running, step: min(index + 1, 4), totalSteps: 4)) }
        if index >= 2 { runs.append(.init(id: "demo-ops", title: "Order compressor part", botName: "Ops", botColor: "14B8A6", state: index == 2 ? .needsInput : index == 5 ? .done : .running, step: index >= 3 ? 2 : 1, totalSteps: 2, threadID: "demo-ops")) }
        return .init(runs: runs, updatedAt: date)
    }
    public static var blocked: HermesActivityAttributes.ContentState {
        var state = frame(2); state.runs[0].state = .blocked; return state
    }
}
