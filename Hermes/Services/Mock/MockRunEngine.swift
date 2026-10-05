import Foundation

/// One step of a simulated run.
nonisolated enum ScriptStep: Sendable {
    case pause(TimeInterval)
    /// Announce upcoming steps (rendered as ○).
    case plan([String])
    /// Run a tool: shown as ● `active` for `seconds`, then ✓ `call.summary`.
    case tool(active: String, call: ToolCall, seconds: TimeInterval)
    /// Complete the step that was already active when the simulation resumed.
    case finishActive(call: ToolCall, after: TimeInterval)
    case approval(ApprovalTemplate, approved: [ScriptStep], denied: [ScriptStep])
    /// Wait on an approval that already exists in fixtures.
    case awaitApproval(id: String, approved: [ScriptStep], denied: [ScriptStep])
    case respond(String)
    case attach(MessagePart)
    case complete(summary: String)
    case fail(reason: String)
}

nonisolated struct ApprovalTemplate: Sendable {
    var kind: ApprovalKind
    var summary: String
    var command: String?
    var workingDirectory: String?
    var paths: [String] = []
    var diff: String?
    var reason: String?
    var risk: ApprovalRisk
    var availability: ApprovalAvailability = .actionable
    var expiresIn: TimeInterval?
}

extension MockHermesBackend {
    func drive(runID: String, messageID: String, script: [ScriptStep]) {
        drivers[runID]?.cancel()
        drivers[runID] = Task {
            try? await self.execute(script, runID: runID, messageID: messageID)
            self.drivers[runID] = nil
        }
    }

    private func execute(_ steps: [ScriptStep], runID: String, messageID: String) async throws {
        for step in steps {
            try Task.checkCancellation()
            try await execute(step, runID: runID, messageID: messageID)
        }
    }

    private func execute(_ step: ScriptStep, runID: String, messageID: String) async throws {
        switch step {
        case .pause(let seconds):
            try await sleep(seconds)

        case .plan(let titles):
            mutateRun(runID) { run in
                for title in titles where !run.events.contains(where: { $0.kind == .planned && $0.title == title }) {
                    run.append(RunEvent(kind: .planned, title: title, status: .pending))
                }
            }

        case .tool(let active, let call, let seconds):
            let eventID = activateStep(runID: runID, title: active, kind: .tool, toolKind: call.kind, detail: call.input)
            var running = call
            running.status = .running
            mutateMessage(messageID, runID: runID) { $0.upsertToolCall(running) }
            try await sleep(seconds)
            completeStep(runID: runID, eventID: eventID, call: call, duration: seconds)
            mutateMessage(messageID, runID: runID) { $0.upsertToolCall(call) }

        case .finishActive(let call, let after):
            try await sleep(after)
            if let eventID = runs[runID]?.events.last(where: { $0.status == .active })?.id {
                completeStep(runID: runID, eventID: eventID, call: call, duration: call.duration)
            }
            mutateMessage(messageID, runID: runID) { $0.upsertToolCall(call) }

        case .approval(let template, let approved, let denied):
            let approval = requestApproval(template, runID: runID)
            let decision = try await waitForDecision(approvalID: approval.id, runID: runID)
            try await execute(decision.isApproval ? approved : denied, runID: runID, messageID: messageID)

        case .awaitApproval(let id, let approved, let denied):
            let decision = try await waitForDecision(approvalID: id, runID: runID)
            try await execute(decision.isApproval ? approved : denied, runID: runID, messageID: messageID)

        case .respond(let text):
            try await streamResponse(text, runID: runID, messageID: messageID)

        case .attach(let part):
            mutateMessage(messageID, runID: runID) { $0.parts.append(part) }

        case .complete(let summary):
            finish(runID: runID, state: .completed, detail: summary)

        case .fail(let reason):
            finish(runID: runID, state: .failed, detail: reason)
        }
    }

    // MARK: Steps

