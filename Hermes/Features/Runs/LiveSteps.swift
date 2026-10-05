import SwiftUI

/// The ✓ ● ○ checklist for a run. Used in the chat live block and Run Detail.
struct LiveSteps: View {
    var steps: [RunEvent]
    /// Collapse finished steps beyond this count into a summary line.
    var maxFinished: Int? = nil

    var body: some View {
        let finished = steps.filter { $0.status != .active && $0.status != .pending }
        let hidden = maxFinished.map { max(0, finished.count - $0) } ?? 0
        VStack(alignment: .leading, spacing: 7) {
            if hidden > 0 {
                Text("\(hidden) earlier step\(hidden == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 24)
            }
            ForEach(Array(steps.dropFirst(hidden))) { step in
                StepLine(step: step)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: steps.map(\.status))
        .animation(.easeInOut(duration: 0.25), value: steps.map(\.id))
    }
}

struct StepLine: View {
    var step: RunEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            glyph
                .frame(width: 14)
            Text(text)
                .font(.subheadline.weight(step.status == .active ? .medium : .regular))
                .foregroundStyle(foreground)
                .strikethrough(step.status == .skipped, color: .secondary)
                .lineLimit(2)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var text: String {
        if step.kind == .steering, let detail = step.detail { return "You: \(detail)" }
        return step.title
    }

    @ViewBuilder private var glyph: some View {
        if step.kind == .steering {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
        } else if step.kind == .approvalRequested && step.status == .active {
            Image(systemName: "hand.raised.fill")
                .font(.caption)
                .foregroundStyle(Theme.attention)
        } else {
            switch step.status {
            case .done:
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            case .active:
                StatusDot(color: Theme.running, pulsing: true, size: 7)
            case .pending:
                Image(systemName: "circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            case .failed:
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.failure)
            case .skipped:
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var foreground: AnyShapeStyle {
        switch step.status {
        case .active: step.kind == .approvalRequested ? AnyShapeStyle(Theme.attention) : AnyShapeStyle(.primary)
        case .done: AnyShapeStyle(.secondary)
        case .failed: AnyShapeStyle(Theme.failure)
        case .pending, .skipped: AnyShapeStyle(.tertiary)
        }
    }

    private var accessibilityText: String {
        let status = switch step.status {
        case .done: "Done"
        case .active: "In progress"
        case .pending: "Upcoming"
        case .failed: "Failed"
        case .skipped: "Skipped"
        }
        return "\(status): \(text)"
    }
}

#Preview {
    LiveSteps(steps: MockFixtures.standard().runs.first { $0.id == "r-bench" }!.steps)
        .padding()
}
