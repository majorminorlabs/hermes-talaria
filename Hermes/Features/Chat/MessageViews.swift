import SwiftUI
import UIKit

/// One message in a conversation.
struct MessageView: View {
    var message: Message
    var isLatestAssistant: Bool
    var onSteer: () -> Void
    var onShowDetails: (Run) -> Void

    @Environment(ActivityStore.self) private var activity
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        switch message.role {
        case .user:
            UserMessageView(message: message)
        case .assistant:
            assistant
        case .system:
            ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
                if case .event(let event) = part { SystemEventView(event: event) }
            }
        }
    }

    @ViewBuilder
    private var assistant: some View {
        let run = activity.run(message.runID)
        let isLive = run?.state.isActive == true
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
                partView(part, isLive: isLive)
            }
            if isLive, let run {
                RunCard(run: run, onSteer: onSteer)
            }
            if !isLive && message.status != .streaming,
               let run, environment.conversations.transcripts[message.conversationID]?.last(where: { $0.role == .assistant && $0.runID == run.id })?.id == message.id {
                ResultFooter(run: run)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.plainText }
            ShareLink(item: message.plainText)
            Button("Capture This Result") { environment.router.captureSeed = CaptureSeed(text: message.plainText) }
            Button("New thread with this agent") { environment.router.askSeed = AskSeed(agentID: environment.conversations.conversations[message.conversationID]?.profileID) }
            Button("Ask another agent…") { environment.router.askSeed = AskSeed(text: message.plainText) }
            if let run, !isLive {
                Button("Steps", systemImage: "info.circle") { onShowDetails(run) }
            }
        }
    }

    @ViewBuilder
    private func partView(_ part: MessagePart, isLive: Bool) -> some View {
        switch part {
        case .markdown(let text):
            if !text.isEmpty { MarkdownView(text: text) }
        case .tools(let calls):
            if !isLive && !calls.isEmpty { ToolActivityView(calls: calls) }
        case .image(let image):
            ImageAttachmentView(image: image)
        case .file(let file):
            FileAttachmentView(file: file)
        case .error(let error):
            MessageErrorView(error: error, runID: message.runID)
        case .event(let event):
            if !isLive { SystemEventView(event: event) }
        }
    }
}

struct UserMessageView: View {
    var message: Message

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if message.isSteering {
                Label("Instruction to running task", systemImage: "arrow.turn.down.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.steering)
            }
            ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .markdown(let text):
                    Text(InlineMarkdown.render(text))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(message.isSteering ? Theme.steering.opacity(0.12) : Theme.userBubble,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .textSelection(.enabled)
                case .file(let file):
                    FileAttachmentView(file: file)
                case .image(let image):
                    ImageAttachmentView(image: image).frame(maxWidth: 220)
                default:
                    EmptyView()
                }
            }
            if message.status == .failed {
                Label("Not delivered", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.failure)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.plainText }
        }
    }
}

struct SystemEventView: View {
    var event: SystemEvent

    var body: some View {
        Label(event.text, systemImage: event.symbol)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: event.symbol == "arrow.turn.down.right" ? .leading : .center)
            .padding(.vertical, 2)
    }
}

struct MessageErrorView: View {
    var error: MessageError
    var runID: String?

    @Environment(ActivityStore.self) private var activity
    @Environment(ConnectionStore.self) private var connection
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FailureCallout(explanation: explanation)
            if runID.flatMap({ activity.run($0) })?.canRetry == true { Text("Earlier effects may already have happened. Check them before retrying.").font(.footnote).foregroundStyle(Theme.secondaryText) }
            if error.isRetryable, let runID, activity.run(runID)?.canRetry == true, connection.supports(.runs) {
                Button {
                    toasts.perform(success: "Retrying") { try await activity.retry(runID) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!connection.connection.isConnected)
            }
        }
        .panel(tint: Theme.failure, padding: 12, cornerRadius: 12)
    }

    /// Raw reasons become words; Hermes's own sentences pass through.
    private var explanation: StatusCopy.Explanation {
        guard let detail = error.detail, StatusCopy.isRawCode(detail) else {
            return StatusCopy.Explanation(title: StatusCopy.isRawCode(error.title) ? "Run failed" : error.title, message: error.detail)
        }
        var copy = StatusCopy.runFailure(detail)
        if !StatusCopy.isRawCode(error.title) { copy.title = error.title }
        return copy
    }
}

