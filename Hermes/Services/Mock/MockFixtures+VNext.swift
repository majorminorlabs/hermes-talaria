import Foundation
extension MockFixtures {
    mutating func addVNext(now: Date) {
        for (id,name) in [("research-orchestrator", "Research Orchestrator"), ("research-worker", "Research Worker")] {
            profiles.append(Profile(id: id, name: name, role: "Research", summary: "Research agent", tint: .indigo, model: MockModels.sonnet, status: .idle, hostID: MockID.studio, isDefault: false, skillIDs: [], toolsets: [], mcpServerIDs: []))
        }
        for (suffix,choices,seconds) in [("choices",["Grainger", "Ferguson"], 240), ("free",[],240), ("expiring",["Continue", "Stop"],45)] {
            let cid = "c-question-" + suffix, rid = "r-question-" + suffix, aid = "q-" + suffix
            conversations.append(Conversation(id: cid, title: "Find replacement compressor part · " + suffix, profileID: "research-worker", hostID: MockID.studio, source: .app, createdAt: now, lastActivity: now, preview: "Waiting for your answer", activeRunID: rid, isPinned: false, messageCount: 1))
            runs.append(Run(id: rid, title: "Find replacement compressor part", profileID: "research-worker", conversationID: cid, hostID: MockID.studio, trigger: .chat, state: .waitingForInput, startedAt: now.addingTimeInterval(-120), currentAction: "Waiting for your answer", events: [RunEvent(sequence: 1, kind: .started, title: "Started")], pendingApprovalID: aid))
            approvals.append(ApprovalRequest(id: aid, runID: rid, conversationID: cid, profileID: "research-worker", kind: .tool, summary: "Which supplier should I contact first?", paths: [], risk: .low, requestedAt: now, expiresAt: now.addingTimeInterval(Double(seconds)), availability: .actionable, allowsSessionApproval: false, clarificationQuestion: suffix == "free" ? "What part number should I search for?" : "Which supplier should I contact first?", clarificationChoices: choices))
        }
        conversations.append(Conversation(id: "c-unknown", title: "Check deployment outcome", profileID: MockID.caddy, hostID: MockID.studio, source: .app, createdAt: now, lastActivity: now, preview: "Outcome unknown", isPinned: false, messageCount: 1))
        runs.append(Run(id: "r-unknown", title: "Check deployment outcome", profileID: MockID.caddy, conversationID: "c-unknown", hostID: MockID.studio, trigger: .chat, state: .unknown, startedAt: now.addingTimeInterval(-300), events: [RunEvent(sequence: 1, kind: .started, title: "Started")], retrySupported: false))
        tasks.append(HermesTask(id: "t-review", title: "Review supplier shortlist", summary: "Check the shortlist before dispatcher follow-up.", status: .review, assigneeProfileID: "research-worker", priority: .normal, hostID: MockID.studio, createdAt: now, updatedAt: now, dependencyIDs: [], runIDs: [], activity: [], sourceState: "review", supportedTransitions: [.completed, .ready]))
        if let i = runs.firstIndex(where: { $0.state == .running }) {
            runs[i].append(RunEvent(kind: .tool, title: "Delegate research", status: .active, toolKind: .delegate))
        }
    }
}
