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
        .accessibilityLabel("Thread options: \(parts.joined(separator: ", "))")
    }

    private var parts: [String] {
        var parts = [profiles.name(configuration.profileID)]
        let model = isNewConversation ? (configuration.model ?? profiles.profile(configuration.profileID)?.model ?? connection.status.defaultModel) : configuration.model
        if let model { parts.append(model.displayName) }
        if isNewConversation && configuration.reasoning != .medium { parts.append("Reasoning \(configuration.reasoning.label.lowercased())") }
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
                LabeledContent("Agent", value: profiles.name(model.configuration.profileID))
                LabeledContent("Model", value: model.configuration.model?.detailedLabel ?? "Not reported by Hermes")
                LabeledContent("Reasoning", value: environment.activity.runs.values.filter { $0.conversationID == model.conversationID }.max(by: { $0.startedAt < $1.startedAt })?.reasoning?.label ?? "Not reported by Hermes")
                LabeledContent("Project", value: model.configuration.project?.name ?? "None")
                LabeledContent("Host", value: connection.activeHost?.name ?? "—")
                Text("Hermes fixes session settings when the thread starts. Start a new Ask to use a different model, reasoning or project.").font(.footnote).foregroundStyle(.secondary)
                Button("Change agent default") { dismiss(); environment.router.open(.profile(model.configuration.profileID)) }
                Button("New ask") { dismiss(); environment.router.askSeed = AskSeed(agentID: model.configuration.profileID) }
            }.navigationTitle("Thread Options").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium,.large])
    }
}
