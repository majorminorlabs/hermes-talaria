import Foundation
import Testing
import TalariaActivityShared
@testable import Hermes

struct LiveActivityTests {
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
