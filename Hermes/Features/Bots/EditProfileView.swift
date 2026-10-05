import SwiftUI

/// Profile configuration. V1 edits model and skills; the rest is shown
/// read-only so the structure is in place for later.
struct EditProfileView: View {
    var profile: Profile
    var skills: [Skill]

    @Environment(ProfileStore.self) private var profiles
    @Environment(ConnectionStore.self) private var connection
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var model: ModelRef
    @State private var enabledSkills: Set<String>
    @State private var saving = false

    init(profile: Profile, skills: [Skill]) {
        self.profile = profile
        self.skills = skills
        _model = State(initialValue: profile.model)
        _enabledSkills = State(initialValue: Set(profile.skillIDs))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Model", selection: $model) {
                        ForEach(modelOptions) { option in
                            VStack(alignment: .leading) {
                                Text(option.displayName)
                                Text(option.provider).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(option)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    SectionHeader("Model")
                }

                if connection.supports(.skills) && !skills.isEmpty {
                    Section {
                        ForEach(skills) { skill in
                            Toggle(isOn: Binding(
                                get: { enabledSkills.contains(skill.id) },
                                set: { isOn in
                                    if isOn { enabledSkills.insert(skill.id) } else { enabledSkills.remove(skill.id) }
                                })) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(skill.name)
                                    Text(skill.category).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        SectionHeader("Skills")
                    }
                }

                Section {
                    readOnlyRow("Toolsets", profile.toolsets.isEmpty ? "None" : profile.toolsets.joined(separator: ", "))
                    readOnlyRow("MCP servers", profile.mcpServerIDs.isEmpty ? "None" : profile.mcpServerIDs.map { $0.replacingOccurrences(of: "mcp-", with: "") }.joined(separator: ", "))
                    readOnlyRow("Memory", profile.memoryEntryCount.map { "\($0) entries" } ?? "Not exposed")
                } header: {
                    SectionHeader("Tools & Memory")
                } footer: {
                    Text("Read-only here. Change these in the profile's config on your Mac.")
                }

                Section {
                    if let soul = profile.soulSummary {
                        Text(soul).foregroundStyle(.secondary)
                    } else {
                        Text("This Mac doesn't share the profile's SOUL.").foregroundStyle(.secondary)
                    }
                } header: {
                    SectionHeader(title: "SOUL") { Image(systemName: "lock").foregroundStyle(.tertiary) }
                } footer: {
                    if let path = profile.configPath {
                        Text("Edit \(path)/SOUL.md on your Mac.")
                    }
                }
            }
            .navigationTitle("Edit \(profile.name)")
            .accentSwitches()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!hasChanges || saving || !connection.connection.isConnected)
                }
            }
            .task {
                if connection.runOptions.models.isEmpty { await connection.loadRunOptions() }
            }
        }
    }

    private var modelOptions: [ModelRef] {
        var options = connection.runOptions.models
        if !options.contains(profile.model) { options.insert(profile.model, at: 0) }
        return options
    }

    private var hasChanges: Bool {
        model != profile.model || enabledSkills != Set(profile.skillIDs)
    }

    private func readOnlyRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        saving = true
        let changes = ProfileChanges(
            model: model != profile.model ? model : nil,
            enabledSkillIDs: enabledSkills != Set(profile.skillIDs) ? skills.map(\.id).filter(enabledSkills.contains) : nil)
        Task {
            do {
                try await profiles.update(profile.id, changes: changes)
                toasts.show("\(profile.name) updated")
                dismiss()
            } catch {
                toasts.show(error: error)
            }
            saving = false
        }
    }
}
