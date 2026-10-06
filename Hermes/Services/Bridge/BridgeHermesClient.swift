import Foundation
import OSLog

/// One aggregate, one SSE subscription. Studio remains the owner of execution.
final class BridgeHermesClient: HostService, HomeService, ConversationService, RunService, ProfileService,
    TaskService, ScheduleService, MemoryService, SkillService, ToolService, IntegrationService, UsageService,
    LogService, HermesEventStream, ArtifactService, CaptureService {
    private let credentials: any BridgeCredentialStore
    private let session: URLSession
    private let defaults: UserDefaults
    private var host: Host?
    private var transport: BridgeTransport?
    private var capabilityJSON: BridgeJSON = .null
    private var discoveredBotMode = false
    private var currentStatus = HostStatus.unknown("")
    private var continuation: AsyncStream<HermesEventEnvelope>.Continuation?
    private var streamTask: Task<Void, Never>?
    private var pendingCursor: String?
    private var acknowledgement: CheckedContinuation<Void, Never>?
    private var committedCursor: EventCursor?
    private var projections: [String: BridgeJSON] = [:]
    private var toolsByRun: [String:[String:ToolCall]] = [:]
    private var timelines: [String: [RunEvent]] = [:]
    private var knownConversations: [String: Conversation] = [:]
    private var seenSeq = 0
    private var epoch = ""
    private var generation = UUID()

    init(credentials: any BridgeCredentialStore = KeychainBridgeCredentialStore(), session: URLSession? = nil, defaults: UserDefaults = .standard) {
        self.credentials = credentials; self.session = session ?? BridgeTransport.makeSession(); self.defaults = defaults
    }
    var client: HermesClient {
        HermesClient(hosts: self, home: self, events: self, conversations: self, runs: self, profiles: self,
            tasks: self, schedules: self, memory: self, skills: self, tools: self, integrations: self, usage: self, logs: self)
    }
    private var hostID: String { host?.id ?? "" }
    private var profileIDs: [String] { capabilityJSON["profiles"].object.keys.sorted() }
    private var primaryProfile: String { profileIDs.contains("default") ? "default" : (profileIDs.first ?? "default") }
    private func requireTransport() throws -> BridgeTransport { guard let transport else { throw HermesError.bridgeUnreachable }; return transport }
    private func request(_ path: String, method: String = "GET", body: BridgeJSON? = nil, query: [String:String] = [:], responseTimeout: TimeInterval? = nil, commandID suppliedID: UUID? = nil) async throws -> BridgeJSON {
        let t = try requireTransport()
        let origin = host?.bridgeURL
        let commandID = method == "GET" ? nil : (suppliedID ?? UUID())
        if let commandID { recordCommand(commandID, method: method, path: path, state: "pending") }
        do {
            let result = try await t.request(method: method, path: path, query: query,
                body: method == "GET" ? nil : (body ?? .object([:])), idempotencyKey: commandID, responseTimeout: responseTimeout)
            guard origin == host?.bridgeURL else { throw CancellationError() }
            if let commandID { recordCommand(commandID, method: method, path: path, state: "accepted") }
            return result
        } catch {
            if (error as? HermesError) == .unauthorized { publishStatus(.authenticationRequired) }
            if let commandID { recordCommand(commandID, method: method, path: path,
                state: (error as? HermesError) == .unauthorized ? "rejected" : "inspect_state") }
            throw error
        }
    }
    private func recordCommand(_ id: UUID, method: String, path: String, state: String) {
        // No credentials, request body, prompts or results in this receipt.
        let key = "bridge.commandReceipts.\(hostID)"
        var rows = defaults.array(forKey: key) as? [[String:String]] ?? []
        rows.removeAll { $0["id"] == id.uuidString }
        rows.append(["id":id.uuidString,"method":method,"resource":path,"state":state,"time":String(Date.now.timeIntervalSince1970)])
        defaults.set(Array(rows.suffix(100)), forKey:key)
    }
    private func check(_ capability: HermesCapability) throws {
        guard currentStatus.capabilities.contains(capability) else { throw HermesError.unsupported(capability) }
    }
    private func resource(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 300, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) }) else { throw HermesError.notFound }
        return id
    }
    private func publishStatus(_ state: ConnectionState) {
        currentStatus.connection = state
        continuation?.yield(HermesEventEnvelope(cursor: EventCursor(value: ""), event: .hostStatus(currentStatus)))
    }
    func connect(to host: Host) async {
        let changed = self.host != nil && (self.host?.id != host.id || self.host?.bridgeURL != host.bridgeURL)
        self.host = host
        if changed {
            projections.removeAll(); toolsByRun.removeAll(); timelines.removeAll(); knownConversations.removeAll()
            capabilityJSON = .null; discoveredBotMode = false; transport = nil
        }
        currentStatus = .unknown(host.id)
        publishStatus(.connecting)
        guard let url = host.bridgeURL else { publishStatus(.bridgeOffline); return }
        do {
            let t = try BridgeTransport(baseURL: url, hostID: host.id, credentialStore: credentials, session: session)
            transport = t
            let j = try await t.request(method: "GET", path: "/capabilities")
            try acceptCapabilities(j)
            publishStatus(currentStatus.connection)
        } catch { publishStatus(state(for: error)) }
    }
    private func acceptCapabilities(_ j: BridgeJSON) throws {
        guard j["api_version"].int == 1 else { throw HermesError.rejected("This bridge API version is unsupported") }
        capabilityJSON = j
        currentStatus = BridgeMapping.host(j, hostID: hostID)
        // Offline capability snapshots withdraw controls, not bot identity.
        discoveredBotMode = discoveredBotMode || currentStatus.capabilities.contains(.botMode)
    }
    private func state(for error: Error) -> ConnectionState {
        switch error as? HermesError { case .unauthorized: .authenticationRequired; case .hermesOffline: .hermesOffline; default: .bridgeOffline }
    }
    func disconnect(hostID: String) async {
        guard self.hostID == hostID else { return }
        streamTask?.cancel(); acknowledgement?.resume(); acknowledgement = nil
        transport = nil; publishStatus(.bridgeOffline)
    }
    func status(hostID: String) async throws -> HostStatus {
        guard self.hostID == hostID else { return .unknown(hostID) }
        let start = Date.now
        let j = try await request("/capabilities"); try acceptCapabilities(j)
        currentStatus.latencyMilliseconds = Int(Date.now.timeIntervalSince(start) * 1000)
        publishStatus(currentStatus.connection)
        return currentStatus
    }
    func runOptions(hostID: String) async throws -> RunOptions {
        var models: [ModelRef] = []
        let j = try await request("/inventory/models", query: ["profile": primaryProfile])
        for provider in j["providers"].array {
            for row in provider["models"].array {
                guard let id = row["id"].string else { continue }
                models.append(ModelRef(id: id, displayName: row["label"].string ?? row["name"].string ?? id, provider: provider["id"].string ?? "Hermes",supportsReasoning:row["supports_reasoning"].bool ?? provider["model_capabilities"][id]["reasoning"].bool))
            }
        }
        let projects = capabilityJSON["profiles"][primaryProfile]["workspaces"].array.compactMap { j -> ProjectContext? in
            guard let id = j["id"].string else { return nil }; return ProjectContext(name: j["name"].string ?? id, path: id)
        }
        return RunOptions(models: models, reasoningLevels: ReasoningLevel.allCases, projects: projects)
    }
    func homeSummary() async throws -> HomeSummary {
        let j = try await request("/home")
        let studios = j["studios"].array
        currentStatus.connection = studios.allSatisfy { $0["connection"]["connected"].bool == true } && !studios.isEmpty ? .connected : .hermesOffline
        currentStatus.bridgeVersion = j["bridge"]["version"].string
        currentStatus.activeRunCount = j["active_runs"].array.count
        currentStatus.lastSeen = .now
        let hostStats = studios.first?["host"] ?? .null
        if let cpu = hostStats["cpu_percent"].double, let mem = hostStats["memory"]["percent"].double, let uptime = hostStats["uptime_seconds"].double {
            currentStatus.resources = HostResources(cpuLoad: cpu / 100, memoryUsed: mem / 100, uptime: uptime)
        }
        publishStatus(currentStatus.connection)
        var attention = j["attention"].array.map { a in
            let value = mapAttention(a)
            return AttentionItem(id: value.id, kind: .approval, title: value.summary, detail: value.availability.explanation,
                date: value.requestedAt, profileID: value.profileID, runID: value.runID, approvalID: value.id)
        }
        for item in j["failed_or_blocked"].array {
            let isTask = item["kind"].string == "kanban"
            let isCron = item["kind"].string == "cron"
            attention.append(AttentionItem(id: item["id"].string ?? "", kind: isTask ? .blockedTask : .failedRun,
                title: item["title"].string ?? item["name"].string ?? (isCron ? "Scheduled work failed" : "Run requires attention"),
                detail: item["block_reason"].string ?? item["reason"].string ?? item["last_error"].string,
                date: BridgeMapping.date(item["updated_at"]) ?? BridgeMapping.date(item["created_at"]) ?? .distantPast,
                profileID: item["profile"].string, runID: !isTask && !isCron ? item["id"].string : nil,
                taskID: isTask ? item["id"].string : nil))
        }
        for error in j["coverage_errors"].array {
            attention.append(AttentionItem(id: "coverage-\(error["profile"].string ?? "")-\(error["resource"].string ?? "")", kind: .hostIssue,
                title: "Some Studio state is unavailable", detail: "Refresh after Hermes reconnects", date: .now, profileID: error["profile"].string))
        }
        return HomeSummary(host: currentStatus, activeRuns: j["active_runs"].array.map { materializeSnapshot($0) }, attention: attention,
            recentRuns: j["recent_completions"].array.filter { $0["origin"].string == "desktop_rpc" }.map { materializeSnapshot($0) },
            upcoming: j["upcoming_jobs"].array.map { BridgeMapping.routine($0, hostID: hostID) }, generatedAt: BridgeMapping.date(j["observed_at"]) ?? .now)
    }
    // MARK: Conversations. Pinning is exclusively local, namespaced by host.
    private var pinKey: String { "bridge.pins.\(hostID)" }
    private var pinnedIDs: Set<String> { Set(defaults.stringArray(forKey: pinKey) ?? []) }
    private func remember(_ j: BridgeJSON) -> Conversation {
        var c = BridgeMapping.conversation(j, hostID: hostID)
        c.isPinned = pinnedIDs.contains(c.id)
        if let previous = knownConversations[c.id] { c.project = previous.project; c.preview = previous.preview }
        let matching = projections.values.filter { $0["conversation_id"].string == c.id }.sorted { ($0["created_at"].double ?? 0) < ($1["created_at"].double ?? 0) }
        if let recent = matching.last {
            c.lastActivity = BridgeMapping.date(recent["updated_at"]) ?? c.lastActivity
            c.activeRunID = BridgeMapping.run(recent, hostID: hostID).state.isActive ? recent["id"].string : nil
            c.preview = String((recent["assistant_text"].string ?? c.preview).prefix(160))
        }
        knownConversations[c.id] = c; return c
    }
    func searchConversations(_ query: String) async throws -> [Conversation] {
        try check(.sessions)
        var matches: [Conversation] = []
        for p in profileIDs { let page = try await request("/conversations", query: ["profile": p, "q": query, "limit": "100"]); matches += page["conversations"].array.map(remember) }
        return matches
    }
    func listConversations() async throws -> [Conversation] {
        try check(.sessions)
        var rows: [Conversation] = []
        for p in profileIDs {
            var offset = 0
            repeat {
                let j = try await request("/conversations", query: ["profile": p, "limit":"100", "offset":String(offset)])
                let page = j["conversations"].array
                rows += page.map(remember)
                offset += 100
                if page.count < 100 || offset >= 10000 { break }
            } while true
        }
        return rows
    }
    func messages(conversationID: String) async throws -> [Message] {
        let id = try resource(conversationID)
        let conversation = knownConversations[conversationID]
        let path: String
        if conversation?.isBotChat == true, let botID = conversation?.botID {
            path = "/bots/\(try resource(botID))/conversation"
        } else if conversation?.readOnly == true, conversationID.hasPrefix("botchat.") {
            // Older Bot Mode bridges encoded the bot ID in this read-only
            // alias. Writable chats use explicit bot metadata above.
            path = "/bots/\(try resource(String(conversationID.dropFirst("botchat.".count))))/conversation"
        } else {
            path = "/conversations/\(id)"
        }
        let j = try await request(path)
        let c = remember(j["conversation"])
        let runs = j["observed_runs"].array.sorted { ($0["created_at"].double ?? 0) < ($1["created_at"].double ?? 0) }
        for r in runs { _ = materializeSnapshot(r) }
        // Match canonical assistant rows to owned runs by timestamp/response order.
        // The database ID is retained for imported rows; live owned bubbles use a run ID.
        var result: [Message] = []
        var used = Set<String>()
        for (index, row) in j["messages"].array.enumerated() {
            let rawRole = row["role"].string ?? "system"
            let role: MessageRole = rawRole == "tool" ? .assistant : (MessageRole(rawValue: rawRole) ?? .system)
            let text = content(row["content"])
            var messageID = "history-\(c.id)-\(row["id"].string ?? row["id"].int.map(String.init) ?? String(index))"
            var runID: String?
            if rawRole == "assistant", !text.isEmpty {
                let timestamp = BridgeMapping.date(row["timestamp"]) ?? BridgeMapping.date(row["created_at"])
                let match = runs.first { r in
                    guard let rid = r["id"].string, !used.contains(rid), let response = r["assistant_text"].string, !response.isEmpty else { return false }
                    if response != text { return false }
                    return timestamp.map { $0 >= (BridgeMapping.date(r["created_at"]) ?? .distantPast).addingTimeInterval(-1) } ?? true
                }
                if let rid = match?["id"].string { runID = rid; messageID = "assistant-\(rid)"; used.insert(rid) }
            }
            var parts: [MessagePart] = text.isEmpty ? [] : [.markdown(text)]
            if rawRole == "tool" {
                let name = row["tool_name"].string ?? "Tool"
                parts = [.tools([ToolCall(id: row["tool_call_id"].string ?? messageID, kind: BridgeMapping.toolKind(name), name: name,
                    summary: name.replacingOccurrences(of: "_", with: " ").capitalized, output: text)])]
            }
            for call in row["tool_calls"].array {
                let name = call["function"]["name"].string ?? "Tool"
                parts.append(.tools([ToolCall(id: call["id"].string ?? messageID, kind: BridgeMapping.toolKind(name), name: name,
                    summary: name.replacingOccurrences(of: "_", with: " ").capitalized, input: call["function"]["arguments"].string)]))
            }
            result.append(Message(id: messageID, conversationID: c.id, role: role,
                createdAt: BridgeMapping.date(row["timestamp"]) ?? BridgeMapping.date(row["created_at"]) ?? c.createdAt.addingTimeInterval(Double(index) / 1000),
                parts: parts, runID: runID))
        }
        // A response not yet persisted by Hermes is kept as one live projection.
        for r in runs where !used.contains(r["id"].string ?? "") {
            if let m = assistantMessage(r), !m.plainText.isEmpty { result.append(m) }
        }
        return result.sorted { $0.createdAt < $1.createdAt }
    }
    private func content(_ j: BridgeJSON) -> String {
        if let text = j.string { return text }
        return j.array.compactMap { $0["text"].string }.joined(separator: "\n")
    }
    func createConversation(configuration: RunConfiguration) async throws -> Conversation { try await createConversation(configuration: configuration, commandID: UUID()) }
    func createConversation(configuration: RunConfiguration, commandID: UUID) async throws -> Conversation {
        try check(.sessions)
        var body: [String:BridgeJSON] = ["reasoning_effort": .string(configuration.reasoning == .off || configuration.model?.supportsReasoning == false ? "none" : configuration.reasoning.rawValue)]
        if let m = configuration.model { body["model"] = .string(m.id); body["provider"] = .string(m.provider) }
        if let w = configuration.project { body["workspace"] = .string(w.path) }
        let isBot = discoveredBotMode && !profileIDs.contains(configuration.profileID)
        if isBot && !currentStatus.capabilities.contains(.botThreads) {
            guard configuration.model == nil, configuration.project == nil else { throw HermesError.unsupported(.botThreads) }
            guard let c = try await canonicalConversation(profileID: configuration.profileID) else { throw HermesError.unsupported(.botChat) }
            return c
        }
        if isBot && configuration.model == nil { body.removeValue(forKey: "reasoning_effort") }
        let path = isBot ? "/bots/\(try resource(configuration.profileID))/conversations" : "/conversations"
        let j = try await request(path, method: "POST", body: .object(body), query: isBot ? [:] : ["profile": configuration.profileID], commandID: commandID)
        var c = remember(j); c.project = configuration.project; knownConversations[c.id] = c
        continuation?.yield(.init(cursor: .init(value:""), event: .conversationUpserted(c)))
        return c
    }
    func commandObservation(_ id: UUID, creating: Bool) async throws -> CommandObservation {
        let receipt = try await request("/commands/\(id.uuidString)")
        if receipt["state"].string == "not_received" { return .notReceived }
        guard receipt["state"].string == "done", let status = receipt["result"]["status"].int else { return .pending }
        let body = receipt["result"]["body"]
        guard (200..<300).contains(status) else { return .rejected(body["error"]["message"].string ?? "Command was rejected") }
        if creating { return .conversation(remember(body)) }
        let mapped = materializeSnapshot(body)
        return .run(mapped)
    }
    func setArchived(_ archived: Bool, conversationID: String) async throws {
        let c = remember(try await request("/conversations/\(resource(conversationID))", method: "PATCH", body: .object(["archived": .bool(archived)])))
        continuation?.yield(.init(cursor: .init(value: ""), event: .conversationUpserted(c)))
    }
    func uploadCaptureMedia(_ media: LocalMedia) async throws -> String {
        let result = try await request("/captures/uploads", method: "POST", body: .object([
            "name": .string(media.name), "content_type": .string(media.contentType),
            "content_base64": .string(media.data.base64EncodedString())]), commandID: media.id)
        guard let id = result["upload_id"].string else { throw HermesError.rejected("Bridge did not confirm the capture upload") }
        return id
    }
    func saveCapture(_ capture: CaptureRecord) async throws -> String {
        let j = try await request("/captures", method: "POST", body: .object([
            "client_capture_id": .string(capture.id.uuidString), "created_at": .string(ISO8601DateFormatter().string(from: capture.createdAt)),
            "kind": .string(capture.kind.rawValue), "text": .string(capture.text),
            "attachment_ids": .array(capture.media.compactMap { $0.uploadID }.map { .string($0) }),
            "context": .object(capture.context.map { key, value in (key, key == "transcribed_on_device" ? BridgeJSON.bool(value == "true") : .string(value)) }.reduce(into: [String:BridgeJSON]()) { $0[$1.0] = $1.1 })]), commandID: capture.id)
        guard let id = j["capture_id"].string else { throw HermesError.rejected("Bridge did not confirm capture persistence") }
        return id
    }
    func resumeConversation(id: String) async throws { _ = try await request("/conversations/\(resource(id))/resume", method:"POST") }
    func renameConversation(id: String, title: String) async throws {
        let c = remember(try await request("/conversations/\(resource(id))", method:"PATCH", body:.object(["title":.string(title)])))
        continuation?.yield(.init(cursor: .init(value:""), event:.conversationUpserted(c)))
    }
    func deleteConversation(id: String) async throws {
        _ = try await request("/conversations/\(resource(id))", method:"DELETE")
        knownConversations[id] = nil
        continuation?.yield(.init(cursor: .init(value:""), event:.conversationRemoved(id)))
    }
    func setPinned(_ pinned: Bool, conversationID: String) async throws {
        var pins = pinnedIDs; if pinned { pins.insert(conversationID) } else { pins.remove(conversationID) }
        defaults.set(Array(pins), forKey: pinKey)
        if var c = knownConversations[conversationID] { c.isPinned = pinned; knownConversations[c.id] = c; continuation?.yield(.init(cursor: .init(value:""), event:.conversationUpserted(c))) }
    }
    private var stagedAttachments: [String: String] = [:]
    func send(_ message: OutgoingMessage, conversationID: String, configuration: RunConfiguration) async throws -> Run { try await send(message, conversationID: conversationID, configuration: configuration, commandID: UUID()) }
    func send(_ message: OutgoingMessage, conversationID: String, configuration: RunConfiguration, commandID: UUID) async throws -> Run {
        try check(.runs)
        var uploaded: [BridgeJSON] = []
        if !message.attachments.isEmpty { try check(.attachments) }
        for file in message.attachments {
            let cacheKey = "\(hostID):\(conversationID):\(file.id)"
            if let id = stagedAttachments[cacheKey] { uploaded.append(.string(id)); continue }
            guard let data = file.data, !data.isEmpty, data.count <= 10 * 1024 * 1024,
                  let mime = file.contentType else { throw HermesError.rejected("Attachment is unavailable or exceeds 10 MiB") }
            let result = try await request("/attachments", method:"POST", body:.object([
                "conversation_id":.string(conversationID), "name":.string(file.name),
                "content_type":.string(mime), "content_base64":.string(data.base64EncodedString())]), commandID: UUID(uuidString: file.id))
            guard let id = result["upload_id"].string else { throw HermesError.rejected("Bridge did not confirm the upload") }
            stagedAttachments[cacheKey] = id; uploaded.append(.string(id))
        }
        let j = try await request("/conversations/\(resource(conversationID))/runs", method:"POST", body:.object([
            "text":.string(message.text.isEmpty ? "Please inspect the attached files." : message.text), "attachment_ids":.array(uploaded)]), commandID: commandID)
        for file in message.attachments { stagedAttachments["\(hostID):\(conversationID):\(file.id)"] = nil }
        let run = materializeSnapshot(j)
        // Refresh the canonical user row, not an optimistic duplicate.
        let events: [HermesEvent] = [.runUpserted(run)] + ((try? await messages(conversationID:conversationID)) ?? []).map { .messageUpserted($0) }
        continuation?.yield(.init(cursor: .init(value:""), event:.batch(events)))
        return run
    }
    // MARK: Runs / safe controls
    private func materializeSnapshot(_ j: BridgeJSON) -> Run {
        let id = j["id"].string ?? ""
        if BridgeMapping.sequence(projections[id]?["snapshot_cursor"].string) <= BridgeMapping.sequence(j["snapshot_cursor"].string) { projections[id] = j }
        var run = BridgeMapping.run(projections[id] ?? j, hostID:hostID)
        if let c = knownConversations[run.conversationID ?? ""] { run.title = c.title; run.model = c.model; run.project = c.project }
        if currentStatus.permissionScopes?.contains("chat.control") == false { run.stopSupported = false; run.steerSupported = false; run.retrySupported = false }
        let watermark = run.lastSequence
        var events = timelines[id] ?? []
        if watermark > (events.last?.sequence ?? 0) { events.append(RunEvent(id:"snapshot-\(id)-\(watermark)", sequence:watermark, kind:.output, title:"State observed")) }
        run.events = events
        return run
    }
    func listRuns() async throws -> [Run] {
        var result: [Run] = []; var offset = 0
        repeat {
            let j = try await request("/runs", query:["limit":"100", "offset":String(offset)])
            let rows = j["runs"].array
            result += rows.map(materializeSnapshot)
            if rows.count < 100 || offset >= 1000 { break }; offset += 100
        } while true
        return result
    }
    func run(id: String) async throws -> Run {
        let j = try await request("/runs/\(resource(id))")
        var cursor: String?; var events: [RunEvent] = []
        do {
            repeat {
                var q = ["limit":"500"]; if let cursor { q["after"] = cursor }
                let page = try await request("/runs/\(resource(id))/events", query:q)
                events += page["events"].array.filter { $0["type"].string != "assistant.delta" }.map(BridgeMapping.timeline)
                cursor = page["cursor"].string
                if page["has_more"].bool != true { break }
            } while true
        } catch HermesError.resyncRequired { /* Retained state remains available; old timeline expired. */ }
        timelines[id] = events; return materializeSnapshot(j)
    }
    private func mapAttention(_ j: BridgeJSON) -> ApprovalRequest {
        var value = BridgeMapping.approval(j)
        if value.isClarification && currentStatus.permissionScopes?.contains("approvals.respond") == false {
            value.availability = .unavailableRemotely("This device has read-only access to input requests")
        }
        return value
    }
    func pendingApprovals() async throws -> [ApprovalRequest] {
        let j = try await request("/attention")
        return j["items"].array.filter { $0["state"].string == "pending" }.map { mapAttention($0) }
    }
    func stop(runID: String) async throws {
        let j = try await request("/runs/\(resource(runID))/stop", method:"POST")
        let r = materializeSnapshot(j["run"])
        continuation?.yield(.init(cursor: .init(value:""), event:.runUpserted(r)))
    }
    func steer(runID: String, instruction: String) async throws {
        try check(.steering)
        _ = try await request("/runs/\(resource(runID))/steer", method:"POST", body:.object(["text":.string(instruction)]))
    }
    func retry(runID: String) async throws -> Run {
        let r = materializeSnapshot(try await request("/runs/\(resource(runID))/retry", method:"POST"))
        continuation?.yield(.init(cursor:.init(value:""), event:.runUpserted(r))); return r
    }
    func resolveApproval(id: String, decision: ApprovalDecision) async throws {
        throw HermesError.rejected("This action must be resolved on the Studio. Remote dangerous approvals are disabled.")
    }
    func answerClarification(id: String, answer: String) async throws {
        _ = try await request("/attention/\(resource(id))/respond", method:"POST", body:.object(["answer":.string(answer)]))
    }
    // MARK: Read-only profiles and inventories
    func listProfiles() async throws -> [Profile] {
        // Startup must finish discovery before choosing an identity namespace.
        guard !capabilityJSON["profiles"].object.isEmpty else { throw HermesError.bridgeUnreachable }
        if discoveredBotMode {
            let j = try await request("/bots")
            return j["bots"].array.map { BridgeMapping.bot($0, hostID: hostID) }
        }
        let j = try await request("/profiles")
        return j["profiles"].array.map { p in
            let active = p["activity"].array.first
            return Profile(id:p["id"].string ?? "", name:p["name"].string ?? "Hermes", role:"Hermes profile",
                summary:p["description"].string ?? "", tint:.slate,
                model:BridgeMapping.model(p) ?? ModelRef(id:"default", displayName:"Hermes default", provider:p["provider"].string ?? "Hermes"),
                status:p["health"]["connected"].bool != true ? .unavailable : (active == nil ? .idle : .working), hostID:hostID,
                isDefault:p["id"].string == "default", skillIDs:[], toolsets:[], mcpServerIDs:[], currentRunID:active?["id"].string)
        }
    }
    func canonicalConversation(profileID: String) async throws -> Conversation? {
        let method: String
        if currentStatus.capabilities.contains(.botChat) {
            method = "POST"
        } else if currentStatus.capabilities.contains(.botMode) {
            method = "GET"
        } else {
            return nil
        }
        let j = try await request("/bots/\(resource(profileID))/conversation", method: method)
        return remember(j["conversation"])
    }
    func profile(id: String) async throws -> Profile {
        if discoveredBotMode {
            // Native detail includes profile-scoped plugin, memory and avatar
            // reads. Allow it to finish alongside startup inventory refreshes.
            return BridgeMapping.bot(try await request("/bots/\(resource(id))", responseTimeout: 90), hostID: hostID)
        }
        guard var value = try await listProfiles().first(where: { $0.id == id }) else { throw HermesError.notFound }
        let j = try await request("/profiles/\(resource(id))")
        value.soulSummary = j["soul"]["content"].string
        if let memory = try? await request("/inventory/memory", query:["profile":id]) {
            let providers = memory["providers"].array.compactMap { $0["name"].string }
            value.memorySummary = "Configuration: " + providers.joined(separator:", ") + ". Memory contents are managed on the Studio."
        }
        return value
    }
    func botInventory(profileID: String?) async throws -> BotInventory {
        try check(.botInventory)
        let j = try await request("/bots/inventory", query: profileID.map { ["bot_id": $0] } ?? [:])
        return BotInventory(j)
    }
    private func botBody(_ changes: ProfileChanges) -> BridgeJSON {
        var fields: [String: BridgeJSON] = [:]
        if let confirm = changes.confirmExpensiveModel { fields["confirm_expensive_model"] = .bool(confirm) }
        if let name = changes.name { fields["name"] = .string(name) }
        if let value = changes.description { fields["description"] = .string(value) }
        if let soul = changes.soul { fields["soul"] = .string(soul) }
        if let model = changes.model { fields["model"] = .string(model.id); fields["provider"] = .string(model.provider) }
        if let skills = changes.enabledSkillIDs { fields["skills"] = .array(skills.map(BridgeJSON.string)) }
        if let tools = changes.toolsets { fields["toolsets"] = .array(tools.map(BridgeJSON.string)) }
        if let mcp = changes.mcpServerIDs { fields["mcp_servers"] = .array(mcp.map(BridgeJSON.string)) }
        return .object(fields)
    }
    func createBot(_ draft: BotDraft) async throws -> Profile {
        try check(.botCreate)
        // Native profile cloning plus configuration/read-back can exceed the
        // normal 30-second request window. Keep one bounded, idempotent request.
        let j = try await request("/bots", method: "POST", body: botBody(draft.changes), responseTimeout: 120)
        return BridgeMapping.bot(j["bot"], hostID: hostID)
    }
    func updateProfile(id: String, changes: ProfileChanges) async throws -> Profile {
        try check(.botEdit)
        let j = try await request("/bots/\(resource(id))", method: "PATCH", body: botBody(changes))
        return BridgeMapping.bot(j["bot"], hostID: hostID)
    }
    func duplicateBot(id: String) async throws -> Profile {
        try check(.botDuplicate)
        let j = try await request("/bots/\(resource(id))/duplicate", method:"POST", responseTimeout: 120)
        return BridgeMapping.bot(j["bot"],hostID:hostID)
    }
    func hideBot(id: String) async throws {
        try check(.botHide)
        _ = try await request("/bots/\(resource(id))/hide", method:"POST", body:.object(["hidden":.bool(true)]))
    }
    func listTasks() async throws -> [HermesTask] {
        try check(.kanban)
        var result: [HermesTask] = []
        for p in profileIDs where capabilityJSON["profiles"][p]["features"]["kanban"].bool == true {
            let boards = capabilityJSON["profiles"][p]["boards"].array.compactMap(\.string)
            for board in boards {
                let j = try await request("/kanban/tasks", query:["profile":p,"board":board])
                for row in j["tasks"].array {
                    if let id = row["id"].string { result.append(try await taskDetail(id:id)) }
                }
            }
        }
        return result
    }
    func taskDetail(id: String) async throws -> HermesTask {
        let j = try await request("/kanban/tasks/\(resource(id))")
        var task = BridgeMapping.task(j, hostID:hostID)
        // Source dependency guards are conditional. Exclude a known blocked promotion.
        if !task.dependencyIDs.isEmpty {
            for parent in task.dependencyIDs {
                let d = try await request("/kanban/tasks/\(resource(parent))")
                if d["task"]["raw_state"].string != "done" { task.supportedTransitions?.removeAll { $0 == .ready }; break }
            }
        }
        return task
    }
    func createTask(_ draft: TaskDraft) async throws -> HermesTask {
        try check(.kanban)
        let p = draft.assigneeProfileID.flatMap { profileIDs.contains($0) ? $0 : nil } ?? primaryProfile
        guard let board = capabilityJSON["profiles"][p]["boards"].array.first?.string else { throw HermesError.unsupported(.kanban) }
        var body: [String:BridgeJSON] = ["title":.string(draft.title),"body":.string(draft.summary),"priority":.number(Double(draft.priority.rawValue))]
        if let assignee = draft.assigneeProfileID { body["assignee"] = .string(assignee) }
        if let workspace = draft.project { body["workspace"] = .string(workspace.path) }
        let j = try await request("/kanban/tasks", method:"POST",body:.object(body),query:["profile":p,"board":board])
        let task = try await taskDetail(id:j["id"].string ?? "")
        continuation?.yield(.init(cursor:.init(value:""),event:.taskUpserted(task))); return task
    }
    func review(taskID: String, status: TaskStatus, summary: String) async throws {
        _ = try await request("/kanban/tasks/\(resource(taskID))", method: "PATCH", body: .object(["status": .string(BridgeMapping.sourceStatus(status)), "summary": .string(summary)]))
    }
    func setStatus(_ status: TaskStatus, taskID: String) async throws {
        let task = try await taskDetail(id:taskID)
        guard task.availableTransitions.contains(status) else { throw HermesError.rejected("This transition is unavailable for the current Hermes task") }
        _ = try await request("/kanban/tasks/\(resource(taskID))",method:"PATCH",body:.object(["status":.string(BridgeMapping.sourceStatus(status))]))
        let updated = try await taskDetail(id:taskID)
        continuation?.yield(.init(cursor:.init(value:""),event:.taskUpserted(updated)))
    }
    func startTask(id: String) async throws {
        // Queue for the canonical dispatcher, never fabricate a worker/run.
        let task = try await taskDetail(id:id)
        if task.status != .ready { try await setStatus(.ready,taskID:id) }
        else { continuation?.yield(.init(cursor:.init(value:""),event:.taskUpserted(task))) }
    }
    func listRoutines() async throws -> [Routine] {
        try check(.cron); var rows: [Routine] = []
        for p in profileIDs where capabilityJSON["profiles"][p]["features"]["cron"].bool == true {
            let j = try await request("/cron",query:["profile":p]); rows += j["jobs"].array.map { BridgeMapping.routine($0,hostID:hostID) }
        }; return rows
    }
    private func publishRoutine(_ j: BridgeJSON) {
        let r = BridgeMapping.routine(j["job"].object.isEmpty ? j : j["job"],hostID:hostID)
        continuation?.yield(.init(cursor:.init(value:""),event:.routineUpserted(r)))
    }
    func setEnabled(_ enabled: Bool, routineID: String) async throws { publishRoutine(try await request("/cron/\(resource(routineID))/\(enabled ? "enable" : "disable")",method:"POST")) }
    func runNow(routineID: String) async throws { publishRoutine(try await request("/cron/\(resource(routineID))/run-now",method:"POST")) }
    func updateRoutine(id: String, draft: RoutineDraft) async throws {
        publishRoutine(try await request("/cron/\(resource(id))",method:"PATCH",body:.object(["name":.string(draft.name),"prompt":.string(draft.prompt),"schedule":.string(draft.scheduleExpression)])))
    }
    func deleteRoutine(id: String) async throws {
        _ = try await request("/cron/\(resource(id))",method:"DELETE")
        continuation?.yield(.init(cursor:.init(value:""),event:.routineRemoved(id)))
    }
    func memoryMetadata() async throws -> BridgeJSON { try await request("/inventory/memory",query:["profile":primaryProfile]) }
    func listMemory(scope: MemoryScope?, query: String) async throws -> [MemoryEntry] { throw HermesError.unsupported(.memory) }
    func deleteMemory(id: String) async throws { throw HermesError.unsupported(.memory) }
    func listSkills() async throws -> [Skill] {
        try check(.skills)
        let j = try await request("/inventory/skills",query:["profile":primaryProfile])
        return j["skills"].array.map { Skill(id:$0["name"].string ?? "",name:$0["name"].string ?? "Skill",summary:$0["description"].string ?? "",
            category:$0["category"].string ?? "",isEnabled:$0["enabled"].bool ?? false,version:nil,origin:.local,usageCount:0,lastUsedAt:nil,
            instructionsPreview:"Instructions are managed on the Studio",requiredToolsets:[]) }
    }
    func setEnabled(_ enabled: Bool, skillID: String) async throws { throw HermesError.rejected("Skills are read-only from the phone") }
    func listTools() async throws -> [ToolInfo] {
        try check(.tools)
        let j = try await request("/inventory/tools",query:["profile":primaryProfile])
        return j["toolsets"].array.flatMap { group in
            let names = group["tools"].array.compactMap(\.string)
            return (names.isEmpty ? [group["name"].string ?? "Toolset"] : names).map { name in
                ToolInfo(name:name,toolset:group["name"].string ?? "",summary:group["description"].string ?? "Configured inventory",
                    availability:group["available"].bool == true ? .available : .unavailable("Configuration does not confirm live tool health"))
            }
        }
    }
    func listMCPServers() async throws -> [MCPServer] {
        try check(.mcp)
        let j = try await request("/inventory/mcp",query:["profile":primaryProfile])
        return j["servers"].array.map { MCPServer(id:$0["name"].string ?? "",name:$0["name"].string ?? "MCP",
            transport:$0["transport"].string == "stdio" ? .stdio : .http,endpoint:"Endpoint stays on Studio",
            status:.disconnected,errorMessage:"Configured metadata; external health is not probed",toolNames:[],lastConnectedAt:nil) }
    }
    func listIntegrations() async throws -> [Integration] { throw HermesError.unsupported(.integrations) }
    func usage(period: UsagePeriod) async throws -> UsageReport {
        try check(.usage)
        let days = period == .day ? 1 : (period == .week ? 7 : 30)
        let j = try await request("/inventory/usage",query:["profile":primaryProfile,"days":String(days)])
        return UsageReport(period:period,totals:BridgeMapping.tokens(j["totals"]),runCount:0,
            models:j["by_model"].array.map { ModelUsage(model:BridgeMapping.model($0) ?? ModelRef(id:"unknown",displayName:"Unknown",provider:"Hermes"),usage:BridgeMapping.tokens($0),runCount:0,sessionCount:$0["sessions"].int) },
            daily:j["daily"].array.map { DailyUsage(date:BridgeMapping.date($0["day"]) ?? .distantPast,tokens:BridgeMapping.tokens($0).total,runs:0,sessionCount:$0["sessions"].int) },
            sessionCount:j["totals"]["total_sessions"].int)
    }
    func recentLogs(limit: Int) async throws -> [LogEntry] { throw HermesError.unsupported(.logs) }
    func artifacts(conversationID: String) async throws -> [FileAttachment] {
        try check(.artifacts)
        let j = try await request("/conversations/\(resource(conversationID))/artifacts")
        return j["artifacts"].array.map { FileAttachment(id:$0["id"].string ?? "",name:$0["name"].string ?? "Artifact",byteCount:$0["size"].int ?? 0,
            fileExtension:($0["name"].string ?? "").split(separator:".").last.map(String.init) ?? "",path:nil, runID: $0["run_id"].string) }
    }
    func downloadArtifact(id: String) async throws -> URL {
        let metadata = try await request("/artifacts/\(resource(id))")
        let (data, _) = try await requireTransport().download(path:"/artifacts/\(resource(id))/download")
        guard data.count <= 50 * 1024 * 1024 else { throw HermesError.rejected("Artifact exceeds the mobile download limit") }
        let name = URL(fileURLWithPath:metadata["name"].string ?? "Artifact").lastPathComponent
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("artifact-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let file = dir.appendingPathComponent(name); try data.write(to:file,options:.atomic); return file
    }
    // MARK: Ordered feed; the consumer commits state before acknowledging each source frame.
    func subscribe(after cursor: EventCursor?) -> AsyncStream<HermesEventEnvelope> {
        streamTask?.cancel(); acknowledgement?.resume(); acknowledgement = nil
        continuation?.finish()
        committedCursor = cursor; seenSeq = BridgeMapping.sequence(cursor?.value); epoch = cursor?.value.split(separator:":").first.map(String.init) ?? ""
        return AsyncStream { continuation in
            self.continuation = continuation
            let subscription = UUID(); self.generation = subscription
            self.streamTask = Task { await self.streamLoop(subscription:subscription) }
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    guard self?.generation == subscription else { return }
                    self?.streamTask?.cancel(); self?.acknowledgement?.resume(); self?.acknowledgement = nil
                }
            }
        }
    }
    func acknowledge(_ cursor: EventCursor) async {
        guard pendingCursor == cursor.value else { return }
        if !cursor.value.isEmpty { committedCursor = cursor }
        pendingCursor = nil
        acknowledgement?.resume(); acknowledgement = nil
    }
    private func deliver(_ event: HermesEvent, cursor: String) async {
        guard !Task.isCancelled else { return }
        await withCheckedContinuation { ack in
            pendingCursor = cursor
            acknowledgement = ack
            continuation?.yield(.init(cursor:.init(value:cursor),event:event))
        }
    }
    private func streamLoop(subscription: UUID) async {
        var attempt = 0
        while !Task.isCancelled, generation == subscription {
            guard let t = transport else { try? await Task.sleep(for:.milliseconds(100)); continue }
            var stage = "capabilities"
            do {
                if attempt > 0 { publishStatus(.reconnecting(attempt:attempt)) }
                let caps = try await t.request(method:"GET",path:"/capabilities")
                guard !Task.isCancelled, generation == subscription else { return }
                try acceptCapabilities(caps); publishStatus(currentStatus.connection)
                if committedCursor == nil || committedCursor?.value.isEmpty == true {
                    let cursor = caps["cursor"].string ?? ""
                    await deliver(.resyncRequired,cursor:cursor)
                    guard !Task.isCancelled, generation == subscription else { return }
                    seenSeq = BridgeMapping.sequence(cursor); epoch = cursor.split(separator:":").first.map(String.init) ?? ""
                }
                stage = "stream"
                for try await frame in await t.events(after:committedCursor?.value) {
                    try Task.checkCancellation()
                    guard generation == subscription else { return }
                    let json = try JSONDecoder().decode(BridgeJSON.self,from:Data(frame.data.utf8))
                    if frame.event == "stream.resync_required" { throw HermesError.resyncRequired(json["error"]["details"]["cursor"].string ?? "") }
                    if frame.event == "stream.checkpoint" {
                        stage = "checkpoint"
                        if let cursor = json["cursor"].string, cursor != committedCursor?.value { await deliver(.checkpoint,cursor:cursor) }
                        guard !Task.isCancelled, generation == subscription else { return }
                        // A checkpoint proves this stream is alive. An auxiliary
                        // health probe may fail on cellular without invalidating it;
                        // retry on the next checkpoint instead of reconnecting SSE.
                        // Authentication/protocol failures still take the normal path.
                        do { _ = try await status(hostID:hostID) }
                        catch HermesError.timeout { }
                        catch HermesError.bridgeUnreachable { }
                        stage = "stream"
                        continue
                    }
                    guard let cursor = json["cursor"].string, let seq = json["seq"].int else { throw HermesError.rejected("Malformed bridge event") }
                    let incomingEpoch = cursor.split(separator:":").first.map(String.init) ?? ""
                    guard incomingEpoch == epoch else { throw HermesError.resyncRequired(cursor) }
                    if seq <= seenSeq { continue }
                    stage = "event:" + (json["type"].string ?? "unknown")
                    let event = try await consume(json:json)
                    guard !Task.isCancelled, generation == subscription else { return }
                    await deliver(event,cursor:cursor)
                    guard !Task.isCancelled, generation == subscription else { return }
                    seenSeq = seq
                    attempt = 0
                    stage = "stream"
                }
                throw HermesError.bridgeUnreachable
            } catch is CancellationError { return }
            catch HermesError.resyncRequired(let cursor) {
                guard !Task.isCancelled, generation == subscription else { return }
                projections.removeAll(); timelines.removeAll()
                let fresh: String
                if cursor.isEmpty { fresh = (try? await request("/capabilities"))?["cursor"].string ?? "" } else { fresh = cursor }
                guard !fresh.isEmpty else { publishStatus(.bridgeOffline); try? await Task.sleep(for:.seconds(1)); continue }
                await deliver(.resyncRequired,cursor:fresh)
                guard !Task.isCancelled, generation == subscription else { return }
                seenSeq = BridgeMapping.sequence(fresh); epoch = fresh.split(separator:":").first.map(String.init) ?? ""
            } catch {
                guard !Task.isCancelled, generation == subscription else { return }
                // Classification only: no URLs, credentials, event bodies or chat text.
                let failure: String = switch error as? HermesError {
                case .notFound: "notFound"
                case .timeout: "timeout"
                case .bridgeUnreachable: "bridgeUnreachable"
                case .hermesOffline: "hermesOffline"
                case .unauthorized: "unauthorized"
                case .rejected(let reason):
                    ["Malformed bridge event", "The bridge did not open an event stream.", "Bridge event exceeds the streaming limit", "The bridge request failed. Try again after checking host status.", "This action isn't permitted by the bridge.", "The bridge rejected the request. Check its fields and try again."].contains(reason) ? reason : "rejected"
                default: String(reflecting: type(of: error))
                }
                Logger(subsystem: "Talaria.Bridge", category: "Connection").notice("stream failed stage=\(stage, privacy: .public) error=\(failure, privacy: .public)")
                publishStatus(state(for:error))
                if (error as? HermesError) == .unauthorized {
                    // A rejected credential needs deliberate pairing. No auth retry storm.
                    while currentStatus.connection == .authenticationRequired && !Task.isCancelled {
                        try? await Task.sleep(for:.milliseconds(250))
                    }
                } else {
                    attempt += 1
                    try? await Task.sleep(for:.seconds(min(pow(2,Double(attempt - 1)),15)))
                }
            }
        }
    }
    private func assistantMessage(_ j: BridgeJSON) -> Message? {
        guard let id = j["id"].string, let cid = j["conversation_id"].string else { return nil }
        let r = BridgeMapping.run(j,hostID:hostID)
        return Message(id:"assistant-\(id)",conversationID:cid,role:.assistant,
            createdAt:BridgeMapping.date(j["created_at"]) ?? .distantPast,parts: (toolsByRun[id, default: [:]].isEmpty ? [] : [.tools(toolsByRun[id, default: [:]].values.sorted { $0.id < $1.id })]) + [.markdown(j["assistant_text"].string ?? "")],runID:id,
            status:r.state.isTerminal ? .sent : .streaming)
    }
    func consume(json: BridgeJSON) async throws -> HermesEvent {
        let type = json["type"].string ?? ""
        let payload = json["payload"]
        if type == "studio.connection" {
            _ = try await status(hostID:hostID); return .hostStatus(currentStatus)
        }
        if type == "task.activity", let id = payload["task_id"].string {
            return .taskUpserted(try await taskDetail(id:id))
        }
        guard let id = json["run_id"].string else { return .checkpoint }
        var source = projections[id]
        if source == nil || payload["hydrate"].bool == true || type == "run.status" || type.hasPrefix("run.") || type == "approval.requested" || type == "approval.resolved" {
            source = try await request("/runs/\(resource(id))")
        }
        guard var j = source else { throw HermesError.notFound }
        let seq = json["seq"].int ?? 0
        let ahead = seq > BridgeMapping.sequence(j["snapshot_cursor"].string)
        if ahead {
            var fields = j.object
            if type == "assistant.delta" { fields["assistant_text"] = .string((j["assistant_text"].string ?? "") + (payload["text"].string ?? "")) }
            if type == "assistant.completed" { fields["assistant_text"] = .string(payload["text"].string ?? "") }
            fields["snapshot_cursor"] = json["cursor"]
            j = .object(fields)
        }
        projections[id] = j
        if type != "assistant.delta", !(timelines[id] ?? []).contains(where: { $0.sequence == seq }) {
            timelines[id,default:[]].append(BridgeMapping.timeline(json)); timelines[id]?.sort { $0.sequence < $1.sequence }
        }
        if type.hasPrefix("tool.") {
            let tid = payload["tool_id"].string ?? payload["id"].string ?? "tool-\(seq)"
            let name = payload["name"].string ?? payload["tool_name"].string ?? "Tool"
            var call = toolsByRun[id]?[tid] ?? ToolCall(id:tid, kind:BridgeMapping.toolKind(name), name:name,
                summary:name.replacingOccurrences(of:"_",with:" ").capitalized)
            call.status = type == "tool.started" ? .running : (type == "tool.failed" ? .failed : .completed)
            call.input = payload["args"].string ?? payload["args_text"].string ?? call.input
            call.output = payload["result"].string ?? call.output
            call.duration = payload["duration_s"].double ?? payload["duration"].double
            toolsByRun[id,default:[:]][tid] = call
        }
        var run = materializeSnapshot(j)
        var events: [HermesEvent] = []
        if type == "approval.requested" {
            let a = mapAttention(payload)
            run.pendingApprovalID = a.id
            if !a.isClarification && run.state == .waitingForInput { run.state = .waitingForApproval }
            events.append(.approvalUpserted(a))
        }
        if type == "approval.resolved", let aid = payload["id"].string { events.append(.approvalResolved(approvalID:aid,decision:nil)) }
        if type == "steering.accepted", run.state == .running { run.state = .steeringPending }
        events.append(.runUpserted(run))
        if let message = assistantMessage(j), !message.plainText.isEmpty || !message.toolCalls.isEmpty { events.append(.messageUpserted(message)) }
        if run.state.isTerminal, let cid = run.conversationID, let history = try? await messages(conversationID:cid) {
            events.append(.transcriptReplaced(conversationID:cid,messages:history))
        }
        if let cid = run.conversationID, var c = knownConversations[cid] {
            c.activeRunID = run.state.isActive ? id : nil; c.lastActivity = .now; c.preview = run.resultSummary ?? c.preview
            knownConversations[cid] = c; events.append(.conversationUpserted(c))
        }
        return .batch(events)
    }
}
