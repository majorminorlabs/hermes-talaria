import SwiftUI

/// Human-readable run history: one row per event with a connecting rail.
struct RunTimeline: View {
    var events: [RunEvent]

    var body: some View {
        let ordered = events.filter { !($0.kind == .planned && $0.status == .pending) }
        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, event in
            TimelineRow(event: event, isFirst: index == 0, isLast: index == ordered.count - 1)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
        }
    }
}

struct TimelineRow: View {
    var event: RunEvent
    var isFirst: Bool
    var isLast: Bool
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rail
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(event.status == .active ? .semibold : .regular))
                        .foregroundStyle(event.status == .failed ? Theme.failure : .primary)
                        .strikethrough(event.status == .skipped, color: .secondary)
                    Spacer(minLength: 8)
                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if let detail = event.detail, !detail.isEmpty, event.kind != .steering {
                    Text(StatusCopy.isRawCode(detail) ? (StatusCopy.sentence(detail) ?? detail) : detail)
                        .font(event.kind == .tool ? .caption.monospaced() : .caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 2)
                        .textSelection(.enabled)
                }
                if let duration = event.duration, duration >= 1 {
                    Text(Format.elapsed(duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 9)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch event.kind {
        case .steering: event.detail.map { "Instruction: \($0)" } ?? event.title
        default: event.title
        }
    }

    private var rail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : Theme.hairline)
                .frame(width: 1, height: 12)
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 24, height: 24)
                if event.status == .active {
                    StatusDot(color: Theme.running, pulsing: true, size: 8)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
            }
            Rectangle()
                .fill(isLast ? Color.clear : Theme.hairline)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 24)
    }

    private var symbol: String {
        switch event.kind {
        case .started: "play.fill"
        case .modelSelected: "cpu"
        case .thinking: "ellipsis"
        case .tool: event.toolKind?.symbol ?? "wrench.and.screwdriver"
        case .planned: "circle.dashed"
        case .approvalRequested: "hand.raised.fill"
        case .approvalResolved: event.status == .done ? "checkmark.shield.fill" : "xmark.shield.fill"
        case .steering: "arrow.turn.down.right"
        case .output: "text.alignleft"
        case .completed: "checkmark"
        case .failed: "xmark"
        case .cancelled: "stop.fill"
        case .connectionLost: "wifi.slash"
        case .connectionRestored: "wifi"
        }
    }

    private var iconColor: Color {
        if event.status == .failed { return Theme.failure }
        switch event.kind {
        case .approvalRequested, .approvalResolved: return Theme.attention
        case .steering: return .indigo
        case .completed: return Theme.success
        case .failed: return Theme.failure
        default: return .secondary
        }
    }

    private var iconBackground: Color {
        switch event.kind {
        case .completed: Theme.success.opacity(0.15)
        case .failed: Theme.failure.opacity(0.15)
        case .approvalRequested, .approvalResolved: Theme.attention.opacity(0.15)
        default: Color(uiColor: .tertiarySystemFill)
        }
    }
}
