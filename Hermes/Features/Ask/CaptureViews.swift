import SwiftUI

struct CaptureSheet: View {
    var seed: CaptureSeed
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var kind: CaptureKind = .note
    @State private var media: [LocalMedia] = []
    @State private var contextOpen = false
    @State private var thread = ""
    @State private var agent = ""
    @State private var tag = ""
    @State private var error: String?
    @State private var saving = false
    @State private var discarding = false
    @State private var onDevice = false
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Keep exactly this…", text: $text, axis: .vertical).lineLimit(3...12).focused($focused).accessibilityIdentifier("capture-text") }
                Section {
                    MediaPicker(media: $media)
                    Button("Paste link") { if let link = UIPasteboard.general.string { text += link; kind = .link } }
                    Picker("Kind", selection: $kind) { ForEach(CaptureKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    Button("Voice input") { environment.voice.start(capture: true, simulated: environment.simulator != nil) }
                    if ![.idle,.cancelled].contains(environment.voice.phase) {
                        VoiceOverlay(session: environment.voice, send: { value,audio in text = value; kind = .voice; onDevice = environment.voice.transcribedOnDevice; if let audio, media.count < 4 { media.append(audio) }; save() }, edit: { text = $0; kind = .voice; onDevice = environment.voice.transcribedOnDevice; if let audio = environment.voice.audio, media.count < 4 { media.append(audio) }; focused = true }, allowAutoSend: false)
                    }
                }
                DisclosureGroup("Add context", isExpanded: $contextOpen) {
                    Picker("Thread", selection: $thread) { Text("None").tag(""); ForEach(environment.work.items) { Text($0.title).tag($0.id) } }
                    Picker("Agent", selection: $agent) { Text("None").tag(""); ForEach(environment.profiles.sorted) { Text($0.name).tag($0.id) } }
                    TextField("Tag", text: $tag)
                }
                Section {
                    Text("Saved exactly as written. Hermes won't act on it unless you ask.").font(.footnote).foregroundStyle(Theme.secondaryText)
                    if let error { Text(error).foregroundStyle(Theme.failure) }
                }
            }.navigationTitle("Capture").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { if !text.isEmpty || !media.isEmpty { discarding = true } else { dismiss() } } }; ToolbarItem(placement: .topBarTrailing) { Button("Save", action: save).accessibilityIdentifier("capture-save").disabled(saving || text.isEmpty && media.isEmpty) } }
        }.presentationDetents(seed.voice ? [.large] : [.medium,.large])
            .interactiveDismissDisabled(!text.isEmpty || !media.isEmpty || environment.voice.phase == .listening || environment.voice.phase == .locked)
            .confirmationDialog("Discard this capture?", isPresented: $discarding, titleVisibility: .visible) { Button("Discard", role: .destructive) { environment.drafts.setDraft("", for: "capture.\(environment.connection.activeHostID)"); dismiss() }; Button("Keep editing", role: .cancel) {} }
            .onAppear { text = seed.text.isEmpty ? environment.drafts.draft(for: "capture.\(environment.connection.activeHostID)") : seed.text; focused = !seed.voice; if seed.voice && environment.voice.phase == .idle { environment.voice.start(capture: true, simulated: environment.simulator != nil) } }
            .onChange(of: text) { environment.drafts.setDraft(text, for: "capture.\(environment.connection.activeHostID)") }
            .onDisappear { environment.voice.reset() }
    }
    private func save() {
        guard !saving else { return }; saving = true
        do {
            var context: [String:String] = [:]
            if !thread.isEmpty { context["thread_id"] = thread }; if !agent.isEmpty { context["agent_id"] = agent }; if !tag.isEmpty { context["tag"] = tag }
            if kind == .voice { context["transcribed_on_device"] = onDevice ? "true" : "false" }
            let inferred: CaptureKind = kind != .note ? kind : text.isEmpty && !media.isEmpty ? (media.first!.contentType.hasPrefix("image/") ? .photo : .file) : URL(string: text)?.scheme.map { ["https","http"].contains($0) } == true && !text.contains("\n") ? .link : .note
            let capture = CaptureRecord(hostID: environment.connection.activeHostID, kind: inferred, text: text, media: media, context: context)
            try environment.outbox.enqueue(capture)
            environment.drafts.setDraft("", for: "capture.\(environment.connection.activeHostID)")
            environment.toasts.show("Saved on iPhone", symbol: "tray.and.arrow.down")
            Task {
                await environment.outbox.syncCaptures(environment: environment)
                if environment.outbox.captures.first(where: { $0.id == capture.id })?.state == .confirmed && environment.toasts.current?.message == "Saved on iPhone" { environment.toasts.show("Saved to Hermes") }
            }
            dismiss()
        } catch { self.error = error.localizedDescription; saving = false }
    }
}
struct OutboxView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        List {
            if let error = environment.outbox.loadError { Text(error).foregroundStyle(Theme.failure) }
            Section("Asks · Send now requires your tap") {
                ForEach(environment.outbox.asks.filter { $0.hostID == environment.connection.activeHostID && $0.state != .confirmed }) { ask in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ask.text).lineLimit(3)
                        Text("\(environment.profiles.name(ask.configuration.profileID)) · \(ask.createdAt.formatted())").font(.caption).foregroundStyle(Theme.secondaryText)
                        if ask.state == .uncertain {
                            Text("Not sure this was sent. Check before resending.").font(.footnote)
                            Button("Check") { environment.toasts.perform { try await environment.outbox.checkAsk(ask.id, environment: environment); await environment.refreshAll() } }
                            if let id = ask.conversationID { NavigationLink("Open thread", value: Route.thread(id)) }
                        } else { Button("Send now") { environment.toasts.perform { _ = try await environment.outbox.sendAsk(ask.id, environment: environment) } }.disabled(!environment.connection.connection.isConnected || ask.state == .sending) }
                        if let error = ask.error { Text(error).font(.footnote).foregroundStyle(Theme.secondaryText) }
                    }.accessibilityIdentifier("outbox-row-\(ask.id.uuidString)")
                        .swipeActions { Button("Delete", role: .destructive) { environment.toasts.perform { try environment.outbox.deleteAsk(ask.id) } } }
                }
            }
            Section("Saved in the last 24 hours") {
                ForEach(environment.outbox.captures.filter { $0.hostID == environment.connection.activeHostID && $0.state == .confirmed && $0.createdAt > .now.addingTimeInterval(-86400) }) { capture in
                    NavigationLink { CaptureDetailView(capture: capture) } label: { Label(capture.text.isEmpty ? capture.kind.rawValue.capitalized : String(capture.text.prefix(120)), systemImage: "checkmark") }
                }
            }
            Section("Captures") {
                ForEach(environment.outbox.captures.filter { $0.hostID == environment.connection.activeHostID && $0.state != .confirmed }) { capture in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(capture.text).lineLimit(3)
                        Text(capture.state == .sending ? "Sending…" : "Saved on iPhone · waiting for Studio").font(.footnote).foregroundStyle(Theme.secondaryText)
                        if let error = capture.error { Text("Not saved: \(error)").font(.footnote); Button("Retry") { Task { await environment.outbox.syncCaptures(environment: environment) } } }
                    }.accessibilityIdentifier("outbox-row-\(capture.id.uuidString)")
                        .swipeActions { Button("Delete", role: .destructive) { environment.toasts.perform { try environment.outbox.deleteCapture(capture.id) } } }
                }
            }
        }.navigationTitle("Outbox")
    }
}

struct CaptureDetailView: View {
    let capture: CaptureRecord
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        List {
            Text(capture.text).textSelection(.enabled)
            ForEach(capture.media) { media in Label(media.name, systemImage: media.contentType == "audio/mp4" ? "waveform" : "paperclip") }
            LabeledContent("Status", value: capture.state == .confirmed ? "Saved to Hermes" : "Saved on iPhone")
            LabeledContent("Captured", value: capture.createdAt.formatted())
            if let bridgeID = capture.bridgeID { Text(bridgeID).font(.caption.monospaced()).textSelection(.enabled) }
            Button("Ask about this") { environment.router.askSeed = AskSeed(text: capture.text) }
        }.navigationTitle("Capture")
    }
}
