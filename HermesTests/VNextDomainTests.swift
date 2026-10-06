import Foundation
import Testing
@testable import Hermes

@MainActor struct VNextDomainTests {
    @Test func unknownIsAnOutcomeNotAConnectionState() {
        var run = MockFixtures.standard().runs[0]
        run.state = .unknown
        #expect(!run.state.isActive)
        #expect(!run.state.isTerminal)
        #expect(!run.canRetry)
        #expect(run.displayState(isLive: false) == .unknown)
        #expect(WorkState.derive([run], needsYou: false) == .unknown)
        run.state = .running
        #expect(run.displayState(isLive: false) == .disconnected)
    }
    @Test func workPriorityAndResultExtraction() {
        var a = MockFixtures.standard().runs[0]
        a.state = .running
        var b = a; b.state = .failed
        #expect(WorkState.derive([a,b], needsYou: false) == .failed)
        #expect(WorkState.derive([a,b], needsYou: true) == .needsYou)
        #expect(ResultSnippet.extract("# Heading\n\n```swift\nignored\n```\n\nFound **three** suppliers.") == "Found three suppliers.")
    }
    @Test func routingIsExplicitDeterministicAndVerbatim() {
        var agents = MockFixtures.standard().profiles.filter { !$0.id.hasPrefix("research-") }
        var a = agents[0]; a = Profile(id: "research-o", name: "Research Orchestrator", role: a.role, summary: a.summary, tint: a.tint, model: a.model, status: a.status, hostID: a.hostID, isDefault: false, skillIDs: [], toolsets: [], mcpServerIDs: [])
        var b = a; b = Profile(id: "research-w", name: "Research Worker", role: a.role, summary: a.summary, tint: a.tint, model: a.model, status: a.status, hostID: a.hostID, isDefault: false, skillIDs: [], toolsets: [], mcpServerIDs: [])
        agents += [a,b]
        #expect(AskRouter.resolve(text: "Research, find this", explicit: nil, agents: agents).isAmbiguous)
        #expect(AskRouter.resolve(text: "Research, find this", explicit: nil, agents: agents, aliasChoices: ["research":a.id]).agentID == a.id)
        #expect(AskRouter.resolve(text: "Research Worker: find this", explicit: nil, agents: agents).agentID == b.id)
        #expect(AskRouter.resolve(text: "Research, find this", explicit: b.id, agents: agents).agentID == b.id)
        #expect(AskRouter.resolve(text: "find research papers", explicit: nil, agents: agents).agentID == Profile.defaultID)
    }
    @Test func snoozeAndSeenAreHostScoped() {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        let seen = SeenStore(defaults: d), snooze = SnoozeStore(defaults: d)
        seen.mark("c", at: .now, host: "a")
        #expect(seen.date("c", host: "a") != nil)
        #expect(seen.date("c", host: "b") == nil)
        snooze.set(.atDesk, id: "q", host: "a")
        #expect(snooze.values(host: "a")["q"]?.active(at: .now) == true)
        #expect(snooze.values(host: "b").isEmpty)
        #expect(!Snooze.date(.now.addingTimeInterval(-1)).active(at: .now))
    }
    @Test func newResultsAfterInitialSyncAreUnreadUntilOpened() {
        let env = AppEnvironment.mock(storage: .ephemeral)
        env.work.seedSeen()
        let c = Conversation(id: "new-unopened-thread", title: "New work", profileID: Profile.defaultID, hostID: env.connection.activeHostID, source: .app, createdAt: .now, lastActivity: .now, preview: "Result", isPinned: false, messageCount: 2)
        env.conversations.apply(.conversationUpserted(c))
        var run = MockFixtures.standard().runs[0]
        run.conversationID = c.id
        run.state = .completed; run.endedAt = .now
        env.activity.apply(.runUpserted(run))
        #expect(env.work.items.first { $0.id == c.id }?.isUnread == true)
        env.work.markSeen(c.id)
        #expect(env.work.items.first { $0.id == c.id }?.isUnread == false)
    }
    @Test func terminalRunsRejectStaleRegressionAndRequireExplicitCompletion() {
        let env = AppEnvironment.mock(storage: .ephemeral)
        var r = MockFixtures.standard().runs[0]
        r.state = .cancelled; r.events = [RunEvent(sequence: 10, kind: .cancelled, title: "Stopped")]
        env.activity.apply(.runUpserted(r))
        r.state = .running; r.events = [RunEvent(sequence: 11, kind: .output, title: "Snapshot")]
        env.activity.apply(.runUpserted(r))
        #expect(env.activity.run(r.id)?.state == .cancelled)
        r.state = .completed
        env.activity.apply(.runUpserted(r))
        #expect(env.activity.run(r.id)?.state == .cancelled)
        r.events = [RunEvent(sequence: 12, kind: .completed, title: "Done")]
        env.activity.apply(.runUpserted(r))
        #expect(env.activity.run(r.id)?.state == .completed)
        #expect(env.activity.run(r.id)?.events.last?.title.contains("after you stopped") == true)
    }
}
