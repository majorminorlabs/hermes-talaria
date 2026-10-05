import SwiftUI

/// Hermes routines (cron jobs).
struct ScheduledView: View {
    @Environment(RoutineStore.self) private var routines
    @Environment(ToastCenter.self) private var toasts
    @Environment(ConnectionStore.self) private var connection
    @State private var deleting: Routine?

    var body: some View {
        CapabilityGate(capability: .cron) {
            LoadableContent(phase: routines.phase, isEmpty: routines.routines.isEmpty, hasData: !routines.routines.isEmpty,
                            retry: { await routines.refresh() }) {
                List {
                    ForEach(routines.sorted) { routine in
                        NavigationLink(value: Route.routine(routine.id)) {
                            RoutineRow(routine: routine)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Run Now", systemImage: "play.fill") { runNow(routine) }
                                .tint(.accentColor)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = routine }
                            Button(routine.isEnabled ? "Pause" : "Resume", systemImage: routine.isEnabled ? "pause.fill" : "play") {
                                toggle(routine)
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button("Run Now", systemImage: "play.fill") { runNow(routine) }
                            Button(routine.isEnabled ? "Pause" : "Resume", systemImage: routine.isEnabled ? "pause" : "play") { toggle(routine) }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = routine }
                        }
                    }
                }
                .refreshable { await routines.refresh() }
            } empty: {
                ContentUnavailableView("No Routines", systemImage: "calendar.badge.clock",
                                       description: Text("Ask Hermes to schedule something — for example, “every weekday at 7, send me a morning report”."))
            }
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Routine", role: .destructive) {
                guard let routine = deleting else { return }
                toasts.perform(success: "Routine deleted") { try await routines.delete(routine.id) }
            }
        } message: {
            Text("The schedule is removed from Hermes on your Mac. Past runs stay in history.")
        }
    }

    private func runNow(_ routine: Routine) {
        toasts.perform(success: "Due time updated · Hermes scheduler required") { try await routines.runNow(routine.id) }
    }

    private func toggle(_ routine: Routine) {
        toasts.perform(success: routine.isEnabled ? "Paused" : "Resumed") {
            try await routines.setEnabled(!routine.isEnabled, for: routine.id)
        }
    }
}

struct RoutineRow: View {
    var routine: Routine

