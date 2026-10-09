import Foundation

// MARK: - ConversationService

extension MockHermesBackend: ConversationService {
    func listConversations() async throws -> [Conversation] {
        try await perform(.sessions) { list(Array(conversations.values)) }
    }

    func messages(conversationID: String) async throws -> [Message] {
        try await perform(.sessions) {
            guard conversations[conversationID] != nil else { throw HermesError.notFound }
            return (messages[conversationID] ?? []).sorted { $0.createdAt < $1.createdAt }
        }
    }

    func createConversation(configuration: RunConfiguration) async throws -> Conversation {
        try await perform(.sessions) {
            let conversation = Conversation(
                id: "c-\(UUID().uuidString.prefix(8).lowercased())", title: "New conversation", profileID: configuration.profileID,
                hostID: configuration.hostID, source: .app, createdAt: .now, lastActivity: .now, preview: "",
                project: configuration.project, model: configuration.model, activeRunID: nil, isPinned: false, messageCount: 0)
            upsert(conversation)
            return conversation
        }
    }

    func renameConversation(id: String, title: String) async throws {
        try await perform(.sessions) {
            guard var conversation = conversations[id] else { throw HermesError.notFound }
            conversation.title = title
            upsert(conversation)
        }
    }

    func deleteConversation(id: String) async throws {
        try await perform(.sessions) {
            guard let conversation = conversations[id] else { throw HermesError.notFound }
            if let runID = conversation.activeRunID { drivers[runID]?.cancel() }
            conversations[id] = nil
            messages[id] = nil
            publish(.conversationRemoved(id))
        }
    }

    func setPinned(_ pinned: Bool, conversationID: String) async throws {
        try await perform(.sessions) {
            guard var conversation = conversations[conversationID] else { throw HermesError.notFound }
            conversation.isPinned = pinned
            upsert(conversation)
        }
    }

    func send(_ outgoing: OutgoingMessage, conversationID: String, configuration: RunConfiguration) async throws -> Run {
        if simulation.nextSendUncertain { simulation.nextSendUncertain = false; throw HermesError.commandUncertain(nil) }
        let conversation = try await perform(.sessions) { () throws -> Conversation in
            guard let conversation = conversations[conversationID] else { throw HermesError.notFound }
            guard conversation.activeRunID == nil else {
                throw HermesError.rejected("Hermes is still working in this conversation. Stop it or send an instruction instead.")
            }
            return conversation
        }

        let text = outgoing.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [MessagePart] = text.isEmpty ? [] : [.markdown(text)]
        parts += outgoing.attachments.map { .file($0) }
        upsert(Message(conversationID: conversationID, role: .user, parts: parts))

        var updated = conversation
        if updated.messageCount == 0 || updated.title == "New conversation" {
            updated.title = MockScripts.title(for: text)
        }
        updated.messageCount += 1
        updated.preview = text
        updated.lastActivity = .now
        upsert(updated)

        let profileID = conversation.usesDefaultProfile ? configuration.profileID : conversation.profileID
        let first = startRun(profileID: profileID, conversationID: conversationID, prompt: text, configuration: configuration)
        return first
    }

    /// Creates a run plus its assistant message placeholder and starts driving it.
    @discardableResult
    func startRun(profileID: String?, conversationID: String?, prompt: String, configuration: RunConfiguration?,
                  title: String? = nil, taskID: String? = nil, routineID: String? = nil, trigger: RunTrigger = .chat,
                  script: [ScriptStep]? = nil) -> Run {
        let profile = profileID.flatMap { profiles[$0] }
        let model = configuration?.model ?? profile?.model ?? MockModels.sonnet
        let runID = "r-\(UUID().uuidString.prefix(8).lowercased())"
        let now = Date.now
        let run = Run(
            id: runID, title: title ?? MockScripts.runTitle(for: prompt), profileID: profileID, conversationID: conversationID,
            taskID: taskID, routineID: routineID, hostID: activeHostID, trigger: trigger, state: .running,
            startedAt: now, endedAt: nil, currentAction: "Thinking",
            events: [
                RunEvent(sequence: 1, timestamp: now, kind: .started, title: "Run started"),
                RunEvent(sequence: 2, timestamp: now, kind: .modelSelected,
                         title: "\(model.displayName) · reasoning \(configuration?.reasoning.label.lowercased() ?? "medium")"),
            ],
            model: model, reasoning: configuration?.reasoning ?? .medium,
            project: configuration?.project ?? conversationID.flatMap { conversations[$0]?.project },
            usage: TokenUsage(input: 0, output: 0))
        upsert(run)
        log(.info, .run, "Run started: \(run.title)", runID: runID)

        let messageID = UUID().uuidString
        if let conversationID, var conversation = conversations[conversationID] {
            upsert(Message(id: messageID, conversationID: conversationID, role: .assistant,
                           parts: [], runID: runID, status: .streaming))
            conversation.activeRunID = runID
            upsert(conversation)
        }
        drive(runID: runID, messageID: messageID, script: script ?? MockScripts.reply(to: prompt, profileID: profileID))
        return run
    }
}

