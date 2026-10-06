import SwiftUI

@Observable final class VoiceSession {
    enum Phase: Equatable { case idle, arming, listening, locked, transcribing, review, cancelled, failed }
    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var error: String?
    private(set) var transcribedOnDevice = false
    private(set) var audio: LocalMedia?
    private var lockRequested = false
    private var startedAt: Date?
    private var token = UUID()
    let dictation = ComposerDictation()
    var isCapture = false
    var secondsRemaining: Int { max(0, 60 - Int(startedAt.map { Date.now.timeIntervalSince($0) } ?? 0)) }
    var canAutoSend: Bool { phase == .review && !isCapture && !transcript.isEmpty }
    func start(capture: Bool, simulated: Bool) {
        cancel(); isCapture = capture; transcript = ""; error = nil; audio = nil; phase = .arming
        let generation = UUID(); token = generation
        Task {
            guard token == generation else { return }
            do {
                if simulated { dictation.simulate(capture ? "Keep this note exactly as spoken" : "Summarize the current work") { self.transcript = $0 } }
                else { try await dictation.start(recordAudio: capture) { self.transcript = $0 } }
                guard token == generation, dictation.isRecording else { return }
                transcribedOnDevice = dictation.status.contains("on device")
                phase = lockRequested ? .locked : .listening; startedAt = .now
                UIAccessibility.post(notification: .announcement, argument: "Listening")
                try? await Task.sleep(for: .seconds(60))
                if token == generation && (phase == .listening || phase == .locked) { finish() }
            } catch { guard token == generation else { return }; self.error = error.localizedDescription; phase = .failed }
        }
    }
    func move(x: CGFloat, y: CGFloat) {
        guard phase == .listening || phase == .locked || phase == .arming else { return }
        if x <= -80 { cancel() }
        else if y >= 60 { lockRequested = true; if phase == .listening { phase = .locked } }
    }
    func release() { if phase != .locked && !(phase == .arming && lockRequested) { finish() } }
    func finish() {
        guard phase == .listening || phase == .locked else { if phase == .arming { cancel() }; return }
        let duration = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        let generation = token; phase = .transcribing
        Task {
            await dictation.finish()
            guard generation == token else { return }
            if duration < 0.5 || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = "Didn't catch that"; phase = .failed; return }
            if isCapture, let url = dictation.audioURL, let data = try? Data(contentsOf: url) {
                audio = LocalMedia(name: "Voice.m4a", contentType: "audio/mp4", data: data)
            }
            phase = .review
        }
    }
    func cancel() { lockRequested = false; token = UUID(); dictation.cancel(); transcript = ""; audio = nil; phase = .cancelled }
    func reset() { cancel(); phase = .idle }
}
struct PushToTalk: ViewModifier {
    var start: () -> Void
    var move: (CGFloat, CGFloat) -> Void
    var release: () -> Void
    var tap: () -> Void
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.allowsHitTesting(false).overlay {
            PressSurface(enabled: enabled, start: start, move: move, release: release, tap: tap)
                .accessibilityHidden(true)
        }.accessibilityAction { if enabled { tap() } }
    }
}

