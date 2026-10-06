import Foundation
@preconcurrency import ActivityKit
import Testing
import TalariaActivityShared
@testable import Hermes

struct LiveActivityTests {
    @Test @MainActor func staleAggregateIsReusedAndOldCardsAreNotSelectedForNewWork() {
        let snapshots: [HermesLiveActivityController.ActivitySnapshot] = [
            .init(id: "old", state: .ended, isDemo: false),
            .init(id: "stale", state: .stale, isDemo: false),
            .init(id: "duplicate", state: .active, isDemo: false),
            .init(id: "demo", state: .active, isDemo: true)
        ]
        #expect(HermesLiveActivityController.retainedID(snapshots: snapshots, currentID: "stale", demo: false, allowEnded: false) == "stale")
        #expect(HermesLiveActivityController.retainedID(snapshots: snapshots, currentID: nil, demo: false, allowEnded: false) == "stale")
        #expect(HermesLiveActivityController.retainedID(snapshots: Array(snapshots.prefix(1)), currentID: "old", demo: false, allowEnded: false) == nil)
        #expect(HermesLiveActivityController.retainedID(snapshots: Array(snapshots.prefix(1)), currentID: "old", demo: false, allowEnded: true) == "old")
        #expect(HermesLiveActivityController.retainedID(snapshots: snapshots, currentID: "stale", demo: true, allowEnded: false) == "demo")
    }

    @Test @MainActor func uncertainOutcomesAreNotPresentedAsBlockedActiveWork() {
        let fixtures = MockFixtures.standard()
        let client = HermesClient.mock(MockHermesBackend(fixtures: fixtures))
        let profiles = ProfileStore(client: client, cache: SnapshotCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let runs = RunState.allCases.map { state in
            Run(id: state.rawValue, title: state.rawValue, hostID: "studio", trigger: .chat, state: state, startedAt: .now, events: [])
        }
        let state = HermesLiveActivityController.project(runs: runs, profiles: profiles)
        #expect(Set(state.runs.map(\.id)) == Set(["queued", "running", "waitingForApproval", "waitingForInput", "steeringPending", "stopping"]))
        #expect(state.activeCount == 6)
        #expect(state.worstState == .needsInput)
        #expect(!state.runs.contains { $0.state == .blocked })
        #expect(HermesLiveActivityController.project(runs: runs.filter { $0.state == .unknown || $0.state == .disconnected }, profiles: profiles).activeCount == 0)
    }

    @Test func aggregatePriorityAndCompletedRuns() {
        var state = HermesActivityFixtures.frame(2)
        #expect(state.activeCount == 3)
        #expect(state.worstState == .needsInput)
        #expect(state.displayRuns.first?.botName == "Ops")
        state.runs[0].state = .blocked
        #expect(state.worstState == .blocked)
        state.runs[0].state = .done
        #expect(state.activeCount == 2)
        #expect(state.worstState == .needsInput)
        #expect(!state.displayRuns.contains { $0.id == "demo-coder" })
    }
    @Test func filmingSequenceIsRepeatable() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let states = HermesActivityFixtures.offsets.indices.map { HermesActivityFixtures.frame($0, at: start.addingTimeInterval(HermesActivityFixtures.offsets[$0])) }
        #expect(states.map(\.activeCount) == [1, 2, 3, 3, 2, 0])
        #expect(states.map(\.worstState) == [.running, .running, .needsInput, .running, .running, .done])
        #expect(states.last?.label == "All done")
        #expect(states[2].runs[2].url.absoluteString == "talaria://thread/demo-ops")
        #expect(states[3].runs[2].detail == "step 2/2")
        let roundTrip = try JSONDecoder().decode(HermesActivityAttributes.ContentState.self, from: JSONEncoder().encode(states[2]))
        #expect(roundTrip == states[2])
        #expect(states[2] == HermesActivityFixtures.frame(2, at: start.addingTimeInterval(7)))
    }
    @Test @MainActor func threadsLinkOpensThreadsWithoutTouchingOtherPaths() {
        let router = AppRouter()
        router.nowPath = [.studio]
        router.threadsPath = [.board]
        router.handle(HermesActivityAttributes.ContentState.threadsURL)
        #expect(router.selectedTab == .threads)
        #expect(router.threadsPath.isEmpty)
        #expect(router.nowPath == [.studio])
    }
}
