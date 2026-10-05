import Foundation

/// Holds the bridge's aggregated Home response. Live events patch it in
/// place for responsiveness; structural changes trigger a debounced refetch
/// rather than recomputing the aggregate on the phone.
@Observable
final class HomeStore {
    private let client: HermesClient
    private let cache: SnapshotCache

    private(set) var summary: HomeSummary?
    private(set) var phase: LoadPhase = .idle
    /// When `summary` was produced; older than "now" means cached.
    private(set) var updatedAt: Date?
    private var refreshTask: Task<Void, Never>?

    init(client: HermesClient, cache: SnapshotCache) {
        self.client = client
        self.cache = cache
        if let snapshot = cache.load(HomeSummary.self, key: .home) {
            summary = snapshot.value
            updatedAt = snapshot.savedAt
        }
        if let state = cache.load(AppliedBridgeState.self, key: .appliedBridgeState) { summary = state.value.home; updatedAt = state.savedAt }

    }

    func restoreScopedCache() {
        refreshTask?.cancel()
        summary = cache.load(AppliedBridgeState.self, key: .appliedBridgeState)?.value.home ?? cache.load(HomeSummary.self, key: .home)?.value
        updatedAt = summary?.generatedAt; phase = .idle
    }

    /// Bridge-reported items plus what only the phone can know (it can't
    /// reach the bridge, or the bridge rejected it). Dismissed failures are hidden.
    func attentionItems(connection: ConnectionStore, preferences: AppPreferences) -> [AttentionItem] {
        var items = (summary?.attention ?? []).filter { item in
            !(item.kind == .failedRun && preferences.acknowledgedRunIDs.contains(item.runID ?? ""))
        }
        switch connection.connection {
        case .authenticationRequired:
            items.insert(AttentionItem(id: "local-auth", kind: .authentication, title: "Pair this iPhone again",
                                       detail: ConnectionState.authenticationRequired.explanation,
                                       date: connection.status.lastSeen ?? .now), at: 0)
        case .bridgeOffline, .hermesOffline:
            items.insert(AttentionItem(id: "local-host", kind: .hostIssue,
                                       title: connection.connection.label(host: connection.activeHost?.name),
                                       detail: connection.connection.explanation,
                                       date: connection.status.lastSeen ?? .now), at: 0)
        default:
            break
        }
        return items
    }

    func refresh() async {
        phase = .loading
        do {
            let summary = try await client.home.homeSummary()
            self.summary = summary
            updatedAt = .now
            phase = .loaded
            cache.save(summary, key: .home)
        } catch {
            if let error = HermesError.from(error) { phase = .failed(error) }
        }
    }

    func apply(_ event: HermesEvent) {
        switch event {
        case .runUpserted(let run):
            patch(run)
            if run.state.isTerminal || run.state.needsUser { scheduleRefresh() }
        case .hostStatus(let status):
            if summary?.host.hostID == status.hostID { summary?.host = status }
        case .approvalUpserted, .approvalResolved, .taskUpserted, .routineUpserted, .routineRemoved, .resyncRequired:
            scheduleRefresh()
        default:
            break
        }
    }

    private func patch(_ run: Run) {
        guard var summary else { return }
        summary.activeRuns.removeAll { $0.id == run.id }
        if run.state.isActive {
            summary.activeRuns.append(run)
            summary.activeRuns.sort { $0.startedAt > $1.startedAt }
        } else if !summary.recentRuns.contains(where: { $0.id == run.id }) {
            summary.recentRuns.insert(run, at: 0)
            summary.recentRuns = Array(summary.recentRuns.prefix(6))
        }
        self.summary = summary
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }
}