// MARK: - RunService

extension MockHermesBackend: RunService {
    func listRuns() async throws -> [Run] {
        try await perform(.runs) { list(Array(runs.values)) }
    }

    func pendingApprovals() async throws -> [ApprovalRequest] {
        try await perform(.runs) { list(Array(approvals.values)) }
    }

    func stop(runID: String) async throws {
        try await perform(.stop) {
            guard runs[runID]?.state.canStop == true else { throw HermesError.rejected("This run isn't stoppable right now.") }
        }
        guard var run = runs[runID] else { return }
        run.state = .stopping
        run.currentAction = "Stopping…"
        upsert(run)
        if let approvalID = run.pendingApprovalID, let waiter = approvalWaiters.removeValue(forKey: approvalID) {
            approvals[approvalID] = nil
            publish(.approvalResolved(approvalID: approvalID, decision: .deny))
            waiter.resume(returning: .deny)
        }
        drivers[runID]?.cancel()
        try? await Task.sleep(for: .seconds(0.9))
        finish(runID: runID, state: .cancelled, detail: "Stopped by you.")
    }

    func steer(runID: String, instruction: String) async throws {
        try await perform(.steering) {
            guard runs[runID]?.state.canSteer == true else {
                throw HermesError.rejected("This run can't take instructions right now.")
            }
        }
        guard var run = runs[runID] else { return }
        run.state = .steeringPending
        run.append(RunEvent(kind: .steering, title: "Instruction sent", detail: instruction))
        upsert(run)
        steeringNotes[runID, default: []].append(instruction)
        if let conversationID = run.conversationID,
           var message = messages[conversationID]?.last(where: { $0.runID == runID && $0.role == .assistant }) {
            message.parts.append(.event(SystemEvent(symbol: "arrow.turn.down.right", text: "You: \(instruction)")))
            upsert(message)
        }
        log(.info, .run, "Steering instruction delivered", detail: instruction, runID: runID)
        Task {
            try? await Task.sleep(for: .seconds(1.4 / self.simulation.runSpeed))
            guard var current = self.runs[runID], current.state == .steeringPending else { return }
            current.state = .running
            current.append(RunEvent(kind: .steering, title: "Instruction picked up"))
            self.upsert(current)
        }
    }

    func retry(runID: String) async throws -> Run {
        let original = try await perform(.runs) { () throws -> Run in
            guard let run = runs[runID] else { throw HermesError.notFound }
            return run
        }
        let routine = original.routineID.flatMap { routines[$0] }
        return startRun(profileID: original.profileID, conversationID: original.conversationID,
                        prompt: routine?.prompt ?? original.title, configuration: nil, title: original.title,
                        taskID: original.taskID, routineID: original.routineID, trigger: original.trigger,
                        script: routine.map { MockScripts.routine($0) })
    }

