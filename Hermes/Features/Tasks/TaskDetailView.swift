import SwiftUI

struct TaskDetailView: View {
    var taskID: String

    @Environment(TaskStore.self) private var tasks
    @Environment(ProfileStore.self) private var profiles
    @Environment(ActivityStore.self) private var activity
    @Environment(ConversationListStore.self) private var conversations
    @Environment(ConnectionStore.self) private var connection
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        Group {
            if let task = tasks.task(taskID) {
                content(task)
            } else {
                ContentUnavailableView("Task Not Found", systemImage: "questionmark.square.dashed")
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ task: HermesTask) -> some View {
        let live = connection.connection.isConnected && connection.canManageTasks && connection.supports(.kanban)
        let runs = activity.runs(forTask: task.id)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title).font(.title3.weight(.semibold))
                    HStack(spacing: 12) {
                        Label(task.status.label, systemImage: task.status.symbol)
                            .foregroundStyle(task.status.tint)
                            .fontWeight(.medium)
                        if task.priority != .normal {
                            Label("\(task.priority.label) priority", systemImage: task.priority == .high ? "arrow.up" : "arrow.down")
                                .foregroundStyle(.secondary)
                        }
                        if let duration = task.duration, let start = task.startedAt {
                            Label {
                                ElapsedText(start: start, end: task.completedAt ?? (task.status == .inProgress ? nil : start.addingTimeInterval(duration)))
                            } icon: {
                                Image(systemName: "timer")
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    Text(task.summary)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)

                NavigationLink(value: Route.profile(task.assigneeProfileID ?? Profile.defaultID)) {
                    HStack(spacing: 10) {
                        ProfileAvatar(profile: profiles.identity(task.assigneeProfileID), size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Assigned to").font(.caption).foregroundStyle(.secondary)
                            Text(profiles.name(task.assigneeProfileID))
                        }
                    }
                }
            }

            if task.status == .blocked || task.status == .failed, let reason = task.blockReason {
                Section {
                    FailureCallout(explanation: StatusCopy.Explanation(title: task.status == .blocked ? "Blocked" : "Failed",
                                                                       message: StatusCopy.sentence(reason) ?? reason,
                                                                       code: StatusCopy.isRawCode(reason) ? reason : nil),
                                   symbol: task.status == .blocked ? "exclamationmark.octagon.fill" : "xmark.octagon.fill",
                                   tint: task.status == .blocked ? Theme.attention : Theme.failure)
                        .padding(.vertical, 4)
                    Button("Queue for Hermes", systemImage: "arrow.clockwise") {
                        toasts.perform(success: "Queued for Hermes dispatcher") { try await tasks.start(task.id) }
                    }
                    .disabled(!live)
                }
            }

            Section {
                if task.status == .ready {
                    Button("Queue for Hermes", systemImage: "play.fill") {
                        toasts.perform(success: "Queued for Hermes dispatcher") { try await tasks.start(task.id) }
                    }
                    .disabled(!live)
                }
                Menu {
                    ForEach(task.availableTransitions) { status in
                        Button(status.label, systemImage: status.symbol) {
                            toasts.perform(success: "Moved to \(status.label)") { try await tasks.setStatus(status, for: task.id) }
                        }
                    }
                } label: {
                    Label("Move To…", systemImage: "arrow.right.square")
                }
                .disabled(!live)
            }

            if !task.dependencyIDs.isEmpty {
                Section {
                    ForEach(task.dependencyIDs, id: \.self) { id in
                        if let dependency = tasks.task(id) {
                            NavigationLink(value: Route.task(id)) {
                                HStack {
                                    Image(systemName: dependency.status.symbol).foregroundStyle(dependency.status.tint)
                                    Text(dependency.title)
                                    Spacer()
                                    Text(dependency.status.label).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    SectionHeader("Depends On")
                }
            }

            if !runs.isEmpty {
                Section {
                    ForEach(runs) { run in
                        NavigationLink(value: Route.run(run.id)) {
                            if run.state.isActive { RunRow(run: run) } else { RecentRunRow(run: run) }
                        }
                    }
                } header: {
                    SectionHeader("Runs")
                }
            }

            Section {
                ForEach(task.activity.sorted { $0.date > $1.date }) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text)
                            Text([item.profileID.map { profiles.name($0) }, Format.relative(item.date)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SectionHeader("Activity")
            }

            Section {
                if let conversation = conversations.conversation(task.conversationID) {
                    NavigationLink(value: Route.conversation(conversation.id)) {
                        LabeledContent("Conversation", value: conversation.title)
                    }
                }
                if let project = task.project {
                    KeyValueRow(label: "Project", value: project.name)
                }
                KeyValueRow(label: "Created", value: Format.timestamp(task.createdAt))
                KeyValueRow(label: "Updated", value: Format.timestamp(task.updatedAt))
                if let completed = task.completedAt {
                    KeyValueRow(label: "Finished", value: Format.timestamp(completed))
                }
                KeyValueRow(label: "Task ID", value: task.id, monospaced: true)
            } header: {
                SectionHeader("Details")
            }
        }
        .refreshable { await tasks.refresh() }
    }
}

struct NewTaskSheet: View {
    var assigneeProfileID: String?

    @Environment(TaskStore.self) private var tasks
    @Environment(ProfileStore.self) private var profiles
    @Environment(ConnectionStore.self) private var connection
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TaskDraft()
    @State private var startImmediately = true
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                    TextField("What should be done?", text: $draft.summary, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Picker("Assignee", selection: $draft.assigneeProfileID) {
                        Text("Unassigned").tag(String?.none)
                        ForEach(profiles.sorted) { profile in
                            Text(profile.name).tag(String?.some(profile.id))
                        }
                    }
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Project", selection: $draft.project) {
                        Text("None").tag(ProjectContext?.none)
                        ForEach(connection.runOptions.projects) { project in
                            Text(project.name).tag(ProjectContext?.some(project))
                        }
                    }
                }
                Section {
                    Toggle("Queue for dispatch", isOn: $startImmediately)
                        .disabled(draft.assigneeProfileID == nil)
                }
            }
            .navigationTitle("New Task")
            .accentSwitches()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear { draft.assigneeProfileID = assigneeProfileID }
        }
    }

    private func create() {
        saving = true
        Task {
            do {
                let task = try await tasks.create(draft)
                if startImmediately && draft.assigneeProfileID != nil { try await tasks.start(task.id) }
                toasts.show("Task created")
                dismiss()
            } catch {
                toasts.show(error: error)
            }
            saving = false
        }
    }
}
