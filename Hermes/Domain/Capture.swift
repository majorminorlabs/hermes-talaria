import Foundation

nonisolated struct LocalMedia: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var contentType: String
    private var bytes: Data
    var localPath: String?
    var data: Data { localPath.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) } ?? bytes }
    init(id: UUID = UUID(), name: String, contentType: String, data: Data, uploadID: String? = nil) {
        self.id = id; self.name = name; self.contentType = contentType; bytes = data; self.uploadID = uploadID
    }
    mutating func persist(in directory: URL) throws {
        guard localPath == nil else { return }
        let path = directory.appendingPathComponent(id.uuidString)
        try bytes.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        localPath = path.path; bytes = Data()
    }
    var uploadID: String?
}
nonisolated enum CaptureKind: String, Codable, CaseIterable, Sendable { case note, idea, task, link, photo, file, voice }
nonisolated enum QueueState: String, Codable, Sendable { case queued, sending, confirmed, failed, uncertain }
nonisolated struct CaptureRecord: Identifiable, Codable, Sendable {
    var id = UUID()
    var hostID: String
    var createdAt = Date()
    var kind: CaptureKind
    var text: String
    var media: [LocalMedia] = []
    var context: [String: String] = [:]
    var state: QueueState = .queued
    var bridgeID: String?
    var error: String?
}
nonisolated struct OutboxAsk: Identifiable, Codable, Sendable {
    var id = UUID()
    var hostID: String
    var createdAt = Date()
    var text: String
    var configuration: RunConfiguration
    var media: [LocalMedia] = []
    var state: QueueState = .queued
    var createCommandID = UUID()
    var sendCommandID = UUID()
    var conversationID: String?
    var error: String?
}
protocol CaptureService: AnyObject, Sendable {
    func uploadCaptureMedia(_ media: LocalMedia) async throws -> String
    func saveCapture(_ capture: CaptureRecord) async throws -> String
}

nonisolated enum CommandObservation: Sendable {
    case notReceived, pending, conversation(Conversation), run(Run), rejected(String)
}
