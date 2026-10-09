import Foundation
import Testing
@testable import Hermes

@MainActor struct ApprovalTests {
    @Test func mapsOfferedChoicesAndState() throws {
        let data = Data("""
        {"id":"a","kind":"approval","state":"pending","can_respond":true,"expires_at":4102444800,
         "details":{"command":"rm fixture.txt","choices":["once","deny","always"],"allow_permanent":false,"on_timeout":"Blocked"}}
        """.utf8)
        let json = try JSONDecoder().decode(BridgeJSON.self, from: data)
        let approval = BridgeMapping.approval(json)
        #expect(approval.kind == .command)
        #expect(approval.risk == nil)
        #expect(approval.effectiveAvailability(remoteApprovalsSupported: true) == .actionable)
        #expect(approval.offeredDecisions == [.approveOnce, .deny])
        #expect(!approval.allowsSessionApproval)
        #expect(approval.timeoutExplanation == "If you don't answer, Hermes blocks this command.")
        #expect(!approval.effectiveAvailability(remoteApprovalsSupported: false).isActionable)
    }
    @Test func nullExpiryIsActionableAndCancellationWithdraws() throws {
        for state in ["pending", "expired"] {
            let json = try JSONDecoder().decode(BridgeJSON.self, from: Data("""
            {"id":"a","kind":"approval","state":"\(state)","can_respond":true,"expires_at":null,
             "observed_at":1,"details":{"command":"rm fixture.txt","choices":["once","deny"]}}
            """.utf8))
            let approval = BridgeMapping.approval(json)
            #expect(approval.expiresAt == nil)
            #expect(approval.effectiveAvailability(remoteApprovalsSupported: true) == (state == "pending" ? .actionable : .expired))
            #expect(approval.timeoutExplanation == "If you don't answer, Hermes blocks this command.")
        }
    }
    @Test func staleClarificationRemovesItemAndRefreshes() async throws {
        let backend = MockHermesBackend()
        backend.simulation.latency = .instant
        var question = try #require(backend.approvals["a-rm"])
        question.clarificationQuestion = "Proceed?"
        question.expiresAt = nil
        backend.approvals[question.id] = question
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActivityStore(client: .mock(backend), cache: SnapshotCache(directory: directory))
        await store.refresh()
        #expect(store.approvals[question.id] != nil)
        let refreshedAt = store.updatedAt
        backend.simulation.staleNextClarification = true
        await #expect(throws: HermesError.staleAttention) { try await store.answerClarification(question.id, answer: "Yes") }
        #expect(store.approvals[question.id] == nil)
        #expect(store.updatedAt != refreshedAt)
        #expect(HermesError.staleAttention.errorDescription == "No longer pending. Refreshed.")
    }
    @Test func mockDecisionCannotBeRepeated() async throws {
        let backend = MockHermesBackend()
        backend.simulation.latency = .instant
        try await backend.resolveApproval(id: "a-rm", decision: .approveOnce)
        #expect(backend.approvals["a-rm"] == nil)
        await #expect(throws: HermesError.staleAttention) { try await backend.resolveApproval(id: "a-rm", decision: .deny) }
    }
    @Test func pendingApprovalResolvesByRunWithoutAnApprovalID() async throws {
        let backend = MockHermesBackend()
        backend.simulation.latency = .instant
        backend.runs["r-ios"]?.pendingApprovalID = nil
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActivityStore(client: .mock(backend), cache: SnapshotCache(directory: directory))
        await store.refresh()
        let run = try #require(store.run("r-ios"))
        #expect(run.state == .waitingForApproval)
        #expect(run.pendingApprovalID == nil)
        #expect(store.pendingApproval(for: run)?.id == "a-rm")
        try await store.resolve("a-rm", decision: .deny)
        #expect(store.pendingApproval(for: run) == nil)
    }
    @Test func staleRefreshRemovesCard() async throws {
        let backend = MockHermesBackend()
        backend.simulation.latency = .instant
        backend.simulation.staleNextApproval = true
        await #expect(throws: HermesError.staleAttention) { try await backend.resolveApproval(id: "a-rm", decision: .approveOnce) }
        #expect(!(try await backend.pendingApprovals()).contains { $0.id == "a-rm" })
    }
}
