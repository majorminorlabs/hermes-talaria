import SwiftUI

/// An active run in a list: who, what, what it's doing now, how long.
struct RunRow: View {
    var run: Run

    @Environment(ProfileStore.self) private var profiles
    @Environment(ConnectionStore.self) private var connection

    var body: some View {
        let state = run.displayState(isLive: connection.connection.isConnected)
        HStack(alignment: .top, spacing: 12) {
            ProfileAvatar(profile: profiles.identity(run.profileID), size: 34)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(byline)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    ElapsedText(start: run.startedAt, end: run.endedAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(run.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    CurrentActionLabel(run: run, state: state)
                    if state == .disconnected || state == .stopping {
                        Spacer(minLength: 4)
                        RunStateLabel(state: state, short: true)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// The bot, plus the host only when there's more than one to tell apart.
    private var byline: String {
        let name = profiles.name(run.profileID)
        guard connection.hosts.count > 1, let host = connection.hosts.first(where: { $0.id == run.hostID })?.name else { return name }
        return "\(name) · \(host)"
    }
}

/// "● Running Python analysis" / "✋ Waiting for approval".
struct CurrentActionLabel: View {
    var run: Run
    var state: RunState

    var body: some View {
        HStack(spacing: 6) {
            switch state {
            case .running, .steeringPending, .queued:
                StatusDot(color: state.tint, pulsing: state == .running, size: 6)
            case .disconnected:
                Image(systemName: "wifi.slash").imageScale(.small)
            default:
                Image(systemName: state.symbol).imageScale(.small)
            }
            Text(text)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .font(.subheadline)
        .foregroundStyle(state.needsUser ? state.tint : .secondary)
        .animation(.default, value: run.currentAction)
    }

    private var text: String {
        switch state {
        case .waitingForApproval: "Waiting for approval"
        case .waitingForInput: "Waiting for your reply"
        case .steeringPending: "Delivering instruction…"
        case .stopping: "Stopping…"
        case .disconnected: "Last known: \(run.currentAction ?? "running")"
        default: run.currentAction ?? run.activeStep?.title ?? "Working"
        }
    }
}

/// A finished run: outcome, title, who, and a plain-language result.
struct RecentRunRow: View {
    var run: Run

    @Environment(ProfileStore.self) private var profiles

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let outcome = RunOutcome(run.state) {
                Image(systemName: outcome.symbol)
                    .foregroundStyle(outcome.tint)
                    .imageScale(.medium)
                    .frame(width: 22)
                    .accessibilityLabel(outcome.label)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(run.title)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if let end = run.endedAt {
                        RelativeTimeText(date: end)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [profiles.name(run.profileID)]
        if run.trigger == .routine { parts.append("Routine") }
        switch run.state {
        case .failed, .cancelled:
            let copy = StatusCopy.runFailure(run.failureReason, cancelled: run.state == .cancelled)
            parts.append(copy.message ?? copy.title)
        default:
            if let summary = run.resultSummary { parts.append(summary) }
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        List {
            Section("Active") {
                ForEach(MockFixtures.standard().runs.filter(\.state.isActive)) { RunRow(run: $0) }
            }
            Section("Recent") {
                ForEach(MockFixtures.standard().runs.filter(\.state.isTerminal).prefix(4)) { RecentRunRow(run: $0) }
            }
        }
    }
    .previewEnvironment()
}
