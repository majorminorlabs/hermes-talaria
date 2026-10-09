import Foundation

/// The versioned bridge contract is translated here, never in SwiftUI views.
nonisolated enum BridgeMapping {
    static func bot(_ j: BridgeJSON, hostID: String) -> Profile {
        let model = configuredModel(j)
        let editableFields: Set<String>?
        if case .object(let fields) = j["editable_fields"] {
            editableFields = Set(fields.filter { $0.value.bool == true }.map(\.key))
        } else {
            editableFields = nil
        }
        return Profile(id: j["id"].string ?? "", name: j["name"].string ?? "", role: j["role"].string ?? "",
            summary: j["description"].string ?? "", tint: .slate,
            model: model ?? ModelRef(id: "unknown", displayName: "Unavailable", provider: ""),
            status: ProfileStatus(rawValue: j["status"].string ?? "unknown") ?? .unknown, hostID: hostID,
            isDefault: j["is_default"].bool ?? false,
            skillIDs: j["skills"].array.filter { $0["enabled"].bool == true }.compactMap { $0["name"].string },
            toolsets: j["toolsets"].array.filter { $0["enabled"].bool == true }.compactMap { $0["name"].string },
            mcpServerIDs: j["mcp_servers"].array.filter { $0["enabled"].bool == true }.compactMap { $0["name"].string },
            memorySummary: j["memory_metadata"]["active"].string.map { "Configured memory: " + $0 },
            soulSummary: j["soul_summary"].string, isBotMode: true,
            canonicalChatAvailable: j["canonical_chat_available"].bool,
            lastActiveAt: date(j["last_active"]), activitySummary: j["activity"]["title"].string,
            avatarData: j["avatar_data"].string,
            routinesMetadata: j["routines"].array.compactMap { $0["name"].string },
            pluginsMetadata: j["plugins"].array.compactMap { $0["name"].string }, modelAvailable: model != nil, soul: j["soul"].string,
            editableFields: editableFields,
            profileKey: j["profile_id"].string, hasAvatar: j["has_avatar"].bool)
    }
    private static func configuredModel(_ j: BridgeJSON) -> ModelRef? {
        j["model"].string.flatMap { name in
            name.isEmpty ? nil : ModelRef(id: name, displayName: name, provider: j["provider"].string ?? "")
        }
    }
    static func date(_ json: BridgeJSON) -> Date? {
        if let seconds = json.double { return Date(timeIntervalSince1970: seconds) }
        guard let value = json.string else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: value) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: value) { return d }
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"; day.locale = Locale(identifier: "en_US_POSIX"); day.timeZone = TimeZone(secondsFromGMT: 0)
        return day.date(from: value)
    }
    static func sequence(_ cursor: String?) -> Int { cursor?.split(separator: ":").last.flatMap { Int($0) } ?? 0 }
    static func model(_ j: BridgeJSON) -> ModelRef? {
        guard let id = j["model"].string ?? j["id"].string, !id.isEmpty else { return nil }
        return ModelRef(id: id, displayName: j["label"].string ?? j["name"].string ?? id, provider: j["provider"].string ?? "Hermes")
    }
    static func tokens(_ j: BridgeJSON) -> TokenUsage {
        let input = j["input"].int ?? j["input_tokens"].int ?? j["total_input"].int ?? 0
        let output = j["output"].int ?? j["output_tokens"].int ?? j["total_output"].int ?? 0
        // Hermes analytics counts input + output; reasoning is an output
        // breakdown, not an additional independently billed token category.
        return TokenUsage(input:input, output:output,
                   cached: j["cache_read"].int ?? j["cache_read_tokens"].int ?? j["total_cache_read"].int ?? 0,
                   reasoning: j["reasoning"].int ?? j["reasoning_tokens"].int ?? j["total_reasoning"].int ?? 0,
                   reportedTotal:j["total"].int ?? j["total_tokens"].int ?? (input + output),
                   cacheWritten:j["cache_write"].int ?? j["cache_write_tokens"].int)
    }
    static func capabilities(_ json: BridgeJSON) -> Set<HermesCapability> {
        var set = Set<HermesCapability>()
        for (_, p) in json["profiles"].object {
            for c in HermesCapability.allCases where p["features"][c.rawValue].bool == true { set.insert(c) }
            // Observing an unsafe approval does not enable approval controls.
            if p["features"]["approvals"]["respond"].bool == true { set.insert(.approvals) }
        }
        set.remove(.memory); set.remove(.integrations); set.remove(.logs)
        return set
    }
    static func host(_ json: BridgeJSON, hostID: String) -> HostStatus {
        let profiles = json["profiles"].object.values
        let healthy = !profiles.isEmpty && profiles.allSatisfy { $0["health"]["connected"].bool == true }
        return HostStatus(hostID: hostID, connection: healthy ? .connected : .hermesOffline,
                          hermesState: healthy ? .running : .unknown, bridgeVersion: json["bridge_version"].string,
                          hermesVersion: profiles.first?["installed_commit"].string ?? profiles.first?["audited_commit"].string,
                          defaultModel: nil, activeRunCount: 0, latencyMilliseconds: nil, lastSeen: .now,
                          capabilities: capabilities(json), resources: nil, permissionScopes:Set(json["scopes"].array.compactMap(\.string)))
    }
    static func conversation(_ j: BridgeJSON, hostID: String) -> Conversation {
        let botID = j["bot_id"].string
        let source: ConversationSource = switch j["source"].string {
        case "mobile": .app
        case "cron": .routine
        default: ConversationSource(rawValue: j["source"].string ?? "") ?? .api
        }
        let created = date(j["started_at"]) ?? .distantPast
        return Conversation(id: j["id"].string ?? "", title: j["title"].string ?? "Untitled conversation",
                            profileID: j["profile"].string ?? "default", hostID: hostID, source: source,
                            createdAt: created, lastActivity: date(j["last_activity"]) ?? date(j["last_active"]) ?? created,
                            preview: j["snippet"].string ?? j["preview"].string ?? "", project: nil,
                            model: j["read_only"].bool == true ? configuredModel(j) : model(j), activeRunID: nil,
                            isPinned: false, messageCount: j["message_count"].int ?? 0, readOnly: j["read_only"].bool, isArchived: j["archived"].bool,
                            isBotChat: j["is_bot_chat"].bool ?? j["canonical"].bool ?? (botID != nil),
                            botID: botID, botProfileID: j["bot_profile"].string)
    }
    static func run(_ j: BridgeJSON, hostID: String) -> Run {
        let state: RunState = switch j["state"].string {
        case "starting": .queued
        case "running": .running
        case "waiting_for_input": .waitingForInput
        case "stop_requested": .stopping
        case "complete": .completed
        case "failed": .failed
        case "cancelled": .cancelled
        case "unknown": .unknown
        default: .unknown
        }
        let seq = sequence(j["snapshot_cursor"].string)
        let text = j["assistant_text"].string ?? ""
        return Run(id: j["id"].string ?? "", title: "Conversation run", profileID: j["profile"].string,
                   conversationID: j["conversation_id"].string, taskID: nil, routineID: nil, hostID: hostID,
                   trigger: .chat, state: state, startedAt: date(j["created_at"]) ?? .distantPast,
                   endedAt: state.isTerminal ? date(j["updated_at"]) : nil,
                   currentAction: state.label,
                   events: seq > 0 ? [RunEvent(id: "snapshot-\(j["id"].string ?? "")", sequence: seq, kind: .output, title: "State observed")] : [],
                   model: model(j), reasoning: nil, project: nil,
                   usage: j["usage"]["tokens"].object.isEmpty ? nil : tokens(j["usage"]["tokens"]), pendingApprovalID: nil,
                   failureReason: j["reason"].string, resultSummary: text.isEmpty ? nil : String(text.prefix(160)),
                   stopSupported: j["controls"]["stop"].bool ?? false, steerSupported: j["controls"]["steer"].bool ?? false,
                   retrySupported: j["controls"]["retry"].bool ?? false)
    }
    static func approval(_ j: BridgeJSON, hostID: String = "") -> ApprovalRequest {
        let clarify = j["kind"].string == "clarification"
        let expiry = date(j["expires_at"])
        let fresh = j["can_respond"].bool == true && j["state"].string == "pending" && (expiry.map { $0 > .now } ?? true)
        let d = j["details"]
        return ApprovalRequest(id: j["id"].string ?? "", runID: j["run_id"].string ?? "",
            conversationID: j["conversation_id"].string, profileID: j["profile"].string, kind: d["command"].string == nil ? .tool : .command,
            summary: clarify ? (d["question"].string ?? "Hermes needs an answer") : (d["description"].string ?? "Hermes needs approval"),
            command: d["command"].string, workingDirectory: nil, paths: [], diff: nil,
            reason: j["limitation"].string, risk: nil, requestedAt: date(j["observed_at"]) ?? .distantPast,
            expiresAt: expiry,
            availability: j["state"].string != "pending" || (expiry ?? .distantFuture) <= .now ? .expired : fresh ? .actionable : .unavailableRemotely(clarify ? "This question is no longer current. Check Hermes on your Mac." : "Hermes can't safely target this approval from the phone. Resolve it on your Mac, or stop the run."),
            allowsSessionApproval: !clarify && d["choices"].array.compactMap(\.string).contains("session"), clarificationQuestion: clarify ? (d["question"].string ?? "Hermes needs an answer") : nil,
            clarificationChoices: clarify ? d["choices"].array.compactMap(\.string) : nil,
            recommendedChoice: d["recommended"].string ?? d["default"].string, onTimeout: d["on_timeout"].string,
            approvalChoices: clarify ? nil : d["choices"].array.compactMap(\.string))
    }
    static func taskStatus(_ raw: String) -> TaskStatus? {
        switch raw { case "running": .inProgress; case "done", "complete": .completed; default: TaskStatus(rawValue: raw) }
    }
    static func sourceStatus(_ s: TaskStatus) -> String { switch s { case .inProgress: "running"; case .completed: "done"; default: s.rawValue } }
    static func task(_ json: BridgeJSON, hostID: String) -> HermesTask {
        let j = json["task"].object.isEmpty ? json : json["task"]
        let raw = j["raw_state"].string ?? j["state"].string ?? "triage"
        let targets = json["supported_targets"].array.compactMap { $0.string.flatMap(taskStatus) }
        return HermesTask(id: j["id"].string ?? "", title: j["title"].string ?? "Task", summary: j["latest_summary"].string ?? j["result"].string ?? j["body"].string ?? "",
            status: taskStatus(raw) ?? .triage, assigneeProfileID: j["assignee"].string,
            priority: TaskPriority(rawValue: j["priority"].int ?? 1) ?? .normal, hostID: hostID, project: nil,
            createdAt: date(j["created_at"]) ?? .distantPast, updatedAt: date(j["updated_at"]) ?? .distantPast,
            startedAt: date(j["started_at"]), completedAt: date(j["completed_at"]),
            dependencyIDs: json["links"]["parents"].array.compactMap(\.string), blockReason: j["block_reason"].string,
            runIDs: [], conversationID: nil,
            activity: json["recent_activity"].array.map { TaskActivity(id: String($0["id"].int ?? 0), date: date($0["created_at"]) ?? .distantPast,
                text: $0["kind"].string ?? "Task activity", profileID: j["profile"].string, symbol: "list.bullet") },
            sourceState: raw, supportedTransitions: targets, boardID: j["board"].string)
    }
    static func routine(_ j: BridgeJSON, hostID: String) -> Routine {
        let expression = j["schedule"].string ?? j["schedule"]["value"].string ?? ""
        let last = date(j["last_run_at"])
        return Routine(id: j["id"].string ?? "", name: j["name"].string ?? "Scheduled work", prompt: j["prompt"].string ?? "",
            schedule: RoutineSchedule(expression: expression, summary: j["schedule_display"].string ?? expression), nextRunAt: date(j["next_run_at"]),
            profileID: j["profile"].string, isEnabled: j["enabled"].bool ?? false,
            lastResult: last.map { RoutineResult(outcome: j["last_status"].string == "error" ? .failed : .succeeded, date: $0, runID: nil,
                summary: j["last_error"].string ?? j["last_status"].string) }, delivery: nil, hostID: hostID, skillIDs: j["skills"].array.compactMap(\.string))
    }
    static func toolKind(_ name: String) -> ToolKind {
        let n = name.lowercased()
        if n.contains("delegate") { return .delegate }
        if n.contains("terminal") { return .terminal }
        if n.contains("file") { return .files }
        if n.contains("browser") { return .browser }
        if n.contains("web") || n.contains("search") { return .web }
        if n.contains("mcp") { return .mcp }
        if n.contains("memory") { return .memory }
        if n.contains("skill") { return .skills }
        return .other
    }
    static func timeline(_ j: BridgeJSON) -> RunEvent {
        let type = j["type"].string ?? ""
        let p = j["payload"]
        let kind: RunEventKind = switch type {
        case "run.started": .started
        case "run.completed": .completed
        case "run.failed": .failed
        case "run.cancelled": .cancelled
        case "tool.started", "tool.completed", "tool.failed": .tool
        case "approval.requested": .approvalRequested
        case "approval.resolved": .approvalResolved
        case "steering.accepted", "steering.rejected": .steering
        default: .output
        }
        let name = p["name"].string ?? p["tool_name"].string ?? "Tool"
        return RunEvent(id: j["cursor"].string ?? "", sequence: j["seq"].int ?? 0,
            timestamp: date(j["observed_at"]) ?? .distantPast, kind: kind,
            title: kind == .tool ? name.replacingOccurrences(of: "_", with: " ").capitalized : type.replacingOccurrences(of: ".", with: " ").capitalized,
            detail: kind == .steering ? p["text"].string : p["summary"].string,
            status: type.hasSuffix("failed") || type.hasSuffix("rejected") ? .failed : (type == "tool.started" ? .active : .done),
            toolKind: kind == .tool ? toolKind(name) : nil, duration: p["duration"].double)
    }
}
