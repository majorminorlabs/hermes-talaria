import Foundation
import Testing
@testable import Hermes

@MainActor
private final class ControlledRosterService: ProfileService {
    var pending: [CheckedContinuation<[Profile], Error>] = []
    func listProfiles() async throws -> [Profile] {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func updateProfile(id: String, changes: ProfileChanges) async throws -> Profile { throw HermesError.notFound }
}

@MainActor
struct ProfileStoreRefreshTests {
    @Test func olderRosterCompletionCannotReplaceTheLatestBotIdentity() async {
        let service = ControlledRosterService()
        let fixtures = MockFixtures.standard()
        var client = HermesClient.mock(MockHermesBackend(fixtures:fixtures)); client.profiles = service
        let store = ProfileStore(client:client,cache:SnapshotCache(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let first = Task { await store.refresh() }
        while service.pending.count < 1 { await Task.yield() }
        let second = Task { await store.refresh() }
        while service.pending.count < 2 { await Task.yield() }
        var current = fixtures.profiles[1]; current.name = "Current native bot"
        service.pending[1].resume(returning:[current]); await second.value
        service.pending[0].resume(returning:[fixtures.profiles[0]]); await first.value
        #expect(store.sorted.map(\.name) == ["Current native bot"])
        #expect(store.phase == .loaded)
    }
}

/// A URLProtocol-backed fixture for exercising the production client without
/// opening a real network connection. Each fixture gets its own host name so
/// Swift Testing can run separate cases concurrently.
nonisolated final class BridgeStubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registry = BridgeStubRegistry()

    fileprivate static func register(host: String, handler: @escaping @Sendable (URLRequest) -> BridgeStubResponse) {
        registry.register(host: host, handler: handler)
    }

    fileprivate static func unregister(host: String) {
        registry.unregister(host: host)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return Self.registry.contains(host: host)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var observedRequest = request
        if observedRequest.httpBody == nil, let stream = observedRequest.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating:0,count:4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer,maxLength:buffer.count)
                if count <= 0 { break }
                data.append(contentsOf:buffer.prefix(count))
            }
            observedRequest.httpBody = data
        }
        guard let host = observedRequest.url?.host,
              let response = Self.registry.response(for: host, request: observedRequest) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        if let failure = response.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        client?.urlProtocol(self, didReceive: response.httpResponse(for: request), cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

nonisolated private final class BridgeStubRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> BridgeStubResponse

    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]

    func register(host: String, handler: @escaping Handler) {
        lock.lock()
        handlers[host] = handler
        lock.unlock()
    }

    func unregister(host: String) {
        lock.lock()
        handlers.removeValue(forKey: host)
        lock.unlock()
    }

    func contains(host: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return handlers[host] != nil
    }

    func response(for host: String, request: URLRequest) -> BridgeStubResponse? {
        lock.lock()
        let handler = handlers[host]
        lock.unlock()
        return handler?(request)
    }
}

nonisolated private struct BridgeStubResponse: Sendable {
    var status: Int = 200
    var contentType = "application/json"
    var body = Data("{}".utf8)
    var failure: URLError.Code?

    init(status: Int = 200, contentType: String = "application/json", body: String = "{}", failure: URLError.Code? = nil) {
        self.status = status
        self.contentType = contentType
        self.body = Data(body.utf8)
        self.failure = failure
    }

    func httpResponse(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!, statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
    }
}

nonisolated private final class BridgeRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock()
        stored.append(request)
        lock.unlock()
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

nonisolated private func makeBridgeTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BridgeStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

nonisolated private func uniqueBridgeTestHost() -> String {
    "bridge-test-\(UUID().uuidString.lowercased()).localhost"
}

nonisolated private func bridgeHost(id: String, domain: String) -> Host {
    Host(id: id, name: "Test Studio", address: "https://\(domain)")
}

nonisolated private func capabilitiesResponse(connected: Bool = true, features: String = #""sessions":true,"runs":true,"runReplay":true,"steering":true,"stop":true,"profiles":true,"cron":true,"kanban":true,"usage":true,"skills":true,"tools":true,"mcp":true,"artifacts":true"#) -> BridgeStubResponse {
    BridgeStubResponse(body: #"{"api_version":1,"bridge_version":"0.1.0","scopes":["read","chat.control","tasks.manage","approvals.respond"],"cursor":"test-epoch:0","profiles":{"default":{"health":{"connected":\#(connected)},"installed_commit":"2a4c9afd7bd7b56d3e1f95524ca8956092f2904c","features":{\#(features)},"workspaces":[],"boards":[]}}}"#)
}

nonisolated private func encodedBridgeJSON(_ json: BridgeJSON) -> String {
    String(data: try! JSONEncoder().encode(json), encoding: .utf8)!
}

nonisolated private func runSnapshot(text: String, cursor: String) -> BridgeJSON {
    .object([
        "id": .string("run-one"), "conversation_id": .string("conversation-one"),
        "profile": .string("default"), "origin": .string("desktop_rpc"), "state": .string("running"),
        "created_at": .number(1_790_916_000), "updated_at": .number(1_790_916_010),
        "assistant_text": .string(text), "snapshot_cursor": .string(cursor),
        "controls": .object(["stop": .bool(true), "steer": .bool(true), "retry": .bool(false)])
    ])
}

nonisolated private func bridgeEvent(type: String, sequence: Int, text: String) -> BridgeJSON {
    .object([
        "seq": .integer(Int64(sequence)), "cursor": .string("test-epoch:\(sequence)"),
        "type": .string(type), "profile": .string("default"), "run_id": .string("run-one"),
        "conversation_id": .string("conversation-one"), "observed_at": .number(1_790_916_000 + Double(sequence)),
        "payload": .object(["text": .string(text)])
    ])
}

nonisolated private func sseFrame(_ event: BridgeJSON) -> String {
    let cursor = event["cursor"].string ?? ""
    return "id: \(cursor)\nevent: \(event["type"].string ?? "message")\ndata: \(encodedBridgeJSON(event))\n\n"
}

nonisolated private func assistantMessage(in event: HermesEvent) -> Message? {
    switch event {
    case .messageUpserted(let message) where message.role == .assistant: message
    case .batch(let events): events.lazy.compactMap(assistantMessage).first
    default: nil
    }
}

nonisolated private final class BridgeTestCredentialStore: BridgeCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: String]

    init(hostID: String? = nil, token: String? = nil) {
        if let hostID, let token { tokens = [hostID: token] } else { tokens = [:] }
    }

    func token(forHostID hostID: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return tokens[hostID]
    }

    func save(_ token: String, forHostID hostID: String) throws {
        lock.lock()
        tokens[hostID] = token
        lock.unlock()
    }

    func remove(forHostID hostID: String) throws {
        lock.lock()
        tokens[hostID] = nil
        lock.unlock()
    }
}

nonisolated private final class BridgeAckRecorder: HermesEventStream, @unchecked Sendable {
    private let lock = NSLock()
    private let cache: SnapshotCache
    private var commitChecks: [Bool] = []
    private var lastSubscription: EventCursor?

    init(cache: SnapshotCache) { self.cache = cache }

    func subscribe(after cursor: EventCursor?) -> AsyncStream<HermesEventEnvelope> {
        lock.lock()
        lastSubscription = cursor
        lock.unlock()
        return AsyncStream { $0.finish() }
    }

    func acknowledge(_ cursor: EventCursor) async {
        let saved = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value.cursor
        record(saved == cursor)
    }

    private func record(_ committed: Bool) {
        lock.lock()
        commitChecks.append(committed)
        lock.unlock()
    }

    var allAcknowledgementsFollowedCommit: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !commitChecks.isEmpty && commitChecks.allSatisfy { $0 }
    }

    var acknowledgementCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return commitChecks.count
    }

    var subscribedCursor: EventCursor? {
        lock.lock()
        defer { lock.unlock() }
        return lastSubscription
    }
}

