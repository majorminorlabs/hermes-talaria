import Testing
@testable import Hermes

@MainActor struct HeldVoiceAskTests {
    private func connected() async -> AppEnvironment {
        let env = AppEnvironment.mock(storage: .ephemeral)
        env.connection.apply(.hostStatus(env.simulator!.currentStatus(for: env.connection.activeHostID)))
        await env.connection.connect(); await env.refreshAll()
        return env
    }
    @Test func releaseSendsWithoutComposerReview() async {
        let env = await connected()
        env.preferences.reviewVoiceBeforeSending = true
        await env.sendHeldVoiceAsk(text: "Summarize the current work", seed: AskSeed())
        #expect(env.outbox.asks.count == 1)
        #expect(env.outbox.asks.first?.state == .confirmed)
        #expect(env.outbox.asks.first?.configuration.profileID == Profile.defaultID)
        #expect(env.router.askSeed == nil)
    }
    @Test func spokenAgentRoutesVerbatim() async {
        let env = await connected()
        let words = "Research Worker, find suppliers"
        await env.sendHeldVoiceAsk(text: words, seed: AskSeed())
        #expect(env.outbox.asks.first?.configuration.profileID == "research-worker")
        #expect(env.outbox.asks.first?.text == words)
        #expect(env.outbox.asks.first?.state == .confirmed)
    }
    @Test func ambiguityNeedsChoiceBeforeSending() async {
        let env = await connected()
        await env.sendHeldVoiceAsk(text: "Research, find suppliers", seed: AskSeed())
        #expect(env.outbox.asks.isEmpty)
        #expect(env.router.askSeed?.text == "Research, find suppliers")
        #expect(env.router.askSeed?.voice == false)
    }
    @Test func offlineKeepsDraftAndEmptySpeechDoesNothing() async {
        let env = AppEnvironment.mock(storage: .ephemeral)
        await env.sendHeldVoiceAsk(text: " \n", seed: AskSeed())
        #expect(env.router.askSeed == nil)
        await env.sendHeldVoiceAsk(text: "Keep this transcript", seed: AskSeed())
        #expect(env.router.askSeed?.text == "Keep this transcript")
        #expect(env.outbox.asks.isEmpty)
    }
    @Test func uncertainDeliveryKeepsReceiptWithoutOpeningDuplicateDraft() async {
        let env = await connected()
        env.simulator!.simulation.nextSendUncertain = true
        await env.sendHeldVoiceAsk(text: "Single voice request", seed: AskSeed())
        #expect(env.outbox.asks.count == 1)
        #expect(env.outbox.asks.first?.state == .uncertain)
        #expect(env.router.askSeed == nil)
        await env.refreshAll()
        #expect(env.outbox.asks.count == 1)
        #expect(env.outbox.asks.first?.state == .uncertain)
    }
}
