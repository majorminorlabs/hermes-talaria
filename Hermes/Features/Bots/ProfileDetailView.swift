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
    @State private var pickingModel = false
    @State private var risk: RiskAction?
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
        .navigationTitle(profiles.profile(profileID)?.name ?? "Agent")
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
        let profileRoutines = routines.sorted.filter { profiles.identity($0.profileID)?.id == profile.id }

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

            Section("Now") {
                ForEach(environment.needsYou.visible.filter { profiles.identity($0.agentID)?.id == profile.id }) { NeedsYouCard(item: $0) }
                ForEach(environment.work.items.filter { profiles.identity($0.agentID)?.id == profile.id && [.working,.needsYou].contains($0.state) }.prefix(3)) { item in NavigationLink(value: item.route) { WorkItemRow(item: item) } }
                if currentRun == nil { statusRow(profile) }
            }
            Section("Recent work") {
                ForEach(environment.work.items.filter { profiles.identity($0.agentID)?.id == profile.id && ![.working,.needsYou].contains($0.state) }.prefix(4)) { item in NavigationLink(value: item.route) { WorkItemRow(item: item) } }
            }
            Section {
                Button { pickingModel = true } label: { LabeledContent("Model", value: profile.model.detailedLabel) }.accessibilityIdentifier("agent-model-row")
                if let note = environment.agentModels.note(host: connection.activeHostID, agent: profile.id) {
                    if profile.model.id == note.applied.id && profile.model.provider == note.applied.provider {
                        HStack { Text("Changed from \(note.previous.displayName)").font(.footnote); Button("Revert") {
                            Task { await revert(profile, confirmed: false) }
                        } }.contextMenu { Button("Dismiss") { environment.agentModels.dismiss(host: connection.activeHostID, agent: profile.id) } }
                    } else { Text("Changed on another device").font(.footnote).foregroundStyle(.secondary) }
                }
                LabeledContent("Reasoning", value: "Set on your Mac")
                Text("Hermes stores reasoning in the agent's configuration, which Talaria can't change yet.").font(.footnote).foregroundStyle(.secondary)
                if !profileRoutines.isEmpty && connection.supports(.cron) {
                    Button(profileRoutines.contains(where: \.isEnabled) ? "Pause all routines" : "Resume all routines") {
                        let enabled = !profileRoutines.contains(where: \.isEnabled)
                        risk = RiskAction(verb: enabled ? "Resume routines" : "Pause routines", effect: enabled ? "Scheduled work can run again." : "Pauses scheduled work. Existing work keeps running.", target: profile.name) {
                            for routine in profileRoutines where routine.isEnabled != enabled { try await environment.client.schedules.setEnabled(enabled, routineID: routine.id) }
                            await routines.refresh()
                        }
                    }.disabled(!connection.connection.isConnected)
                }
                ForEach(profileRoutines) { routine in
                    NavigationLink(value: Route.routine(routine.id)) { RoutineRow(routine: routine) }
                }
            } header: { SectionHeader("Runtime") }
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
            // 6. Management
            managementSection(profile)
        }
        .listSectionSpacing(.compact)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if connection.supports(.botEdit) || environment.simulator != nil { Button("Edit") { editing = true } }
            }
        }
        .sheet(isPresented: $pickingModel) { AgentModelPicker(profile: profile) }
        .sheet(item: $risk) { RiskConfirmSheet(action: $0) }
        .sheet(isPresented: $editing) {
            if profile.isBotMode == true { BotEditorView(profile: profile) }
            else { EditProfileView(profile: profile, skills: skills.value ?? []) }
        }
        .confirmationDialog("Hide this agent? Its canonical thread and history remain on Hermes. You can unhide it on Desktop.", isPresented: $confirmingHide, titleVisibility: .visible) {
            Button("Hide Agent", role: .destructive) {
                Task { do { try await profiles.hide(profile.id); dismiss() } catch { toasts.show(error: error) } }
            }
        }
        .sheet(isPresented: $creatingTask) {
            NewTaskSheet(assigneeProfileID: profile.id)
        }
    }

    private func revert(_ profile: Profile, confirmed: Bool) async {
        do { try await environment.agentModels.revert(profile: profile, confirmed: confirmed, environment: environment); toasts.show("Default restored") }
        catch HermesError.botModelConfirmationText(let message) { risk = RiskAction(verb: "Restore default", effect: message, target: profile.name, high: true) { try await environment.agentModels.revert(profile: profile, confirmed: true, environment: environment); toasts.show("Default restored") } }
        catch HermesError.botModelConfirmation { risk = RiskAction(verb: "Restore default", effect: "Hermes requires confirmation before applying this model.", target: profile.name, high: true) { try await environment.agentModels.revert(profile: profile, confirmed: true, environment: environment); toasts.show("Default restored") } }
        catch { toasts.show(error: error) }
    }
    private func count(_ value: Int) -> some View {
        Text("\(value)").monospacedDigit().foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                        Text("Needs you").foregroundStyle(Theme.attention)
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
                    Text("Open this agent on your Mac to start its canonical thread.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func actions(_ profile: Profile) -> some View {
        HStack {
            Button("Ask \(profile.name)") { router.askSeed = AskSeed(agentID: profile.id) }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("agent-ask")
            Button("Voice input", systemImage: "mic") {
                environment.voice.start(capture: false, simulated: environment.simulator != nil)
                router.askSeed = AskSeed(agentID: profile.id, voice: true)
            }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                .modifier(PushToTalk(start: {
                    environment.voice.start(capture: false, simulated: environment.simulator != nil)
                    router.heldVoiceAsk = AskSeed(agentID: profile.id, voice: true)
                }, move: environment.voice.move, release: environment.voice.release, tap: { environment.voice.start(capture: false, simulated: environment.simulator != nil); environment.router.askSeed = AskSeed(agentID: profile.id, voice: true) }))
        }
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
                                Text(profile.model.provider).font(.caption).foregroundStyle(.secondary)
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
                        Task { do { try await profiles.duplicate(profile.id); toasts.show("Agent duplicated") } catch { toasts.show(error: error) } }
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
                if canHide { Text("Hiding keeps the agent's thread and history on Hermes. Unhide it from Hermes Desktop.") }
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
