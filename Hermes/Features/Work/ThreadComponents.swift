import SwiftUI
struct RunCard: View {
    var run: Run
    var onSteer: () -> Void
    @Environment(AppEnvironment.self) private var environment
    @State private var expanded = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var steps = false
    @State private var risk: RiskAction?
    var body: some View {
        let state = run.displayState(isLive: environment.connection.connection.isConnected)
        VStack(alignment: .leading, spacing: 8) {
            HStack { ProfileAvatar(profile: environment.profiles.identity(run.profileID), size: 28); Text(environment.profiles.name(run.profileID)); Spacer(); ElapsedText(start: run.startedAt, end: run.endedAt ?? (environment.connection.connection.isConnected ? nil : environment.connection.status.lastSeen)) }
            Text(state == .disconnected ? "Last known: \(run.currentAction ?? "working")" : run.currentAction ?? state.label).font(.subheadline).foregroundStyle(state.tint)
            HStack {
                Button("\(run.steps.count) steps") { expanded.toggle() }
                Button("Steps") { steps = true }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("steps-button")
            }.font(.footnote).frame(minHeight: 44)
            if expanded { LiveSteps(steps: run.steps, maxFinished: 6) }
            if state == .stopping { Text("Hermes finishes its current step first.").font(.footnote).foregroundStyle(Theme.secondaryText) }
            if state == .disconnected { Text("Talaria will catch up when it reconnects.").font(.footnote).foregroundStyle(Theme.secondaryText) }
            if run.toolEvents.contains(where: { $0.toolKind == .delegate }) { HandoffMarker(events: run.toolEvents.filter { $0.toolKind == .delegate }) }
        }.padding(.leading, 12)
            .overlay(alignment: .leading) { Rectangle().fill(.tint.opacity(0.4)).frame(width: 2) }
            .sheet(isPresented: $steps) { StepsSheet(runID: run.id) }
            .sheet(item: $risk) { RiskConfirmSheet(action: $0) }
            .contextMenu {
                Button("Steps") { steps = true }
                if run.canSteer { Button("Add instruction", action: onSteer).disabled(!environment.connection.connection.isConnected) }
                if run.canStop { Button("Stop", role: .destructive) { risk = RiskAction(verb: "Stop", effect: "Stops all of this work. Work already done stays.", target: run.title) { try await environment.activity.stop(run.id) } }.disabled(!environment.connection.connection.isConnected) }
            }
    }
}
struct HandoffMarker: View {
    var events: [RunEvent]
    var body: some View {
        DisclosureGroup("Hermes started \(events.count) subagent\(events.count == 1 ? "" : "s")") {
            ForEach(events) { StepLine(step: $0) }
            if events.contains(where: { $0.status == .active || $0.status == .pending }) { Label("Not tracked from iPhone", systemImage: "eye.slash").font(.caption).foregroundStyle(Theme.secondaryText) }
        }.font(.caption).foregroundStyle(Theme.secondaryText)
    }
}
struct WorkStatusBar: View {
    var run: Run
    var steer: () -> Void
    var steps: () -> Void
    @Environment(AppEnvironment.self) private var environment
    @State private var risk: RiskAction?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Label(run.displayState(isLive: environment.connection.connection.isConnected).label, systemImage: run.displayState(isLive: environment.connection.connection.isConnected).symbol); Spacer(); ElapsedText(start: run.startedAt, end: run.endedAt ?? (environment.connection.connection.isConnected ? nil : environment.connection.status.lastSeen)) }
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())) {
                Button("Add instruction", action: steer).disabled(!run.canSteer || !environment.connection.connection.isConnected)
                Button("Stop", role: .destructive) { risk = RiskAction(verb: "Stop", effect: "Stops all of this work. Work already done stays.", target: run.title) { try await environment.activity.stop(run.id) } }.accessibilityIdentifier("work-status-stop").disabled(!run.canStop || !environment.connection.connection.isConnected)
                Spacer()
                Button("Steps", action: steps).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("steps-button")
            }.font(.subheadline).frame(minHeight: 44)
        }.padding(12).background(.bar)
            .sheet(item: $risk) { RiskConfirmSheet(action: $0) }
    }
}
struct ResultFooter: View {
    var run: Run
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var steps = false
    @State private var summary = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if run.state == .unknown { Text("Outcome unknown. Talaria didn't see this finish. Check on your Mac before asking again.").font(.footnote).foregroundStyle(Theme.secondaryText) }
            if run.state == .cancelled { Text("Partial: stopped before finishing").font(.footnote).foregroundStyle(Theme.secondaryText) }
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())) {
                Label(run.state.label, systemImage: run.state.symbol)
                Text(environment.profiles.name(run.profileID))
                Text(Format.elapsed(run.elapsed()))
                Button("Steps") { steps = true }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("steps-button")
                Button("Details", systemImage: "info.circle") { summary = true }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }.font(.caption).foregroundStyle(Theme.secondaryText)
        }.sheet(isPresented: $steps) { StepsSheet(runID: run.id) }
            .sheet(isPresented: $summary) { RunSummarySheet(run: run) }
    }
}
