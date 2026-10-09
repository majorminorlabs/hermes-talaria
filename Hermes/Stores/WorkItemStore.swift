import Foundation

/// Durable UI facts are host-scoped and independent of Hermes's canonical data.
@Observable final class SeenStore {
    private let defaults: UserDefaults
    private(set) var revision = 0
    init(defaults: UserDefaults) { self.defaults = defaults }
    private func key(_ host: String) -> String { "vnext.seen.\(host)" }
    func date(_ id: String, host: String) -> Date? { (defaults.dictionary(forKey: key(host))?[id] as? Double).map(Date.init(timeIntervalSince1970:)) }
    func mark(_ id: String, at date: Date, host: String) {
        var map = defaults.dictionary(forKey: key(host)) ?? [:]; map[id] = date.timeIntervalSince1970
        defaults.set(map, forKey: key(host)); revision += 1
    }
    func seed(_ items: [WorkItem], host: String) {
        guard !defaults.bool(forKey: key(host) + ".seeded"), !items.isEmpty else { return }
        for item in items { mark(item.id, at: item.lastActivity, host: host) }
        defaults.set(true, forKey: key(host) + ".seeded")
    }
}
@Observable final class SnoozeStore {
    private let defaults: UserDefaults
    private(set) var revision = 0
    init(defaults: UserDefaults) { self.defaults = defaults }
    private func key(_ host: String) -> String { "vnext.snooze.\(host)" }
    func values(host: String) -> [String: Snooze] {
        guard let data = defaults.data(forKey: key(host)) else { return [:] }
        return (try? JSONDecoder().decode([String: Snooze].self, from: data)) ?? [:]
    }
    func set(_ value: Snooze?, id: String, host: String) {
        var map = values(host: host); map[id] = value
        defaults.set(try? JSONEncoder().encode(map), forKey: key(host)); revision += 1
    }
    func dismiss(_ id: String, host: String) {
        var ids = Set(defaults.stringArray(forKey: key(host) + ".dismissed") ?? [])
        ids.insert(id); defaults.set(Array(ids), forKey: key(host) + ".dismissed"); revision += 1
    }
    func dismissed(_ id: String, host: String) -> Bool { (defaults.stringArray(forKey: key(host) + ".dismissed") ?? []).contains(id) }
}
@Observable final class NeedsYouStore {
    let activity: ActivityStore
    let tasks: TaskStore
    let home: HomeStore
    let routines: RoutineStore
    let connection: ConnectionStore
    let snoozes: SnoozeStore
    let outbox: OutboxStore
    init(activity: ActivityStore, tasks: TaskStore, home: HomeStore, routines: RoutineStore, connection: ConnectionStore, snoozes: SnoozeStore, outbox: OutboxStore) {
        self.activity = activity; self.tasks = tasks; self.home = home; self.routines = routines; self.connection = connection; self.snoozes = snoozes; self.outbox = outbox
    }
    private var retained: [String: NeedsYouItem] = [:]
    private var confirmedIDs: Set<String> = []
    func retain(_ item: NeedsYouItem) { retained[item.id] = item }
    func confirm(_ id: String) { confirmedIDs.insert(id) }
    func isConfirmed(_ id: String) -> Bool { confirmedIDs.contains(id) }
    func release(_ id: String) { retained[id] = nil; confirmedIDs.remove(id) }
    var all: [NeedsYouItem] {
        var items = activity.approvals.values.map { a in
            NeedsYouItem(id: a.id, kind: a.isClarification ? ((a.clarificationChoices ?? []).isEmpty ? .question : .decision) : .approval,
                workItemID: a.conversationID, agentID: a.profileID, request: a.clarificationQuestion ?? a.summary,
                context: a.reason, choices: a.clarificationChoices ?? [], deadline: a.expiresAt,
                canRespond: a.effectiveAvailability(remoteApprovalsSupported: connection.supports(.approvals)).isActionable, riskTier: .low, observedAt: a.requestedAt,
                runID: a.runID, approval: a)
        }
        for ask in outbox.asks where ask.hostID == connection.activeHostID && ask.state == .uncertain {
            items.append(NeedsYouItem(id: "outbox:\(ask.id)", kind: .intervention, workItemID: ask.conversationID,
                agentID: ask.configuration.profileID, request: "Not sure this Ask was sent", context: "Check its receipt before sending again.", choices: [], canRespond: true, riskTier: .low, observedAt: ask.createdAt))
        }
        for run in activity.runs.values where run.state == .failed || run.state == .unknown {
            items.append(NeedsYouItem(id: "run:\(run.id)", kind: .intervention, workItemID: run.conversationID,
                agentID: run.profileID, request: run.state == .unknown ? "Outcome unknown: Talaria didn't see this finish" : "Work failed: \(StatusCopy.runFailure(run.failureReason).message ?? "No failure details reported")",
                choices: [], canRespond: run.canRetry && run.state != .unknown, riskTier: .low,
                observedAt: run.endedAt ?? run.startedAt, runID: run.id))
        }
        for task in tasks.tasks.values where task.status == .blocked || task.status == .review {
            items.append(NeedsYouItem(id: "task:\(task.id)", kind: task.status == .review ? .review : .intervention,
                workItemID: "task:\(task.id)", agentID: task.assigneeProfileID,
                request: task.status == .review ? "Review: \(task.title)" : "Blocked: \(task.blockReason ?? task.title)",
                context: task.summary, choices: [], canRespond: !task.availableTransitions.isEmpty,
                riskTier: task.status == .review ? .low : .medium, observedAt: task.updatedAt, taskID: task.id))
        }
        for routine in routines.sorted where routine.lastResult?.outcome == .failed && !items.contains(where: { $0.runID == routine.lastResult?.runID && $0.runID != nil }) {
            items.append(NeedsYouItem(id: "routine:\(routine.id):\(routine.lastResult?.date.timeIntervalSince1970 ?? 0)", kind: .intervention,
                agentID: routine.profileID, request: "Routine failed: \(routine.name)", context: routine.lastResult?.summary,
                choices: [], canRespond: connection.supports(.cron), riskTier: .low, observedAt: routine.lastResult!.date, routineID: routine.id))
        }
        for item in home.summary?.attention ?? [] where item.kind == .hostIssue || item.kind == .authentication {
            items.append(NeedsYouItem(id: item.id, kind: .intervention, agentID: item.profileID,
                request: item.title, context: item.detail, choices: [], canRespond: true, riskTier: .low, observedAt: item.date))
        }
        for item in retained.values where !items.contains(where: { $0.id == item.id }) { items.append(item) }
        return items.filter { !snoozes.dismissed($0.id, host: connection.activeHostID) && ($0.deadline.map { $0.addingTimeInterval(600) > .now } ?? true) }.sorted {
            func rank(_ i: NeedsYouItem) -> Int { i.deadline != nil ? 0 : i.actionable(at: .now) ? 1 : i.kind == .approval ? 2 : 3 }
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            if let a = $0.deadline, let b = $1.deadline { return a < b }
            return $0.observedAt > $1.observedAt
        }
    }
    var visible: [NeedsYouItem] {
        _ = snoozes.revision
        let parked = snoozes.values(host: connection.activeHostID)
        return all.filter { !(parked[$0.id]?.active(at: .now) ?? false) }
    }
    var snoozed: [NeedsYouItem] { let ids = Set(visible.map(\.id)); return all.filter { !ids.contains($0.id) } }
    var actionableCount: Int { connection.connection.isConnected ? visible.filter { !isConfirmed($0.id) && $0.actionable(at: .now) }.count : 0 }
    var groups: [[NeedsYouItem]] {
        var result: [[NeedsYouItem]] = []
        for item in visible {
            if let index = result.firstIndex(where: { $0.first?.groupKey == item.groupKey }) { result[index].append(item) }
            else { result.append([item]) }
        }
        return result
    }
}
@Observable final class WorkItemStore {
    let conversations: ConversationListStore
    let activity: ActivityStore
    let tasks: TaskStore
    let needs: NeedsYouStore
    let seen: SeenStore
    let connection: ConnectionStore
    init(conversations: ConversationListStore, activity: ActivityStore, tasks: TaskStore, needs: NeedsYouStore, seen: SeenStore, connection: ConnectionStore) {
        self.conversations = conversations; self.activity = activity; self.tasks = tasks; self.needs = needs; self.seen = seen; self.connection = connection
    }
    var items: [WorkItem] {
        _ = seen.revision
        let pending = Set(needs.all.filter { !needs.isConfirmed($0.id) && !$0.expired(at: .now) }.compactMap(\.workItemID))
        var result = conversations.sorted.map { c in
            let runs = activity.runs.values.filter { $0.conversationID == c.id }.sorted { $0.startedAt > $1.startedAt }
            let lastAssistant = conversations.transcripts[c.id]?.last { $0.role == .assistant }
            let latestResult = runs.first { $0.state.isTerminal }?.endedAt ?? lastAssistant?.createdAt
            let state = WorkState.derive(runs, needsYou: pending.contains(c.id))
            return WorkItem(id: c.id, kind: .conversation, title: c.title, agentID: c.botID ?? c.profileID, state: state, runs: runs,
                latestResultSnippet: ResultSnippet.extract(lastAssistant?.plainText ?? runs.first?.resultSummary ?? c.preview),
                lastActivity: max(c.lastActivity, runs.first?.endedAt ?? runs.first?.startedAt ?? c.lastActivity),
                isPinned: c.isPinned, isArchived: c.isArchived == true,
                isUnread: latestResult.map { $0 > (seen.date(c.id, host: connection.activeHostID) ?? .distantPast) } ?? false,
                artifactCount: lastAssistant?.parts.filter { if case .file = $0 { true } else if case .image = $0 { true } else { false } }.count ?? 0,
                source: c.source.label, canArchive: c.isBotChat != true)
        }
        result += tasks.tasks.values.map { t in
            WorkItem(id: "task:\(t.id)", kind: .task, title: t.title, agentID: t.assigneeProfileID,
                state: pending.contains("task:\(t.id)") ? .needsYou : t.status == .inProgress ? .working : t.status == .completed ? .done : t.status == .failed ? .failed : .idle,
                runs: activity.runs(forTask: t.id), latestResultSnippet: ResultSnippet.extract(t.summary), lastActivity: t.updatedAt,
                isPinned: false, isArchived: t.status == .archived,
                isUnread: (t.completedAt ?? .distantPast) > (seen.date("task:\(t.id)", host: connection.activeHostID) ?? .distantPast), artifactCount: 0, source: "Task", canArchive: false)
        }
        return result.sorted { $0.lastActivity > $1.lastActivity }
    }
    func seedSeen() { seen.seed(items, host: connection.activeHostID) }
    func markSeen(_ id: String) { seen.mark(id, at: .now, host: connection.activeHostID) }
}
