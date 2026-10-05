import SwiftUI

/// Multi-agent tasks on iPhone: pick a state, see its tasks. A paged board
/// is available for an overview, but the filtered list is primary.
struct KanbanView: View {
    @Environment(TaskStore.self) private var tasks
    @State private var column: TaskStatus = .inProgress
    @AppStorage("kanban.board") private var showsBoard = false

    var body: some View {
        CapabilityGate(capability: .kanban) {
            LoadableContent(phase: tasks.phase, isEmpty: tasks.tasks.isEmpty, hasData: !tasks.tasks.isEmpty,
                            retry: { await tasks.refresh() }) {
                VStack(spacing: 0) {
                    controls
                    if showsBoard { board } else { list }
                }
            } empty: {
                ContentUnavailableView("No Tasks", systemImage: "rectangle.split.3x1",
                                       description: Text("Durable work Hermes is tracking across profiles shows up here."))
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TaskStatus.board) { status in
                        StatusChip(status: status, count: tasks.tasks(in: status).count,
                                   isSelected: !showsBoard && column == status) {
                            withAnimation(.snappy) {
                                column = status
                                showsBoard = false
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            Button {
                withAnimation(.snappy) { showsBoard.toggle() }
            } label: {
                Image(systemName: showsBoard ? "list.bullet" : "rectangle.split.3x1")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(showsBoard ? "Show list" : "Show board")
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var list: some View {
        let items = tasks.tasks(in: column)
        return List {
            if items.isEmpty {
                Text("No \(column.label.lowercased()) tasks.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { task in
                NavigationLink(value: Route.task(task.id)) {
                    TaskRow(task: task)
                }
            }
        }
        .refreshable { await tasks.refresh() }
    }

    private var board: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(TaskStatus.board) { status in
                    BoardColumn(status: status, tasks: tasks.tasks(in: status))
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.86 }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct StatusChip: View {
    var status: TaskStatus
    var count: Int
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(status.label)
                Text("\(count)")
                    .foregroundStyle(isSelected ? tint.opacity(0.8) : .secondary)
                    .monospacedDigit()
            }
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? tint : .primary)
            .background(isSelected ? tint.opacity(0.14) : Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tint: Color { status == .blocked ? Theme.attention : .accentColor }
}

private struct BoardColumn: View {
    var status: TaskStatus
    var tasks: [HermesTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: status.symbol).foregroundStyle(status.tint)
                Text(status.label).font(.headline)
                Text("\(tasks.count)").foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            ScrollView {
                VStack(spacing: 8) {
                    if tasks.isEmpty {
                        Text("Empty")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    ForEach(tasks) { task in
                        NavigationLink(value: Route.task(task.id)) {
                            TaskRow(task: task)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.groupedRow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(.top, 8)
    }
}

/// A task: priority, title, who's on it, its state when it isn't implied
/// by the list it's in, how long it's run, and why it's stuck.
struct TaskRow: View {
    var task: HermesTask

    @Environment(ProfileStore.self) private var profiles
    @Environment(TaskStore.self) private var tasks

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if task.priority == .high {
                    Image(systemName: "arrow.up").font(.caption.weight(.bold)).foregroundStyle(Theme.attention)
                        .accessibilityLabel("High priority")
                }
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                duration
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if task.assigneeProfileID == nil {
                    Image(systemName: "person.crop.circle.dashed")
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                    Text("Unassigned")
                } else {
                    ProfileAvatar(profile: profiles.identity(task.assigneeProfileID), size: 18)
                    Text(profiles.name(task.assigneeProfileID))
                        .lineLimit(1)
                }
                if task.status != task.status.boardColumn || task.status == .completed || task.status == .blocked || task.status == .failed {
                    Tag(task.status.label, tone: tone, symbol: task.status.symbol)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            if task.status == .blocked, let reason = task.blockReason {
                Text(StatusCopy.sentence(reason) ?? reason)
                    .font(.footnote)
                    .foregroundStyle(Theme.attention)
                    .lineLimit(2)
            } else if let waiting = unmetDependency {
                Label("Waits on \(waiting.title)", systemImage: "arrow.triangle.branch")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let latest = task.latestActivity {
                Text(latest.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var duration: some View {
        if task.status == .inProgress, let start = task.startedAt {
            ElapsedText(start: start, end: nil)
        } else if let start = task.startedAt, let end = task.completedAt {
            Text(Format.elapsed(end.timeIntervalSince(start)))
        }
    }

    private var tone: Tag.Tone {
        switch task.status {
        case .blocked, .review: .attention
        case .failed: .failure
        case .completed: .success
        case .inProgress: .accent
        default: .muted
        }
    }

    private var unmetDependency: HermesTask? {
        task.dependencyIDs.compactMap { tasks.task($0) }.first { $0.status != .completed }
    }
}

#Preview {
    NavigationStack { KanbanView().routeDestinations() }
        .previewEnvironment()
}
