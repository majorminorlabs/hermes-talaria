import Foundation

extension MockHermesBackend: CaptureService {
    func uploadCaptureMedia(_ media: LocalMedia) async throws -> String {
        try ensureReachable()
        if simulation.failCaptureSync { throw HermesError.rejected("Simulated capture sync failure") }
        return media.id.uuidString
    }
    func saveCapture(_ capture: CaptureRecord) async throws -> String {
        try ensureReachable()
        if simulation.failCaptureSync { throw HermesError.rejected("Simulated capture sync failure") }
        if let old = savedCaptures[capture.id], old.text != capture.text { throw HermesError.rejected("Capture ID conflict") }
        savedCaptures[capture.id] = capture
        return capture.id.uuidString
    }
    func commandObservation(_ id: UUID, creating: Bool) async throws -> CommandObservation {
        try ensureReachable()
        if creating, let c = createdCommands[id] { return .conversation(c) }
        if !creating, let r = sentCommands[id] { return .run(r) }
        return .notReceived
    }
    func setArchived(_ archived: Bool, conversationID: String) async throws {
        try await perform(.sessions) {
            guard var c = conversations[conversationID] else { throw HermesError.notFound }
            c.isArchived = archived; upsert(c)
        }
    }
    func createConversation(configuration: RunConfiguration, commandID: UUID) async throws -> Conversation {
        if let c = createdCommands[commandID] { return c }
        let c = try await createConversation(configuration: configuration); createdCommands[commandID] = c; return c
    }
    func send(_ outgoing: OutgoingMessage, conversationID: String, configuration: RunConfiguration, commandID: UUID) async throws -> Run {
        if let r = sentCommands[commandID] { return r }
        let r = try await send(outgoing, conversationID: conversationID, configuration: configuration); sentCommands[commandID] = r; return r
    }
    func answerClarification(id: String, answer: String) async throws {
        try await perform(.runs) {
            if simulation.staleNextClarification {
                simulation.staleNextClarification = false
                approvals[id] = nil
                publish(.approvalResolved(approvalID: id, decision: nil))
                throw HermesError.staleAttention
            }
            guard let request = approvals[id], request.isClarification, request.availability.isActionable,
                  request.expiresAt.map({ $0 > .now }) ?? true else { throw HermesError.rejected("This question has expired") }
            guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw HermesError.rejected("Enter an answer") }
            approvals[id] = nil; publish(.approvalResolved(approvalID: id, decision: .approveOnce))
            if var run = runs[request.runID] {
                run.state = .completed; run.endedAt = .now; run.pendingApprovalID = nil; run.resultSummary = "Answer received: " + answer
                run.append(RunEvent(kind: .completed, title: "Answer received")); upsert(run)
                if let cid = run.conversationID {
                    upsert(Message(conversationID: cid, role: .assistant, parts: [.markdown("Answer received: " + answer)], runID: run.id))
                    if var c = conversations[cid] { c.activeRunID = nil; c.lastActivity = .now; upsert(c) }
                }
            }
        }
    }
    func review(taskID: String, status: TaskStatus, summary: String) async throws {
        try await setStatus(status, taskID: taskID)
        if var t = tasks[taskID], !summary.isEmpty { t.summary = summary; upsert(t) }
    }
    func expireClarifications() {
        for var request in approvals.values where request.isClarification {
            request.expiresAt = .now.addingTimeInterval(-1); approvals[request.id] = request; publish(.approvalUpserted(request))
        }
    }
}

extension MockHermesBackend: ArtifactService {
    func artifacts(conversationID: String) async throws -> [FileAttachment] {
        try ensureReachable()
        return (messages[conversationID] ?? []).flatMap { message in message.parts.compactMap { if case .file(var file) = $0 { file.runID = message.runID; return file }; return nil } }
    }
    func downloadArtifact(id: String) async throws -> URL {
        try ensureReachable()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-artifact-" + UUID().uuidString + ".txt")
        try Data("Simulation artifact \(id)".utf8).write(to: url); return url
    }
}
