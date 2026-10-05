import SwiftUI

/// Top of Home: which host, whether it's live, and one line saying what
/// Hermes is doing. Degraded states explain themselves and offer recovery.
struct HomeStatusHeader: View {
    var updatedAt: Date?
    var summary: HomeSummary?
    var attentionCount: Int

    @Environment(ConnectionStore.self) private var connection
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var pairing = false

    var body: some View {
        let state = connection.connection
        VStack(alignment: .leading, spacing: 8) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                if !connection.hosts.isEmpty { hostMenu(state) }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                if connection.activeHost != nil {
                    ConnectionLabel(state: state, host: connection.activeHost?.name)
                }
            }

            if state.isConnected, let summary {
                statusLine(summary)
            }

            if state.isDegraded && connection.activeHost != nil {
                degraded(state)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.default, value: state)
        .sheet(isPresented: $pairing) { HostEditorView(host: connection.activeHost) }
    }

    private func hostMenu(_ state: ConnectionState) -> some View {
        Menu {
            Picker("Host", selection: Binding(
                get: { connection.activeHostID },
                set: { id in Task { await connection.switchHost(to: id) } })) {
                ForEach(connection.hosts) { host in
                    Label(host.name, systemImage: host.symbol).tag(host.id)
                }
            }
            Divider()
            if state.isDegraded {
                Button("Reconnect", systemImage: "arrow.clockwise") { Task { await connection.reconnect() } }
            }
        } label: {
            HStack(spacing: 4) {
                Text(connection.activeHost?.name ?? "No Host")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Host: \(connection.activeHost?.name ?? "none"). Switch host")
    }

    /// "2 running · 1 needs you · next routine in 47m". One Text so it wraps
    /// at large type sizes instead of compressing.
    private func statusLine(_ summary: HomeSummary) -> some View {
        let running = summary.activeRuns.count
        let next = summary.upcoming.compactMap(\.nextRunAt).filter { $0 > .now }.min()
        return TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if running > 0 {
                    StatusDot(color: Theme.running, pulsing: true, size: 6)
                }
                statusText(running: running, next: next, now: context.date)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statusText(running: Int, next: Date?, now: Date) -> Text {
        var text = running > 0 ? Text("\(running) running").foregroundStyle(Theme.running) : Text("Hermes is idle")
        if attentionCount > 0 {
            text = text + Text(" · ") + Text("\(attentionCount) need\(attentionCount == 1 ? "s" : "") you").foregroundStyle(Theme.attention)
        }
        if let next {
            let when = Format.future(next, now: now)
            text = text + Text(" · next routine \(when == "now" ? "due now" : when)")
        }
        return text
    }

    private func degraded(_ state: ConnectionState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let updatedAt {
                    Text("Last-known state · \(Format.updated(updatedAt))")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !state.isTransitioning {
                    Button(state == .authenticationRequired ? "Pair Again" : "Reconnect") {
                        if state == .authenticationRequired { pairing = true }
                        else { Task { await connection.reconnect() } }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

/// First run, before any Mac is paired: the one place Home shows the brand.
struct UnpairedWelcome: View {
    @State private var adding = false

    var body: some View {
        VStack(spacing: 14) {
            TalariaMark(size: 72)
            VStack(spacing: 6) {
                Text("Pair with your Mac")
                    .font(.title3.weight(.semibold))
                Text("Talaria connects to Hermes running on your Mac Studio over your tailnet. Add the bridge address and pairing token to begin.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Add Host") { adding = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .sheet(isPresented: $adding) { HostEditorView(host: nil) }
    }
}

/// A row in Needs Attention: what, why (in words), when. Actionable
/// approvals get swipe actions. No tinted row wash: the glyph carries state.
struct AttentionRow: View {
    var item: AttentionItem

    @Environment(ActivityStore.self) private var activity
    @Environment(ConnectionStore.self) private var connection
    @Environment(AppPreferences.self) private var preferences
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationLink(value: destination) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.kind.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(item.kind.tint)
                    .frame(width: 28, height: 28)
                    .background(item.kind.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.title)
                            .font(.body.weight(.semibold))
                            .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                        if !typeSize.isAccessibilitySize {
                            Spacer(minLength: 4)
                            RelativeTimeText(date: item.date)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    detail
                    if typeSize.isAccessibilitySize {
                        RelativeTimeText(date: item.date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let note = approvalNote {
                        Text(note)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let approval, isActionable(approval) {
                Button("Approve", systemImage: "checkmark") {
                    toasts.perform(success: "Approved") { try await activity.resolve(approval.id, decision: .approveOnce) }
                }
                .tint(Theme.success)
                Button("Deny", systemImage: "xmark") {
                    toasts.perform(success: "Denied") { try await activity.resolve(approval.id, decision: .deny) }
                }
                .tint(Theme.failure)
            }
            if item.kind == .failedRun, let runID = item.runID {
                Button("Dismiss", systemImage: "eye.slash") { preferences.acknowledge(runID: runID) }
                    .tint(.gray)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if item.kind == .approval, let approval, !approval.isClarification, !approval.payload.isEmpty {
            Text(approval.payload)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if let text = detailText {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    /// Kind-prefixed, plain-language detail ("Blocked · FLY_API_TOKEN is missing").
    private var detailText: String? {
        let sentence = StatusCopy.sentence(item.detail)
        switch item.kind {
        case .failedRun:
            return "Failed · " + (sentence ?? "Hermes could not complete this run.")
        case .blockedTask:
            return sentence.map { "Blocked · \($0)" } ?? "Blocked"
        default:
            return sentence
        }
    }

    private var approval: ApprovalRequest? { activity.approval(item.approvalID) }

    private func isActionable(_ approval: ApprovalRequest) -> Bool {
        connection.connection.isConnected && !approval.isClarification
            && approval.effectiveAvailability(remoteApprovalsSupported: connection.supports(.approvals)).isActionable
    }

    private var approvalNote: String? {
        guard let approval else { return nil }
        let availability = approval.effectiveAvailability(remoteApprovalsSupported: connection.supports(.approvals))
        switch availability {
        case .actionable: return nil
        case .expired: return "Expired"
        case .unavailableRemotely, .ambiguous: return "Resolve on your Mac"
        }
    }

    private var destination: Route {
        switch item.kind {
        case .approval:
            if let approval, !isActionable(approval) { return .approval(approval.id) }
            return item.runID.map(Route.run) ?? .approval(item.approvalID ?? "")
        case .failedRun: return .run(item.runID ?? "")
        case .blockedTask: return .task(item.taskID ?? "")
        case .hostIssue, .authentication: return .hosts
        }
    }
}

/// A scheduled routine with its next run time.
struct UpcomingRow: View {
    var routine: Routine

    @Environment(ProfileStore.self) private var profiles

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: routine.isEnabled ? "calendar.badge.clock" : "pause.circle")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .lineLimit(2)
                Text(profiles.name(routine.profileID))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let next = routine.nextRunAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Format.future(next, now: context.date))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Compact host summary: Hermes, model, link and load, in metadata type.
struct HostSummaryRows: View {
    var status: HostStatus

    @Environment(ConnectionStore.self) private var connection

    var body: some View {
        let host = connection.hosts.first { $0.id == status.hostID }
        NavigationLink(value: Route.host(status.hostID)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: host?.symbol ?? "desktopcomputer")
                        .foregroundStyle(.secondary)
                    Text(host?.name ?? "Host")
                        .font(.body.weight(.semibold))
                    Spacer()
                    StatusPill(text: status.connection.label(host: nil), color: status.connection.tint)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        metric("Hermes", hermesValue)
                        metric("Active runs", "\(status.activeRunCount)")
                    }
                    GridRow {
                        metric("Model", status.defaultModel?.displayName ?? "—")
                        metric("Latency", status.latencyMilliseconds.map { "\($0) ms" } ?? "—")
                    }
                    if let resources = status.resources {
                        GridRow {
                            metric("CPU", Format.percent(resources.cpuLoad))
                            metric("Memory", Format.percent(resources.memoryUsed))
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var hermesValue: String {
        guard status.hermesState == .running else { return status.hermesState.label }
        return status.hermesVersion.map { "Running · \(Format.version($0))" } ?? "Running"
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.3)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