    @Environment(ProfileStore.self) private var profiles

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: routine.isEnabled ? "calendar.badge.clock" : "pause.circle")
                .font(.title3)
                .foregroundStyle(routine.isEnabled ? Color.accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(routine.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(routine.isEnabled ? .primary : .secondary)
                    if !routine.isEnabled { Tag("Paused") }
                }
                Text("\(routine.schedule.summary) · \(profiles.name(routine.profileID))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                statusLine
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusLine: Text {
        var parts: [Text] = []
        if routine.isEnabled, let next = routine.nextRunAt {
            parts.append(Text("Next \(Format.future(next))").foregroundStyle(.secondary))
        }
        if let result = routine.lastResult {
            let text = result.outcome == .failed ? "Last run failed \(Format.relative(result.date))" : "Last ran \(Format.relative(result.date))"
            parts.append(Text(text).foregroundStyle(result.outcome == .failed ? Theme.failure : .secondary))
        }
        return parts.enumerated().reduce(Text("")) { result, item in
            item.offset == 0 ? item.element : result + Text(" · ").foregroundStyle(.secondary) + item.element
        }
    }
}

/// Full routine view with controls.
struct RoutineDetailView: View {
    var routineID: String

    @Environment(RoutineStore.self) private var routines
    @Environment(ProfileStore.self) private var profiles
    @Environment(ActivityStore.self) private var activity
    @Environment(ConnectionStore.self) private var connection
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if let routine = routines.routine(routineID) {
                content(routine)
            } else {
                ContentUnavailableView("Routine Not Found", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle("Routine")
        .accentSwitches()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ routine: Routine) -> some View {
        let live = connection.connection.isConnected
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(routine.name).font(.title3.weight(.semibold))
                    Label(routine.schedule.summary, systemImage: "calendar")
                        .foregroundStyle(.secondary)
                    if routine.isEnabled, let next = routine.nextRunAt {
                        Text("Next run \(Format.future(next))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Toggle("Enabled", isOn: Binding(
                    get: { routine.isEnabled },
                    set: { enabled in toasts.perform { try await routines.setEnabled(enabled, for: routine.id) } }))
                    .disabled(!live)

                Button {
                    toasts.perform(success: "Due time updated · Hermes scheduler required") { try await routines.runNow(routine.id) }
                } label: {
                    Label("Run Now", systemImage: "play.fill")
                }
                .disabled(!live)
            }

            Section {
                Text(routine.prompt).textSelection(.enabled)
            } header: {
                SectionHeader("Prompt")
            }

            Section {
                NavigationLink(value: Route.profile(routine.profileID ?? Profile.defaultID)) {
                    LabeledContent("Profile", value: profiles.name(routine.profileID))
                }
                KeyValueRow(label: "Schedule", value: routine.schedule.expression, monospaced: true)
                if let delivery = routine.delivery {
                    KeyValueRow(label: "Delivers to", value: delivery)
                }
            } header: {
                SectionHeader("Configuration")
            }

            if let result = routine.lastResult {
                Section {
                    if let runID = result.runID {
                        NavigationLink(value: Route.run(runID)) { resultRow(result) }
                    } else {
                        resultRow(result)
                    }
                } header: {
                    SectionHeader("Last Result")
                }
            }

            let runs = activity.runs(forRoutine: routine.id)
            if !runs.isEmpty {
                Section {
                    ForEach(runs.prefix(6)) { run in
                        NavigationLink(value: Route.run(run.id)) {
                            if run.state.isActive { RunRow(run: run) } else { RecentRunRow(run: run) }
                        }
                    }
                } header: {
                    SectionHeader("Recent Runs")
                }
            }

            Section {
                Button("Edit Routine", systemImage: "pencil") { editing = true }
                    .disabled(!live)
                Button("Delete Routine", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .disabled(!live)
            }
        }
        .sheet(isPresented: $editing) { RoutineEditView(routine: routine) }
        .confirmationDialog("Delete “\(routine.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Routine", role: .destructive) {
                toasts.perform(success: "Routine deleted") {
                    try await routines.delete(routine.id)
                    dismiss()
                }
            }
        }
    }

    private func resultRow(_ result: RoutineResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.outcome.symbol).foregroundStyle(result.outcome.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(result.outcome.label) · \(Format.relative(result.date))")
                if let summary = result.summary {
                    Text(summary).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct RoutineEditView: View {
    var routine: Routine

    @Environment(RoutineStore.self) private var routines
    @Environment(ProfileStore.self) private var profiles
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RoutineDraft
    @State private var saving = false

    init(routine: Routine) {
        self.routine = routine
        _draft = State(initialValue: RoutineDraft(routine))
    }

    private let presets: [(String, String)] = [
        ("Every hour", "0 * * * *"), ("Every day at 7:00 AM", "0 7 * * *"),
        ("Weekdays at 9:00 AM", "0 9 * * 1-5"), ("Sundays at 6:00 PM", "0 18 * * 0"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                } header: {
                    SectionHeader("Name")
                }
                Section {
                    TextEditor(text: $draft.prompt)
                        .frame(minHeight: 120)
                } header: {
                    SectionHeader("Prompt")
                }
                Section {
                    TextField("Cron expression", text: $draft.scheduleExpression)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Menu("Presets") {
                        ForEach(presets, id: \.1) { label, expression in
                            Button(label) { draft.scheduleExpression = expression }
                        }
                    }
                } header: {
                    SectionHeader("Schedule")
                } footer: {
                    Text("Uses the host's cron syntax. Hermes validates it when saving.")
                }
                Section {
                    Picker("Profile", selection: $draft.profileID) {
                        ForEach(profiles.sorted) { profile in
                            Text(profile.name).tag(String?.some(profile.id))
                        }
                    }
                    TextField("Delivery (optional)", text: Binding(
                        get: { draft.delivery ?? "" }, set: { draft.delivery = $0.isEmpty ? nil : $0 }))
                } header: {
                    SectionHeader("Run As")
                }
            }
            .navigationTitle("Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            do {
                                try await routines.update(routine.id, draft: draft)
                                toasts.show("Routine saved")
                                dismiss()
                            } catch {
                                toasts.show(error: error)
                            }
                            saving = false
                        }
                    }
                    .disabled(draft.name.isEmpty || draft.scheduleExpression.isEmpty || saving)
                }
            }
        }
    }
}
