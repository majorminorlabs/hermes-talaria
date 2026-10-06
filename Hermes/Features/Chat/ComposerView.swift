import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

/// Message input. When a run is active, sending steers that run instead of
/// starting a new one; Stop is always one tap away.
struct ComposerView: View {
    @Bindable var model: ConversationModel
    var focus: FocusState<Bool>.Binding

    @Environment(ConnectionStore.self) private var connection
    @Environment(ProfileStore.self) private var profiles
    @Environment(ToastCenter.self) private var toasts
    @Environment(ActivityStore.self) private var activity
    @Environment(AppEnvironment.self) private var environment
    @State private var showingSettings = false
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var showingCamera = false
    @State private var loadingMedia = false
    @State private var dictation = ComposerDictation()
    @State private var dictationBase = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var sendCount = 0

    var body: some View {
        VStack(spacing: 8) {
            contextLine
            if dictation.isRecording { listeningRow }
            if loadingMedia || model.isSending {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(model.isSending ? "Sending…" : "Preparing attachments…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            if !model.attachments.isEmpty {
                attachmentStrip
            }

            HStack(alignment: .bottom, spacing: 8) {
                if connection.supports(.attachments) && model.composerMode == .send {
                    attachMenu
                }

                HStack(alignment: .bottom, spacing: 0) {
                    TextField(placeholder, text: $model.draft, axis: .vertical)
                        .lineLimit(1...6)
                        .focused(focus)
                        .disabled(dictation.isRecording || model.isSending || model.composerMode == .busy || !connection.connection.isConnected)
                        .padding(.leading, 14)
                        .padding(.trailing, model.composerMode == .busy ? 14 : 4)
                        .padding(.vertical, 9)
                        .onSubmit { submit() }
                    if model.composerMode != .busy { micButton }
                }
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(fieldStroke, lineWidth: model.composerMode == .steer || dictation.isRecording ? 1 : 0.5)
                }
                .animation(.snappy, value: dictation.isRecording)

                trailingButton
            }
            if ![.idle,.cancelled].contains(environment.voice.phase) {
                VoiceOverlay(session: environment.voice, send: { words,_ in model.draft = words; if model.composerMode != .clarify { submit() } }, edit: { model.draft = $0; focus.wrappedValue = true }, allowAutoSend: model.composerMode != .clarify && connection.connection.isConnected, targetName: profiles.name(model.configuration.profileID))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
        .sheet(isPresented: $showingSettings) {
            RunSettingsSheet(model: model)
        }
        .photosPicker(isPresented: $showingPhotos, selection: $photoItems, maxSelectionCount: 4, matching: .images)
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): addFiles(urls)
            case .failure: toasts.show(error: HermesError.rejected("File selection could not be completed"))
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraCapture { image in
                showingCamera = false
                guard let image else { return }
                do { try append(ComposerMedia.photo(image)) } catch { toasts.show(error: error) }
            }.ignoresSafeArea()
        }
        .onDisappear { dictation.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { dictation.cancel() } }
        .onChange(of: photoItems) { _, items in
            addPhotos(items)
        }
        .haptic(.impact(weight: .light), trigger: sendCount)
    }

    private var fieldStroke: Color {
        if dictation.isRecording { return Theme.failure.opacity(0.55) }
        if model.composerMode == .steer { return Theme.steering.opacity(0.5) }
        return Theme.hairline.opacity(0.4)
    }

    // MARK: Pieces

