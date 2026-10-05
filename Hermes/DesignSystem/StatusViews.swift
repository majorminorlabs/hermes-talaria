import SwiftUI

/// Small state dot. `pulsing` marks live activity without demanding
/// attention: like Hermes Desktop, it rings briefly every few seconds and
/// leaves the render loop idle in between. Static under Reduce Motion.
struct StatusDot: View {
    var color: Color
    var pulsing = false
    var size: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringing = false

    var body: some View {
        let animates = pulsing && !reduceMotion
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                if animates {
                    Circle()
                        .fill(color)
                        .scaleEffect(ringing ? 2.6 : 1)
                        .opacity(ringing ? 0 : 0.45)
                }
            }
            .task(id: animates) {
                guard animates else { return }
                while !Task.isCancelled {
                    var reset = Transaction()
                    reset.disablesAnimations = true
                    withTransaction(reset) { ringing = false }
                    try? await Task.sleep(for: .milliseconds(60))
                    withAnimation(.easeOut(duration: 1.1)) { ringing = true }
                    try? await Task.sleep(for: .seconds(3.6))
                }
            }
            .accessibilityHidden(true)
    }
}

/// Run state as compact text. Attention and failure states get a tinted tag
/// so they stand out in dense lists; everything else stays quiet.
struct RunStateLabel: View {
    var state: RunState
    var short = false

    var body: some View {
        let text = short ? state.shortLabel : state.label
        if state.needsUser {
            Tag(text, tone: .attention, symbol: state.symbol)
        } else if state == .failed {
            Tag(text, tone: .failure, symbol: state.symbol)
        } else {
            HStack(spacing: 5) {
                if state.isActive {
                    StatusDot(color: state.tint, pulsing: state == .running || state == .steeringPending, size: 6)
                } else {
                    Image(systemName: state.symbol).imageScale(.small).foregroundStyle(state.tint)
                }
                Text(text)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(state.isActive ? state.tint : .secondary)
        }
    }
}

/// Connection status for headers and rows. Never color alone: always a word.
struct ConnectionLabel: View {
    var state: ConnectionState
    var host: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if state.isTransitioning {
                ProgressView().controlSize(.mini)
            } else {
                StatusDot(color: state.tint, pulsing: false, size: 7)
            }
            Text(state.label(host: host))
                .lineLimit(1)
        }
        .font(.subheadline)
        .foregroundStyle(state.isConnected ? .secondary : state.tint)
        .contentTransition(.opacity)
        .animation(.default, value: state)
        .accessibilityElement(children: .combine)
    }
}

/// Ticking elapsed time for active work; static once ended.
struct ElapsedText: View {
    var start: Date
    var end: Date?

    var body: some View {
        if let end {
            Text(Format.elapsed(end.timeIntervalSince(start)))
                .monospacedDigit()
        } else {
            TimelineView(.periodic(from: start, by: 1)) { context in
                Text(Format.elapsed(context.date.timeIntervalSince(start)))
                    .monospacedDigit()
            }
        }
    }
}

/// "4m ago" that stays fresh.
struct RelativeTimeText: View {
    var date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(Format.relative(date, now: context.date))
        }
    }
}

/// Muted chip for project/working-directory context.
struct ProjectChip: View {
    var project: ProjectContext

    var body: some View {
        Label(project.name, systemImage: "folder")
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }
}

/// Generic status pill (MCP, integrations, tools).
struct StatusPill: View {
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            StatusDot(color: color, size: 6)
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }
}