    func resolveApproval(id: String, decision: ApprovalDecision) async throws {
        try await perform(.approvals) {
            if simulation.staleNextApproval {
                simulation.staleNextApproval = false
                approvals[id] = nil
                approvalWaiters.removeValue(forKey: id)?.resume(returning: .deny)
                publish(.approvalResolved(approvalID: id, decision: nil))
                throw HermesError.staleAttention
            }
            guard let approval = approvals[id] else { throw HermesError.staleAttention }
            guard approval.offeredDecisions.contains(decision) else { throw HermesError.rejected("Choose an offered approval choice.") }
            switch approval.effectiveAvailability(remoteApprovalsSupported: true) {
            case .actionable: break
            case .expired: throw HermesError.staleAttention
            case .unavailableRemotely, .ambiguous:
                throw HermesError.rejected("This approval can't be resolved from the phone. Resolve it on the Studio.")
            }
        }
        let waiter = approvalWaiters.removeValue(forKey: id)
        let request = approvals.removeValue(forKey: id)
        publish(.approvalResolved(approvalID: id, decision: decision))
        log(.info, .approval, "\(decision.isApproval ? "Approved" : "Denied"): \(request?.payload ?? id)", runID: request?.runID)
        waiter?.resume(returning: decision)
    }
}

// MARK: - ProfileService

extension MockHermesBackend: ProfileService {
    func listProfiles() async throws -> [Profile] {
        try await perform(.profiles) {
            let all = profiles.values.sorted { ($0.isDefault ? 0 : 1, $0.name) < ($1.isDefault ? 0 : 1, $1.name) }
            return simulation.emptyData ? all.filter(\.isDefault) : all
        }
    }

    func canonicalConversation(profileID: String) async throws -> Conversation? {
        if let existing = conversations.values.first(where: { $0.profileID == profileID && $0.isBotChat == true }) { return existing }
        var chat = try await createConversation(configuration:RunConfiguration(profileID:profileID,hostID:activeHostID))
        chat.isBotChat = true; chat.botID = profileID; chat.botProfileID = profileID; chat.readOnly = false
        upsert(chat)
        if var bot = profiles[profileID] { bot.canonicalChatAvailable = true; upsert(bot) }
        return chat
    }
    func botInventory(profileID: String?) async throws -> BotInventory {
        try await perform(.profiles) {
            let models = Array(Set(MockModels.all + profiles.values.map(\.model)))
            let providers = Dictionary(grouping:models,by:\.provider).map { provider, models in
                BridgeJSON.object(["id":.string(provider),"name":.string(provider),"available":.bool(true),"models":.array(models.map { .object(["id":.string($0.id),"name":.string($0.displayName)]) })])
            }
            return BotInventory(.object(["providers":.array(providers),"availability":.object(["skills":.bool(true),"toolsets":.bool(true),"mcp_servers":.bool(true)]),
                "skills":.array(skillList.map { .object(["name":.string($0.id),"enabled":.bool($0.isEnabled)]) }),
                "toolsets":.array(Set(toolList.map(\.toolset)).sorted().map { .object(["name":.string($0),"enabled":.bool(true)]) }),
                "mcp_servers":.array(mcpList.map { .object(["name":.string($0.id),"enabled":.bool(true)]) })]))
        }
    }
    func createBot(_ draft: BotDraft) async throws -> Profile {
        try await perform(.profiles) {
            guard let name = draft.changes.name, let description = draft.changes.description,
                  var bot = profiles.values.first(where: \.isDefault) else { throw HermesError.rejected("Provide a bot name and description") }
            bot = Profile(id:UUID().uuidString,name:name,role:description,summary:description,tint:.slate,
                model:draft.changes.model ?? bot.model,status:.idle,hostID:activeHostID,isDefault:false,
                skillIDs:draft.changes.enabledSkillIDs ?? [],toolsets:draft.changes.toolsets ?? [],mcpServerIDs:draft.changes.mcpServerIDs ?? [],
                soulSummary:draft.changes.soul,isBotMode:true,canonicalChatAvailable:false,soul:draft.changes.soul,
                editableFields:["name","description","soul","model","skills","toolsets","mcp_servers","hide"])
            upsert(bot); return bot
        }
    }
    func hideBot(id: String) async throws { _ = try await perform(.profiles) { profiles.removeValue(forKey:id) } }
    func duplicateBot(id: String) async throws -> Profile {
        guard let profile = profiles[id] else { throw HermesError.notFound }
        var fields = ProfileChanges(); fields.name = profile.name + " (copy)"; fields.description = profile.summary; fields.soul = profile.soul
        fields.model = profile.model; fields.enabledSkillIDs = profile.skillIDs; fields.toolsets = profile.toolsets; fields.mcpServerIDs = profile.mcpServerIDs
        return try await createBot(BotDraft(changes:fields))
    }

