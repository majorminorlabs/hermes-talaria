import SwiftUI

/// A bot (Hermes profile): identity, what it's doing, its conversations,
/// runs, routines, skills and configuration metadata.
struct ProfileDetailView: View {
    var profileID: String

    @Environment(AppEnvironment.self) private var environment
    @Environment(ProfileStore.self) private var profiles
    @Environment(ActivityStore.self) private var activity
    @Environment(ConversationListStore.self) private var conversations
    @Environment(RoutineStore.self) private var routines
    @Environment(TaskStore.self) private var tasks
    @Environment(ConnectionStore.self) private var connection
    @Environment(AppRouter.self) private var router
    @State private var skills = Resource<[Skill]>()
    @State private var editing = false
    @State private var creatingTask = false
    @State private var openingBotChat = false
    @State private var confirmingHide = false
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        Group {
            if let profile = profiles.profile(profileID) {
                content(profile)
            } else {
                ContentUnavailableView("Profile Not Found", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .navigationTitle(profiles.profile(profileID)?.name ?? "Bot")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: connection.supports(.botMode)) {
            if !connection.supports(.botMode) && connection.supports(.skills) { await skills.load { try await environment.client.skills.listSkills() } }
            repeat {
                await profiles.loadProfile(profileID)
                guard connection.supports(.botMode) else { return }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            } while !Task.isCancelled
        }
    }

    private func content(_ profile: Profile) -> some View {
        let currentRun = activity.run(profile.currentRunID).flatMap { $0.state.isActive ? $0 : nil }
        let profileConversations = conversations.conversations(forProfile: profile.id)
        let recentRuns = activity.runs(forProfile: profile.id).filter(\.state.isTerminal)
        let profileRoutines = routines.routines(forProfile: profile.id)
        let openTasks = tasks.tasks(forProfile: profile.id).filter { $0.status != .completed && $0.status != .cancelled }

        return List {
            // 1. Identity
            Section {
                header(profile)
            }

            // 2. Chat
            Section {
                actions(profile)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            // 3. Current status
            Section {
                if let currentRun {
                    NavigationLink(value: Route.run(currentRun.id)) { RunRow(run: currentRun) }
                } else {
                    statusRow(profile)
                }
                ForEach(openTasks.prefix(4)) { task in
                    NavigationLink(value: Route.task(task.id)) { TaskRow(task: task) }
                }
                ForEach(recentRuns.prefix(3)) { run in
                    NavigationLink(value: Route.run(run.id)) { RecentRunRow(run: run) }
                }
            } header: {
                SectionHeader("Activity")
            }

            if profile.isBotMode != true && !profileConversations.isEmpty {
                Section {
                    ForEach(profileConversations.prefix(4)) { conversation in
                        NavigationLink(value: Route.conversation(conversation.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conversation.title).lineLimit(2)
                                Text(conversation.preview)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } header: {
                    SectionHeader(title: "Conversations") {
                        if profileConversations.count > 4 {
                            Text("\(profileConversations.count)").monospacedDigit().foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            // 4. Configuration
            configurationSection(profile)

            // 5. Skills and tools
            skillsSection(profile)
            if !profile.toolsets.isEmpty {
                Section {
                    TagCloud(items: profile.toolsets, limit: 24)
                } header: {
                    SectionHeader(title: "Toolsets") { count(profile.toolsets.count) }
                }
            }
            if !profile.mcpServerIDs.isEmpty {
                Section {
                    TagCloud(items: profile.mcpServerIDs.map { $0.replacingOccurrences(of: "mcp-", with: "") }, limit: 24)
                } header: {
                    SectionHeader(title: "MCP Servers") { count(profile.mcpServerIDs.count) }
                }
            }
            if let names = profile.pluginsMetadata, !names.isEmpty {
                Section {
                    TagCloud(items: names, limit: 24)
                } header: {
                    SectionHeader(title: "Plugins") { count(names.count) }
                }
            }
            if !profileRoutines.isEmpty {
                Section {
                    ForEach(profileRoutines) { routine in
                        NavigationLink(value: Route.routine(routine.id)) { UpcomingRow(routine: routine) }
                    }
                } header: {
                    SectionHeader("Routines")
                }
            } else if let names = profile.routinesMetadata, !names.isEmpty {
                Section {
                    ForEach(names, id: \.self) { Label($0, systemImage: "calendar.badge.clock") }
                } header: {
                    SectionHeader("Routines")
                }
            }

            // 6. Management
            managementSection(profile)
        }
        .listSectionSpacing(.compact)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if connection.supports(.botEdit) || environment.simulator != nil { Button("Edit") { editing = true } }
            }
        }
        .sheet(isPresented: $editing) {
            if profile.isBotMode == true { BotEditorView(profile: profile) }
            else { EditProfileView(profile: profile, skills: skills.value ?? []) }
        }
        .confirmationDialog("Hide this bot? Its canonical chat and history remain on Hermes. You can unhide it on Desktop.", isPresented: $confirmingHide, titleVisibility: .visible) {
            Button("Hide Bot", role: .destructive) {
                Task { do { try await profiles.hide(profile.id); dismiss() } catch { toasts.show(error: error) } }
            }
        }
        .sheet(isPresented: $creatingTask) {
            NewTaskSheet(assigneeProfileID: profile.id)
        }
    }

    private func count(_ value: Int) -> some View {
        Text("\(value)").monospacedDigit().foregroundStyle(.tertiary)
    }

    private func header(_ profile: Profile) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ProfileAvatar(profile: profile, size: 64)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(profile.name)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if profile.isDefault { Tag("Default") }
                }
                if !profile.role.isEmpty && profile.role != profile.summary {
                    Text(profile.role)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if !profile.summary.isEmpty {
                    Text(profile.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if profile.modelAvailable != false {
                    Label(profile.model.detailedLabel, systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// Idle/last-active state when nothing is running.
    @ViewBuilder
    private func statusRow(_ profile: Profile) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            StatusDot(color: profile.status == .needsAttention ? Theme.attention : Color(uiColor: .tertiaryLabel), size: 7)
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if profile.status == .needsAttention {
                        Text("Needs attention").foregroundStyle(Theme.attention)
                    } else if let last = profile.lastActiveAt {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(Format.lastActive(last, now: context.date))
                        }
                    } else {
                        Text(profile.status == .idle ? "Idle" : "No recent activity")
                    }
                }
                .font(.subheadline.weight(.medium))
                if let action = profile.activitySummary, !action.isEmpty {
                    Text(action)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if profile.isBotMode == true && profile.canonicalChatAvailable != true && !connection.supports(.botChat) {
                    Text("Open this bot on your Mac to start its chat.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func actions(_ profile: Profile) -> some View {
        HStack(spacing: 10) {
            Button {
                if profile.isBotMode == true {
                    guard !openingBotChat else { return }
                    openingBotChat = true
                    environment.toasts.perform {
                        defer { openingBotChat = false }
                        if let chat = try await environment.client.profiles.canonicalConversation(profileID: profile.id) {
                            conversations.apply(.conversationUpserted(chat))
                            router.open(.conversation(chat.id))
                        }
                    }
                } else { router.open(.newConversation(NewChatSeed(profileID: profile.id))) }
            } label: {
                if openingBotChat {
                    ProgressView().controlSize(.small)
                    Text("Opening…").frame(maxWidth: .infinity)
                } else {
                    Label("Chat", systemImage: "bubble.left.fill").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!connection.supports(.sessions) || (profile.isBotMode == true &&
                (!connection.connection.isConnected || (profile.canonicalChatAvailable != true && !connection.supports(.botChat)) || openingBotChat)))

            if profile.isBotMode != true && connection.supports(.kanban) {
                Button {
                    creatingTask = true
                } label: {
                    Label("Start Task", systemImage: "checklist").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!connection.connection.isConnected)
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private func configurationSection(_ profile: Profile) -> some View {
        let hasSoul = profile.soulSummary?.isEmpty == false
        if hasSoul || profile.memorySummary != nil || profile.memoryEntryCount != nil || profile.configPath != nil || profile.modelAvailable != false {
            Section {
                if profile.modelAvailable != false {
                    LabeledContent("Model") {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(profile.model.displayName)
                            if !profile.model.provider.isEmpty {
                                Text(profile.model.provider).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                if let soul = profile.soulSummary, !soul.isEmpty {
                    SoulPreview(text: soul)
                }
                if let summary = profile.memorySummary {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Memory").font(.subheadline.weight(.medium))
                        Text(summary).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                if profile.isBotMode != true && connection.supports(.memory) {
                    NavigationLink(value: Route.memory) {
                        LabeledContent("Memory entries", value: profile.memoryEntryCount.map(String.init) ?? "—")
                    }
                }
                if let path = profile.configPath {
                    KeyValueRow(label: "Config", value: path, monospaced: true)
                }
            } header: {
                SectionHeader("Configuration")
            }
        }
    }

    @ViewBuilder
    private func skillsSection(_ profile: Profile) -> some View {
        if !profile.skillIDs.isEmpty {
            let resolved = profile.skillIDs.compactMap { id in skills.value?.first { $0.id == id } }
            Section {
                if resolved.count == profile.skillIDs.count {
                    ForEach(resolved) { skill in
                        NavigationLink(value: Route.skill(skill)) { SkillRow(skill: skill) }
                    }
                } else {
                    TagCloud(items: profile.skillIDs)
                }
            } header: {
                SectionHeader(title: "Skills") { count(profile.skillIDs.count) }
            }
        }
    }

    @ViewBuilder
    private func managementSection(_ profile: Profile) -> some View {
        let canDuplicate = connection.supports(.botDuplicate)
        let canHide = connection.supports(.botHide) && !profile.isDefault
        if canDuplicate || canHide {
            Section {
                if canDuplicate {
                    Button {
                        Task { do { try await profiles.duplicate(profile.id); toasts.show("Bot duplicated") } catch { toasts.show(error: error) } }
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                }
                if canHide {
                    Button(role: .destructive) { confirmingHide = true } label: {
                        Label("Hide", systemImage: "eye.slash")
                    }
                }
            } header: {
                SectionHeader("Management")
            } footer: {
                if canHide { Text("Hiding keeps the bot's chat and history on Hermes. Unhide it from Hermes Desktop.") }
            }
        }
    }
}

/// SOUL instructions, collapsed to a few lines with an inline expander.
private struct SoulPreview: View {
    var text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SOUL").font(.subheadline.weight(.medium))
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 5)
                .textSelection(.enabled)
            if text.count > 280 || text.filter(\.isNewline).count > 4 {
                Button(expanded ? "Show Less" : "Show More") { withAnimation(.snappy) { expanded.toggle() } }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack { ProfileDetailView(profileID: MockID.caddy).routeDestinations() }
        .previewEnvironment()
}
