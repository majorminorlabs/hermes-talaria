import SwiftUI

/// Operational status at a glance, top to bottom: is Hermes connected, is
/// anything running, does anything need me, what happened, what's next.
/// Renders the bridge's aggregated Home summary.
struct HomeView: View {
    @Environment(HomeStore.self) private var home
    @Environment(ConnectionStore.self) private var connection
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            Section {
                HomeStatusHeader(updatedAt: home.updatedAt, summary: home.summary,
                                 attentionCount: home.attentionItems(connection: connection, preferences: preferences).count)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 6, trailing: 20))

            if connection.activeHost == nil {
                Section { UnpairedWelcome() }
            } else if let summary = home.summary {
                sections(summary)
            } else if home.phase.isLoading || connection.connection.isTransitioning {
                Section { LoadingRows(count: 4) }
            } else {
                Section { noSummary }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle("Talaria")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.startNewChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New Chat")
                .disabled(!connection.supports(.sessions))
            }
        }
        .refreshable { await environment.refreshAll() }
    }

    @ViewBuilder
    private func sections(_ summary: HomeSummary) -> some View {
        let attention = home.attentionItems(connection: connection, preferences: preferences)
        if !attention.isEmpty {
            Section {
                ForEach(attention) { item in
                    AttentionRow(item: item)
                }
            } header: {
                SectionHeader(title: "Needs Attention") {
                    Tag("\(attention.count)", tone: .attention)
                        .accessibilityLabel("\(attention.count) items")
                }
            }
        }

        Section {
            if summary.activeRuns.isEmpty {
                Label {
                    Text("Nothing running")
                } icon: {
                    Image(systemName: "moon.zzz").foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
            } else {
                ForEach(summary.activeRuns) { run in
                    NavigationLink(value: Route.run(run.id)) {
                        RunRow(run: run)
                    }
                }
            }
        } header: {
            SectionHeader(title: "Active") {
                if !summary.activeRuns.isEmpty {
                    Text("\(summary.activeRuns.count) running").monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }

        if !summary.recentRuns.isEmpty {
            Section {
                ForEach(summary.recentRuns.prefix(5)) { run in
                    NavigationLink(value: Route.run(run.id)) {
                        RecentRunRow(run: run)
                    }
                }
            } header: {
                SectionHeader(title: "Recent") {
                    Button("See All") { router.showTasks(.completed) }
                        .font(.footnote.weight(.medium))
                }
            }
        }

        if connection.supports(.cron) {
            Section {
                if summary.upcoming.isEmpty {
                    Text("Nothing scheduled").foregroundStyle(.secondary)
                } else {
                    ForEach(summary.upcoming) { routine in
                        NavigationLink(value: Route.routine(routine.id)) {
                            UpcomingRow(routine: routine)
                        }
                    }
                }
            } header: {
                SectionHeader(title: "Upcoming") {
                    Button("Schedule") { router.showTasks(.scheduled) }
                        .font(.footnote.weight(.medium))
                }
            }
        }

        Section {
            // Live link state wins over the (possibly cached) aggregate.
            HostSummaryRows(status: connection.statuses[summary.host.hostID] ?? summary.host)
        } header: {
            SectionHeader("Host")
        }
    }

    @ViewBuilder
    private var noSummary: some View {
        if let error = home.phase.error {
            VStack(alignment: .leading, spacing: 6) {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(.headline)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion).font(.subheadline).foregroundStyle(.secondary)
                }
                Button("Try Again") { Task { await home.refresh() } }
                    .padding(.top, 4)
            }
            .padding(.vertical, 6)
        } else {
            Text("Hermes status appears here once Talaria reaches your Mac.")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack { HomeView().routeDestinations() }
        .previewEnvironment()
}