    private func sleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds / max(simulation.runSpeed, 0.1)))
    }

    func mutateRun(_ id: String, _ body: (inout Run) -> Void) {
        guard var run = runs[id] else { return }
        body(&run)
        upsert(run)
    }

    private func mutateMessage(_ id: String, runID: String, _ body: (inout Message) -> Void) {
        guard let conversationID = runs[runID]?.conversationID,
              var message = messages[conversationID]?.first(where: { $0.id == id }) else { return }
        body(&message)
        upsert(message)
    }

    /// Promotes a matching planned step to active, or appends a new active step.
    @discardableResult
    private func activateStep(runID: String, title: String, kind: RunEventKind, toolKind: ToolKind?, detail: String?) -> String {
        var eventID = ""
        mutateRun(runID) { run in
            let next = run.lastSequence + 1
            if let index = run.events.firstIndex(where: { $0.kind == .planned && $0.status == .pending && $0.title == title }) {
                var event = run.events.remove(at: index)
                event.kind = kind == .planned ? .planned : kind
                event.status = .active
                event.toolKind = toolKind
                event.detail = detail ?? event.detail
                event.timestamp = .now
                event.sequence = next
                run.events.append(event)
                eventID = event.id
            } else {
                let event = RunEvent(sequence: next, kind: kind, title: title, detail: detail, status: .active, toolKind: toolKind)
                run.events.append(event)
                eventID = event.id
            }
            run.currentAction = title
        }
        return eventID
    }

    private func completeStep(runID: String, eventID: String, call: ToolCall, duration: TimeInterval?) {
        mutateRun(runID) { run in
            guard let index = run.events.firstIndex(where: { $0.id == eventID }) else { return }
            run.events[index].status = call.status == .failed ? .failed : .done
            run.events[index].title = call.summary
            run.events[index].detail = call.output ?? call.input ?? call.targets.joined(separator: ", ").nilIfEmpty ?? run.events[index].detail
            run.events[index].duration = duration
            run.currentAction = "Thinking"
        }
    }

    private func requestApproval(_ template: ApprovalTemplate, runID: String) -> ApprovalRequest {
        let run = runs[runID]
        let approval = ApprovalRequest(
            id: "a-\(UUID().uuidString.prefix(8).lowercased())", runID: runID, conversationID: run?.conversationID,
            profileID: run?.profileID, kind: template.kind, summary: template.summary, command: template.command,
            workingDirectory: template.workingDirectory, paths: template.paths, diff: template.diff,
            reason: template.reason, risk: template.risk, requestedAt: .now,
            expiresAt: template.expiresIn.map { Date.now.addingTimeInterval($0) },
            availability: template.availability, allowsSessionApproval: template.availability.isActionable)
        upsert(approval)
        mutateRun(runID) { run in
            run.state = .waitingForApproval
            run.pendingApprovalID = approval.id
            run.currentAction = "Waiting for approval"
            run.append(RunEvent(kind: .approvalRequested, title: "Approve \(approval.payload)", detail: approval.reason, status: .active))
        }
        log(.warning, .approval, "Approval requested: \(approval.payload)", detail: "\(profileName(run?.profileID)) · \(approval.kind.label)", runID: runID)
        if let expiresIn = template.expiresIn {
            Task {
                try? await Task.sleep(for: .seconds(expiresIn))
                self.expireApproval(approval.id)
            }
        }
        return approval
    }

    private func expireApproval(_ id: String) {
        guard var approval = approvals[id], let waiter = approvalWaiters.removeValue(forKey: id) else { return }
        approval.availability = .expired
        upsert(approval)
        approvals[id] = nil
        publish(.approvalResolved(approvalID: id, decision: nil))
        mutateRun(approval.runID) { run in
            run.append(RunEvent(kind: .approvalResolved, title: "Approval expired", status: .skipped))
        }
        log(.warning, .approval, "Approval expired: \(approval.payload)", runID: approval.runID)
        waiter.resume(returning: .deny)
    }

    private func waitForDecision(approvalID: String, runID: String) async throws -> ApprovalDecision {
        let decision = await withCheckedContinuation { continuation in
            approvalWaiters[approvalID] = continuation
        }
        try Task.checkCancellation()
        mutateRun(runID) { run in
            if let index = run.events.lastIndex(where: { $0.kind == .approvalRequested && $0.status == .active }) {
                run.events[index].status = decision.isApproval ? .done : .skipped
            }
            if run.events.last?.title != "Approval expired" {
                let title = switch decision {
                case .approveOnce: "Approved from iPhone"
                case .approveForSession: "Approved for this session"
                case .deny: "Denied from iPhone"
                }
                run.append(RunEvent(kind: .approvalResolved, title: title, status: decision.isApproval ? .done : .skipped))
            }
            run.state = .running
            run.pendingApprovalID = nil
            run.currentAction = "Thinking"
        }
        return decision
    }

    private func streamResponse(_ text: String, runID: String, messageID: String) async throws {
        let pendingTitle = runs[runID]?.events.first(where: { $0.kind == .planned && $0.status == .pending })?.title
        let eventID = activateStep(runID: runID, title: pendingTitle ?? "Writing response", kind: .output, toolKind: nil, detail: nil)
        var full = text
        if let note = steeringNotes[runID]?.last {
            full = "Adjusted for your instruction — *\(note)*.\n\n" + text
        }
        mutateMessage(messageID, runID: runID) { $0.parts.append(.markdown("")) }
        var accumulated = ""
        for chunk in MockScripts.chunks(full) {
            try await sleep(0.03)
            accumulated += chunk
            mutateMessage(messageID, runID: runID) { message in
                if let index = message.parts.lastIndex(where: { if case .markdown = $0 { true } else { false } }) {
                    message.parts[index] = .markdown(accumulated)
                }
            }
        }
        mutateRun(runID) { run in
            if let index = run.events.firstIndex(where: { $0.id == eventID }) { run.events[index].status = .done }
        }
    }

    // MARK: Completion

    func finish(runID: String, state: RunState, detail: String?) {
        guard var run = runs[runID], run.state.isActive else { return }
        run.state = state
        run.endedAt = .now
        run.currentAction = nil
        run.pendingApprovalID = nil
        run.events.removeAll { $0.kind == .planned && $0.status == .pending }
        for index in run.events.indices where run.events[index].status == .active {
            run.events[index].status = state == .completed ? .done : .skipped
        }
        switch state {
        case .completed:
            run.resultSummary = detail
            run.append(RunEvent(kind: .completed, title: "Completed"))
        case .failed:
            run.failureReason = detail
            run.append(RunEvent(kind: .failed, title: "Failed", detail: detail, status: .failed))
        default:
            run.failureReason = detail
            run.append(RunEvent(kind: .cancelled, title: "Stopped", detail: detail))
        }
        var usage = run.usage ?? TokenUsage(input: 0, output: 0)
        usage.input += Int.random(in: 6_000...40_000)
        usage.output += Int.random(in: 300...2_400)
        run.usage = usage
        upsert(run)
        steeringNotes[runID] = nil

        if let conversationID = run.conversationID {
            if var message = messages[conversationID]?.last(where: { $0.runID == runID && $0.role == .assistant }) {
                message.status = .sent
                if state == .cancelled {
                    message.parts.append(.event(SystemEvent(symbol: "stop.circle", text: "Stopped by you")))
                } else if state == .failed {
                    message.parts.append(.error(MessageError(title: "Run failed", detail: detail, isRetryable: true)))
                }
                upsert(message)
            }
            if var conversation = conversations[conversationID] {
                if conversation.activeRunID == runID { conversation.activeRunID = nil }
                conversation.lastActivity = .now
                conversation.messageCount += 1
                conversation.preview = messages[conversationID]?.last(where: { $0.role == .assistant })?.plainText.nilIfEmpty
                    ?? detail ?? conversation.preview
                upsert(conversation)
            }
        }

        if let taskID = run.taskID, var task = tasks[taskID] {
            let text = switch state {
            case .completed: "Run completed: \(detail ?? run.title)"
            case .failed: "Run failed: \(detail ?? "unknown error")"
            default: "Run stopped"
            }
            task.activity.append(TaskActivity(id: UUID().uuidString, date: .now, text: text, profileID: run.profileID,
                                              symbol: RunOutcome(state)?.symbol ?? "circle"))
            task.updatedAt = .now
            if run.trigger == .task {
                switch state {
                case .completed: task.status = .completed; task.completedAt = .now
                case .failed: task.status = .failed; task.completedAt = .now
                default: task.status = .ready
                }
            }
            upsert(task)
        }

        if let routineID = run.routineID, var routine = routines[routineID], let outcome = RunOutcome(state) {
            routine.lastResult = RoutineResult(outcome: outcome, date: .now, runID: runID, summary: detail)
            upsert(routine)
        }

        let level: LogLevel = state == .failed ? .error : .info
        log(level, .run, "Run \(state.label.lowercased()): \(run.title)", detail: state == .completed ? nil : detail, runID: runID)
    }
}

private extension Message {
    /// Replaces a tool call by ID, or appends it in chronological position.
    mutating func upsertToolCall(_ call: ToolCall) {
        for index in parts.indices {
            if case .tools(var calls) = parts[index], let callIndex = calls.firstIndex(where: { $0.id == call.id }) {
                calls[callIndex] = call
                parts[index] = .tools(calls)
                return
            }
        }
        if case .tools(var calls) = parts.last {
            calls.append(call)
            parts[parts.count - 1] = .tools(calls)
        } else {
            parts.append(.tools([call]))
        }
    }
}

extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
