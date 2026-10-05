import SwiftUI

/// What a running agent is doing, in the transcript. Never just a spinner:
/// the step list, the current action, approvals and controls live here.
struct LiveRunBlock: View {
    var run: Run
    var onSteer: () -> Void

    @Environment(ActivityStore.self) private var activity
    @Environment(ConnectionStore.self) private var connection
    @Environment(ToastCenter.self) private var toasts
    @Environment(AppRouter.self) private var router
    @State private var expanded = true
    @State private var confirmingStop = false

    var body: some View {
        let state = run.displayState(isLive: connection.connection.isConnected)
        let approval = activity.pendingApproval(for: run)

        VStack(alignment: .leading, spacing: 12) {
            header(state)

            if expanded {
                LiveSteps(steps: run.steps, maxFinished: 4)
                    .transition(.opacity)
            } else if let active = run.activeStep {
                StepLine(step: active)
            }

            if let approval {
                Divider()
                ApprovalCard(approval: approval, style: .plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            controls(state)
        }
        .panel(tint: state.needsUser ? Theme.attention : nil)
        .animation(.snappy, value: approval?.id)
        .animation(.snappy, value: state)
        .confirmationDialog("Stop this run?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop Run", role: .destructive) {
                toasts.perform { try await activity.stop(run.id) }
            }
        } message: {
            Text("Hermes will finish its current step, then stop.")
        }
    }

    private func header(_ state: RunState) -> some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                switch state {
                case .running, .queued:
                    StatusDot(color: Theme.running, pulsing: true, size: 8)
                case .steeringPending:
                    ProgressView().controlSize(.mini)
                default:
                    Image(systemName: state.symbol)
                        .font(.footnote)
                        .foregroundStyle(state.tint)
                }
                Text(title(state))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.needsUser ? state.tint : .primary)
                Spacer()
                ElapsedText(start: run.startedAt, end: run.endedAt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title(state)), \(Format.elapsed(run.elapsed()))")
        .accessibilityHint(expanded ? "Collapse steps" : "Expand steps")
    }

    @ViewBuilder
    private func controls(_ state: RunState) -> some View {
        let live = connection.connection.isConnected
        let canSteer = run.canSteer && connection.supports(.steering)
        let canStop = run.canStop && connection.supports(.stop)
        HStack(spacing: 8) {
            if canSteer {
                Button(action: onSteer) {
                    Label("Send Instruction", systemImage: "arrow.turn.down.right")
                }
                .buttonStyle(.bordered)
            }
            if canStop {
                Button(role: .destructive) {
                    confirmingStop = true
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button("Details") { router.open(.run(run.id)) }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.medium))
        }
        .controlSize(.small)
        .disabled(!live)
    }

    private func title(_ state: RunState) -> String {
        switch state {
        case .waitingForApproval: "Needs approval"
        case .waitingForInput: "Waiting for you"
        case .steeringPending: "Delivering instruction"
        case .stopping: "Stopping"
        case .disconnected: "Working · last known"
        case .queued: "Queued"
        default: "Working"
        }
    }
}
