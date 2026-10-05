import SwiftUI
import UIKit

/// Everything about one run. Reachable from Home, Chat, Tasks and Bots.
struct RunDetailView: View {
    var runID: String

    @Environment(ActivityStore.self) private var activity
    @Environment(ProfileStore.self) private var profiles
    @Environment(ConnectionStore.self) private var connection
    @Environment(ConversationListStore.self) private var conversations
    @Environment(TaskStore.self) private var tasks
    @Environment(RoutineStore.self) private var routines
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @State private var showingSteer = false
    @State private var confirmingStop = false

    var body: some View {
        Group {
            if let run = activity.run(runID) {
                content(run)
            } else if activity.phase.isLoading {
                ProgressView()
            } else {
                ContentUnavailableView("Run Not Found", systemImage: "questionmark.circle",
                                       description: Text("It may have been removed from the host's history."))
            }
        }
        .navigationTitle("Run")
        .task { await activity.loadRun(runID) }
        .navigationBarTitleDisplayMode(.inline)
        .connectionBanner(updatedAt: activity.updatedAt)
    }

    @ViewBuilder
    private func content(_ run: Run) -> some View {
        let state = run.displayState(isLive: connection.connection.isConnected)
        List {
            Section {
                header(run, state: state)
            }

            if run.state == .failed || run.state == .cancelled {
                Section {
                    FailureCallout(explanation: StatusCopy.runFailure(run.failureReason, cancelled: run.state == .cancelled),
                                   symbol: run.state == .failed ? "xmark.octagon.fill" : "stop.circle.fill",
                                   tint: run.state == .failed ? Theme.failure : .secondary)
                        .padding(.vertical, 4)
                    if run.canRetry && connection.supports(.runs) {
                        Button {
                            toasts.perform(success: "Retrying") { try await activity.retry(run.id) }
                        } label: {
                            Label("Retry Run", systemImage: "arrow.clockwise")
                        }
                        .disabled(!connection.connection.isConnected)
                    }
                    if let conversationID = run.conversationID {
                        Button {
                            router.open(.conversation(conversationID))
                        } label: {
                            Label("Open Conversation", systemImage: "bubble.left.and.bubble.right")
                        }
                    }
                }
            }

            if let approval = activity.pendingApproval(for: run) {
                Section {
                    ApprovalCard(approval: approval, style: .plain)
                        .padding(.vertical, 6)
                }
            }

            if run.state.isActive && !run.steps.isEmpty {
                Section {
                    LiveSteps(steps: run.steps)
                        .padding(.vertical, 4)
                } header: {
                    SectionHeader("Now")
                }
            }

            controls(run)

            if run.state == .completed, let result = run.resultSummary {
                Section {
                    Text(result)
                        .textSelection(.enabled)
                } header: {
                    SectionHeader("Result")
                }
            }

            Section {
                RunTimeline(events: run.events)
            } header: {
                SectionHeader(title: "Timeline") {
                    Text("\(run.events.count) events").monospacedDigit().foregroundStyle(.tertiary)
                }
            }

            metadata(run)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let conversationID = run.conversationID {
                        Button("Open Conversation", systemImage: "bubble.left.and.bubble.right") {
                            router.open(.conversation(conversationID))
                        }
                    }
                    Button("Copy Run ID", systemImage: "number") { UIPasteboard.general.string = run.id }
                    ShareLink(item: summary(run)) { Label("Share Summary", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Run actions")
            }
        }
        .sheet(isPresented: $showingSteer) {
            SteerSheet(run: run)
        }
        .confirmationDialog("Stop this run?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop Run", role: .destructive) {
                toasts.perform(success: "Stopping run") { try await activity.stop(run.id) }
            }
        } message: {
            Text("Hermes will finish its current step, then stop. Work already done stays on your Mac.")
        }
        .refreshable { await activity.refresh() }
    }

