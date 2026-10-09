import Foundation

/// Runs and approvals across the host. The single source the UI uses for
/// run state, so Home, Chat, Tasks and Run Detail always agree.
@Observable
final class ActivityStore {
    private let client: HermesClient
    private let cache: SnapshotCache

    private(set) var runs: [String: Run] = [:]
    private(set) var approvals: [String: ApprovalRequest] = [:]
    /// Approvals resolved recently, so cards can show the outcome briefly.
    private(set) var resolvedApprovals: [String: ApprovalDecision?] = [:]
    private(set) var phase: LoadPhase = .idle
    private(set) var updatedAt: Date?

    init(client: HermesClient, cache: SnapshotCache) {
        self.client = client
        self.cache = cache
        if let snapshot = cache.load([Run].self, key: .runs) {
            runs = Dictionary(snapshot.value.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            updatedAt = snapshot.savedAt
        }
        if let snapshot = cache.load([ApprovalRequest].self, key: .approvals) {
            approvals = Dictionary(snapshot.value.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        }
        if let state = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value {
            runs = Dictionary(state.runs.map { ($0.id,$0) }, uniquingKeysWith: { $1 })
            approvals = Dictionary(state.approvals.map { ($0.id,$0) }, uniquingKeysWith: { $1 })
        }

    }

    func restoreScopedCache() {
        let state = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value
        let fetchedRuns = state?.runs ?? cache.load([Run].self, key: .runs)?.value ?? []
        runs = Dictionary(fetchedRuns.map { ($0.id,$0) }, uniquingKeysWith: { $1 })
        let fetchedApprovals = state?.approvals ?? cache.load([ApprovalRequest].self, key: .approvals)?.value ?? []
        approvals = Dictionary(fetchedApprovals.map { ($0.id,$0) }, uniquingKeysWith: { $1 })
        phase = .idle; resolvedApprovals = [:]
    }

    // MARK: Queries

    var activeRuns: [Run] {
        runs.values.filter(\.state.isActive).sorted { $0.startedAt > $1.startedAt }
    }

    var finishedRuns: [Run] {
        runs.values.filter { $0.state.isTerminal || $0.state == .unknown }.sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
    }

    func run(_ id: String?) -> Run? { id.flatMap { runs[$0] } }

    func approval(_ id: String?) -> ApprovalRequest? { id.flatMap { approvals[$0] } }

    func pendingApproval(for run: Run) -> ApprovalRequest? {
        approval(run.pendingApprovalID) ?? approvals.values.first { $0.runID == run.id }
    }

    func runs(forProfile id: String) -> [Run] {
        runs.values.filter { $0.profileID == id }.sorted { $0.startedAt > $1.startedAt }
    }

    func runs(forTask id: String) -> [Run] {
        runs.values.filter { $0.taskID == id }.sorted { $0.startedAt > $1.startedAt }
    }

    func runs(forRoutine id: String) -> [Run] {
        runs.values.filter { $0.routineID == id }.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: Loading

    func refresh() async {
        phase = .loading
        do {
            async let fetchedRuns = client.runs.listRuns()
            async let fetchedApprovals = client.runs.pendingApprovals()
            let (runs, approvals) = try await (fetchedRuns, fetchedApprovals)
            for run in runs { merge(run) }
            let fetchedIDs = Set(runs.map(\.id))
            self.runs = self.runs.filter { fetchedIDs.contains($0.key) }
            self.approvals = Dictionary(approvals.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            updatedAt = .now
            phase = .loaded
            persist()
        } catch {
            if let error = HermesError.from(error) { phase = .failed(error) }
        }
    }

    func apply(_ event: HermesEvent) {
        switch event {
        case .runUpserted(let run):
            merge(run)
        case .approvalUpserted(let approval):
            approvals[approval.id] = approval
        case .approvalResolved(let id, let decision):
            approvals[id] = nil
            resolvedApprovals[id] = decision
        default:
            return
        }
        persistSoon()
    }

    /// Ignores snapshots older than what we already have; replayed and live
    /// events can overlap after a reconnect.
    private func merge(_ run: Run) {
        if let existing = runs[run.id] {
            guard existing.lastSequence <= run.lastSequence else { return }
            if existing.state.isTerminal && existing.state != run.state {
                // A snapshot cannot undo termination. A later explicit completion
                // can report a finish after a stop, but must remain visible as such.
                guard run.state == .completed, run.lastSequence > existing.lastSequence,
                      run.events.contains(where: { $0.kind == .completed && $0.sequence > existing.lastSequence }) else { return }
                var corrected = run
                if existing.state == .cancelled {
                    corrected.events.append(RunEvent(sequence: run.lastSequence, kind: .output,
                        title: "Hermes reported this finished after you stopped it"))
                }
                runs[run.id] = corrected
                return
            }
        }
        runs[run.id] = run
    }

    // MARK: Actions

    func stop(_ runID: String) async throws {
        try await client.runs.stop(runID: runID)
    }

    func steer(_ runID: String, instruction: String) async throws {
        try await client.runs.steer(runID: runID, instruction: instruction)
    }

    @discardableResult
    func retry(_ runID: String) async throws -> Run {
        try await client.runs.retry(runID: runID)
    }

    func resolve(_ approvalID: String, decision: ApprovalDecision) async throws {
        do {
            try await client.runs.resolveApproval(id: approvalID, decision: decision)
            approvals[approvalID] = nil
            resolvedApprovals[approvalID] = decision
            persist()
        } catch HermesError.staleAttention {
            approvals[approvalID] = nil
            persist()
            await refresh()
            throw HermesError.staleAttention
        }
    }

    func answerClarification(_ id: String, answer: String) async throws {
        do {
            try await client.runs.answerClarification(id: id, answer: answer)
        } catch HermesError.staleAttention {
            approvals[id] = nil
            persist()
            await refresh()
            throw HermesError.staleAttention
        }
    }

    func loadRun(_ id: String) async {
        if let run = try? await client.runs.run(id: id) { merge(run) }
    }

    // MARK: Cache

    private var persistTask: Task<Void, Never>?

    private func persistSoon() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private func persist() {
        let recent = activeRuns + finishedRuns.prefix(60)
        cache.save(recent, key: .runs)
        cache.save(Array(approvals.values), key: .approvals)
    }
}
