import SwiftUI

struct ConversationListView: View {
    @Environment(ConversationListStore.self) private var conversations
    @Environment(ProfileStore.self) private var profiles
    @Environment(ConnectionStore.self) private var connection
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @State private var query = ""
    @State private var renaming: Conversation?
    @State private var renameText = ""
    @State private var deleting: Conversation?

    var body: some View {
        CapabilityGate(capability: .sessions) {
            LoadableContent(phase: conversations.phase, isEmpty: conversations.conversations.isEmpty,
                            hasData: !conversations.conversations.isEmpty, retry: { await conversations.refresh() }) {
                list
            } empty: {
                ContentUnavailableView {
                    Label("No Conversations", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Conversations from the app, Telegram and the terminal all show up here.")
                } actions: {
                    Button("New Chat") { router.startNewChat() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Chat")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("New chat with") {
                        ForEach(profiles.sorted) { profile in
                            Button(profile.isDefault ? "\(profile.name) (default)" : profile.name) {
                                router.open(.newConversation(NewChatSeed(profileID: profile.id)))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                } primaryAction: {
                    router.open(.newConversation(NewChatSeed()))
                }
                .accessibilityLabel("New Chat")
                .disabled(!connection.supports(.sessions))
            }
        }
        .alert("Rename Conversation", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Save") {
                guard let conversation = renaming else { return }
                toasts.perform { try await conversations.rename(conversation.id, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(deleting?.title ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let conversation = deleting else { return }
                toasts.perform { try await conversations.delete(conversation.id) }
            }
        } message: {
            if deleting?.activeRunID != nil {
                Text("Hermes is still working in this conversation. Deleting stops the run.")
            } else {
                Text("It will be deleted from Hermes on your Mac.")
            }
        }
    }

    private var list: some View {
        let sections = conversations.sections(matching: query)
        return List {
            ConnectionNoticeSection(updatedAt: conversations.updatedAt)
            if sections.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.conversations) { conversation in
                        NavigationLink(value: Route.conversation(conversation.id)) {
                            ConversationRow(conversation: conversation)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = conversation }
                            Button("Rename", systemImage: "pencil") { beginRename(conversation) }
                                .tint(.gray)
                        }
                        .swipeActions(edge: .leading) {
                            Button(conversation.isPinned ? "Unpin" : "Pin", systemImage: conversation.isPinned ? "pin.slash" : "pin") {
                                toasts.perform { try await conversations.setPinned(!conversation.isPinned, conversation.id) }
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { beginRename(conversation) }
                            Button(conversation.isPinned ? "Unpin" : "Pin", systemImage: conversation.isPinned ? "pin.slash" : "pin") {
                                toasts.perform { try await conversations.setPinned(!conversation.isPinned, conversation.id) }
                            }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = conversation }
                        }
                    }
                } header: {
                    SectionHeader(section.title)
                }
            }
        }
        .listStyle(.plain)
        .task { await profiles.loadMissingAvatars() }
        .searchable(text: $query, prompt: "Search conversations")
        .refreshable { await conversations.refresh() }
    }

    private func beginRename(_ conversation: Conversation) {
        renameText = conversation.title
        renaming = conversation
    }
}

struct ConversationRow: View {
    var conversation: Conversation

    @Environment(ProfileStore.self) private var profiles
    @Environment(ActivityStore.self) private var activity
    @Environment(ConnectionStore.self) private var connection
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let run = activity.run(conversation.activeRunID).flatMap { $0.state.isActive ? $0 : nil }
        let profile = profiles.identity(conversation.profileID)
        let large = typeSize.isAccessibilitySize
        HStack(alignment: .top, spacing: 12) {
            ProfileAvatar(profile: profile, size: large ? 32 : 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(conversation.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(large ? 4 : 2)
                    if conversation.isPinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.tertiary)
                            .accessibilityLabel("Pinned")
                    }
                    if !large {
                        Spacer(minLength: 6)
                        Text(Format.listTimestamp(conversation.lastActivity))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if !conversation.preview.isEmpty || conversation.messageCount == 0 {
                    Text(conversation.preview.isEmpty ? "No messages yet" : conversation.preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(large ? 3 : 1)
                }
                if large {
                    Text(Format.listTimestamp(conversation.lastActivity))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                metadata(run, profile: profile)
            }
        }
        .padding(.vertical, 4)
    }

    /// Who (when it isn't obvious from the title), what's live, and where it
    /// came from. The generic "API" origin is omitted: it says nothing.
    @ViewBuilder
    private func metadata(_ run: Run?, profile: Profile?) -> some View {
        let botName = profile.flatMap { profile in
            !profile.isDefault && profile.name.caseInsensitiveCompare(conversation.title) != .orderedSame ? profile.name : nil
        }
        let source = conversation.source.symbol != nil && conversation.source != .api ? conversation.source : nil
        if run != nil || botName != nil || conversation.project != nil || source != nil || conversation.isBotChat == true {
            HStack(spacing: 8) {
                if let run {
                    let state = run.displayState(isLive: connection.connection.isConnected)
                    HStack(spacing: 4) {
                        if state.needsUser {
                            Image(systemName: "hand.raised.fill")
                        } else {
                            StatusDot(color: state.tint, pulsing: state == .running, size: 6)
                        }
                        Text(state.needsUser ? "Needs approval" : state == .disconnected ? "Last known: working" : "Working")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(state.tint)
                }
                if let botName {
                    Text(botName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if conversation.isBotChat == true {
                    Tag("Bot chat")
                }
                if let source {
                    Tag(source.label, symbol: source.symbol)
                }
                if let project = conversation.project {
                    ProjectChip(project: project)
                }
            }
            .padding(.top, 1)
        }
    }
}

#Preview {
    NavigationStack { ConversationListView().routeDestinations() }
        .previewEnvironment()
}
