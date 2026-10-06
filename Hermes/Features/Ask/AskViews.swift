import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AskBar: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        HStack(spacing: 8) {
            Button { environment.router.captureSeed = CaptureSeed() } label: { Image(systemName: "tray.and.arrow.down").frame(width: 44, height: 44) }
                .accessibilityLabel("Capture").accessibilityIdentifier("capture-button").accessibilityAction(named: "Start voice capture") { beginVoice(capture: true) }
                .modifier(PushToTalk(start: { beginVoice(capture: true) }, move: environment.voice.move, release: environment.voice.release, tap: { environment.router.captureSeed = CaptureSeed() }))
            Button { environment.router.askSeed = AskSeed() } label: {
                HStack { Text("Auto").font(.caption); Text(environment.connection.connection.isConnected ? "Ask Hermes…" : "Ask · Offline").lineLimit(1); Spacer(); Image(systemName: "mic") }.frame(minHeight: 44)
            }.buttonStyle(.plain)
                .accessibilityIdentifier("ask-bar").accessibilityLabel("Ask Hermes").accessibilityAction(named: "Start voice ask") { beginVoice(capture: false) }
                .modifier(PushToTalk(start: { beginVoice(capture: false) }, move: environment.voice.move, release: environment.voice.release, tap: { environment.router.askSeed = AskSeed() }))
        }.padding(.horizontal, 8).padding(.vertical, 4)
    }
    private func beginVoice(capture: Bool) {
        environment.voice.start(capture: capture, simulated: environment.simulator != nil)
        if capture { environment.router.heldVoiceCapture = true }
        else { environment.router.heldVoiceAsk = AskSeed(voice: true) }
    }
}
struct RouteChip: View {
    var route: AskRoute
    var pick: () -> Void
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        Button(action: pick) {
            HStack {
                ProfileAvatar(profile: environment.profiles.identity(route.agentID), size: 16)
                Text(route.isAmbiguous ? "\(route.matchedAlias ?? "Agent") ▾ (\(route.candidates.count))" : route.matchedAlias != nil ? "\(environment.profiles.name(route.agentID)) · from your words" : route.agentID == Profile.defaultID ? "Auto · Hermes" : environment.profiles.name(route.agentID))
            }.font(.subheadline).frame(minHeight: 44)
        }.accessibilityIdentifier("ask-route-chip")
            .accessibilityLabel("Sending to \(environment.profiles.name(route.agentID)). Double-tap to change.")
    }
}
struct AgentPicker: View {
    var choose: (String?) -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Button("Auto (Hermes)") { choose(nil); dismiss() }
                ForEach(environment.profiles.sorted) { p in Button { choose(p.id); dismiss() } label: { BotRow(profile: p) }.accessibilityIdentifier("ask-agent-\(p.id)") }
            }.navigationTitle("Send to")
        }.presentationDetents([.medium,.large])
    }
}
struct AskSheet: View {
    var seed: AskSeed
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var target: String?
    @State private var picker = false
    @State private var options = false
    @State private var model: ModelRef?
    @State private var reasoning: ReasoningLevel = .medium
    @State private var project: ProjectContext?
    @State private var media: [LocalMedia] = []
    @State private var sending = false
    @State private var error: String?
    @State private var queuedID: UUID?
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RouteChip(route: route) { picker = true }
                    if !online {
                        Text("Studio is offline. This won't be sent until you send it again.").font(.footnote).foregroundStyle(Theme.secondaryText)
                        Button("Save as Capture instead") { environment.router.askSeed = nil; environment.router.captureSeed = CaptureSeed(text: text) }
                    }
                    if environment.profiles.profile(route.agentID)?.isBotMode == true && !environment.connection.supports(.botThreads) {
                        Text("Continues \(environment.profiles.name(route.agentID))'s canonical thread.").font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    if options { optionsView }
                    TextField("Ask Hermes…", text: $text, axis: .vertical).lineLimit(3...12).focused($focused).disabled(sending)
                        .accessibilityIdentifier("ask-text")
                    MediaPicker(media: $media)
                    if let error { Text(error).font(.footnote).foregroundStyle(Theme.failure) }
                    HStack {
                        Button("Voice input") { environment.voice.start(capture: false, simulated: environment.simulator != nil) }
                            .frame(minWidth: 44, minHeight: 44)
                            .modifier(PushToTalk(start: { environment.voice.start(capture: false, simulated: environment.simulator != nil) }, move: environment.voice.move, release: environment.voice.release, tap: { environment.voice.start(capture: false, simulated: environment.simulator != nil) }))
                        Spacer()
                        if sending { ProgressView("Sending…") }
                        else { Button(online ? "Send" : "Save to Outbox", action: submit).buttonStyle(.borderedProminent).accessibilityIdentifier("ask-send").disabled((text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && media.isEmpty) || route.isAmbiguous) }
                    }.frame(minHeight: 44)
                    if ![.idle,.cancelled].contains(environment.voice.phase) {
                        VoiceOverlay(session: environment.voice, send: { value,_ in text = value; submit() }, edit: { text = $0; focused = true }, allowAutoSend: !route.isAmbiguous && online, targetName: environment.profiles.name(route.agentID))
                    }
                }.padding()
            }.navigationTitle("Ask").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(sending) }; ToolbarItem(placement: .topBarTrailing) { Button("Options") { options.toggle() } } }
        }.presentationDetents(seed.voice ? [.large] : [.medium,.large])
            .sheet(isPresented: $picker) { AgentPicker { id in rememberAlias(id); target = id } }
            .onAppear { target = seed.agentID; model = seed.model; reasoning = environment.preferences.defaultReasoning; text = seed.text.isEmpty ? environment.drafts.draft(for: "ask.\(seed.agentID ?? "auto")") : seed.text; focused = !seed.voice; if seed.voice && environment.voice.phase == .idle { environment.voice.start(capture: false, simulated: environment.simulator != nil) } }
            .onChange(of: text) { environment.drafts.setDraft(text, for: "ask.\(target ?? "auto")") }
            .onDisappear { environment.voice.reset() }
    }
    private var online: Bool { environment.connection.connection.isConnected }
    private var route: AskRoute {
        AskRouter.resolve(text: [.listening,.locked,.transcribing,.review].contains(environment.voice.phase) && !environment.voice.transcript.isEmpty ? environment.voice.transcript : text, explicit: target, agents: environment.profiles.sorted,
            aliasChoices: environment.preferences.defaults.dictionary(forKey: "vnext.alias.\(environment.connection.activeHostID)") as? [String:String] ?? [:])
    }
    private func rememberAlias(_ id: String?) {
        guard let alias = route.matchedAlias, let id else { return }
        let key = "vnext.alias.\(environment.connection.activeHostID)"
        var choices = environment.preferences.defaults.dictionary(forKey: key) as? [String:String] ?? [:]
        choices[alias] = id; environment.preferences.defaults.set(choices, forKey: key)
    }
    private var optionsView: some View {
        VStack {
            Picker("Model · next ask only", selection: $model) {
                Text("Agent default").tag(nil as ModelRef?)
                if !environment.preferences.recentModels.isEmpty { Section("Recent") { ForEach(environment.preferences.recentModels.filter { environment.connection.runOptions.models.contains($0) }) { Text($0.detailedLabel).tag(Optional($0)) } } }
                ForEach(environment.connection.runOptions.models) { Text($0.detailedLabel).tag(Optional($0)) }
            }.accessibilityIdentifier("scope-next-ask")
            if model?.supportsReasoning == true {
                Picker("Reasoning", selection: $reasoning) { ForEach(environment.connection.runOptions.reasoningLevels) { Text($0.label).tag($0) } }
            }
            if !environment.connection.runOptions.projects.isEmpty {
                Picker("Project", selection: $project) { Text("None").tag(nil as ProjectContext?); ForEach(environment.connection.runOptions.projects) { Text($0.name).tag(Optional($0)) } }
            }
        }.font(.subheadline)
    }
    private func submit() {
        guard !sending, !route.isAmbiguous else { return }
        sending = true; error = nil
        environment.preferences.rememberModel(model)
        let config = RunConfiguration(profileID: route.agentID, model: model, reasoning: reasoning, hostID: environment.connection.activeHostID, project: project)
        Task {
            do {
                let id: UUID
                if let queuedID { id = queuedID }
                else { let ask = OutboxAsk(hostID: config.hostID, text: text, configuration: config, media: media); try environment.outbox.enqueue(ask); id = ask.id; queuedID = id }
                if environment.connection.connection == .connecting {
                    for _ in 0..<10 where !online { try await Task.sleep(for: .milliseconds(500)) }
                }
                if online {
                    let conversation = try await environment.outbox.sendAsk(id, environment: environment)
                    environment.drafts.setDraft("", for: "ask.\(target ?? "auto")")
                    UIAccessibility.post(notification: .announcement, argument: "Sent to \(environment.profiles.name(config.profileID))")
                    environment.toasts.show("Handed to \(environment.profiles.name(config.profileID))", actionTitle: "Open") { environment.router.open(.thread(conversation)) }
                } else { environment.toasts.show("Ask saved to Outbox", symbol: "tray") }
                dismiss()
            } catch {
                if environment.outbox.asks.first(where: { $0.id == queuedID })?.state == .uncertain { environment.toasts.show("Not sure this was sent. Check Outbox.", symbol: "questionmark.circle"); dismiss() }
                else { self.error = error.localizedDescription }
            }
            sending = false
        }
    }
}
struct MediaPicker: View {
    @Binding var media: [LocalMedia]
    @State private var photos = false
    @State private var files = false
    @State private var camera = false
    @State private var selected: [PhotosPickerItem] = []
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Menu("Add attachment", systemImage: "plus") {
                    Button("Files") { files = true }
                    Button("Photos") { photos = true }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Camera") { camera = true } }
                }.frame(minWidth: 44, minHeight: 44).disabled(media.count >= 4)
                ForEach(media) { file in Button(file.name) { media.removeAll { $0.id == file.id } }.font(.caption).lineLimit(1) }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.failure) }
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            do { for url in try result.get() { try append(ComposerMedia.importFile(url)) } } catch { self.error = error.localizedDescription }
        }
        .photosPicker(isPresented: $photos, selection: $selected, maxSelectionCount: max(1,4-media.count), matching: .images)
        .onChange(of: selected) { _, items in Task { for item in items { do { if let bytes = try await item.loadTransferable(type: Data.self), let image = UIImage(data: bytes) { try append(ComposerMedia.photo(image)) } } catch { self.error = error.localizedDescription } }; selected = [] } }
        .sheet(isPresented: $camera) { CameraCapture { image in camera = false; if let image { do { try append(ComposerMedia.photo(image)) } catch { self.error = error.localizedDescription } } } }
    }
    private func append(_ file: FileAttachment) throws {
        guard media.count < 4, let data = file.data else { throw HermesError.rejected("Choose at most four attachments") }
        media.append(LocalMedia(name: file.name, contentType: file.contentType ?? "application/octet-stream", data: data))
    }
}
