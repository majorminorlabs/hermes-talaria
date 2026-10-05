import SwiftUI

enum TasksSegment: String, CaseIterable, Identifiable {
    case running, scheduled, kanban, completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .running: "Running"
        case .scheduled: "Scheduled"
        case .kanban: "Kanban"
        case .completed: "Completed"
        }
    }

    var capability: HermesCapability {
        switch self {
        case .running, .completed: .runs
        case .scheduled: .cron
        case .kanban: .kanban
        }
    }
}

/// Operational work across Hermes. Each segment keeps its own meaning:
/// runs are executions, routines are schedules, tasks are durable work.
struct TasksView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ConnectionStore.self) private var connection
    @Environment(ActivityStore.self) private var activity
    @State private var showingNewTask = false

    var body: some View {
        @Bindable var router = router
        let segments = availableSegments
        Group {
            switch segments.contains(router.tasksSegment) ? router.tasksSegment : (segments.first ?? .running) {
            case .running: RunningRunsView()
            case .scheduled: ScheduledView()
            case .kanban: KanbanView()
            case .completed: CompletedRunsView()
            }
        }
        .pinnedTopBar {
            Picker("Section", selection: $router.tasksSegment) {
                ForEach(segments) { segment in
                    Text(segment.label).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .connectionBanner(updatedAt: activity.updatedAt)
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if router.tasksSegment == .kanban && connection.supports(.kanban) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewTask = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New Task")
                        .disabled(!connection.connection.isConnected)
                }
            }
        }
        .sheet(isPresented: $showingNewTask) {
            NewTaskSheet(assigneeProfileID: nil)
        }
    }

    private var availableSegments: [TasksSegment] {
        let supported = TasksSegment.allCases.filter { connection.supports($0.capability) }
        return supported.isEmpty ? [.running, .completed] : supported
    }
}

// MARK: - Running

struct RunningRunsView: View {
    @Environment(ActivityStore.self) private var activity

    var body: some View {
        let runs = activity.activeRuns
        LoadableContent(phase: activity.phase, isEmpty: runs.isEmpty, hasData: !activity.runs.isEmpty,
                        retry: { await activity.refresh() }) {
            List {
                let waiting = runs.filter(\.state.needsUser)
                let others = runs.filter { !$0.state.needsUser }
                if !waiting.isEmpty {
                    Section {
                        ForEach(waiting) { run in
                            NavigationLink(value: Route.run(run.id)) { RunRow(run: run) }
                        }
                    } header: {
                        SectionHeader(title: "Waiting on You") { Tag("\(waiting.count)", tone: .attention) }
                    }
                }
                if !others.isEmpty {
                    Section {
                        ForEach(others) { run in
                            NavigationLink(value: Route.run(run.id)) { RunRow(run: run) }
                        }
                    } header: {
                        SectionHeader(title: "Running") {
                            Text("\(others.count)").monospacedDigit().foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .refreshable { await activity.refresh() }
        } empty: {
            ContentUnavailableView("Nothing Running", systemImage: "moon.zzz",
                                   description: Text("Runs from conversations, routines and tasks appear here while Hermes works."))
        }
    }
}

// MARK: - Completed

struct CompletedRunsView: View {
    @Environment(ActivityStore.self) private var activity
    @State private var filter: RunOutcome?

    var body: some View {
        let runs = activity.finishedRuns.filter { filter == nil || RunOutcome($0.state) == filter }
        LoadableContent(phase: activity.phase, isEmpty: activity.finishedRuns.isEmpty, hasData: !activity.runs.isEmpty,
                        retry: { await activity.refresh() }) {
            List {
                Section {
                    Picker("Outcome", selection: $filter) {
                        Text("All").tag(RunOutcome?.none)
                        ForEach(RunOutcome.allCases) { outcome in
                            Text(outcome.label).tag(RunOutcome?.some(outcome))
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if runs.isEmpty {
                    Text("No \(filter?.label.lowercased() ?? "finished") runs in recent history.")
                        .foregroundStyle(.secondary)
                }
                ForEach(groups(runs), id: \.0) { title, runs in
                    Section {
                        ForEach(runs) { run in
                            NavigationLink(value: Route.run(run.id)) { RecentRunRow(run: run) }
                        }
                    } header: {
                        SectionHeader(title: title) {
                            Text("\(runs.count)").monospacedDigit().foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .refreshable { await activity.refresh() }
        } empty: {
            ContentUnavailableView("No History Yet", systemImage: "clock.arrow.circlepath",
                                   description: Text("Finished, failed and cancelled runs appear here."))
        }
    }

    private func groups(_ runs: [Run]) -> [(String, [Run])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: runs) { run -> String in
            let date = run.endedAt ?? run.startedAt
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            return "Earlier"
        }
        return ["Today", "Yesterday", "Earlier"].compactMap { key in grouped[key].map { (key, $0) } }
    }
}

#Preview {
    NavigationStack { TasksView().routeDestinations() }
        .previewEnvironment()
}
