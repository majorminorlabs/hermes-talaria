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
    @State private var stepsRun: Run?
    @State private var isNearBottom = true
    @State private var renaming = false
    @State private var renameText = ""
    @State private var confirmingDelete = false
    @State private var artifacts: [FileAttachment] = []
    @State private var showingFiles = false
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
            if let pending = environment.needsYou.all.first(where: { $0.workItemID == model.conversationID && ($0.kind == .question || $0.kind == .decision || $0.kind == .approval) }) { NeedsYouCard(item: pending) }
            if model.conversation?.readOnly == true {
                HStack(spacing: 6) {
                    Image(systemName: "lock").accessibilityHidden(true)
                    Text(model.conversation?.isBotChat == true ? "Studio canonical thread · Read only" : "Read-only thread")
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
        .task { if let id = model.conversationID { environment.work.markSeen(id) }; await model.load(); await loadArtifacts(); if let id = environment.router.stepsRunID { stepsRun = environment.activity.run(id); environment.router.stepsRunID = nil } }
        .refreshable { await model.load() }
        .onChange(of: model.activeRun?.state) { if let id = model.conversationID { environment.work.markSeen(id) }; Task { await loadArtifacts() } }
        .quickLookPreview($downloadedArtifact)
        .sheet(isPresented: $showingFiles) {
            NavigationStack { List { ForEach(artifacts.reversed()) { file in ArtifactRow(file: file) { download(file) } }; Text("Only files Hermes registered for the phone appear here.").font(.footnote).foregroundStyle(Theme.secondaryText) }.navigationTitle("Files").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFiles = false } } } }
        }
        .sheet(item: $steeringRun) { run in SteerSheet(run: run) }
        .sheet(item: $stepsRun) { StepsSheet(runID: $0.id) }
        .sheet(item: $detailsRun) { run in RunSummarySheet(run: run) }
        .alert("Rename Thread", isPresented: $renaming) {
            TextField("Title", text: $renameText)
            Button("Save") {
                guard let id = model.conversationID else { return }
                toasts.perform { try await conversations.rename(id, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this thread?", isPresented: $confirmingDelete, titleVisibility: .visible) {
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

    private func download(_ artifact: FileAttachment) {
        toasts.perform { guard let service = environment.client.conversations as? any ArtifactService else { return }; downloadedArtifact = try await service.downloadArtifact(id: artifact.id) }
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
                Text("Ask a follow-up…").foregroundStyle(.secondary)
            }
        } else {
            let latestAssistantID = model.messages.last(where: { $0.role == .assistant && !$0.plainText.isEmpty })?.id
            ForEach(TranscriptItem.build(model.messages)) { item in
                switch item {
                case .message(let message):
                    MessageView(message: message, isLatestAssistant: message.id == latestAssistantID,
                                onSteer: { steeringRun = model.activeRun },
                                onShowDetails: { stepsRun = $0 })
                        .id(message.id)
                    if message.role == .assistant && !message.plainText.isEmpty {
                        let lastForTurn = model.messages.last(where: { $0.role == .assistant && $0.runID == message.runID && !$0.plainText.isEmpty })?.id == message.id
                        let latest = model.messages.last(where: { $0.role == .assistant && !$0.plainText.isEmpty })?.id == message.id
                        ForEach(artifacts.filter { ($0.runID != nil && $0.runID == message.runID && lastForTurn) || ($0.runID == nil && latest) }) { file in ArtifactRow(file: file) { download(file) } }
                    }
                case .tools(let id, let calls):
                    ToolActivityView(calls: calls).id(id)
                }
            }
        }
        if let run = environment.activity.runs.values.filter({ $0.conversationID == model.conversationID && ($0.state.isTerminal || $0.state == .unknown) }).max(by: { $0.startedAt < $1.startedAt }),
           !model.messages.contains(where: { $0.role == .assistant && $0.runID == run.id }) { ResultFooter(run: run) }
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
                        Button("Steps") { stepsRun = run }
                    }
                    if !conversation.usesDefaultProfile {
                        NavigationLink(value: Route.profile(conversation.profileID)) {
                            Label("View Agent", systemImage: "person.crop.circle")
                        }
                    }
                    if !artifacts.isEmpty { Button("Files (\(artifacts.count))") { showingFiles = true } }
                    Button("Mark Unread") { environment.seen.mark(conversation.id, at: .distantPast, host: connection.activeHostID) }
                    if conversation.isBotChat != true { Button("Archive") { toasts.perform { try await conversations.setArchived(true, conversation.id); dismiss() } } }
                    Divider()
                    if conversation.isBotChat != true { Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true } }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Thread actions")
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
        let title = model.conversation?.title ?? "New Thread"
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
            parts.append("Shared thread")
        } else if let profile, !profile.isDefault || title == "New Thread" {
            parts.append(profile.name)
        }
        if let project = model.configuration.project { parts.append(project.name) }
        if let model = model.conversation?.model?.displayName, parts.count < 2 { parts.append(model) }
        let filtered = parts.filter { $0.caseInsensitiveCompare(title) != .orderedSame }
        return filtered.isEmpty ? nil : filtered.joined(separator: " · ")
    }
}

/// Empty state for a fresh conversation.