    func updateProfile(id: String, changes: ProfileChanges) async throws -> Profile {
        try await perform(.profiles) {
            guard var profile = profiles[id] else { throw HermesError.notFound }
            if let model = changes.model { profile.model = model }
            if let name = changes.name { profile.name = name }
            if let description = changes.description { profile.summary = description; profile.role = description }
            if let soul = changes.soul { profile.soul = soul; profile.soulSummary = soul }
            if let skills = changes.enabledSkillIDs { profile.skillIDs = skills }
            if let toolsets = changes.toolsets { profile.toolsets = toolsets }
            upsert(profile)
            return profile
        }
    }
}

// MARK: - TaskService

extension MockHermesBackend: TaskService {
    func listTasks() async throws -> [HermesTask] {
        try await perform(.kanban) { list(Array(tasks.values)) }
    }

    func createTask(_ draft: TaskDraft) async throws -> HermesTask {
        try await perform(.kanban) {
            let task = HermesTask(
                id: "t-\(UUID().uuidString.prefix(8).lowercased())", title: draft.title, summary: draft.summary,
                status: .ready, assigneeProfileID: draft.assigneeProfileID, priority: draft.priority, hostID: activeHostID,
                project: draft.project, createdAt: .now, updatedAt: .now, startedAt: nil, completedAt: nil,
                dependencyIDs: [], blockReason: nil, runIDs: [], conversationID: nil,
                activity: [TaskActivity(id: UUID().uuidString, date: .now, text: "Created from iPhone", profileID: nil, symbol: "plus.circle")])
            upsert(task)
            return task
        }
    }

    func setStatus(_ status: TaskStatus, taskID: String) async throws {
        try await perform(.kanban) {
            guard var task = tasks[taskID] else { throw HermesError.notFound }
            task.status = status
            task.updatedAt = .now
            if status != .blocked { task.blockReason = nil }
            if status == .completed || status == .cancelled { task.completedAt = .now }
            task.activity.append(TaskActivity(id: UUID().uuidString, date: .now, text: "Moved to \(status.label)", profileID: nil, symbol: status.symbol))
            upsert(task)
        }
    }

    func startTask(id: String) async throws {
        let task = try await perform(.kanban) { () throws -> HermesTask in
            guard let task = tasks[id] else { throw HermesError.notFound }
            return task
        }
        let run = startRun(profileID: task.assigneeProfileID, conversationID: nil, prompt: task.summary, configuration: nil,
                           title: task.title, taskID: task.id, trigger: .task)
        var updated = task
        updated.status = .inProgress
        updated.blockReason = nil
        updated.startedAt = updated.startedAt ?? .now
        updated.updatedAt = .now
        updated.runIDs.append(run.id)
        updated.activity.append(TaskActivity(id: UUID().uuidString, date: .now, text: "Run started", profileID: task.assigneeProfileID, symbol: "play.circle"))
        upsert(updated)
    }
}

// MARK: - ScheduleService

extension MockHermesBackend: ScheduleService {
    func listRoutines() async throws -> [Routine] {
        try await perform(.cron) { list(Array(routines.values)) }
    }

    func setEnabled(_ enabled: Bool, routineID: String) async throws {
        try await perform(.cron) {
            guard var routine = routines[routineID] else { throw HermesError.notFound }
            routine.isEnabled = enabled
            upsert(routine)
            log(.info, .routine, "\(enabled ? "Resumed" : "Paused") routine: \(routine.name)")
        }
    }