nonisolated private final class BotModeFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var names = ["Research Orchestrator", "Hermes", "Research Worker"]
    func replace(_ names: [String]) { lock.lock(); self.names = names; lock.unlock() }
    func response(_ request: URLRequest) -> BridgeStubResponse {
        lock.lock(); let names = self.names; lock.unlock()
        let path = request.url!.path
        if path.hasSuffix("/capabilities") { return capabilitiesResponse(features: #""sessions":true,"profiles":true,"botMode":true"#) }
        let skills = ["research-terminal", "arxiv", "hermes-bluebubbles-operations", "llama-cpp", "llm-wiki", "online-price-comparison"]
        let rows: [BridgeJSON] = names.map { name in .object([
            "id": .string(name == "Hermes" ? "default-bot" : name.replacingOccurrences(of: " ", with: "-")),
            "name": .string(name), "is_default": .bool(name == "Hermes"), "role": .string(""),
            "model": .string("studio-model"), "provider": .string("studio-provider"), "status": .string("unknown"),
            "last_active": .number(10), "canonical_chat_available": .bool(true),
            "skills": .array(skills.map { .object(["name": .string($0), "enabled": .bool(true)]) }),
            "soul_summary": .string("Configured Studio SOUL")]) }
        if path.hasSuffix("/conversation") {
            return BridgeStubResponse(body: #"{"conversation":{"id":"botchat.Research-Orchestrator","profile":"Research-Orchestrator","title":"Bot Chat","read_only":true},"messages":[{"id":1,"role":"user","content":"Existing Studio history"}]}"#)
        }
        if path.hasSuffix("/bots") { return BridgeStubResponse(body: encodedBridgeJSON(.object(["bots": .array(rows)]))) }
        if path.hasSuffix("/conversations") { return BridgeStubResponse(body: #"{"conversations":[]}"#) }
        return BridgeStubResponse(body: encodedBridgeJSON(rows.first ?? .null))
    }
}

nonisolated private final class WritableBotChatFixture: @unchecked Sendable {
    let recorder = BridgeRequestRecorder()

    private var conversation: BridgeJSON {
        .object([
            "id": .string("atlas-chat-opaque"), "title": .string("Atlas"),
            "profile": .string("atlas-bot-opaque"), "bot_id": .string("atlas-bot-opaque"),
            "bot_profile": .string("Atlas_Profile"), "bot_name": .string("Atlas"),
            "canonical": .bool(true), "read_only": .bool(false),
            "model": .string("atlas-canonical-model"), "provider": .string("atlas-provider"),
            "source": .string("mobile"), "started_at": .number(1_790_916_000),
            "last_activity": .number(1_790_916_003), "message_count": .integer(1)
        ])
    }

    private var run: BridgeJSON {
        .object([
            "id": .string("atlas-run"), "conversation_id": .string("atlas-chat-opaque"),
            "profile": .string("atlas-bot-opaque"), "origin": .string("desktop_rpc"),
            "state": .string("running"), "created_at": .number(1_790_916_000),
            "updated_at": .number(1_790_916_010), "assistant_text": .string("working"),
            "snapshot_cursor": .string("atlas-epoch:0"),
            "model": .string("atlas-canonical-model"), "provider": .string("atlas-provider"),
            "controls": .object(["stop": .bool(true), "steer": .bool(true), "retry": .bool(false)])
        ])
    }

    func response(_ request: URLRequest) -> BridgeStubResponse {
        recorder.append(request)
        let path = request.url!.path
        if path.hasSuffix("/capabilities") {
            return capabilitiesResponse(features: #""sessions":true,"runs":true,"runReplay":true,"steering":true,"stop":true,"botMode":true,"botChat":true"#)
        }
        if path.hasSuffix("/bots/atlas-bot-opaque/conversation") {
            let rows: [BridgeJSON] = [.object(["id": .string("atlas-user-row"), "role": .string("user"),
                                                "content": .string("Use Atlas's configured profile")])]
            return BridgeStubResponse(body: encodedBridgeJSON(.object(["conversation": conversation,
                "messages": .array(rows), "observed_runs": .array([])])))
        }
        if path.hasSuffix("/conversations"), request.httpMethod == "GET" {
            return BridgeStubResponse(body: encodedBridgeJSON(.object(["conversations": .array([conversation])])))
        }
        if path.hasSuffix("/conversations/atlas-chat-opaque/runs"), request.httpMethod == "POST" {
            return BridgeStubResponse(body: encodedBridgeJSON(run))
        }
        if path.hasSuffix("/runs/atlas-run/events") {
            return BridgeStubResponse(body: #"{"events":[],"cursor":"atlas-epoch:0","has_more":false}"#)
        }
        if path.hasSuffix("/runs/atlas-run/stop") {
            return BridgeStubResponse(body: encodedBridgeJSON(.object(["run": run])))
        }
        if path.hasSuffix("/runs/atlas-run/steer") {
            return BridgeStubResponse(body: #"{"accepted":true}"#)
        }
        if path.hasSuffix("/runs/atlas-run") {
            return BridgeStubResponse(body: encodedBridgeJSON(run))
        }
        return BridgeStubResponse(status: 404, body: #"{"error":{"code":"not_found"}}"#)
    }
}

nonisolated private func runUpserted(in event: HermesEvent) -> Run? {
    switch event {
    case .runUpserted(let run): run
    case .batch(let events): events.lazy.compactMap(runUpserted).first
    default: nil
    }
}

@MainActor
struct BridgeIntegrationTests {
    @Test func botMetadataDoesNotInferAModelFromItsIdentity() {
        let missing = BridgeMapping.bot(.object(["id": .string("opaque-id"), "name": .string("Studio Bot")]), hostID: "studio")
        #expect(missing.editableFields == nil)
        #expect(missing.modelAvailable == false)
        #expect(missing.status == .unknown)
        #expect(missing.skillIDs.isEmpty && missing.soulSummary == nil)
        let configured = BridgeMapping.bot(.object(["id": .string("opaque-id"), "name": .string("Studio Bot"), "model": .string("actual-model"), "provider": .string("actual-provider")]), hostID: "studio")
        #expect(configured.model.displayName == "actual-model")
        #expect(configured.model.provider == "actual-provider")
        let chat = BridgeMapping.conversation(.object(["id": .string("botchat.opaque-id"), "read_only": .bool(true)]), hostID: "studio")
        #expect(chat.model == nil)
        let writable = BridgeMapping.conversation(.object([
            "id": .string("alias-without-prefix"), "profile": .string("opaque-bot-id"),
            "bot_id": .string("opaque-bot-id"), "bot_profile": .string("Native_Profile"),
            "canonical": .bool(true), "read_only": .bool(false),
            "model": .string("profile-model"), "provider": .string("profile-provider")
        ]), hostID: "studio")
        #expect(writable.isBotChat == true && writable.botID == "opaque-bot-id")
        #expect(writable.botProfileID == "Native_Profile")
        #expect(writable.profileID == "opaque-bot-id")
        #expect(writable.model?.id == "profile-model" && writable.model?.provider == "profile-provider")
    }

    @Test func botModeDiscoveryDetailsCanonicalChatAndRefresh() async throws {
        let domain = uniqueBridgeTestHost(), hostID = UUID().uuidString
        let fixture = BotModeFixture()
        BridgeStubURLProtocol.register(host: domain) { fixture.response($0) }
        defer { BridgeStubURLProtocol.unregister(host: domain) }
        let backend = BridgeHermesClient(credentials: BridgeTestCredentialStore(hostID: hostID, token: "test-token"), session: makeBridgeTestSession())
        let host = bridgeHost(id: hostID, domain: domain)
        await backend.connect(to: host)
        let cache = SnapshotCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let store = ProfileStore(client: backend.client, cache: cache)
        await store.refresh()
        #expect(Set(store.bots.map(\.name)) == ["Research Orchestrator", "Hermes", "Research Worker"])
        #expect(store.bots.filter(\.isDefault).count == 1)
        let detail = try await backend.profile(id: "Research-Orchestrator")
        #expect(detail.skillIDs.contains("research-terminal"))
        #expect(detail.skillIDs.count == 6)
        #expect(detail.soulSummary == "Configured Studio SOUL")
        #expect(detail.status == .unknown)
        let chat = try #require(try await backend.canonicalConversation(profileID: detail.id))
        #expect(chat.title == "Bot Chat" && chat.readOnly == true)
        #expect(try await backend.messages(conversationID: chat.id).first?.plainText == "Existing Studio history")
        #expect(try await backend.listConversations().allSatisfy { $0.id != chat.id })
        fixture.replace(["Research Orchestrator", "Hermes", "Research Worker", "New Studio Bot"])
        await store.refresh()
        #expect(store.bots.contains { $0.name == "New Studio Bot" })
        fixture.replace(["Hermes"])
        await backend.disconnect(hostID: hostID)
        await backend.connect(to: host)
        await store.refresh()
        #expect(store.bots.map(\.name) == ["Hermes"])
        #expect(try await backend.listConversations().allSatisfy { $0.id != chat.id })
    }

    @Test func transientOfflineCapabilitiesDoNotDowngradeBotIdentities() async throws {
        let domain = uniqueBridgeTestHost(), hostID = UUID().uuidString
        let recorder = BridgeRequestRecorder()
        BridgeStubURLProtocol.register(host:domain) { request in
            recorder.append(request)
            return capabilitiesResponse(features:#""profiles":true,"botMode":true"#)
        }
        defer { BridgeStubURLProtocol.unregister(host:domain) }
        let client = BridgeHermesClient(credentials:BridgeTestCredentialStore(hostID:hostID,token:"token"),session:makeBridgeTestSession())
        await client.connect(to:bridgeHost(id:hostID,domain:domain))
        BridgeStubURLProtocol.register(host:domain) { request in
            recorder.append(request)
            if request.url?.path.hasSuffix("/capabilities") == true { return capabilitiesResponse(connected:false,features:#""profiles":true,"botMode":false"#) }
            if request.url?.path.hasSuffix("/bots") == true { return BridgeStubResponse(body:#"{"bots":[{"id":"native-bot","name":"Real bot"}]}"#) }
            if request.url?.path.hasSuffix("/bots/native-bot") == true { return BridgeStubResponse(body:#"{"id":"native-bot","name":"Real bot","editable_fields":{"soul":true}}"#) }
            return BridgeStubResponse(body:#"{"profiles":[{"id":"default","name":"Legacy profile"}]}"#)
        }
        _ = try await client.status(hostID:hostID)
        #expect(try await client.listProfiles().map(\.id) == ["native-bot"])
        #expect(try await client.profile(id:"native-bot").editableFields == ["soul"])
        #expect(!recorder.requests.contains { $0.url?.path.hasSuffix("/profiles") == true })
    }

    @Test func writableBotChatUsesCanonicalPostGenericRunLifecycleAndBotProfile() async throws {
        let domain = uniqueBridgeTestHost(), hostID = UUID().uuidString
        let fixture = WritableBotChatFixture()
        BridgeStubURLProtocol.register(host: domain) { fixture.response($0) }
        defer { BridgeStubURLProtocol.unregister(host: domain) }
        let backend = BridgeHermesClient(
            credentials: BridgeTestCredentialStore(hostID: hostID, token: "test-token"),
            session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        let host = bridgeHost(id: hostID, domain: domain)
        await backend.client.hosts.connect(to: host)

        let chat = try #require(try await backend.client.profiles.canonicalConversation(profileID: "atlas-bot-opaque"))
        #expect(chat.id == "atlas-chat-opaque")
        #expect(chat.title == "Atlas" && chat.readOnly == false && chat.isBotChat == true)
        #expect(chat.profileID == "atlas-bot-opaque" && chat.botProfileID == "Atlas_Profile")
        #expect(chat.model?.id == "atlas-canonical-model" && chat.model?.provider == "atlas-provider")
        let history = try await backend.client.conversations.messages(conversationID: chat.id)
        #expect(history.first?.plainText == "Use Atlas's configured profile")

        let list = try await backend.client.conversations.listConversations()
        #expect(list.count == 1 && list.first?.id == chat.id)
        #expect(list.first?.isBotChat == true && list.first?.botProfileID == "Atlas_Profile")

        // A stale/default editor configuration must not override the bot's
        // configured profile, model or provider on an existing canonical chat.
        let wrongDefaultModel = ModelRef(id: "wrong-default", displayName: "Wrong default", provider: "Wrong")
        let run = try await backend.client.conversations.send(
            OutgoingMessage(text: "Continue as Atlas", attachments: []), conversationID: chat.id,
            configuration: RunConfiguration(profileID: "default", model: wrongDefaultModel, reasoning: .high, hostID: hostID)
        )
        #expect(run.profileID == "atlas-bot-opaque")
        #expect(run.model?.id == "atlas-canonical-model" && run.model?.provider == "atlas-provider")

        let replayed = try await backend.client.runs.run(id: run.id)
        #expect(replayed.profileID == "atlas-bot-opaque")
        try await backend.client.runs.stop(runID: run.id)
        try await backend.client.runs.steer(runID: run.id, instruction: "Keep using Atlas's profile")

        // The transport's source profile is `default`; run projection must
        // keep the bot identity supplied by the run snapshot.
        let started = try await backend.consume(json: .object([
            "seq": .integer(1), "cursor": .string("atlas-epoch:1"), "type": .string("run.started"),
            "profile": .string("default"), "run_id": .string("atlas-run"),
            "conversation_id": .string(chat.id), "payload": .object(["profile": .string("default")])
        ]))
        #expect(runUpserted(in: started)?.profileID == "atlas-bot-opaque")

        let requests = fixture.recorder.requests
        #expect(requests.contains { $0.httpMethod == "POST" && $0.url?.path == "/mobile/v1/bots/atlas-bot-opaque/conversation" })
        #expect(requests.contains { $0.httpMethod == "GET" && $0.url?.path == "/mobile/v1/bots/atlas-bot-opaque/conversation" })
        #expect(requests.contains { $0.httpMethod == "POST" && $0.url?.path == "/mobile/v1/conversations/atlas-chat-opaque/runs" })
        #expect(requests.contains { $0.httpMethod == "GET" && $0.url?.path == "/mobile/v1/runs/atlas-run/events" })
        #expect(requests.contains { $0.httpMethod == "POST" && $0.url?.path == "/mobile/v1/runs/atlas-run/stop" })
        #expect(requests.contains { $0.httpMethod == "POST" && $0.url?.path == "/mobile/v1/runs/atlas-run/steer" })
        let runRequest = try #require(requests.first { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/conversations/atlas-chat-opaque/runs") == true })
        let runBody = String(data: try #require(runRequest.httpBody), encoding: .utf8) ?? ""
        #expect(runBody.contains("Continue as Atlas"))
        #expect(!runBody.contains("wrong-default") && !runBody.contains("\"profile\""))

        await backend.client.hosts.disconnect(hostID: hostID)
        await backend.client.hosts.connect(to: host)
        let reconnected = try await backend.client.conversations.listConversations()
        #expect(reconnected.count == 1 && reconnected.first?.id == chat.id)
        #expect(reconnected.first?.profileID == "atlas-bot-opaque" && reconnected.first?.botProfileID == "Atlas_Profile")
    }

    @Test func writableBotChatControlRequiresCapabilityAndIgnoresIdentityPrefix() {
        let environment = AppEnvironment.mock(storage: .ephemeral)
        var status = environment.connection.status
        status.connection = .connected
        status.capabilities.insert(.botChat)
        environment.connection.apply(.hostStatus(status))
        let writable = Conversation(id: "botchat.alias-without-native-id", title: "Writable bot",
            profileID: "opaque-bot-id", hostID: status.hostID, source: .app,
            createdAt: .now, lastActivity: .now, preview: "", project: nil, model: nil,
            activeRunID: nil, isPinned: false, messageCount: 0, readOnly: false,
            isBotChat: true, botID: "opaque-bot-id", botProfileID: "Native_Profile")
        let readOnly = Conversation(id: "botchat.legacy", title: "Legacy read only",
            profileID: "Native_Profile", hostID: status.hostID, source: .app,
            createdAt: .now, lastActivity: .now, preview: "", project: nil, model: nil,
            activeRunID: nil, isPinned: false, messageCount: 0, readOnly: true)
        environment.conversations.apply(.conversationUpserted(writable))
        environment.conversations.apply(.conversationUpserted(readOnly))
        let writableModel = environment.makeConversationModel(conversationID: writable.id, profileID: nil)
        writableModel.draft = "Send as this bot"
        let readOnlyModel = environment.makeConversationModel(conversationID: readOnly.id, profileID: nil)
        readOnlyModel.draft = "Must remain blocked"
        #expect(writableModel.canSend)
        #expect(!readOnlyModel.canSend)
        var statusWithoutBotChat = status
        statusWithoutBotChat.capabilities.remove(.botChat)
        environment.connection.apply(.hostStatus(statusWithoutBotChat))
        #expect(!writableModel.canSend)
    }

    @Test func olderBridgeFallsBackToGenericProfiles() async throws {
        let domain = uniqueBridgeTestHost(), hostID = UUID().uuidString
        BridgeStubURLProtocol.register(host: domain) { request in
            if request.url!.path.hasSuffix("/capabilities") { return capabilitiesResponse() }
            return BridgeStubResponse(body: #"{"profiles":[{"id":"default","name":"default","health":{"connected":true}}]}"#)
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }
        let backend = BridgeHermesClient(credentials: BridgeTestCredentialStore(hostID: hostID, token: "test-token"), session: makeBridgeTestSession())
        await backend.connect(to: bridgeHost(id: hostID, domain: domain))
        let rows = try await backend.listProfiles()
        #expect(rows.count == 1 && rows.first?.id == "default")
        #expect(rows.allSatisfy { $0.isBotMode != true })
        #expect(try await backend.canonicalConversation(profileID: "default") == nil)
    }

    @Test func appPersistsEveryEventCursorBeforeAcknowledgingIt() async throws {
        let fixtures = MockFixtures.standard()
        let backend = MockHermesBackend(fixtures: fixtures)
        var client = HermesClient.mock(backend)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = SnapshotCache(directory: directory)
        let acknowledger = BridgeAckRecorder(cache: cache)
        client.events = acknowledger
        let environment = AppEnvironment(
            client: client, simulator: backend, preferences: AppPreferences(defaults: defaults), cache: cache,
            savedHosts: SavedHostStore(defaults: defaults), drafts: DraftStore(defaults: defaults),
            notifier: LocalNotificationService(), defaultHosts: fixtures.hosts
        )
        let original = try #require(fixtures.runs.first)
        let firstCursor = EventCursor(value: "test-epoch:1")
        let secondCursor = EventCursor(value: "test-epoch:2")

        await environment.handle(.init(cursor: firstCursor, event: .runUpserted(original)))
        await environment.handle(.init(cursor: secondCursor, event: .log(LogEntry(
            id: "log-one", timestamp: .now, level: .info, category: .connection, message: "Connected"
        ))))

        #expect(cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value.cursor == secondCursor)
        #expect(acknowledger.acknowledgementCount == 2)
        #expect(acknowledger.allAcknowledgementsFollowedCommit)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func streamedDeltasAndCanonicalHistoryReuseOneAssistantMessage() async throws {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let storedRun = runSnapshot(text: "Hello world", cursor: "test-epoch:3")
        let conversation: BridgeJSON = .object([
            "conversation": .object([
                "id": .string("conversation-one"), "title": .string("Test chat"),
                "profile": .string("default"), "source": .string("mobile"),
                "started_at": .number(1_790_916_000), "last_activity": .number(1_790_916_003)
            ]),
            "messages": .array([.object([
                "id": .string("canonical-assistant-row"), "role": .string("assistant"),
                "content": .string("Hello world"), "timestamp": .number(1_790_916_003)
            ])]),
            "observed_runs": .array([storedRun])
        ])
        BridgeStubURLProtocol.register(host: domain) { request in
            if request.url?.path.hasSuffix("/capabilities") == true { return capabilitiesResponse() }
            if request.url?.path.hasSuffix("/runs/run-one") == true {
                return BridgeStubResponse(body: encodedBridgeJSON(runSnapshot(text: "", cursor: "test-epoch:0")))
            }
            if request.url?.path.hasSuffix("/conversations/conversation-one") == true {
                return BridgeStubResponse(body: encodedBridgeJSON(conversation))
            }
            return BridgeStubResponse(status: 404, body: #"{"error":{"code":"not_found"}}"#)
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }

        let client = BridgeHermesClient(
            credentials: BridgeTestCredentialStore(hostID: hostID, token: "token"),
            session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))

        let first = try await client.consume(json: bridgeEvent(type: "assistant.delta", sequence: 1, text: "Hello "))
        let second = try await client.consume(json: bridgeEvent(type: "assistant.delta", sequence: 2, text: "world"))
        let completed = try await client.consume(json: bridgeEvent(type: "assistant.completed", sequence: 3, text: "Hello world"))
        let firstMessage = try #require(assistantMessage(in: first))
        let secondMessage = try #require(assistantMessage(in: second))
        let completedMessage = try #require(assistantMessage(in: completed))

        #expect(firstMessage.id == "assistant-run-one")
        #expect(firstMessage.id == secondMessage.id)
        #expect(secondMessage.id == completedMessage.id)
        #expect(firstMessage.plainText == "Hello ")
        #expect(secondMessage.plainText == "Hello world")
        #expect(completedMessage.plainText == "Hello world")

        let history = try await client.client.conversations.messages(conversationID: "conversation-one")
        let assistants = history.filter { $0.role == .assistant }
        #expect(assistants.count == 1)
        #expect(assistants.first?.id == completedMessage.id)
        #expect(assistants.first?.plainText == "Hello world")
    }

    @Test func clarificationUsesExactAttentionRouteWhileDangerousApprovalStaysDisabled() async throws {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        BridgeStubURLProtocol.register(host: domain) { request in
            recorder.append(request)
            if request.url?.path.hasSuffix("/capabilities") == true { return capabilitiesResponse() }
            return BridgeStubResponse(body: #"{"acknowledged":true}"#)
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }
        let client = BridgeHermesClient(
            credentials: BridgeTestCredentialStore(hostID: hostID, token: "token"),
            session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))

        let clarification = BridgeMapping.approval(.object([
            "id": .string("question-1"), "run_id": .string("run-one"),
            "kind": .string("clarification"), "state": .string("pending"),
            "can_respond": .bool(true), "expires_at": .number(Date.now.addingTimeInterval(120).timeIntervalSince1970),
            "observed_at": .number(Date.now.timeIntervalSince1970),
            "details": .object(["question": .string("Which file should I inspect?"), "choices": .array([.string("A.swift")])])
        ]))
        let dangerous = BridgeMapping.approval(.object([
            "id": .string("approval-1"), "run_id": .string("run-one"),
            "kind": .string("command"), "state": .string("pending"), "can_respond": .bool(false),
            "limitation": .string("upstream_fifo_without_exact_target"),
            "details": .object(["description": .string("Run a destructive command"), "command": .string("rm -rf output")])
        ]))
        #expect(clarification.availability == .actionable)
        #expect(clarification.clarificationQuestion == "Which file should I inspect?")
        #expect(!dangerous.availability.isActionable)

        try await client.client.runs.answerClarification(id: clarification.id, answer: "A.swift")
        await #expect(throws: HermesError.self) {
            try await client.client.runs.resolveApproval(id: dangerous.id, decision: .deny)
        }
        let posts = recorder.requests.filter { $0.httpMethod == "POST" }
        #expect(posts.count == 1)
        #expect(posts.first?.url?.path.hasSuffix("/attention/question-1/respond") == true)
        #expect(String(data: posts.first?.httpBody ?? Data(), encoding: .utf8)?.contains("A.swift") == true)
    }

    @Test func sseTransportRequestsReplayFromProvidedCursor() async throws {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        let payload = encodedBridgeJSON(bridgeEvent(type: "assistant.delta", sequence: 8, text: "replayed"))
        BridgeStubURLProtocol.register(host: domain) { request in
            recorder.append(request)
            return BridgeStubResponse(contentType: "text/event-stream", body: "id: test-epoch:8\nevent: assistant.delta\ndata: \(payload)\n\n")
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }

        let transport = try BridgeTransport(
            baseURL: URL(string: "https://\(domain)")!, hostID: hostID,
            credentialStore: BridgeTestCredentialStore(hostID: hostID, token: "token"),
            session: makeBridgeTestSession()
        )
        let stream = await transport.events(after: "test-epoch:7")
        var frames: [BridgeSSEFrame] = []
        for try await frame in stream { frames.append(frame) }

        #expect(frames.count == 1)
        #expect(frames.first?.id == "test-epoch:8")
        #expect(frames.first?.event == "assistant.delta")
        #expect(frames.first?.data == payload)
        let query = URLComponents(url: try #require(recorder.requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first(where: { $0.name == "after" })?.value == "test-epoch:7")
        #expect(recorder.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test func byteSSEParserHandlesLineEndingsSplitUTF8AndMultilineData() throws {
        let wire = "id: journal:41\r\nevent: assistant.delta\r\ndata: café\r\ndata: second line\r\n\r\n" +
            "id: journal:42\nevent: tool.completed\ndata: {\"ok\":\ndata: true}\n\n"
        var parser = BridgeSSEByteParser()
        var frames: [BridgeSSEFrame] = []

        // Feeding one byte at a time splits the multibyte UTF-8 character as it
        // would across network chunks and exercises both CRLF and LF separators.
        for byte in Data(wire.utf8) {
            if let frame = try parser.consume(byte: byte) { frames.append(frame) }
        }

        #expect(frames.count == 2)
        #expect(frames[0].id == "journal:41")
        #expect(frames[0].event == "assistant.delta")
        #expect(frames[0].data == "café\nsecond line")
        #expect(frames[1].id == "journal:42")
        #expect(frames[1].event == "tool.completed")
        #expect(frames[1].data == "{\"ok\":\ntrue}")
    }

    @Test(arguments: [URLError.Code.timedOut, .networkConnectionLost])
    func checkpointProbeFailureKeepsStreamAndRetriesHealth(failure: URLError.Code) async throws {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        let event = bridgeEvent(type: "assistant.completed", sequence: 1, text: "Still streaming")
        BridgeStubURLProtocol.register(host: domain) { request in
            recorder.append(request)
            if request.url?.path.hasSuffix("/capabilities") == true {
                let probes = recorder.requests.filter { $0.url?.path.hasSuffix("/capabilities") == true }.count
                if probes == 3 { return BridgeStubResponse(failure: failure) }
                // A confirmed unhealthy backend must still be reflected, followed by recovery.
                return capabilitiesResponse(connected: probes != 4)
            }
            if request.url?.path.hasSuffix("/runs/run-one") == true {
                return BridgeStubResponse(body: encodedBridgeJSON(runSnapshot(text: "", cursor: "test-epoch:0")))
            }
            let checkpoint = "event: stream.checkpoint\ndata: {\"cursor\":\"test-epoch:0\"}\n\n"
            return BridgeStubResponse(contentType: "text/event-stream", body: checkpoint + checkpoint + checkpoint + sseFrame(event))
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }
        let client = BridgeHermesClient(credentials: BridgeTestCredentialStore(hostID: hostID, token: "token"), session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await client.connect(to: bridgeHost(id: hostID, domain: domain))
        let stream = client.subscribe(after: EventCursor(value: "test-epoch:0"))
        var states: [ConnectionState] = []
        var received = false
        for await envelope in stream {
            if case .hostStatus(let status) = envelope.event { states.append(status.connection) }
            if envelope.cursor.value == "test-epoch:1" {
                received = true
                #expect(assistantMessage(in: envelope.event)?.plainText == "Still streaming")
                await client.acknowledge(envelope.cursor)
                break
            }
            #expect(states.count < 10)
            if states.count >= 10 { break }
        }
        await client.disconnect(hostID: hostID)
        #expect(received)
        #expect(states == [.connected, .hermesOffline, .connected])
        #expect(recorder.requests.filter { $0.url?.path.hasSuffix("/events/stream") == true }.count == 1)
        #expect(recorder.requests.filter { $0.url?.path.hasSuffix("/capabilities") == true }.count == 5)
    }

    @Test func checkpointProbeAuthenticationFailureStillRequiresPairing() async throws {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        BridgeStubURLProtocol.register(host: domain) { request in
            recorder.append(request)
            if request.url?.path.hasSuffix("/capabilities") == true {
                let probes = recorder.requests.filter { $0.url?.path.hasSuffix("/capabilities") == true }.count
                return probes <= 2 ? capabilitiesResponse() : BridgeStubResponse(status: 401)
            }
            return BridgeStubResponse(contentType: "text/event-stream", body: "event: stream.checkpoint\ndata: {\"cursor\":\"test-epoch:0\"}\n\n")
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }
        let client = BridgeHermesClient(credentials: BridgeTestCredentialStore(hostID: hostID, token: "token"), session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await client.connect(to: bridgeHost(id: hostID, domain: domain))
        let stream = client.subscribe(after: EventCursor(value: "test-epoch:0"))
        var pairingRequired = false
        for await envelope in stream {
            if case .hostStatus(let status) = envelope.event, status.connection == .authenticationRequired {
                pairingRequired = true
                break
            }
        }
        await client.disconnect(hostID: hostID)
        #expect(pairingRequired)
        #expect(recorder.requests.filter { $0.url?.path.hasSuffix("/events/stream") == true }.count == 1)
    }

    @Test func reconnectReplaysAfterCommittedCursorAndDeduplicatesSequence() async throws {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        let firstEvent = bridgeEvent(type: "assistant.delta", sequence: 1, text: "Hello ")
        let duplicateFirst = bridgeEvent(type: "assistant.delta", sequence: 1, text: "Hello ")
        let secondEvent = bridgeEvent(type: "assistant.completed", sequence: 2, text: "Hello world")
        BridgeStubURLProtocol.register(host: domain) { request in
            recorder.append(request)
            if request.url?.path.hasSuffix("/capabilities") == true { return capabilitiesResponse() }
            if request.url?.path.hasSuffix("/runs/run-one") == true {
                return BridgeStubResponse(body: encodedBridgeJSON(runSnapshot(text: "", cursor: "test-epoch:0")))
            }
            if request.url?.path.hasSuffix("/events/stream") == true {
                let priorStreams = recorder.requests.filter { $0.url?.path.hasSuffix("/events/stream") == true }.count
                let frames = priorStreams == 1 ? sseFrame(firstEvent) : sseFrame(duplicateFirst) + sseFrame(secondEvent)
                return BridgeStubResponse(contentType: "text/event-stream", body: frames)
            }
            return BridgeStubResponse(status: 404, body: #"{"error":{"code":"not_found"}}"#)
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }

        let client = BridgeHermesClient(
            credentials: BridgeTestCredentialStore(hostID: hostID, token: "token"),
            session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))
        let firstStream = client.client.events.subscribe(after: EventCursor(value: "test-epoch:0"))
        var firstIterator = firstStream.makeAsyncIterator()
        var firstEnvelope: HermesEventEnvelope?
        for _ in 0..<5 {
            guard let candidate = await firstIterator.next() else { break }
            if candidate.cursor.value == "test-epoch:1" { firstEnvelope = candidate; break }
        }
        let first = try #require(firstEnvelope)
        await client.client.events.acknowledge(first.cursor)
        let firstMessage = try #require(assistantMessage(in: first.event))
        await client.client.hosts.disconnect(hostID: hostID)

        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))
        let replayStream = client.client.events.subscribe(after: first.cursor)
        var replayIterator = replayStream.makeAsyncIterator()
        var replayEnvelope: HermesEventEnvelope?
        for _ in 0..<5 {
            guard let candidate = await replayIterator.next() else { break }
            if candidate.cursor.value == "test-epoch:2" { replayEnvelope = candidate; break }
        }
        let replayed = try #require(replayEnvelope)
        await client.client.events.acknowledge(replayed.cursor)
        let replayedMessage = try #require(assistantMessage(in: replayed.event))
        await client.client.hosts.disconnect(hostID: hostID)

        #expect(firstMessage.id == "assistant-run-one")
        #expect(replayedMessage.id == firstMessage.id)
        #expect(replayedMessage.plainText == "Hello world")
        let streams = recorder.requests.filter { $0.url?.path.hasSuffix("/events/stream") == true }
        #expect(streams.count >= 2)
        let replayQuery = URLComponents(url: try #require(streams.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(replayQuery?.first(where: { $0.name == "after" })?.value == "test-epoch:1")
    }

    @Test func authenticatedConnectionSendsBearerAndSeparatesHermesHealth() async throws {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        BridgeStubURLProtocol.register(host: domain) { request in
            recorder.append(request)
            return capabilitiesResponse()
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }

        let credentials = BridgeTestCredentialStore(hostID: hostID, token: "mobile-secret")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = BridgeHermesClient(credentials: credentials, session: makeBridgeTestSession(),
                                        defaults: defaults)
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))
        let status = try await client.client.hosts.status(hostID: hostID)

        #expect(status.connection == .connected)
        #expect(status.hermesState == .running)
        #expect(status.capabilities.contains(.sessions))
        #expect(recorder.requests.count >= 2)
        #expect(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer mobile-secret" })
        let storedStrings = defaults.dictionaryRepresentation().values.compactMap { $0 as? String }.joined(separator: " ")
        #expect(!storedStrings.contains("mobile-secret"))
    }

    @Test func bridgeReachableWithHermesOfflineHasDistinctStatus() async throws {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        BridgeStubURLProtocol.register(host: domain) { _ in capabilitiesResponse(connected: false) }
        defer { BridgeStubURLProtocol.unregister(host: domain) }

        let client = BridgeHermesClient(
            credentials: BridgeTestCredentialStore(hostID: hostID, token: "token"),
            session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))
        let status = try await client.client.hosts.status(hostID: hostID)
        #expect(status.connection == .hermesOffline)
        #expect(status.hermesState == .unknown)
    }

    @Test func bridgeNetworkFailureMapsToBridgeUnreachable() async {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        BridgeStubURLProtocol.register(host: domain) { _ in
            BridgeStubResponse(failure: .notConnectedToInternet)
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }

        let client = BridgeHermesClient(
            credentials: BridgeTestCredentialStore(hostID: hostID, token: "token"),
            session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))
        await #expect(throws: HermesError.bridgeUnreachable) {
            _ = try await client.client.hosts.status(hostID: hostID)
        }
    }

    @Test func homeUsesOneAggregateAndKeepsCachedSummaryWhenBridgeIsOffline() async throws {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        let homeJSON: BridgeJSON = .object([
            "bridge": .object(["version": .string("0.1.0")]),
            "studios": .array([.object(["connection": .object(["connected": .bool(true)]), "host": .object([:])])]),
            "active_runs": .array([runSnapshot(text: "Partial", cursor: "test-epoch:1")]),
            "attention": .array([]), "failed_or_blocked": .array([]), "recent_completions": .array([]),
            "upcoming_jobs": .array([]), "coverage_errors": .array([]), "observed_at": .number(1_790_916_010)
        ])
        BridgeStubURLProtocol.register(host: domain) { request in
            recorder.append(request)
            if request.url?.path.hasSuffix("/capabilities") == true { return capabilitiesResponse() }
            if request.url?.path.hasSuffix("/home") == true { return BridgeStubResponse(body: encodedBridgeJSON(homeJSON)) }
            return BridgeStubResponse(status: 404, body: #"{"error":{"code":"not_found"}}"#)
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }

        let credentials = BridgeTestCredentialStore(hostID: hostID, token: "token")
        let client = BridgeHermesClient(credentials: credentials, session: makeBridgeTestSession(),
                                        defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))
        let summary = try await client.client.home.homeSummary()
        #expect(summary.activeRuns.map(\.id) == ["run-one"])
        #expect(recorder.requests.filter { $0.url?.path.hasSuffix("/home") == true }.count == 1)

        let cache = SnapshotCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        cache.save(summary, key: .home)
        let offlineClient = BridgeHermesClient(credentials: credentials, session: makeBridgeTestSession(),
                                               defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let store = HomeStore(client: offlineClient.client, cache: cache)
        await store.refresh()
        #expect(store.summary == summary)
        #expect(store.phase.error == .bridgeUnreachable)
    }

    @Test func rejectedAuthenticationIsNotTreatedAsBridgeOffline() async {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        BridgeStubURLProtocol.register(host: domain) { request in
            BridgeStubResponse(status: 401, body: #"{"error":{"code":"unauthorized","message":"no"}}"#)
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }

        let client = BridgeHermesClient(
            credentials: BridgeTestCredentialStore(hostID: hostID, token: "expired-token"),
            session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))
        await #expect(throws: HermesError.unauthorized) {
            _ = try await client.client.hosts.status(hostID: hostID)
        }
    }

    @Test func upstreamErrorTextDoesNotLeakIntoUserVisibleError() async {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let secret = "private-provider-secret"
        BridgeStubURLProtocol.register(host: domain) { request in
            if request.url?.path.hasSuffix("/capabilities") == true { return capabilitiesResponse() }
            return BridgeStubResponse(status: 502, body: #"{"error":{"code":"upstream_error","message":"\#(secret)"}}"#)
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }
        let client = BridgeHermesClient(
            credentials: BridgeTestCredentialStore(hostID: hostID, token: "mobile-token"),
            session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))
        var message = ""
        do {
            _ = try await client.client.home.homeSummary()
            Issue.record("Expected the bridge's upstream error to be surfaced")
        } catch {
            message = error.localizedDescription
        }
        #expect(!message.contains(secret))
        #expect(!message.contains("mobile-token"))
    }

    @Test func uncertainRunSubmissionIsNeverRetriedAutomatically() async {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        BridgeStubURLProtocol.register(host: domain) { request in
            recorder.append(request)
            if request.url?.path.hasSuffix("/capabilities") == true { return capabilitiesResponse() }
            return BridgeStubResponse(status: 409, body: #"{"error":{"code":"command_uncertain","message":"pending"}}"#)
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }

        let client = BridgeHermesClient(
            credentials: BridgeTestCredentialStore(hostID: hostID, token: "token"),
            session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))
        do {
            _ = try await client.client.conversations.send(
                OutgoingMessage(text: "Safe test prompt"), conversationID: "conversation-one",
                configuration: RunConfiguration(hostID: hostID)
            )
            Issue.record("The bridge should surface the uncertain command result")
        } catch let error as HermesError {
            guard case .commandUncertain = error else {
                Issue.record("Expected commandUncertain, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected HermesError.commandUncertain, got \(error)")
        }

        let posts = recorder.requests.filter { $0.httpMethod == "POST" }
        #expect(posts.count == 1)
        #expect(posts.first?.value(forHTTPHeaderField: "Idempotency-Key") != nil)
        #expect(posts.first?.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test func unsupportedSteeringAndKanbanMovesNeverReachMutationEndpoints() async {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        let task: BridgeJSON = .object([
            "task": .object([
                "id": .string("task-one"), "profile": .string("default"),
                "state": .string("ready"), "raw_state": .string("ready"), "title": .string("Wait")
            ]),
            "board": .string("main"), "links": .object(["parents": .array([])]),
            "recent_activity": .array([]), "supported_targets": .array([.string("blocked")])
        ])
        BridgeStubURLProtocol.register(host: domain) { request in
            recorder.append(request)
            if request.url?.path.hasSuffix("/capabilities") == true {
                return capabilitiesResponse(features: #""sessions":true,"runs":true,"steering":false,"kanban":true"#)
            }
            if request.url?.path.hasSuffix("/kanban/tasks/task-one") == true { return BridgeStubResponse(body: encodedBridgeJSON(task)) }
            return BridgeStubResponse(body: #"{"acknowledged":true}"#)
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }
        let client = BridgeHermesClient(
            credentials: BridgeTestCredentialStore(hostID: hostID, token: "token"),
            session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))

        await #expect(throws: HermesError.unsupported(.steering)) {
            try await client.client.runs.steer(runID: "run-one", instruction: "Keep going")
        }
        await #expect(throws: HermesError.self) {
            try await client.client.tasks.setStatus(.inProgress, taskID: "task-one")
        }
        #expect(recorder.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func stopAndSteerUseRunScopedBridgeCommandsWithoutInventingCompletion() async throws {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        let stopping = runSnapshot(text: "", cursor: "test-epoch:1")
        let stoppingFields: [String: BridgeJSON] = {
            var fields = stopping.object
            fields["state"] = .string("stop_requested")
            return fields
        }()
        BridgeStubURLProtocol.register(host: domain) { request in
            recorder.append(request)
            if request.url?.path.hasSuffix("/capabilities") == true { return capabilitiesResponse() }
            if request.url?.path.hasSuffix("/runs/run-one/stop") == true {
                return BridgeStubResponse(body: encodedBridgeJSON(.object([
                    "acknowledged": .bool(true), "termination_confirmed": .bool(false), "run": .object(stoppingFields)
                ])))
            }
            if request.url?.path.hasSuffix("/runs/run-one/steer") == true {
                return BridgeStubResponse(body: #"{"status":"queued","consumed":false}"#)
            }
            return BridgeStubResponse(status: 404, body: #"{"error":{"code":"not_found"}}"#)
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }

        let client = BridgeHermesClient(
            credentials: BridgeTestCredentialStore(hostID: hostID, token: "token"),
            session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))
        try await client.client.runs.stop(runID: "run-one")
        try await client.client.runs.steer(runID: "run-one", instruction: "Finish the summary")

        let mutations = recorder.requests.filter { $0.httpMethod == "POST" }
        #expect(mutations.count == 2)
        #expect(mutations.contains { $0.url?.path.hasSuffix("/runs/run-one/stop") == true })
        #expect(mutations.contains { $0.url?.path.hasSuffix("/runs/run-one/steer") == true })
        #expect(mutations.allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") != nil })
        #expect(mutations.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token" })
    }

    @Test func attachmentsAreStagedAndLinkedToTheSubmittedConversation() async throws {
        let hostID = "studio-\(UUID().uuidString)", domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        BridgeStubURLProtocol.register(host: domain) { request in
            recorder.append(request)
            if request.url?.path.hasSuffix("/capabilities") == true { return capabilitiesResponse(features: #""sessions":true,"runs":true,"attachments":true"#) }
            if request.url?.path.hasSuffix("/attachments") == true { return BridgeStubResponse(body: #"{"staged":true,"upload_id":"upload-one"}"#) }
            if request.url?.path.hasSuffix("/runs") == true { return BridgeStubResponse(body: encodedBridgeJSON(runSnapshot(text:"", cursor:"test-epoch:1"))) }
            return BridgeStubResponse(status:404)
        }
        defer { BridgeStubURLProtocol.unregister(host:domain) }
        let client = BridgeHermesClient(credentials: BridgeTestCredentialStore(hostID:hostID, token:"token"), session:makeBridgeTestSession(), defaults:UserDefaults(suiteName:UUID().uuidString)!)
        await client.client.hosts.connect(to:bridgeHost(id:hostID,domain:domain))
        let file = try ComposerMedia.file(name:"evidence.md",data:Data("# local evidence".utf8))
        _ = try await client.client.conversations.send(OutgoingMessage(text:"Read it",attachments:[file]),conversationID:"conversation-one",configuration:RunConfiguration(hostID:hostID))
        let mutations = recorder.requests.filter { $0.httpMethod == "POST" }
        #expect(mutations.count == 2)
        let upload = try JSONDecoder().decode(BridgeJSON.self,from:mutations[0].httpBody!)
        let prompt = try JSONDecoder().decode(BridgeJSON.self,from:mutations[1].httpBody!)
        #expect(upload["conversation_id"].string == "conversation-one")
        #expect(upload["content_type"].string == "text/markdown")
        #expect(prompt["attachment_ids"].array.first?.string == "upload-one")
        #expect(mutations.allSatisfy { $0.value(forHTTPHeaderField:"Idempotency-Key") != nil })
        let saved = try JSONEncoder().encode(file)
        #expect(!String(decoding:saved,as:UTF8.self).contains("local evidence"))
    }

    @Test func botManagementUsesNormalizedFieldsAndReReadsThePersistedBot() async throws {
        let hostID = "studio-\(UUID().uuidString)", domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        let bot = #"{"id":"opaque-bot","name":"Updated bot","description":"Read-only helper","profile_id":"native-slug","model":"test","provider":"local","soul":"Use existing records only.","editable_fields":{"name":true,"description":true,"soul":true}}"#
        BridgeStubURLProtocol.register(host:domain) { request in
            recorder.append(request)
            if request.url?.path.hasSuffix("/capabilities") == true { return capabilitiesResponse(features:#""sessions":true,"runs":true,"botMode":true,"botCreate":true,"botEdit":true,"botHide":true,"botDuplicate":true,"botInventory":true"#) }
            if request.httpMethod == "POST" || request.httpMethod == "PATCH" { return BridgeStubResponse(body:"{\"bot\":\(bot)}") }
            return BridgeStubResponse(status:404)
        }
        defer { BridgeStubURLProtocol.unregister(host:domain) }
        let client = BridgeHermesClient(credentials:BridgeTestCredentialStore(hostID:hostID,token:"token"),session:makeBridgeTestSession(),defaults:UserDefaults(suiteName:UUID().uuidString)!)
        await client.client.hosts.connect(to:bridgeHost(id:hostID,domain:domain))
        var fields = ProfileChanges(); fields.name = "Phone bot"; fields.description = "Read-only helper"; fields.soul = "Use existing records only."
        let created = try await client.client.profiles.createBot(BotDraft(changes:fields))
        #expect(created.id == "opaque-bot")
        #expect(created.name == "Updated bot")
        #expect(created.soul == fields.soul)
        fields.name = "Edited bot"
        let edited = try await client.client.profiles.updateProfile(id:created.id,changes:fields)
        #expect(edited.id == created.id)
        _ = try await client.client.profiles.duplicateBot(id:created.id)
        let mutations = recorder.requests.filter { $0.httpMethod == "POST" || $0.httpMethod == "PATCH" }
        #expect(mutations.count == 3)
        #expect(mutations[1].url?.path.hasSuffix("/bots/opaque-bot") == true)
        #expect(mutations[0].timeoutInterval == 120)
        #expect(mutations[1].timeoutInterval == 30)
        #expect(mutations[2].timeoutInterval == 120)
        #expect(mutations.allSatisfy { $0.value(forHTTPHeaderField:"Idempotency-Key") != nil })
        #expect(recorder.requests.first?.timeoutInterval == 30)
    }

    @Test func confirmedBotCreationKeepsSoulWhenFollowupDetailFails() async throws {
        let hostID = UUID().uuidString, domain = uniqueBridgeTestHost()
        let bot = #"{"id":"confirmed-bot","name":"Phone bot","description":"Safe helper","soul":"Answer briefly.","editable_fields":{"soul":true,"description":true}}"#
        BridgeStubURLProtocol.register(host:domain) { request in
            if request.url?.path.hasSuffix("/capabilities") == true { return capabilitiesResponse(features:#""botMode":true,"botCreate":true"#) }
            if request.httpMethod == "POST" { return BridgeStubResponse(body:"{\"bot\":\(bot)}") }
            if request.url?.path.hasSuffix("/bots") == true { return BridgeStubResponse(body:#"{"bots":[{"id":"confirmed-bot","name":"Phone bot","description":"Safe helper"}]}"#) }
            return BridgeStubResponse(status:503)
        }
        defer { BridgeStubURLProtocol.unregister(host:domain) }
        let client = BridgeHermesClient(credentials:BridgeTestCredentialStore(hostID:hostID,token:"token"),session:makeBridgeTestSession())
        await client.connect(to:bridgeHost(id:hostID,domain:domain))
        let store = ProfileStore(client:client.client,cache:SnapshotCache(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        var fields = ProfileChanges(); fields.name = "Phone bot"; fields.description = "Safe helper"
        let created = try await store.create(BotDraft(changes:fields))
        #expect(created.soul == "Answer briefly.")
        #expect(created.editableFields == ["soul", "description"])
        #expect(store.profiles.count == 1)
    }

    @Test func timedOutMutationSurfacesUncertainAndIsNotRetried() async {
        let hostID = "studio-\(UUID().uuidString)"
        let domain = uniqueBridgeTestHost()
        let recorder = BridgeRequestRecorder()
        BridgeStubURLProtocol.register(host: domain) { request in
            recorder.append(request)
            if request.url?.path.hasSuffix("/capabilities") == true { return capabilitiesResponse() }
            return BridgeStubResponse(failure: .timedOut)
        }
        defer { BridgeStubURLProtocol.unregister(host: domain) }
        let client = BridgeHermesClient(
            credentials: BridgeTestCredentialStore(hostID: hostID, token: "token"),
            session: makeBridgeTestSession(), defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await client.client.hosts.connect(to: bridgeHost(id: hostID, domain: domain))
        do {
            _ = try await client.client.conversations.send(
                OutgoingMessage(text: "Safe prompt"), conversationID: "conversation-one",
                configuration: RunConfiguration(hostID: hostID)
            )
            Issue.record("A timed out prompt must be surfaced as uncertain")
        } catch let error as HermesError {
            guard case .commandUncertain = error else {
                Issue.record("Expected commandUncertain, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected HermesError.commandUncertain, got \(error)")
        }
        #expect(recorder.requests.filter { $0.httpMethod == "POST" }.count == 1)
    }

    @Test func appRelaunchRestoresActiveRunAndSubscribesFromSavedCursor() async throws {
        let fixtures = MockFixtures.standard()
        let backend = MockHermesBackend(fixtures: fixtures)
        var client = HermesClient.mock(backend)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = SnapshotCache(directory: directory)
        let cursor = EventCursor(value: "saved-epoch:41")
        let activeRun = try #require(fixtures.runs.first(where: { $0.state.isActive }))
        let summary = try await backend.homeSummary()
        try cache.commit(AppliedBridgeState(
            cursor: cursor, hostID: MockID.studio, home: summary, runs: [activeRun], approvals: [],
            conversations: [], transcripts: [:], profiles: [], tasks: [], routines: []
        ))
        let acknowledger = BridgeAckRecorder(cache: cache)
        client.events = acknowledger
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let environment = AppEnvironment(
            client: client, simulator: nil, preferences: AppPreferences(defaults: defaults), cache: cache,
            savedHosts: SavedHostStore(defaults: defaults), drafts: DraftStore(defaults: defaults),
            notifier: LocalNotificationService(), defaultHosts: fixtures.hosts
        )

        await environment.start()

        #expect(environment.activity.run(activeRun.id)?.state.isActive == true)
        #expect(environment.home.summary == summary)
        #expect(acknowledger.subscribedCursor == cursor)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func canonicalPublicIdentityIsBuiltIntoTheHostedApp() {
        #expect(Bundle.main.bundleIdentifier == "xyz.majorminor.talaria")
    }

    @Test func defaultKeychainServiceUsesTheRuntimeBundleIdentifier() throws {
        let runtimeID = try #require(Bundle.main.bundleIdentifier)
        let hostID = "identity-fixture-\(UUID().uuidString)"
        let defaultStore = KeychainBridgeCredentialStore()
        let explicitStore = KeychainBridgeCredentialStore(service: runtimeID)
        defer { try? defaultStore.remove(forHostID: hostID) }
        try defaultStore.save("identity-fixture-token", forHostID: hostID)
        #expect(try explicitStore.token(forHostID: hostID) == "identity-fixture-token")
    }

    @Test func keychainServicesKeepBaseAndResignedIdentifiersSeparate() throws {
        // This tests service isolation, not Apple signing or access-group migration.
        let hostID = "identity-fixture-\(UUID().uuidString)"
        let base = KeychainBridgeCredentialStore(service: "xyz.majorminor.talaria")
        let resigned = KeychainBridgeCredentialStore(service: "xyz.majorminor.talaria.EXAMPLETEAM")
        defer { try? base.remove(forHostID: hostID); try? resigned.remove(forHostID: hostID) }
        try resigned.save("resigned-fixture-token", forHostID: hostID)
        #expect(try resigned.token(forHostID: hostID) == "resigned-fixture-token")
        #expect(try base.token(forHostID: hostID) == nil)
    }

    @Test func keychainCredentialCanBeSavedReadAndRevokedLocally() throws {
        let service = "hermes.tests.\(UUID().uuidString)"
        let credentials = KeychainBridgeCredentialStore(service: service)
        defer { try? credentials.remove(forHostID: "studio") }

        try credentials.save("private-mobile-token", forHostID: "studio")
        #expect(try credentials.token(forHostID: "studio") == "private-mobile-token")
        try credentials.remove(forHostID: "studio")
        #expect(try credentials.token(forHostID: "studio") == nil)
    }

    @Test func capabilityDiscoveryKeepsUnsafeOrUnimplementedFeaturesDisabled() {
        let json: BridgeJSON = .object([
            "profiles": .object(["default": .object([
                "features": .object([
                    "sessions": .bool(true),
                    "runs": .bool(true),
                    "kanban": .bool(true),
                    "approvals": .object(["respond": .bool(false)]),
                    "memory": .bool(true),
                    "integrations": .bool(true),
                    "logs": .bool(true),
                    "attachments": .bool(true)
                ])
            ])])
        ])

        let capabilities = BridgeMapping.capabilities(json)
        #expect(capabilities.contains(.sessions))
        #expect(capabilities.contains(.runs))
        #expect(capabilities.contains(.kanban))
        #expect(!capabilities.contains(.botChat))
        #expect(!capabilities.contains(.approvals))
        #expect(!capabilities.contains(.memory))
        #expect(!capabilities.contains(.integrations))
        #expect(!capabilities.contains(.logs))
        #expect(capabilities.contains(.attachments))
        var optedIn = json
        var root = optedIn.object
        var profiles = root["profiles"]?.object ?? [:]
        var defaultProfile = profiles["default"]?.object ?? [:]
        var features = defaultProfile["features"]?.object ?? [:]
        features["botChat"] = .bool(true)
        defaultProfile["features"] = .object(features)
        profiles["default"] = .object(defaultProfile)
        root["profiles"] = .object(profiles)
        optedIn = .object(root)
        #expect(BridgeMapping.capabilities(optedIn).contains(.botChat))
    }

    @Test func reportedUsageDoesNotDoubleCountReasoning() {
        let analytics = BridgeMapping.tokens(.object([
            "total_input":.integer(50),"total_output":.integer(25),"total_reasoning":.integer(15)
        ]))
        #expect(analytics.total == 75)
        #expect(analytics.reasoning == 15)
        let run = BridgeMapping.tokens(.object([
            "input":.integer(50),"output":.integer(25),"reasoning":.integer(15),
            "total":.integer(80),"cache_write":.integer(4)
        ]))
        #expect(run.total == 80)
        #expect(run.cacheWritten == 4)
    }

    @Test func taskMappingPreservesBridgeTransitionsAndOpaqueDependencies() {
        let json: BridgeJSON = .object([
            "task": .object([
                "id": .string("task-opaque-42"),
                "board": .string("board-mobile"),
                "profile": .string("default"),
                "state": .string("done"),
                "raw_state": .string("done"),
                "title": .string("Review integration"),
                "body": .string("Check the bridge mapping"),
                "priority": .integer(2),
                "created_at": .number(1_790_916_000),
                "updated_at": .number(1_790_916_010)
            ]),
            "links": .object(["parents": .array([.string("parent-mobile-id")])]),
            "supported_targets": .array([
                .string("triage"), .string("todo"), .string("ready"), .string("archived")
            ])
        ])

        let task = BridgeMapping.task(json, hostID: "studio")
        #expect(task.id == "task-opaque-42")
        #expect(task.status == .completed)
        #expect(task.sourceState == "done")
        #expect(task.boardID == "board-mobile")
        #expect(task.dependencyIDs == ["parent-mobile-id"])
        #expect(task.availableTransitions == [.triage, .todo, .ready, .archived])
        #expect(!task.availableTransitions.contains(.inProgress))
    }
}

/// Talaria shows each bot's Studio avatar (Desktop's face) in the roster and
/// chat list. The roster read omits avatar bytes, so the store fetches the
/// existing detail once per bot per session and keeps it across refreshes.
@MainActor
struct BotIdentityTests {
    nonisolated private final class AvatarFixture: @unchecked Sendable {
        let recorder = BridgeRequestRecorder()
        static let avatar = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        func response(_ request: URLRequest) -> BridgeStubResponse {
            recorder.append(request)
            let path = request.url!.path
            if path.hasSuffix("/capabilities") { return capabilitiesResponse(features: #""sessions":true,"profiles":true,"botMode":true"#) }
            func row(_ id: String, _ name: String, avatar: Bool, detail: Bool) -> BridgeJSON {
                var fields: [String: BridgeJSON] = ["id": .string(id), "name": .string(name), "profile_id": .string(id),
                    "is_default": .bool(id == "default"), "status": .string("unknown"), "has_avatar": .bool(avatar),
                    "model": .string("studio-model"), "provider": .string("studio-provider")]
                if detail && avatar { fields["avatar_data"] = .string(Self.avatar) }
                return .object(fields)
            }
            if path.hasSuffix("/bots") {
                return BridgeStubResponse(body: encodedBridgeJSON(.object(["bots": .array([
                    row("default", "Hermes", avatar: true, detail: false),
                    row("research-worker", "Research Worker", avatar: false, detail: false)])])))
            }
            if path.hasSuffix("/bots/default") { return BridgeStubResponse(body: encodedBridgeJSON(row("default", "Hermes", avatar: true, detail: true))) }
            return BridgeStubResponse(body: encodedBridgeJSON(row("research-worker", "Research Worker", avatar: false, detail: true)))
        }
        var detailReads: Int { recorder.requests.filter { $0.url!.path.contains("/bots/") }.count }
    }

    @Test func rosterLoadsStudioAvatarsOnceAndKeepsThemAcrossRefresh() async throws {
        let domain = uniqueBridgeTestHost(), hostID = UUID().uuidString
        let fixture = AvatarFixture()
        BridgeStubURLProtocol.register(host: domain) { fixture.response($0) }
        defer { BridgeStubURLProtocol.unregister(host: domain) }
        let backend = BridgeHermesClient(credentials: BridgeTestCredentialStore(hostID: hostID, token: "test-token"), session: makeBridgeTestSession())
        await backend.connect(to: bridgeHost(id: hostID, domain: domain))
        let cache = SnapshotCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let store = ProfileStore(client: backend.client, cache: cache)

        await store.refresh()
        #expect(store.profile("default")?.profileKey == "default")
        #expect(store.profile("default")?.hasAvatar == true)
        #expect(store.profile("default")?.avatarData == nil)

        await store.loadMissingAvatars()
        #expect(store.profile("default")?.avatarData == AvatarFixture.avatar)
        // Only the bot that has an avatar is read in detail.
        #expect(fixture.detailReads == 1)

        await store.refresh()
        #expect(store.profile("default")?.avatarData == AvatarFixture.avatar)
        await store.loadMissingAvatars()
        #expect(fixture.detailReads == 1)

        // Sessions on the default Hermes profile wear the default bot's identity.
        #expect(store.identity(Profile.defaultID)?.name == "Hermes")
        #expect(store.identity("research-worker")?.name == "Research Worker")
        #expect(store.identity("unknown-bot") == nil)
    }
}