/// Subtle actions under the latest reply. Telemetry lives behind "Details".
struct MessageFooter: View {
    var message: Message
    var run: Run?
    var onShowDetails: (Run) -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 18) {
            Button {
                UIPasteboard.general.string = message.plainText
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel("Copy")
            ShareLink(item: message.plainText) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share")
            if let run {
                Button { onShowDetails(run) } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Run details")
            }
            Spacer()
            Text(Calendar.current.isDateInToday(message.createdAt) ? Format.clock(message.createdAt) : Format.timestamp(message.createdAt))
                .font(.caption)
        }
        .font(.footnote)
        .foregroundStyle(.tertiary)
        .buttonStyle(.borderless)
        .haptic(.success, trigger: copied)
    }
}

// MARK: - Attachments

struct ImageAttachmentView: View {
    var image: ImageAttachment
    @State private var presented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { presented = true } label: {
                imageContent
                    .aspectRatio(image.aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(image.caption ?? image.name)
            if let caption = image.caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .fullScreenCover(isPresented: $presented) {
            NavigationStack {
                imageContent
                    .aspectRatio(image.aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                    .navigationTitle(image.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { presented = false }
                        }
                    }
            }
        }
    }

    @ViewBuilder private var imageContent: some View {
        switch image.source {
        case .asset(let name):
            Image(name).resizable()
        case .remote(let url):
            AsyncImage(url: url) { phase in
                if let loaded = phase.image { loaded.resizable() } else { Color(uiColor: .secondarySystemFill) }
            }
        case .data(let data):
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable()
            } else {
                Color(uiColor: .secondarySystemFill)
            }
        }
    }
}

struct FileAttachmentView: View {
    var file: FileAttachment

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text("\(file.fileExtension.uppercased()) · \(Format.bytes(file.byteCount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: 280, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            if let path = file.path {
                Button("Copy Path", systemImage: "doc.on.doc") { UIPasteboard.general.string = path }
            }
        }
    }
}

// MARK: - Run details sheet

/// Telemetry for a completed reply, kept out of the transcript.
struct RunSummarySheet: View {
    var run: Run

    @Environment(ProfileStore.self) private var profiles
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    KeyValueRow(label: "Elapsed", value: Format.elapsed(run.elapsed()))
                    if let model = run.model { KeyValueRow(label: "Model", value: model.detailedLabel) }
                    KeyValueRow(label: "Profile", value: profiles.name(run.profileID))
                    KeyValueRow(label: "Outcome", value: run.state.label)
                }
                if let usage = run.usage, usage.total > 0 {
                    Section {
                        KeyValueRow(label: "Input", value: Format.tokens(usage.input))
                        KeyValueRow(label: "Output", value: Format.tokens(usage.output))
                        if usage.reasoning > 0 { KeyValueRow(label: "Reasoning", value: Format.tokens(usage.reasoning)) }
                    } header: {
                        SectionHeader("Tokens")
                    }
                }
                if !run.toolsUsed.isEmpty {
                    Section {
                        ForEach(run.toolsUsed, id: \.0) { kind, count in
                            LabeledContent {
                                Text("\(count)")
                            } label: {
                                Label(kind.label, systemImage: kind.symbol)
                            }
                        }
                    } header: {
                        SectionHeader("Tools Used")
                    }
                }
                Section {
                    Button("Open Full Run Detail") {
                        dismiss()
                        router.open(.run(run.id))
                    }
                }
            }
            .navigationTitle("Response Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
