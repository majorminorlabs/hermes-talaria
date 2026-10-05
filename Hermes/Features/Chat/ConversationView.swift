import SwiftUI
import QuickLook

/// A conversation with any profile. Bot chats from the Bots tab use this
/// same view; there is one chat implementation.
struct ConversationView: View {
    @State private var model: ConversationModel

    @Environment(ProfileStore.self) private var profiles
    @Environment(ConversationListStore.self) private var conversations
    @Environment(ConnectionStore.self) private var connection
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composerFocused: Bool
    @State private var steeringRun: Run?
    @State private var detailsRun: Run?
    @State private var isNearBottom = true
    @State private var renaming = false
    @State private var renameText = ""
    @State private var confirmingDelete = false
    @State private var artifacts: [FileAttachment] = []
    @State private var downloadedArtifact: URL?
    @Environment(AppEnvironment.self) private var environment

    init(model: ConversationModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    content
                    if !artifacts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader("Artifacts")
                            ForEach(artifacts) { artifact in
                                Button {
                                    toasts.perform {
                                        guard let service = environment.client.conversations as? any ArtifactService else { return }
                                        downloadedArtifact = try await service.downloadArtifact(id:artifact.id)
                                    }
                                } label: {
                                    FileAttachmentView(file: artifact)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Downloads and previews the file")
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id(bottomID)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 160
            } action: { _, nearBottom in
                isNearBottom = nearBottom
            }
            .onChange(of: scrollSignature) {
                guard isNearBottom else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .onChange(of: composerFocused) { _, focused in
                if focused { withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.conversation?.readOnly == true {
                HStack(spacing: 6) {
                    Image(systemName: "lock").accessibilityHidden(true)
                    Text(model.conversation?.isBotChat == true ? "Studio Bot Chat · Read only" : "Read-only conversation")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.bar)
            } else { ComposerView(model: model, focus: $composerFocused) }
        }
        // Like other chat apps, the conversation owns the bottom edge: the
        // composer replaces the floating tab bar instead of stacking on it.
        .toolbar(.hidden, for: .tabBar)
        .connectionBanner(updatedAt: conversations.updatedAt)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task { await model.load(); await loadArtifacts() }
        .refreshable { await model.load() }
        .onChange(of: model.activeRun?.state) { Task { await loadArtifacts() } }
        .quickLookPreview($downloadedArtifact)
        .sheet(item: $steeringRun) { run in SteerSheet(run: run) }
        .sheet(item: $detailsRun) { run in RunSummarySheet(run: run) }
        .alert("Rename Conversation", isPresented: $renaming) {
            TextField("Title", text: $renameText)
            Button("Save") {
                guard let id = model.conversationID else { return }
                toasts.perform { try await conversations.rename(id, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this conversation?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let id = model.conversationID else { return }
                toasts.perform {
                    try await conversations.delete(id)
                    dismiss()
                }
            }
        } message: {
            Text("It will be deleted from Hermes on your Mac, not just this iPhone.")
        }
    }

    private func loadArtifacts() async {
        guard connection.supports(.artifacts), let id = model.conversationID,
              let service = environment.client.conversations as? any ArtifactService else { return }
        artifacts = (try? await service.artifacts(conversationID:id)) ?? artifacts
    }

    private let bottomID = "bottom"

    /// Changes whenever new content should pull the view to the bottom.
    private var scrollSignature: Int {
        var hasher = Hasher()
        hasher.combine(model.messages.count)
        hasher.combine(model.messages.last?.plainText.count)
        hasher.combine(model.activeRun?.events.count)
        hasher.combine(model.pendingApproval?.id)
        return hasher.finalize()
    }

    @ViewBuilder
    private var content: some View {
        if model.messages.isEmpty {
            switch model.phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            case .failed(let error):
                ErrorContentView(error: error) { await model.load() }
                    .padding(.top, 40)
            default:
                NewConversationIntro(profile: profiles.identity(model.configuration.profileID)) { suggestion in
                    model.draft = suggestion
                    composerFocused = true
                }
            }
        } else {
            let latestAssistantID = model.messages.last(where: { $0.role == .assistant && !$0.plainText.isEmpty })?.id
            ForEach(TranscriptItem.build(model.messages)) { item in
                switch item {
                case .message(let message):
                    MessageView(message: message, isLatestAssistant: message.id == latestAssistantID,
                                onSteer: { steeringRun = model.activeRun },
                                onShowDetails: { detailsRun = $0 })
                        .id(message.id)
                case .tools(let id, let calls):
                    ToolActivityView(calls: calls).id(id)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ConversationTitle(model: model)
        }
        if let conversation = model.conversation, conversation.readOnly != true {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if conversation.isBotChat != true { Button("Rename", systemImage: "pencil") {
                        renameText = conversation.title
                        renaming = true
                    } }
                    Button(conversation.isPinned ? "Unpin" : "Pin", systemImage: conversation.isPinned ? "pin.slash" : "pin") {
                        toasts.perform { try await conversations.setPinned(!conversation.isPinned, conversation.id) }
                    }
                    if let run = model.activeRun {
                        NavigationLink(value: Route.run(run.id)) {
                            Label("Active Run", systemImage: "play.circle")
                        }
                    }
                    if !conversation.usesDefaultProfile {
                        NavigationLink(value: Route.profile(conversation.profileID)) {
                            Label("Bot Profile", systemImage: "person.crop.circle")
                        }
                    }
                    Divider()
                    if conversation.isBotChat != true { Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true } }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Conversation actions")
            }
        }
    }
}

/// Who and what, in the navigation bar: the bot's face, the title, and a
/// subtitle that adds information (never a repeat of the title).
private struct ConversationTitle: View {
    var model: ConversationModel
    @Environment(ProfileStore.self) private var profiles
    @Environment(ConnectionStore.self) private var connection

    var body: some View {
        let profile = profiles.identity(model.conversation?.profileID ?? model.configuration.profileID)
        let title = model.conversation?.title ?? "New Chat"
        HStack(spacing: 8) {
            ProfileAvatar(profile: profile, size: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                subtitle(profile, title: title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 260)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func subtitle(_ profile: Profile?, title: String) -> some View {
        if let run = model.activeRun {
            let state = run.displayState(isLive: connection.connection.isConnected)
            HStack(spacing: 4) {
                StatusDot(color: state.tint, pulsing: state == .running, size: 6)
                Text(state == .running ? "Working" : state == .disconnected ? "Last known: working" : state.shortLabel)
            }
        } else if let text = subtitleText(profile, title: title) {
            Text(text)
        }
    }

    private func subtitleText(_ profile: Profile?, title: String) -> String? {
        var parts: [String] = []
        if model.conversation?.isBotChat == true {
            parts.append("Bot chat")
        } else if let profile, !profile.isDefault || title == "New Chat" {
            parts.append(profile.name)
        }
        if let project = model.configuration.project { parts.append(project.name) }
        if let model = model.conversation?.model?.displayName, parts.count < 2 { parts.append(model) }
        let filtered = parts.filter { $0.caseInsensitiveCompare(title) != .orderedSame }
        return filtered.isEmpty ? nil : filtered.joined(separator: " · ")
    }
}

/// Empty state for a fresh conversation.
private struct NewConversationIntro: View {
    var profile: Profile?
    var onSuggestion: (String) -> Void

    var body: some View {
        VStack(spacing: 18) {
            ProfileAvatar(profile: profile, size: 52)
            VStack(spacing: 4) {
                Text(profile?.name ?? "Hermes").font(.title3.weight(.semibold))
                Text((profile?.summary).flatMap { $0.isEmpty ? nil : $0 } ?? "Hermes runs on your Mac Studio.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onSuggestion(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            Text(suggestion)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .panel(padding: 12, cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private var suggestions: [String] {
        switch profile?.id {
        case MockID.caddy: ["Run the test suite and fix anything that fails", "Clean up the build cache", "Summarize what changed this week"]
        case MockID.researcher: ["Compare the latest open-weight coding models", "Find papers on agent memory from this month"]
        case MockID.dex: ["What's on my calendar tomorrow?", "Draft a reply to the landlord"]
        default: ["What's running on the Studio right now?", "Summarize yesterday's routine results", "Research speculative decoding on Apple silicon"]
        }
    }
}