/// A native recognizer keeps touch timing and cancellation stable across SwiftUI
/// updates in the system tab accessory. Tap waits for the hold to fail.
private struct PressSurface: UIViewRepresentable {
    var enabled: Bool
    var start: () -> Void
    var move: (CGFloat, CGFloat) -> Void
    var release: () -> Void
    var tap: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.backgroundColor = .clear
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.delegate = context.coordinator
        hold.minimumPressDuration = 0.25; hold.allowableMovement = .greatestFiniteMagnitude
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: hold)
        view.addGestureRecognizer(hold); view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self; view.isUserInteractionEnabled = enabled
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PressSurface
        var origin = CGPoint.zero
        var holding = false
        var touch: UITouch?
        var touchBeganAt: TimeInterval = 0
        init(_ parent: PressSurface) { self.parent = parent }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { // Measure from finger-down, even if a surrounding recognizer delays the hold.
            self.touch = touch; touchBeganAt = touch.timestamp; origin = touch.location(in: nil); return true }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
        @objc func tap(_ recognizer: UITapGestureRecognizer) { if parent.enabled { parent.tap() } }
        @objc func hold(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: nil)
            switch recognizer.state {
            case .began: holding = true; parent.start(); parent.move(point.x - origin.x, point.y - origin.y)
            case .changed: parent.move(point.x - origin.x, point.y - origin.y)
            case .ended:
                holding = false
                // A delayed recognizer can begin during a short tap; use event time.
                let duration = (touch?.timestamp ?? touchBeganAt) - touchBeganAt
                if duration < recognizer.minimumPressDuration {
                    parent.move(-1000, 0); parent.tap()
                } else { parent.move(point.x - origin.x, point.y - origin.y); parent.release() }
                touch = nil
            case .cancelled: if holding { holding = false; parent.move(-1000, 0) }; touch = nil
            default: break
            }
        }
    }
}
struct VoiceOverlay: View {
    @Bindable var session: VoiceSession
    var send: (String, LocalMedia?) -> Void
    var edit: (String) -> Void
    var allowAutoSend = true
    var targetName = "Hermes"
    var sendOnStop = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reviewProgress = 0.0
    @Environment(AppEnvironment.self) private var environment
    @State private var reviewToken = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(session.isCapture ? "Capturing · word for word" : "Asking \(targetName)", systemImage: session.isCapture ? "tray.and.arrow.down" : "bubble.left")
            Text(session.transcript.isEmpty ? status : session.transcript).font(session.isCapture ? .body : .title3)
            if session.phase == .listening || session.phase == .locked {
                TimelineView(.periodic(from: .now, by: 1)) { _ in Text("\(session.secondsRemaining)s remaining").font(.caption).foregroundStyle(Theme.secondaryText) }
                Text(session.dictation.status).font(.footnote).foregroundStyle(Theme.secondaryText)
                Label(session.phase == .locked ? "Locked" : "Slide down to lock · slide left to cancel", systemImage: session.phase == .locked ? "lock.fill" : "waveform")
                if sendOnStop {
                    Button("Send") { session.finish() }.buttonStyle(.borderedProminent)
                        .frame(minHeight: 44).accessibilityIdentifier("held-voice-send")
                } else {
                    Button("Stop dictation") { session.finish() }.frame(minHeight: 44)
                }
            }
            if session.phase == .review {
                Button(session.isCapture ? "Save" : "Send") { finish() }.overlay { Circle().trim(from: 0, to: reviewProgress).stroke(.tint, lineWidth: 2).allowsHitTesting(false) }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                Button("Edit") { reviewToken = UUID(); edit(session.transcript); session.reset() }.frame(minHeight: 44)
                if session.canAutoSend && allowAutoSend && !environment.preferences.reviewVoiceBeforeSending { Text("Sending after 1.5-second review…").font(.footnote) }
            }
            if let error = session.error { Text(error).foregroundStyle(Theme.failure); Button(session.error == "Didn't catch that" ? "Try again" : "Open Settings") { if session.error == "Didn't catch that" { session.start(capture: session.isCapture, simulated: environment.simulator != nil) } else if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
            Button("Cancel") { reviewToken = UUID(); session.cancel() }.frame(minHeight: 44)
        }.padding().background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(session.isCapture ? Color.primary.opacity(0.2) : Color.accentColor, lineWidth: 1) }
        .haptic(.impact(weight: .medium), trigger: session.phase == .listening)
        .haptic(.impact(weight: .light), trigger: session.phase == .locked)
        .haptic(.impact(flexibility: .soft), trigger: session.phase == .cancelled)
        .task(id: session.phase) {
            let phase = session.phase
            reviewToken = UUID(); reviewProgress = 0
            if phase == .review && session.canAutoSend && allowAutoSend && !environment.preferences.reviewVoiceBeforeSending {
                withAnimation(reduceMotion ? nil : .linear(duration: 1.5)) { reviewProgress = 1 }
                let token = reviewToken
                Task { try? await Task.sleep(for: .seconds(1.5)); if token == reviewToken && session.phase == .review { finish() } }
            }
        }
        .onChange(of: session.dictation.isRecording) { _, recording in if !recording && [.listening,.locked].contains(session.phase) { session.finish() } }
        .onDisappear { reviewToken = UUID() }
    }
    private var status: String { switch session.phase { case .arming: "Starting microphone…"; case .transcribing: "Finishing…"; case .failed: "Didn't catch that"; case .listening, .locked: "Listening"; default: "Ready for voice input" } }
    private func finish() { let text = session.transcript, audio = session.audio; reviewToken = UUID(); session.reset(); send(text,audio) }
}
