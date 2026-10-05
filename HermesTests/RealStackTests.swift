import Foundation
import Testing
@testable import Hermes

/// Runs in the iOS Simulator test host against actual installed Hermes and the
/// production bridge. Only the model provider is a deterministic local fixture.
@Suite(.serialized)
struct RealStackTests {
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["HERMES_STACK_FIXTURE"] != nil))
    func simulatorInstalledHermesStack() async throws {
        let fixturePath = try #require(ProcessInfo.processInfo.environment["HERMES_STACK_FIXTURE"])
        let data = try Data(contentsOf:URL(fileURLWithPath:fixturePath))
        let fixture = try JSONDecoder().decode(BridgeJSON.self,from:data)
        let url = try #require(fixture["url"].string)
        let token = try #require(fixture["token"].string)
        let controlURL = try #require(fixture["control_url"].string)
        let defaults = try #require(UserDefaults(suiteName:"real-stack-\(UUID().uuidString)"))
        let credentialStore = KeychainBridgeCredentialStore(service:"xyz.majorminor.talaria.stack-\(UUID().uuidString)")
        let host = Host(id:"isolated-local-stack",name:"Local Studio",address:url,network:.custom)
        try credentialStore.save(token,forHostID:host.id)
        defer { try? credentialStore.remove(forHostID:host.id) }
        let client = BridgeHermesClient(credentials:credentialStore,defaults:defaults)
        await client.connect(to:host)
        #expect(try await client.status(hostID:host.id).connection == .connected)
        _ = try await client.listConversations()
        #expect(try await client.listProfiles().contains { $0.id == "default" })
        #expect(try await client.listRoutines().contains { $0.name == "Local scheduled work" })
        #expect(try await client.listTasks().contains { $0.title == "Local Kanban fixture" })
        #expect(try await client.usage(period:.day).sessionCount != nil)
        let aggregate = try await client.homeSummary()
        #expect(aggregate.host.connection == .connected)

        let collector = StackCollector()
        func subscribe(_ target: BridgeHermesClient, after: EventCursor?) -> Task<Void,Never> {
            let stream=target.subscribe(after:after)
            return Task { @MainActor in
                for await envelope in stream {
                    collector.apply(envelope.event)
                    if !envelope.cursor.value.isEmpty { collector.cursor=envelope.cursor }
                    await target.acknowledge(envelope.cursor)
                }
            }
        }
        var subscription = subscribe(client,after:nil)
        defer { subscription.cancel() }
        let config = RunConfiguration(reasoning:.off,hostID:host.id,project:ProjectContext(name:"test",path:"test"))
        let conversation = try await client.createConversation(configuration:config)
        let first = try await client.send(OutgoingMessage(text:"Say a safe local hello"),conversationID:conversation.id,configuration:config)
        try await wait { collector.messages["assistant-\(first.id)"]?.plainText.contains("Local") == true }
        #expect(collector.runs[first.id]?.state.isActive == true)
        // A cancelled phone subscription does not stop or re-submit a run.
        subscription.cancel()
        let replayCursor = try #require(collector.cursor)
        try await Task.sleep(for:.seconds(2))
        subscription = subscribe(client,after:replayCursor)
        try await wait { collector.runs[first.id]?.state == .completed }
        #expect(collector.messages.values.filter { $0.runID == first.id && $0.role == .assistant }.count == 1)
        #expect(collector.messages["assistant-\(first.id)"]?.plainText == "Local Studio stream complete.")
        let canonical = try await client.messages(conversationID:conversation.id)
        #expect(canonical.filter { $0.id == "assistant-\(first.id)" }.count == 1)

        // Relaunch a production client with the committed cursor and same Keychain item.
        subscription.cancel()
        var relaunched = BridgeHermesClient(credentials:credentialStore,defaults:defaults)
        await relaunched.connect(to:host)
        subscription = subscribe(relaunched,after:collector.cursor)
        let tc = try await relaunched.createConversation(configuration:config)
        let tool = try await relaunched.send(OutgoingMessage(text:"exercise-safe-tool"),conversationID:tc.id,configuration:config)
        try await wait { collector.runs[tool.id]?.toolEvents.isEmpty == false }
        subscription.cancel()
        relaunched = BridgeHermesClient(credentials:credentialStore,defaults:defaults)
        await relaunched.connect(to:host)
        subscription = subscribe(relaunched,after:collector.cursor)
        #expect(try await relaunched.run(id:tool.id).state.isActive)
        try await relaunched.steer(runID:tool.id,instruction:"safe-steering-evidence")
        try await wait { collector.runs[tool.id]?.state == .completed }
        #expect(collector.messages["assistant-\(tool.id)"] != nil)
        let stopConversation = try await relaunched.createConversation(configuration:config)
        let stopRun = try await relaunched.send(OutgoingMessage(text:"exercise-safe-tool"),conversationID:stopConversation.id,configuration:config)
        try await wait { collector.runs[stopRun.id]?.toolEvents.isEmpty == false }
        try await relaunched.stop(runID:stopRun.id)
        try await wait { collector.runs[stopRun.id]?.state == .cancelled }

        func restart(_ which: String) async throws {
            var req=URLRequest(url:URL(string:controlURL+"/restart/"+which)!)
            req.httpMethod="POST";req.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
            let (_,response)=try await URLSession.shared.data(for:req)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        }
        let rc = try await relaunched.createConversation(configuration:config)
        let restartRun = try await relaunched.send(OutgoingMessage(text:"exercise-safe-tool"),conversationID:rc.id,configuration:config)
        try await wait { collector.runs[restartRun.id]?.toolEvents.isEmpty == false }
        try await restart("hermes")
        try await wait { collector.runs[restartRun.id]?.state == .disconnected }
        try await wait {
            guard let s = try? await relaunched.status(hostID:host.id) else { return false }
            return s.connection == .connected
        }
        #expect(try await relaunched.run(id:restartRun.id).state == .disconnected)
        try await restart("bridge")
        try await wait {
            guard let s = try? await relaunched.status(hostID:host.id) else { return false }
            return s.connection == .connected
        }
        #expect(try await relaunched.run(id:first.id).state == .completed)
        let recovered = try await relaunched.messages(conversationID:conversation.id)
        #expect(recovered.filter { $0.id == "assistant-\(first.id)" }.count == 1)
        var evidenceReq=URLRequest(url:URL(string:controlURL+"/evidence")!)
        evidenceReq.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
        let (evidenceData,_)=try await URLSession.shared.data(for:evidenceReq)
        let evidence=try JSONDecoder().decode(BridgeJSON.self,from:evidenceData)
        #expect(evidence["steering_consumed"].bool == true)
        #expect(evidence["commit"].string?.hasPrefix("2a4c9afd7bd") == true)
        // Provision this simulator's production composition for the opt-in UI
        // smoke test without exposing the bearer to XCTest typing/launch logs.
        let uiCredentials=KeychainBridgeCredentialStore()
        try uiCredentials.save(token,forHostID:host.id)
        let saved=SavedHostStore();saved.save(saved.load().filter { $0.id != host.id } + [host]);saved.activeHostID=host.id
        UserDefaults.standard.set(false,forKey:"app.backendSimulation")
    }

    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["HERMES_STACK_CLEANUP"] == "1"))
    func removeIsolatedSimulatorPairing() throws {
        let id = "isolated-local-stack"
        try KeychainBridgeCredentialStore().remove(forHostID:id)
        let saved = SavedHostStore()
        let hosts = saved.load().filter { $0.id != id }
        saved.save(hosts)
        if saved.activeHostID == id { saved.activeHostID = hosts.first?.id }
        let path = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("BridgeCache/" + id)
        if FileManager.default.fileExists(atPath:path.path) { try FileManager.default.removeItem(at:path) }
        #expect(try KeychainBridgeCredentialStore().token(forHostID:id) == nil)
    }

    @MainActor private func wait(_ predicate: () async throws -> Bool) async throws {
        let deadline=Date.now.addingTimeInterval(35)
        while Date.now < deadline {
            if try await predicate() { return }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw HermesError.timeout
    }
}

@MainActor private final class StackCollector {
    var cursor: EventCursor?
    var runs:[String:Run]=[:]
    var messages:[String:Message]=[:]
    func apply(_ event:HermesEvent) {
        switch event {
        case .batch(let events): events.forEach(apply)
        case .runUpserted(let run):runs[run.id]=run
        case .messageUpserted(let message):messages[message.id]=message
        case .transcriptReplaced(let id,let canonical):
            messages=messages.filter { $0.value.conversationID != id }
            for m in canonical { messages[m.id]=m }
        default:break
        }
    }
}
