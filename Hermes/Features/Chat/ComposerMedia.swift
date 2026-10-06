import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import Speech

@MainActor enum ComposerMedia {
    static let limit = 10 * 1024 * 1024
    static let textExtensions: Set<String> = ["txt","md","markdown","json","csv","tsv","py","swift","js","jsx","ts","tsx","c","h","cpp","hpp","rs","go","java","kt","rb","sh","bash","zsh","css","html","xml","yaml","yml","toml","sql","log"]
    static func file(name: String, data: Data) throws -> FileAttachment {
        guard !data.isEmpty, data.count <= limit else { throw HermesError.rejected("Choose a nonempty file up to 10 MiB") }
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        let mime: String
        switch ext {
        case "png": mime = "image/png"
        case "jpg", "jpeg": mime = "image/jpeg"
        case "webp": mime = "image/webp"
        case "gif": mime = "image/gif"
        case "pdf": mime = "application/pdf"
        case "json": mime = "application/json"
        case "csv": mime = "text/csv"
        case "md", "markdown": mime = "text/markdown"
        default:
            guard textExtensions.contains(ext), String(data: data, encoding: .utf8) != nil else { throw HermesError.rejected("Choose an image, PDF, JSON or UTF-8 text/source file") }
            mime = "text/plain"
        }
        return FileAttachment(id: UUID().uuidString, name: name, byteCount: data.count, fileExtension: ext, path: nil, data: data, contentType: mime)
    }
    static func photo(_ image: UIImage) throws -> FileAttachment {
        // Bound image dimensions before encoding (at most 4096px along the longest edge).
        let scale = min(1, 4096 / max(image.size.width * image.scale, image.size.height * image.scale))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let bytes = rendered.jpegData(compressionQuality: 0.9) else { throw HermesError.rejected("The photo could not be prepared") }
        return try file(name: "Photo-\(UUID().uuidString.prefix(8)).jpg", data: bytes)
    }
    static func importFile(_ url: URL) throws -> FileAttachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= limit else { throw HermesError.rejected("Choose a regular file up to 10 MiB") }
        let handle = try FileHandle(forReadingFrom:url); defer { try? handle.close() }
        return try file(name: url.lastPathComponent, data: handle.read(upToCount:limit + 1) ?? Data())
    }
}

struct CameraCapture: UIViewControllerRepresentable {
    var completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void
        init(_ completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { completion(info[.originalImage] as? UIImage) }
    }
}

@MainActor @Observable final class ComposerDictation {
    private(set) var isRecording = false
    private(set) var isStarting = false
    private(set) var status = ""
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()
    private var tapped = false
    private var onWords: ((String) -> Void)?
    private(set) var audioURL: URL?
    func start(recordAudio: Bool = false, words: @escaping (String) -> Void) async throws {
        guard !isRecording && !isStarting else { return }
        isStarting = true; defer { isStarting = false }
        generation = UUID(); let pending = generation
        let authorization = await Self.speechAuthorization()
        guard authorization == .authorized else { throw HermesError.rejected("Enable Speech Recognition for Talaria in Settings") }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard microphone else { throw HermesError.rejected("Enable microphone access for Talaria in Settings") }
        guard generation == pending, !Task.isCancelled else { return }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else { throw HermesError.rejected("Speech recognition is currently unavailable") }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers]); try session.setActive(true, options: .notifyOthersOnDeactivation)
        let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        status = request.requiresOnDeviceRecognition ? "Listening · on device" : "Listening · Apple network recognition"
        self.request = request; self.onWords = words; generation = UUID(); let current = generation
        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString; let finished = result?.isFinal == true
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                if let text { self.onWords?(text) }
                if finished || error != nil { self.stop(); if error != nil { self.status = "Recognition stopped; your text is editable" } }
            }
        }
        let input = engine.inputNode; let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { stop(); throw HermesError.rejected("Microphone input is unavailable") }
        var recording: AVAudioFile?
        if recordAudio {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            recording = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000])
            audioURL = url
        }
        let sink = SpeechAudioSink(request, recording: recording)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in sink.append(buffer) }; tapped = true
        engine.prepare()
        do { try engine.start(); isRecording = true } catch { stop(); throw HermesError.rejected("Microphone could not start") }
    }
    // Speech/TCC and audio callbacks arrive on framework queues, not MainActor.
    // Explicit Sendable callbacks prevent inherited actor assertions at the boundary.
    nonisolated static func speechAuthorization(
        using request: (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void = { callback in
            SFSpeechRecognizer.requestAuthorization(callback)
        }
    ) async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            request { @Sendable status in continuation.resume(returning: status) }
        }
    }
    /// Simulation/UI testing only: drives the same listening state with
    /// scripted partial results instead of the microphone.
    func simulate(_ phrase: String, words: @escaping (String) -> Void) {
        guard !isRecording && !isStarting else { return }
        generation = UUID(); let current = generation
        status = "Listening · simulated"; onWords = words; isRecording = true
        Task { @MainActor in
            var spoken: [String] = []
            for word in phrase.split(separator: " ") {
                try? await Task.sleep(for: .milliseconds(220))
                guard self.generation == current else { return }
                spoken.append(String(word)); self.onWords?(spoken.joined(separator: " "))
            }
        }
    }
    func finish() async {
        engine.stop(); if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio()
        try? await Task.sleep(for: .seconds(1.5))
        stop()
    }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil
        engine.stop(); if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func cancel() {
        generation = UUID(); stop(); task?.cancel(); task = nil; request = nil; onWords = nil; status = ""
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }; audioURL = nil
    }
}

// The immutable request is shared only for Speech's documented audio-buffer append
// from AVAudioEngine's render callback. UI state remains isolated to MainActor.
nonisolated private final class SpeechAudioSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let recording: AVAudioFile?
    init(_ request: SFSpeechAudioBufferRecognitionRequest, recording: AVAudioFile? = nil) { self.request = request; self.recording = recording }
    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
        guard let recording else { return }
        if buffer.format.channelCount == recording.processingFormat.channelCount { try? recording.write(from: buffer); return }
        guard let converter = AVAudioConverter(from: buffer.format, to: recording.processingFormat),
              let mono = AVAudioPCMBuffer(pcmFormat: recording.processingFormat, frameCapacity: buffer.frameLength) else { return }
        let input = AudioBufferOnce(buffer)
        var error: NSError?
        converter.convert(to: mono, error: &error) { _, status in
            guard let next = input.take() else { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData; return next
        }
        if error == nil { try? recording.write(from: mono) }
    }
}

/// AVAudioConverter's input callback is Sendable; the one-shot flag is locked.
nonisolated private final class AudioBufferOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        let next = buffer; buffer = nil; return next
    }
}