    @ViewBuilder private var contextLine: some View {
        if !connection.connection.isConnected {
            Label("\(connection.connection.label(host: connection.activeHost?.name)) · messages can't be sent", systemImage: connection.connection.symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        } else {
            modeLine
        }
    }

    @ViewBuilder private var modeLine: some View {
        switch model.composerMode {
        case .send:
            RunSettingsBar(configuration: model.configuration, isNewConversation: model.conversation == nil) {
                showingSettings = true
            }
        case .clarify:
            VStack(alignment: .leading, spacing: 6) {
                Label(model.pendingApproval?.clarificationQuestion ?? "Reply to Hermes", systemImage: "questionmark.bubble.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.attention)
                    .fixedSize(horizontal: false, vertical: true)
                if let choices = model.pendingApproval?.clarificationChoices, !choices.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(choices, id: \.self) { choice in
                            Button(choice) { model.draft = choice }
                                .font(.footnote)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        case .steer:
            Label("Goes to the current work. Hermes reads it at its next step.", systemImage: "arrow.turn.down.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.steering)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        case .busy:
            if let run = model.activeRun {
                Label(run.state == .waitingForApproval ? "Approve on your Mac" : run.state.label,
                      systemImage: run.state.symbol)
                    .font(.caption)
                    .foregroundStyle(run.state.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            } else {
                Text("Hermes is still settling this thread").font(.footnote).foregroundStyle(.secondary)
                Button("New thread with this ask") { environment.router.askSeed = AskSeed(agentID: model.configuration.profileID, text: model.draft) }
            }
        }
    }

    /// While dictating: what's listening, where recognition runs, and a way out.
    private var listeningRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(Theme.failure)
                .symbolEffect(.variableColor.iterative, isActive: dictation.isRecording)
            Text(dictation.status.isEmpty ? "Listening" : dictation.status)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Cancel") { dictation.cancel(); model.draft = dictationBase }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var micButton: some View {
        Button { toggleDictation() } label: {
            Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic")
                .font(.body.weight(dictation.isRecording ? .semibold : .regular))
                .foregroundStyle(dictation.isRecording ? Theme.failure : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .modifier(PushToTalk(start: { environment.voice.start(capture: false, simulated: environment.simulator != nil) }, move: environment.voice.move, release: environment.voice.release, tap: toggleDictation))
        .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Voice input")
        .disabled(!connection.connection.isConnected || model.isSending || loadingMedia || dictation.isStarting)
    }

    private var attachMenu: some View {
        Menu {
            Button("Capture", systemImage: "tray.and.arrow.down") { environment.router.captureSeed = CaptureSeed() }
            if connection.supports(.imageUpload) { Button("Photo Library", systemImage: "photo.on.rectangle") { showingPhotos = true } }
            Button("Files", systemImage: "folder") { showingFiles = true }
            if connection.supports(.imageUpload) { Button("Camera", systemImage: "camera") {
                Task { await openCamera() }
            } }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(uiColor: .secondarySystemBackground), in: Circle())
        }
        .accessibilityLabel("Add attachment")
        .disabled(model.attachments.count >= 4)
    }

    @ViewBuilder private var trailingButton: some View {
        let hasText = !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.attachments.isEmpty
        if model.activeRun != nil && (!hasText || model.composerMode == .busy) {
            Button(role: .destructive) {
                toasts.perform { try await model.stop() }
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.failure)
                    .frame(width: 44, height: 44)
            }
            .disabled(!(model.activeRun?.canStop ?? false) || !connection.supports(.stop) || !connection.connection.isConnected)
            .accessibilityLabel("Stop run")
        } else if hasText {
            Button(action: submit) {
                Image(systemName: model.composerMode == .steer ? "arrow.turn.down.right.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, model.composerMode == .steer ? Theme.steering : Color.accentColor)
                    .frame(width: 44, height: 44)
            }
            .disabled(!model.canSend || loadingMedia || dictation.isRecording)
            .accessibilityLabel(model.composerMode == .steer ? "Send instruction" : "Send")
        }
    }

    /// Pending attachments: photo thumbnails and file chips, each removable.
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.attachments) { file in
                    if let data = file.data, file.contentType?.hasPrefix("image/") == true, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .topTrailing) { removeButton(file).offset(x: 6, y: -6) }
                            .accessibilityLabel(file.name)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: file.symbol)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name).lineLimit(1).frame(maxWidth: 140, alignment: .leading)
                                Text("\(file.fileExtension.uppercased()) · \(Format.bytes(file.byteCount))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .padding(.leading, 10)
                        .padding(.trailing, 14)
                        .frame(height: 56)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) { removeButton(file).offset(x: 6, y: -6) }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
        }
    }

    private func removeButton(_ file: FileAttachment) -> some View {
        Button {
            model.attachments.removeAll { $0.id == file.id }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color(uiColor: .systemGray))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .accessibilityLabel("Remove \(file.name)")
    }

    private var placeholder: String {
        if !connection.connection.isConnected { return "Not connected to \(connection.activeHost?.name ?? "your Mac")" }
        return switch model.composerMode {
        case .clarify: "Your answer…"
        case .send: "Ask a follow-up…"
        case .steer: "Add an instruction…"
        case .busy: "Hermes is waiting…"
        }
    }

    // MARK: Actions

    private func submit() {
        guard model.canSend, !loadingMedia else { return }
        dictation.cancel()
        sendCount += 1
        let steering = model.composerMode == .steer
        toasts.perform(success: steering ? "Instruction sent" : nil) { try await model.submit() }
    }

    private func append(_ file: FileAttachment) throws {
        guard model.attachments.count < 4 else { throw HermesError.rejected("Attach up to four files per message") }
        model.attachments.append(file)
    }
    private func addPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadingMedia = true
        Task {
            defer { loadingMedia = false; photoItems = [] }
            do {
                for item in items {
                    guard let data = try await item.loadTransferable(type: Data.self), data.count <= 30 * 1024 * 1024,
                          let image = UIImage(data: data) else { throw HermesError.rejected("Choose a smaller readable photo") }
                    try append(ComposerMedia.photo(image))
                }
            } catch { toasts.show(error: error) }
        }
    }
    private func addFiles(_ urls: [URL]) {
        do { for url in urls { try append(ComposerMedia.importFile(url)) } }
        catch { toasts.show(error: error) }
    }
    private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { toasts.show(error: HermesError.rejected("Camera is unavailable on this device")); return }
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        if allowed { showingCamera = true }
        else { toasts.show(error: HermesError.rejected("Enable camera access for Talaria in Settings")) }
    }
    private func toggleDictation() {
        if dictation.isRecording { dictation.stop(); return }
        dictationBase = model.draft
        if environment.simulator != nil && ProcessInfo.processInfo.arguments.contains("-simulateDictation") {
            dictation.simulate("Summarize what Hermes changed on the Studio today") { words in
                model.draft = dictationBase + (dictationBase.isEmpty ? "" : " ") + words
            }
            return
        }
        Task {
            do {
                try await dictation.start { words in
                    model.draft = dictationBase + (dictationBase.isEmpty ? "" : " ") + words
                }
            } catch { dictation.cancel(); toasts.show(error: error) }
        }
    }
}