    func runNow(routineID: String) async throws {
        let routine = try await perform(.cron) { () throws -> Routine in
            guard let routine = routines[routineID] else { throw HermesError.notFound }
            return routine
        }
        let conversation = Conversation(
            id: "c-\(UUID().uuidString.prefix(8).lowercased())", title: routine.name,
            profileID: routine.profileID ?? Profile.defaultID, hostID: activeHostID, source: .routine,
            createdAt: .now, lastActivity: .now, preview: "Running…", project: nil, model: nil,
            activeRunID: nil, isPinned: false, messageCount: 0)
        upsert(conversation)
        upsert(Message(conversationID: conversation.id, role: .system,
                       parts: [.event(SystemEvent(symbol: "calendar.badge.clock", text: "Started manually from routine “\(routine.name)”"))]))
        log(.info, .routine, "Routine run manually: \(routine.name)")
        _ = startRun(profileID: routine.profileID, conversationID: conversation.id, prompt: routine.prompt, configuration: nil,
                        title: routine.name, routineID: routine.id, trigger: .routine, script: MockScripts.routine(routine))
    }

    func updateRoutine(id: String, draft: RoutineDraft) async throws {
        try await perform(.cron) {
            guard var routine = routines[id] else { throw HermesError.notFound }
            routine.name = draft.name
            routine.prompt = draft.prompt
            routine.profileID = draft.profileID
            routine.delivery = draft.delivery
            if routine.schedule.expression != draft.scheduleExpression {
                routine.schedule = RoutineSchedule(expression: draft.scheduleExpression, summary: "Custom · \(draft.scheduleExpression)")
            }
            upsert(routine)
        }
    }

    func deleteRoutine(id: String) async throws {
        try await perform(.cron) {
            guard routines.removeValue(forKey: id) != nil else { throw HermesError.notFound }
            publish(.routineRemoved(id))
        }
    }
}

// MARK: - Knowledge & diagnostics

extension MockHermesBackend: MemoryService {
    func listMemory(scope: MemoryScope?, query: String) async throws -> [MemoryEntry] {
        try await perform(.memory) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            return list(memoryEntries)
                .filter { scope == nil || $0.scope == scope }
                .filter {
                    trimmed.isEmpty
                        || $0.content.localizedCaseInsensitiveContains(trimmed)
                        || $0.tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
                        || ($0.sourceTitle?.localizedCaseInsensitiveContains(trimmed) ?? false)
                }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func deleteMemory(id: String) async throws {
        try await perform(.memory) { memoryEntries.removeAll { $0.id == id } }
    }
}

extension MockHermesBackend: SkillService {
    func listSkills() async throws -> [Skill] {
        try await perform(.skills) { list(skillList) }
    }

    func setEnabled(_ enabled: Bool, skillID: String) async throws {
        try await perform(.skills) {
            guard let index = skillList.firstIndex(where: { $0.id == skillID }) else { throw HermesError.notFound }
            skillList[index].isEnabled = enabled
        }
    }
}

extension MockHermesBackend: ToolService {
    func listTools() async throws -> [ToolInfo] {
        try await perform(.tools) { list(toolList) }
    }

    func listMCPServers() async throws -> [MCPServer] {
        try await perform(.mcp) { list(mcpList) }
    }
}

extension MockHermesBackend: IntegrationService {
    func listIntegrations() async throws -> [Integration] {
        try await perform(.integrations) { list(integrationList) }
    }
}

extension MockHermesBackend: UsageService {
    func usage(period: UsagePeriod) async throws -> UsageReport {
        try await perform(.usage) {
            if simulation.emptyData {
                return UsageReport(period: period, totals: TokenUsage(input: 0, output: 0), runCount: 0, models: [], daily: [])
            }
            return MockFixtures.usage(period: period, now: .now)
        }
    }
}

extension MockHermesBackend: LogService {
    func recentLogs(limit: Int) async throws -> [LogEntry] {
        try await perform(.logs) { Array(list(logEntries).sorted { $0.timestamp > $1.timestamp }.prefix(limit)) }
    }
}

// MARK: - Client wiring

extension HermesClient {
    /// A client backed entirely by the in-memory simulator.
    static func mock(_ backend: MockHermesBackend) -> HermesClient {
        HermesClient(hosts: backend, home: backend, events: backend, conversations: backend, runs: backend, profiles: backend,
                     tasks: backend, schedules: backend, memory: backend, skills: backend, tools: backend,
                     integrations: backend, usage: backend, logs: backend)
    }
}