    private func header(_ run: Run, state: RunState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                RunStateLabel(state: state)
                Spacer()
                Label {
                    ElapsedText(start: run.startedAt, end: run.endedAt)
                } icon: {
                    Image(systemName: "timer")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            Text(run.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ProfileAvatar(profile: profiles.identity(run.profileID), size: 22)
                Text(profiles.name(run.profileID))
                    .font(.subheadline.weight(.medium))
                Text("·").foregroundStyle(.tertiary)
                Text(run.trigger.label)
                    .foregroundStyle(.secondary)
                if let host = connection.hosts.first(where: { $0.id == run.hostID })?.name {
                    Text("·").foregroundStyle(.tertiary)
                    Text(host).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .font(.subheadline)
            if run.state.isActive, run.steps.isEmpty, let action = run.currentAction, !run.state.needsUser {
                CurrentActionLabel(run: run, state: state)
                    .accessibilityLabel("Current action: \(action)")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func controls(_ run: Run) -> some View {
        let live = connection.connection.isConnected
        let canStop = run.canStop && connection.supports(.stop)
        let canSteer = run.canSteer && connection.supports(.steering)
        // Failed/cancelled runs offer Retry inside their failure section; the
        // bridge may also allow it in other states.
        let canRetryHere = run.canRetry && connection.supports(.runs) && run.state != .failed && run.state != .cancelled
        if (run.state.isActive && (canStop || canSteer)) || canRetryHere {
            Section {
                HStack(spacing: 10) {
                    if canSteer {
                        Button {
                            showingSteer = true
                        } label: {
                            Label("Send Instruction", systemImage: "arrow.turn.down.right").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if canStop {
                        Button(role: .destructive) {
                            confirmingStop = true
                        } label: {
                            Label("Stop", systemImage: "stop.fill").frame(maxWidth: canSteer ? nil : .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if canRetryHere {
                        Button {
                            toasts.perform(success: "Retrying") { try await activity.retry(run.id) }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
                .disabled(!live)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                if !live { Text("Controls return when Talaria reconnects to your Mac.") }
            }
        }
    }

    @ViewBuilder
    private func metadata(_ run: Run) -> some View {
        Section {
            if let conversation = conversations.conversation(run.conversationID) {
                NavigationLink(value: Route.conversation(conversation.id)) {
                    LabeledContent("Conversation", value: conversation.title)
                }
            }
            if let task = tasks.task(run.taskID) {
                NavigationLink(value: Route.task(task.id)) {
                    LabeledContent("Task", value: task.title)
                }
            }
            if let routine = routines.routine(run.routineID) {
                NavigationLink(value: Route.routine(routine.id)) {
                    LabeledContent("Routine", value: routine.name)
                }
            }
            if let project = run.project {
                KeyValueRow(label: "Project", value: project.name)
                KeyValueRow(label: "Working directory", value: project.path, monospaced: true)
            }
            if let model = run.model {
                KeyValueRow(label: "Model", value: model.detailedLabel)
            }
            if let reasoning = run.reasoning {
                KeyValueRow(label: "Reasoning", value: reasoning.label)
            }
            KeyValueRow(label: "Started", value: Format.timestamp(run.startedAt))
            if let end = run.endedAt {
                KeyValueRow(label: "Ended", value: Format.timestamp(end))
            }
            KeyValueRow(label: "Run ID", value: run.id, monospaced: true)
        } header: {
            SectionHeader("Details")
        }

        if let usage = run.usage, usage.total > 0 {
            Section {
                KeyValueRow(label: "Input", value: Format.tokens(usage.input))
                KeyValueRow(label: "Output", value: Format.tokens(usage.output))
                if usage.cached > 0 { KeyValueRow(label: "Cached", value: Format.tokens(usage.cached)) }
                if usage.reasoning > 0 { KeyValueRow(label: "Reasoning", value: Format.tokens(usage.reasoning)) }
            } header: {
                SectionHeader("Tokens")
            }
        }
    }

    private func outcomeText(_ run: Run) -> String? {
        switch run.state {
        case .completed: return run.resultSummary
        case .failed, .cancelled:
            let copy = StatusCopy.runFailure(run.failureReason, cancelled: run.state == .cancelled)
            return [copy.title, copy.message].compactMap { $0 }.joined(separator: ": ")
        default: return nil
        }
    }

    private func summary(_ run: Run) -> String {
        var lines = ["\(run.title) — \(run.state.label)", "\(profiles.name(run.profileID)) · \(Format.elapsed(run.elapsed()))"]
        if let outcome = outcomeText(run) { lines.append(outcome) }
        lines += run.steps.map { "• \($0.title)" }
        return lines.joined(separator: "\n")
    }
}

#Preview("Running") {
    NavigationStack { RunDetailView(runID: "r-bench") }.previewEnvironment()
}

#Preview("Approval") {
    NavigationStack { RunDetailView(runID: "r-ios") }.previewEnvironment()
}

#Preview("Failed") {
    NavigationStack { RunDetailView(runID: "r-nightly") }.previewEnvironment()
}
