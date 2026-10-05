import SwiftUI

/// One compact line summarizing the next run's settings. Tapping opens the
/// full settings sheet; advanced controls never crowd the composer.
struct RunSettingsBar: View {
    var configuration: RunConfiguration
    var isNewConversation: Bool
    var action: () -> Void

    @Environment(ProfileStore.self) private var profiles
    @Environment(ConnectionStore.self) private var connection

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ProfileAvatar(profile: profiles.identity(configuration.profileID), size: 16)
                Text(parts.joined(separator: " · "))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Run settings: \(parts.joined(separator: ", "))")
    }

    private var parts: [String] {
        var parts = [profiles.name(configuration.profileID)]
        let model = configuration.model ?? profiles.profile(configuration.profileID)?.model ?? connection.status.defaultModel
        if let model { parts.append(model.displayName) }
        if configuration.reasoning != .medium { parts.append("Reasoning \(configuration.reasoning.label.lowercased())") }
        if let project = configuration.project { parts.append(project.name) }
        return parts
    }
}

struct RunSettingsSheet: View {
    @Bindable var model: ConversationModel

    @Environment(ProfileStore.self) private var profiles
    @Environment(ConnectionStore.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.conversation == nil && connection.supports(.profiles) && !connection.supports(.botMode) {
                        Picker("Profile", selection: $model.configuration.profileID) {
                            ForEach(profiles.sorted.filter { $0.isBotMode != true }) { profile in
                                Text(profile.isDefault ? "\(profile.name) (default)" : profile.name).tag(profile.id)
                            }
                        }
                    } else {
                        LabeledContent("Profile", value: profiles.name(model.configuration.profileID))
                    }
                } footer: {
                    if model.conversation != nil {
                        Text("A conversation keeps the profile it started with.")
                    }
                }

                Section {
                    Picker("Model", selection: $model.configuration.model) {
                        Text("Profile default").tag(ModelRef?.none)
                        ForEach(connection.runOptions.models) { option in
                            VStack(alignment: .leading) {
                                Text(option.displayName)
                                Text(option.provider).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(ModelRef?.some(option))
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Picker("Reasoning", selection: $model.configuration.reasoning) {
                        ForEach(connection.runOptions.reasoningLevels) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.configuration.model?.supportsReasoning == false)
                } header: {
                    SectionHeader("Model")
                }

                .disabled(environment.simulator == nil && model.conversation != nil)

                Section {
                    LabeledContent("Host", value: connection.activeHost?.name ?? "—")
                    Picker("Project", selection: $model.configuration.project) {
                        Text("None").tag(ProjectContext?.none)
                        ForEach(connection.runOptions.projects) { project in
                            VStack(alignment: .leading) {
                                Text(project.name)
                                Text(project.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            .tag(ProjectContext?.some(project))
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    SectionHeader("Where")
                } footer: {
                    Text(environment.simulator == nil ? "Model, reasoning and workspace are selected when creating a conversation. Existing sessions keep their Studio configuration." : "Settings apply to the next run in this conversation.")
                }
                .disabled(environment.simulator == nil && model.conversation != nil)
            }
            .navigationTitle("Run Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                if connection.runOptions.models.isEmpty { await connection.loadRunOptions() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
