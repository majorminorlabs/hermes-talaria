import SwiftUI

/// Native bot identity/configuration fields, persisted and re-read by Hermes.
struct BotEditorView: View {
    private var initialProfile: Profile?
    @State private var hydratedProfile: Profile?
    private var profile: Profile? { hydratedProfile ?? initialProfile }
    init(profile: Profile?) { initialProfile = profile }
    @Environment(AppEnvironment.self) private var environment
    @Environment(ProfileStore.self) private var profiles
    @Environment(ConnectionStore.self) private var connection
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var inventory: BotInventory?
    @State private var name = ""
    @State private var description = ""
    @State private var soul = ""
    @State private var provider = ""
    @State private var modelID = ""
    @State private var skills = Set<String>()
    @State private var tools = Set<String>()
    @State private var mcp = Set<String>()
    @State private var saving = false
    @State private var loadError: String?
    @State private var loaded = false
    @State private var confirmingModel = false
    @State private var modelWarning = "Hermes warns that this model may increase usage or cost. Apply the selected model?"
    @State private var confirmModel = false
    var body: some View {
        NavigationStack {
            Form {
                if let loadError {
                    Section {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Button("Retry") { Task { await load() } }
                    }
                }
                if !loaded && loadError == nil {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Fetching options from your Mac").foregroundStyle(.secondary)
                        }
                    }
                }
                if loaded {
                    Section {
                        TextField("Name", text: $name).accessibilityIdentifier("bot-name")
                        TextField("What this bot is for", text: $description, axis: .vertical)
                            .lineLimit(2...5)
                            .accessibilityIdentifier("bot-description")
                    } header: {
                        SectionHeader("Basics")
                    } footer: {
                        Text("The name appears in Talaria and on Hermes Desktop.")
                    }

                    if editable("model") || editable("soul") {
                        Section {
                            if editable("model"), let inventory {
                                Picker("Provider", selection: Binding(get: { provider }, set: { provider = $0; modelID = ""; confirmModel = false })) {
                                    Text(profile == nil ? "Hermes default" : "Keep current model").tag("")
                                    ForEach(inventory.providers) { p in Text(p.name).tag(p.id) }
                                }
                                if !provider.isEmpty {
                                    Picker("Model", selection: $modelID) {
                                        Text("Select a model").tag("")
                                        ForEach(inventory.providers.first { $0.id == provider }?.models ?? []) { m in Text(m.displayName).tag(m.id) }
                                    }
                                }
                            }
                            if editable("soul") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("SOUL").font(.subheadline.weight(.medium))
                                    TextEditor(text: $soul)
                                        .font(.callout)
                                        .frame(minHeight: 140)
                                        .scrollContentBackground(.hidden)
                                        .accessibilityIdentifier("bot-soul")
                                        .overlay(alignment: .topLeading) {
                                            if soul.isEmpty {
                                                Text("Personality and standing instructions")
                                                    .font(.callout)
                                                    .foregroundStyle(.tertiary)
                                                    .padding(.top, 8)
                                                    .padding(.leading, 5)
                                                    .allowsHitTesting(false)
                                            }
                                        }
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            SectionHeader("Brain")
                        } footer: {
                            if editable("model") && profile == nil {
                                Text("Leave the provider on Hermes default to use the default profile's model.")
                            }
                        }
                    }

                    if let inventory, editable("skills") || editable("toolsets") || editable("mcp_servers") {
                        Section {
                            if editable("skills") { capabilityLink("Skills", symbol: "book.closed", inventory.skills, $skills) }
                            if editable("toolsets") { capabilityLink("Toolsets", symbol: "wrench.and.screwdriver", inventory.toolsets, $tools) }
                            if editable("mcp_servers") { capabilityLink("MCP Servers", symbol: "point.3.connected.trianglepath.dotted", inventory.mcpServers, $mcp) }
                        } header: {
                            SectionHeader("Capabilities")
                        } footer: {
                            Text(profile == nil ? "New bots start with Hermes's default selection." : "Changes apply to the bot's next run.")
                        }
                    }
                }
            }
            .disabled(saving)
            .navigationTitle(profile == nil ? "New Agent" : "Edit Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button(profile == nil ? "Create" : "Save") { save() }
                            .disabled(!loaded || saving || !hasChanges || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!provider.isEmpty && modelID.isEmpty))
                    }
                }
            }
            .confirmationDialog(modelWarning, isPresented:$confirmingModel,titleVisibility:.visible) {
                Button("Apply Model") { confirmModel = true; save() }
                Button("Cancel",role:.cancel) {}
            }
            .task(id: connection.connection.isConnected) { await load() }
        }
    }

    private func capabilityLink(_ title: String, symbol: String, _ choices: [BotChoice], _ selected: Binding<Set<String>>) -> some View {
        NavigationLink {
            BotChoiceList(title: title, choices: choices, selected: selected)
        } label: {
            LabeledContent {
                Text("\(selected.wrappedValue.intersection(choices.map(\.id)).count) of \(choices.count)")
                    .monospacedDigit()
            } label: {
                Label(title, systemImage: symbol)
            }
        }
    }

    private func editable(_ field: String) -> Bool {
        if ["skills", "toolsets", "mcp_servers"].contains(field), inventory?.available.contains(field) != true { return false }
        return profile == nil || profile?.editableFields?.contains(field) == true
    }
    private func load() async {
        do {
            // A roster summary is enough to open this sheet, but never enough
            // to populate an editor. Read confirmed native fields first.
            if !loaded, let initialProfile {
                let detail = try await environment.client.profiles.profile(id: initialProfile.id)
                guard !Task.isCancelled else { return }
                guard detail.editableFields?.isEmpty == false else { throw HermesError.rejected("Bot editing metadata is unavailable.") }
                hydratedProfile = detail
            }
            let options = try await environment.client.profiles.botInventory(profileID: profile?.id)
            guard !Task.isCancelled else { return }
            inventory = options
            if !loaded {
                name = profile?.name ?? ""; description = profile?.summary ?? ""; soul = profile?.soul ?? ""
                skills = Set(profile?.skillIDs ?? options.skills.filter(\.enabled).map(\.id))
                tools = Set(profile?.toolsets ?? options.toolsets.filter(\.enabled).map(\.id))
                mcp = Set(profile?.mcpServerIDs ?? options.mcpServers.filter(\.enabled).map(\.id))
                if let p = profile, options.providers.contains(where: { $0.id == p.model.provider && $0.models.contains(where: { $0.id == p.model.id }) }) { provider = p.model.provider; modelID = p.model.id }
            }
            loaded = true; loadError = nil
        } catch {
            guard !Task.isCancelled else { return }
            loadError = "Studio bot options are unavailable. Reconnect and try again."
        }
    }
    private var hasChanges: Bool {
        guard let profile else { return true }
        let selectedModel = inventory?.providers.first { $0.id == provider }?.models.first { $0.id == modelID }
        return name != profile.name || description != profile.summary || soul != (profile.soul ?? "") ||
            skills != Set(profile.skillIDs) || tools != Set(profile.toolsets) || mcp != Set(profile.mcpServerIDs) ||
            (selectedModel != nil && selectedModel != profile.model)
    }
    private func save() {
        saving = true
        var changes = ProfileChanges()
        if profile == nil || name != profile?.name { changes.name = name }
        if profile == nil || description != profile?.summary { changes.description = description }
        if editable("soul"), profile == nil || soul != profile?.soul { changes.soul = soul }
        if !provider.isEmpty, let model = inventory?.providers.first(where: { $0.id == provider })?.models.first(where: { $0.id == modelID }), model != profile?.model { changes.model = model }
        if editable("skills"), skills != Set(profile?.skillIDs ?? inventory?.skills.filter(\.enabled).map(\.id) ?? []) { changes.enabledSkillIDs = skills.sorted() }
        if editable("toolsets"), tools != Set(profile?.toolsets ?? inventory?.toolsets.filter(\.enabled).map(\.id) ?? []) { changes.toolsets = tools.sorted() }
        if editable("mcp_servers"), mcp != Set(profile?.mcpServerIDs ?? inventory?.mcpServers.filter(\.enabled).map(\.id) ?? []) { changes.mcpServerIDs = mcp.sorted() }
        if confirmModel { changes.confirmExpensiveModel = true }
        let submitted = changes
        Task {
            defer { saving = false }
            do {
                if let profile { try await profiles.update(profile.id, changes: submitted) }
                else { _ = try await profiles.create(BotDraft(changes: submitted)) }
                toasts.show(profile == nil ? "Agent created" : "Agent updated"); dismiss()
            } catch HermesError.botModelConfirmationText(let message) { modelWarning = message; confirmingModel = true }
            catch HermesError.botModelConfirmation { confirmingModel = true }
            catch { await profiles.refresh(); toasts.show(error: error) }
        }
    }
}

/// One capability inventory (skills, toolsets, MCP servers): searchable,
/// with a live count, instead of a wall of toggles in the main form.
private struct BotChoiceList: View {
    var title: String
    var choices: [BotChoice]
    @Binding var selected: Set<String>
    @State private var query = ""

    var body: some View {
        let filtered = choices.filter { query.isEmpty || $0.id.localizedCaseInsensitiveContains(query) }
        List {
            Section {
                if filtered.isEmpty {
                    Text("No matches").foregroundStyle(.secondary)
                }
                ForEach(filtered) { choice in
                    Toggle(choice.id, isOn: Binding(get: { selected.contains(choice.id) }, set: { value in
                        if value { selected.insert(choice.id) } else { selected.remove(choice.id) }
                    }))
                }
            } header: {
                SectionHeader("\(selected.intersection(choices.map(\.id)).count) of \(choices.count) enabled")
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(title.lowercased())")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accentSwitches()
    }
}
