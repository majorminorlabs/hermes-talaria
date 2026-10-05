import SwiftUI

// MARK: - Memory

struct MemoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(ProfileStore.self) private var profiles
    @State private var entries = Resource<[MemoryEntry]>()
    @State private var query = ""
    @State private var scope: MemoryScope?

    var body: some View {
        CapabilityGate(capability: .memory) {
            List {
                Section {
                    Picker("Scope", selection: $scope) {
                        Text("All").tag(MemoryScope?.none)
                        ForEach(MemoryScope.allCases) { Text($0.label).tag(MemoryScope?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if let list = entries.value {
                    if list.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "No Memories" : "No Results", systemImage: "brain",
                                               description: Text(query.isEmpty ? "Hermes saves facts and preferences here as it works." : "Try a different search."))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(list) { entry in
                        NavigationLink(value: Route.memoryEntry(entry)) {
                            MemoryRow(entry: entry)
                        }
                    }
                } else if let error = entries.phase.error {
                    ErrorContentView(error: error) { await load() }.listRowBackground(Color.clear)
                } else {
                    LoadingRows(count: 5)
                }
            }
            .searchable(text: $query, prompt: "Search memory")
        }
        .navigationTitle("Memory")
        .task(id: "\(query)|\(scope?.rawValue ?? "")") {
            try? await Task.sleep(for: .milliseconds(query.isEmpty ? 0 : 250))
            await load()
        }
        .refreshable { await load() }
    }

    private func load() async {
        await entries.load { try await environment.client.memory.listMemory(scope: scope, query: query) }
    }
}

private struct MemoryRow: View {
    var entry: MemoryEntry
    @Environment(ProfileStore.self) private var profiles

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(InlineMarkdown.render(entry.content))
                .lineLimit(3)
            HStack(spacing: 6) {
                Label(entry.sourceTitle ?? entry.source.label, systemImage: entry.source.symbol)
                    .lineLimit(1)
                if owner != entry.sourceTitle {
                    Text("· \(owner)").lineLimit(1)
                }
                Spacer()
                Text(Format.relative(entry.updatedAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var owner: String {
        entry.scope == .user ? "User profile" : profiles.name(entry.profileID)
    }
}

struct MemoryDetailView: View {
    var entry: MemoryEntry

    @Environment(AppEnvironment.self) private var environment
    @Environment(ProfileStore.self) private var profiles
    @Environment(ConversationListStore.self) private var conversations
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section {
                Text(InlineMarkdown.render(entry.content))
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }
            Section {
                KeyValueRow(label: "Type", value: entry.scope.label)
                if entry.scope == .agent {
                    KeyValueRow(label: "Profile", value: profiles.name(entry.profileID))
                }
                if let conversation = conversations.conversation(entry.conversationID) {
                    NavigationLink(value: Route.conversation(conversation.id)) {
                        LabeledContent(entry.source.label, value: conversation.title)
                    }
                } else {
                    KeyValueRow(label: "From", value: entry.sourceTitle.map { "\(entry.source.label) · \($0)" } ?? entry.source.label)
                }
                KeyValueRow(label: "Saved", value: Format.timestamp(entry.createdAt))
                if entry.updatedAt != entry.createdAt {
                    KeyValueRow(label: "Updated", value: Format.timestamp(entry.updatedAt))
                }
            } header: {
                SectionHeader("Source")
            }
            if !entry.tags.isEmpty {
                Section {
                    Text(entry.tags.map { "#\($0)" }.joined(separator: "  "))
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                } header: {
                    SectionHeader("Tags")
                }
            }
            Section {
                Button("Forget This", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Forget this memory?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                toasts.perform(success: "Forgotten") {
                    try await environment.client.memory.deleteMemory(id: entry.id)
                    dismiss()
                }
            }
        } message: {
            Text("Hermes will no longer recall this. It's removed from memory on your Mac.")
        }
    }
}

// MARK: - Skills

struct SkillsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var skills = Resource<[Skill]>()
    @State private var query = ""
    @State private var filter: SkillFilter = .all

    enum SkillFilter: String, CaseIterable, Identifiable {
        case all, enabled, disabled
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        CapabilityGate(capability: .skills) {
            List {
                if let list = skills.value {
                    let filtered = list.filter(matches)
                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: query).listRowBackground(Color.clear)
                    }
                    ForEach(categories(filtered), id: \.0) { category, items in
                        Section {
                            ForEach(items) { skill in
                                NavigationLink(value: Route.skill(skill)) { SkillRow(skill: skill, showsCategory: false) }
                            }
                        } header: {
                            SectionHeader(title: category) {
                                Text("\(items.count)").monospacedDigit().foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else if let error = skills.phase.error {
                    ErrorContentView(error: error) { await load() }.listRowBackground(Color.clear)
                } else {
                    LoadingRows(count: 6)
                }
            }
            .searchable(text: $query, prompt: "Search skills")
        }
        .navigationTitle("Skills")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(SkillFilter.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter skills")
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await skills.load { try await environment.client.skills.listSkills() }
    }

    private func matches(_ skill: Skill) -> Bool {
        let filterMatch = switch filter {
        case .all: true
        case .enabled: skill.isEnabled
        case .disabled: !skill.isEnabled
        }
        return filterMatch && (query.isEmpty || skill.name.localizedCaseInsensitiveContains(query)
                               || skill.summary.localizedCaseInsensitiveContains(query))
    }

    private func categories(_ skills: [Skill]) -> [(String, [Skill])] {
        Dictionary(grouping: skills, by: \.category)
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.0 < $1.0 }
    }
}

/// A skill as Hermes Desktop lists it: name, category, origin tag
/// (`learned` when Hermes wrote it, `hub` when installed from the Skills Hub)
/// and how often it's been used.
struct SkillRow: View {
    var skill: Skill
    /// Off where rows are already grouped under their category.
    var showsCategory = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .foregroundStyle(skill.isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                    if let tag = skill.origin.tag { Tag(tag.0, tone: tag.1) }
                }
                if !skill.summary.isEmpty {
                    Text(skill.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if showsCategory {
                    Text(skill.category)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 6)
            if !skill.isEnabled {
                Text("Off").font(.caption.weight(.medium)).foregroundStyle(.tertiary)
            } else if skill.usageCount > 0 {
                Text("×\(skill.usageCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .accessibilityLabel("Used \(skill.usageCount) times")
            }
        }
        .padding(.vertical, 1)
    }
}

extension SkillOrigin {
    /// Desktop's origin badges; bundled skills carry none.
    var tag: (String, Tag.Tone)? {
        switch self {
        case .agentCreated: ("learned", .accent)
        case .hub: ("hub", .muted)
        case .local: ("local", .muted)
        case .bundled: nil
        }
    }
}

struct SkillDetailView: View {
    @State var skill: Skill

    @Environment(AppEnvironment.self) private var environment
    @Environment(ConnectionStore.self) private var connection
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(skill.name).font(.title3.weight(.semibold))
                        Tag(skill.category)
                        if let tag = skill.origin.tag { Tag(tag.0, tone: tag.1) }
                    }
                    Text(skill.summary).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Toggle("Enabled", isOn: Binding(get: { skill.isEnabled }, set: { setEnabled($0) }))
                    .disabled(environment.simulator == nil)
                    .disabled(!connection.connection.isConnected)
            }
            Section {
                KeyValueRow(label: "Category", value: skill.category)
                KeyValueRow(label: "Source", value: skill.origin.label)
                if let version = skill.version { KeyValueRow(label: "Version", value: version) }
                KeyValueRow(label: "Used", value: "\(skill.usageCount) times")
                if let last = skill.lastUsedAt { KeyValueRow(label: "Last used", value: Format.relative(last)) }
                if !skill.requiredToolsets.isEmpty {
                    KeyValueRow(label: "Needs", value: skill.requiredToolsets.joined(separator: ", "))
                }
            } header: {
                SectionHeader("Details")
            }
            Section {
                Text(skill.instructionsPreview)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            } header: {
                SectionHeader("Instructions")
            }
        }
        .navigationTitle("Skill")
        .accentSwitches()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setEnabled(_ enabled: Bool) {
        skill.isEnabled = enabled
        Task {
            do {
                try await environment.client.skills.setEnabled(enabled, skillID: skill.id)
            } catch {
                skill.isEnabled = !enabled
                toasts.show(error: error)
            }
        }
    }
}
