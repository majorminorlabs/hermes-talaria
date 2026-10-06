import Foundation

nonisolated enum WorkState: String, Codable, Sendable {
    case needsYou, failed, working, unknown, done, idle
    static func derive(_ runs: [Run], needsYou: Bool) -> Self {
        if needsYou || runs.contains(where: { $0.state.needsUser }) { return .needsYou }
        if runs.contains(where: { $0.state == .failed }) { return .failed }
        if runs.contains(where: { $0.state.isActive }) { return .working }
        if runs.contains(where: { $0.state == .unknown }) { return .unknown }
        if runs.first?.state == .completed { return .done }
        return .idle
    }
}
nonisolated struct WorkItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case conversation, task }
    let id: String
    var kind: Kind
    var title: String
    var agentID: String?
    var state: WorkState
    var runs: [Run]
    var latestResultSnippet: String
    var lastActivity: Date
    var isPinned: Bool
    var isArchived: Bool
    var isUnread: Bool
    var artifactCount: Int
    var source: String
    var canArchive: Bool
    var route: Route { kind == .task ? .task(String(id.dropFirst(5))) : .conversation(id) }
}
nonisolated enum NeedsYouKind: String, Codable, Sendable { case question, decision, approval, intervention, review }
nonisolated enum RiskTier: String, Codable, Sendable { case low, medium, high }
nonisolated enum Snooze: Codable, Equatable, Sendable {
    case date(Date), atDesk
    func active(at now: Date) -> Bool { switch self { case .date(let date): date > now; case .atDesk: true } }
}
nonisolated struct NeedsYouItem: Identifiable, Hashable, Sendable {
    let id: String
    var kind: NeedsYouKind
    var workItemID: String?
    var agentID: String?
    var request: String
    var context: String?
    var choices: [String]
    var deadline: Date?
    var canRespond: Bool
    var riskTier: RiskTier
    var observedAt: Date
    var runID: String?
    var taskID: String?
    var routineID: String?
    var approval: ApprovalRequest?
    var groupKey: String { "\(kind.rawValue):\(agentID ?? "default"):\(workItemID ?? id)" }
    func expired(at now: Date) -> Bool { deadline.map { $0 <= now } ?? false }
    func actionable(at now: Date) -> Bool { canRespond && !expired(at: now) && kind != .approval }
}
nonisolated enum ResultSnippet {
    static func extract(_ markdown: String, limit: Int = 160) -> String {
        var inCode = false
        for paragraph in markdown.components(separatedBy: "\n\n") {
            let lines = paragraph.components(separatedBy: "\n").filter { line in
                if line.hasPrefix("```") { inCode.toggle(); return false }
                return !inCode && !line.hasPrefix("#") && !line.trimmingCharacters(in: .whitespaces).isEmpty
            }
            if !lines.isEmpty {
                let plain = lines.joined(separator: " ").replacingOccurrences(of: #"[!*_`>]"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
                return String(plain.prefix(limit))
            }
        }
        return ""
    }
}

nonisolated struct AskRoute: Equatable, Sendable {
    var agentID: String
    var matchedAlias: String?
    var candidates: [String] = []
    var isAmbiguous: Bool { candidates.count > 1 }
}
nonisolated enum AskRouter {
    static func resolve(text: String, explicit: String?, agents: [Profile], aliasChoices: [String: String] = [:]) -> AskRoute {
        if let explicit { return AskRoute(agentID: explicit) }
        let input = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var matches: [String: Set<String>] = [:]
        for agent in agents {
            let full = agent.name.lowercased()
            let short = full.replacingOccurrences(of: #"\s+(orchestrator|worker)$"#, with: "", options: .regularExpression)
            for alias in Set([full, short, agent.id.lowercased(), agent.profileKey?.lowercased() ?? full]) where !alias.isEmpty {
                for prefix in [alias + ",", alias + ":", "hey " + alias + " ", "ask " + alias + " to "] {
                    if input.hasPrefix(prefix) { matches[alias, default: []].insert(agent.id) }
                }
            }
        }
        guard let alias = matches.keys.sorted(by: { $0.count > $1.count }).first, let ids = matches[alias] else {
            return AskRoute(agentID: Profile.defaultID)
        }
        let candidates = ids.sorted()
        if candidates.count == 1 { return AskRoute(agentID: candidates[0], matchedAlias: alias) }
        if let chosen = aliasChoices[alias], ids.contains(chosen) { return AskRoute(agentID: chosen, matchedAlias: alias) }
        return AskRoute(agentID: Profile.defaultID, matchedAlias: alias, candidates: candidates)
    }
}
