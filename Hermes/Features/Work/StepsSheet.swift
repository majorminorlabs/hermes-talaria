import SwiftUI
struct StepsSheet: View {
    var runID: String
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    var body: some View {
        NavigationStack {
            List {
                if let current = environment.activity.run(selected ?? runID) {
                    let runs = environment.activity.runs.values.filter { $0.conversationID == current.conversationID }.sorted { $0.startedAt < $1.startedAt }
                    if runs.count > 1 { Picker("Work turn", selection: Binding(get: { selected ?? runID }, set: { selected = $0 })) { ForEach(runs) { Text($0.startedAt.formatted(date: .omitted, time: .shortened)).tag($0.id) } } }
                    if current.state.isActive {
                        Section("Now") { Text(current.currentAction ?? current.displayState(isLive: environment.connection.connection.isConnected).label); LiveSteps(steps: current.steps, maxFinished: 6); if current.toolEvents.contains(where: { $0.toolKind == .delegate }) { HandoffMarker(events: current.toolEvents.filter { $0.toolKind == .delegate }) } }
                    } else { Section { Label(current.state.label, systemImage: current.state.symbol); if let summary = current.resultSummary { Text(summary) } } }
                    Section("Timeline") { RunTimeline(events: current.events) }
                    Section("Details") {
                        LabeledContent("Agent", value: environment.profiles.name(current.profileID))
                        LabeledContent("Model", value: current.model?.detailedLabel ?? "Not reported")
                        LabeledContent("Reasoning", value: current.reasoning?.label ?? "Set on your Mac")
                        LabeledContent("Project", value: current.project?.name ?? "None")
                        LabeledContent("Source", value: current.trigger.label)
                        if let usage = current.usage { LabeledContent("Tokens", value: "\(usage.input) in · \(usage.output) out") }
                        Text(current.id).font(.caption.monospaced()).textSelection(.enabled)
                    }
                } else { Text("Loading steps…") }
            }.navigationTitle("Steps").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium,.large])
            .task(id: selected ?? runID) { await environment.activity.loadRun(selected ?? runID) }
    }
}
struct RunThreadDestination: View {
    var runID: String
    @Environment(AppEnvironment.self) private var environment
    @State private var showing = true
    var body: some View {
        Group {
            if let id = environment.activity.run(runID)?.conversationID { ConversationView(model: environment.makeConversationModel(conversationID: id, profileID: nil)) }
            else { Text("Work has no thread. Check on your Mac.").foregroundStyle(Theme.secondaryText) }
        }.sheet(isPresented: $showing) { StepsSheet(runID: runID) }
            .task { await environment.activity.loadRun(runID) }
    }
}
