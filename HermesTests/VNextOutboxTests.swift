import Foundation
import Testing
@testable import Hermes

@MainActor struct VNextOutboxTests {
    @Test func offlineAsksPersistAndNeverExecuteOnReconnect() async throws {
        let env = AppEnvironment.mock(storage: .ephemeral)
        env.connection.apply(.hostStatus(env.simulator!.currentStatus(for: env.connection.activeHostID))); await env.connection.connect(); await env.refreshAll()
        let ask = OutboxAsk(hostID: env.connection.activeHostID, text: "Do not auto execute", configuration: RunConfiguration(profileID: Profile.defaultID, hostID: env.connection.activeHostID))
        try env.outbox.enqueue(ask)
        let count = env.simulator!.conversations.count
        await env.refreshAll()
        #expect(env.simulator!.conversations.count == count)
        #expect(env.outbox.asks.first?.state == .queued)
        let id = try await env.outbox.sendAsk(ask.id, environment: env)
        #expect(env.outbox.asks.first?.state == .confirmed)
        #expect(env.simulator!.conversations[id] != nil)
    }
    @Test func uncertainAskRequiresReceiptCheckThenExplicitSend() async throws {
        let env = AppEnvironment.mock(storage: .ephemeral)
        env.connection.apply(.hostStatus(env.simulator!.currentStatus(for: env.connection.activeHostID))); await env.connection.connect(); await env.refreshAll()
        let ask = OutboxAsk(hostID: env.connection.activeHostID, text: "Safe fixture", configuration: RunConfiguration(profileID: Profile.defaultID, hostID: env.connection.activeHostID))
        try env.outbox.enqueue(ask); env.simulator!.simulation.nextSendUncertain = true
        await #expect(throws: HermesError.self) { _ = try await env.outbox.sendAsk(ask.id, environment: env) }
        #expect(env.outbox.asks.first?.state == .uncertain)
        await #expect(throws: HermesError.self) { _ = try await env.outbox.sendAsk(ask.id, environment: env) }
        try await env.outbox.checkAsk(ask.id, environment: env)
        #expect(env.outbox.asks.first?.state == .queued)
        #expect(env.simulator!.sentCommands.isEmpty)
        _ = try await env.outbox.sendAsk(ask.id, environment: env)
        #expect(env.outbox.asks.first?.state == .confirmed)
    }
    @Test func offlineCaptureSyncsVerbatimOnlyAfterConfirmation() async throws {
        let env = AppEnvironment.mock(storage: .ephemeral)
        env.connection.apply(.hostStatus(env.simulator!.currentStatus(for: env.connection.activeHostID))); await env.connection.connect(); await env.refreshAll()
        env.simulator!.simulateConnection(.bridgeOffline); env.connection.apply(.hostStatus(env.simulator!.currentStatus(for: env.connection.activeHostID)))
        let capture = CaptureRecord(hostID: env.connection.activeHostID, kind: .note, text: "  Exact\n\n**text**  ")
        try env.outbox.enqueue(capture)
        await env.outbox.syncCaptures(environment: env)
        #expect(env.outbox.captures.first?.state != .confirmed)
        env.simulator!.simulateConnection(nil); env.connection.apply(.hostStatus(env.simulator!.currentStatus(for: env.connection.activeHostID))); await env.connection.reconnect(); env.connection.apply(.hostStatus(env.simulator!.currentStatus(for: env.connection.activeHostID))); await env.refreshAll()
        #expect(env.outbox.captures.first?.state == .confirmed)
        #expect(env.simulator!.savedCaptures[capture.id]?.text == capture.text)
        await env.refreshAll(); #expect(env.simulator!.savedCaptures.count == 1)
    }
    @Test func mediaLivesInProtectedFilesAndCorruptMetadataIsNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OutboxStore(directory: directory)
        let capture = CaptureRecord(hostID: "h", kind: .file, text: "", media: [LocalMedia(name: "note.txt", contentType: "text/plain", data: Data("attachment".utf8))])
        try store.enqueue(capture)
        let restored = OutboxStore(directory: directory)
        #expect(restored.captures.first?.media.first?.data == Data("attachment".utf8))
        let metadata = directory.appendingPathComponent("captures.json")
        #expect(try Data(contentsOf: metadata).count < 1500)
        try Data("corrupt but preserve".utf8).write(to: metadata)
        let broken = OutboxStore(directory: directory)
        #expect(broken.loadError != nil)
        #expect(throws: HermesError.self) { try broken.enqueue(CaptureRecord(hostID: "h", kind: .note, text: "new")) }
        #expect(try String(contentsOf: metadata, encoding: .utf8) == "corrupt but preserve")
    }
    @Test func modelDefaultChangeRevertAndExternalChangeGuard() async throws {
        let env = AppEnvironment.mock(storage: .ephemeral)
        env.connection.apply(.hostStatus(env.simulator!.currentStatus(for: env.connection.activeHostID))); await env.connection.connect(); await env.refreshAll()
        let p = try #require(env.profiles.sorted.first(where: { !$0.isDefault }))
        try await env.agentModels.change(profile: p, to: MockModels.local, confirmed: true, environment: env)
        let changed = try #require(env.profiles.profile(p.id))
        #expect(changed.model == MockModels.local)
        try await env.agentModels.revert(profile: changed, confirmed: true, environment: env)
        #expect(env.profiles.profile(p.id)?.model == p.model)
        #expect(env.agentModels.note(host: env.connection.activeHostID, agent: p.id) == nil)
        try await env.agentModels.change(profile: p, to: MockModels.local, confirmed: true, environment: env)
        try await env.profiles.update(p.id, changes: ProfileChanges(model: MockModels.gpt, confirmExpensiveModel: true))
        await #expect(throws: HermesError.self) { try await env.agentModels.revert(profile: p, confirmed: true, environment: env) }
        #expect(env.profiles.profile(p.id)?.model == MockModels.gpt)
    }
    @Test func replyConfirmationSurvivesEventRemovalAndReviewIsObservable() async throws {
        let env = AppEnvironment.mock(storage: .ephemeral)
        env.connection.apply(.hostStatus(env.simulator!.currentStatus(for: env.connection.activeHostID))); await env.connection.connect(); await env.refreshAll()
        let question = try #require(env.needsYou.all.first(where: { $0.id == "q-expiring" }))
        env.needsYou.retain(question)
        try await env.activity.answerClarification(question.id, answer: "Continue")
        env.activity.apply(.approvalResolved(approvalID: question.id, decision: nil))
        env.needsYou.confirm(question.id)
        #expect(env.needsYou.all.contains { $0.id == question.id })
        #expect(env.needsYou.isConfirmed(question.id))
        env.needsYou.release(question.id)
        #expect(!env.needsYou.all.contains { $0.id == question.id })
        let review = try #require(env.needsYou.all.first(where: { $0.taskID == "t-review" }))
        #expect(review.kind == .review)
        #expect(env.tasks.task("t-review")?.availableTransitions.contains(.completed) == true)
    }
    @Test func lockRequestedWhileMicrophoneArmsSurvivesRelease() async throws {
        let voice = VoiceSession(); voice.start(capture: false, simulated: true)
        voice.move(x: 0, y: -80); voice.release()
        try await Task.sleep(for: .milliseconds(100))
        #expect(voice.phase == .locked)
        voice.cancel(); #expect(voice.phase == .cancelled)
    }
    @Test func cancellationBeforeStartupCannotLeaveMicrophoneRunning() async throws {
        let voice = VoiceSession(); voice.start(capture: false, simulated: true)
        voice.cancel()
        try await Task.sleep(for: .milliseconds(300))
        #expect(voice.phase == .cancelled)
        #expect(!voice.dictation.isRecording)
        #expect(voice.transcript.isEmpty)
        #expect(!voice.canAutoSend)
    }
    @Test func briefVoiceHoldIsDiscardedInsteadOfSending() async throws {
        let voice = VoiceSession(); voice.start(capture: false, simulated: true)
        try await Task.sleep(for: .milliseconds(100)); voice.release()
        try await Task.sleep(for: .seconds(2))
        #expect(voice.phase == .failed)
        #expect(!voice.canAutoSend)
    }
    @Test func voiceCancellationCannotProduceSendableTranscript() async throws {
        let voice = VoiceSession(); voice.start(capture: false, simulated: true)
        try await Task.sleep(for: .milliseconds(100)); voice.move(x: -100, y: 0)
        #expect(voice.phase == .cancelled); #expect(voice.transcript.isEmpty); #expect(!voice.canAutoSend)
        try await Task.sleep(for: .milliseconds(100)); #expect(voice.transcript.isEmpty)
    }
}
