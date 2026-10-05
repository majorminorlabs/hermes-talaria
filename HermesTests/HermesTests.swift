import Foundation
import Testing
import Speech
@testable import Hermes

@MainActor
struct MarkdownParserTests {
    @Test func parsesBlocks() {
        let blocks = MarkdownParser.parse("""
        ## Title

        Some **bold** text
        across lines.

        - one
        - two

        1. first
        2. second

        > quoted

        ```swift
        let x = 1
        ```

        | A | B |
        |:--|--:|
        | 1 | 2 |
        """)
        #expect(blocks.count == 7)
        #expect(blocks[0] == .heading(level: 2, text: "Title"))
        #expect(blocks[1] == .paragraph("Some **bold** text\nacross lines."))
        guard case .list(false, let bullets) = blocks[2] else { Issue.record("expected bullets"); return }
        #expect(bullets.map(\.text) == ["one", "two"])
        guard case .list(true, let numbered) = blocks[3] else { Issue.record("expected ordered list"); return }
        #expect(numbered.map(\.marker) == ["1.", "2."])
        #expect(blocks[4] == .quote("quoted"))
        #expect(blocks[5] == .code(language: "swift", code: "let x = 1"))
        guard case .table(let table) = blocks[6] else { Issue.record("expected table"); return }
        #expect(table.header == ["A", "B"])
        #expect(table.alignments == [.leading, .trailing])
        #expect(table.rows == [["1", "2"]])
    }

    @Test func unterminatedFenceRendersAsCodeWhileStreaming() {
        let blocks = MarkdownParser.parse("Here:\n\n```python\nprint('hi')")
        #expect(blocks.last == .code(language: "python", code: "print('hi')"))
    }

    @Test func taskListItems() {
        let blocks = MarkdownParser.parse("- [x] done\n- [ ] todo")
        guard case .list(_, let items) = blocks.first else { Issue.record("expected list"); return }
        #expect(items.map(\.checked) == [true, false])
    }
}

@MainActor
struct FormatTests {
    @Test func elapsed() {
        #expect(Format.elapsed(42) == "42s")
        #expect(Format.elapsed(222) == "3m 42s")
        #expect(Format.elapsed(720) == "12m")
        #expect(Format.elapsed(3_900) == "1h 05m")
    }

    @Test func tokens() {
        #expect(Format.tokens(950) == "950")
        #expect(Format.tokens(38_210) == "38.2k")
        #expect(Format.tokens(1_204_000) == "1.2M")
    }
}

@MainActor
struct DomainTests {
    @Test func stepsListPendingLast() {
        var run = MockFixtures.standard().runs.first { $0.id == "r-bench" }!
        run.append(RunEvent(kind: .tool, title: "Late tool", status: .active, toolKind: .code))
        let steps = run.steps
        #expect(steps.last?.status == .pending)
        #expect(steps.firstIndex { $0.title == "Late tool" }! < steps.firstIndex { $0.status == .pending }!)
    }

    @Test func appendAssignsIncreasingSequence() {
        var run = MockFixtures.sequenced(MockFixtures.standard().runs.first { $0.id == "r-ios" }!)
        let before = run.lastSequence
        run.append(RunEvent(kind: .steering, title: "Instruction", detail: "Skip tests"))
        #expect(run.lastSequence == before + 1)
    }

    @Test func approvalAvailability() {
        let approvals = MockFixtures.standard().approvals
        let actionable = approvals.first { $0.id == "a-rm" }!
        let hostOnly = approvals.first { $0.id == "a-index" }!
        #expect(actionable.effectiveAvailability(remoteApprovalsSupported: true).isActionable)
        #expect(!actionable.effectiveAvailability(remoteApprovalsSupported: false).isActionable)
        #expect(!hostOnly.effectiveAvailability(remoteApprovalsSupported: true).isActionable)

        var expiring = actionable
        expiring.expiresAt = .now.addingTimeInterval(-1)
        #expect(expiring.effectiveAvailability(remoteApprovalsSupported: true) == .expired)
    }

    @Test func degradedConnectionShowsActiveRunsAsDisconnected() {
        let run = MockFixtures.standard().runs.first { $0.id == "r-bench" }!
        #expect(run.displayState(isLive: false) == .disconnected)
        #expect(run.displayState(isLive: true) == .running)
    }
}

@MainActor
struct MockBackendTests {
    private func makeBackend() -> MockHermesBackend {
        let simulation = SimulationControls()
        simulation.latency = .instant
        simulation.runSpeed = 50
        return MockHermesBackend(simulation: simulation)
    }

    @Test func homeSummaryAggregatesAttention() async throws {
        let backend = makeBackend()
        let summary = try await backend.homeSummary()
        #expect(summary.activeRuns.count == 4)
        #expect(summary.attention.contains { $0.kind == .approval })
        #expect(summary.attention.contains { $0.kind == .blockedTask })
        #expect(summary.attention.contains { $0.kind == .failedRun })
    }

    @Test func unsupportedCapabilityThrows() async {
        let backend = makeBackend()
        backend.simulation.disabledCapabilities = [.kanban]
        await #expect(throws: HermesError.unsupported(.kanban)) {
            _ = try await backend.listTasks()
        }
    }

    @Test func offlineBridgeThrowsUnreachable() async {
        let backend = makeBackend()
        backend.simulateConnection(.bridgeOffline)
        await #expect(throws: HermesError.bridgeUnreachable) {
            _ = try await backend.listRuns()
        }
    }

    @Test func nonActionableApprovalCannotBeResolvedRemotely() async {
        let backend = makeBackend()
        await #expect(throws: HermesError.self) {
            try await backend.resolveApproval(id: "a-index", decision: .approveOnce)
        }
    }

    @Test func approvingResumesRun() async throws {
        let backend = makeBackend()
        backend.startSimulation()
        try await Task.sleep(for: .milliseconds(50))
        try await backend.resolveApproval(id: "a-rm", decision: .approveOnce)
        try await Task.sleep(for: .seconds(2))
        let run = try #require(backend.runs["r-ios"])
        #expect(run.state == .completed)
        #expect(run.events.contains { $0.kind == .approvalResolved })
    }

    @Test func replayDeliversMissedEvents() async throws {
        let backend = makeBackend()
        let first = backend.subscribe(after: nil)
        backend.log(.info, .app, "one")
        var iterator = first.makeAsyncIterator()
        let cursor = try #require(await iterator.next()?.cursor)
        backend.log(.info, .app, "two")
        backend.log(.info, .app, "three")
        var replay = backend.subscribe(after: cursor).makeAsyncIterator()
        var messages: [String] = []
        for _ in 0..<2 {
            if case .log(let entry) = await replay.next()?.event { messages.append(entry.message) }
        }
        #expect(messages == ["two", "three"])
    }
}


@MainActor
struct ComposerDictationTests {
    @Test func speechAuthorizationCallbackOnBackgroundQueue() async {
        let status = await ComposerDictation.speechAuthorization { callback in
            DispatchQueue.global().async { callback(.authorized) }
        }
        #expect(status == .authorized)
    }
}
