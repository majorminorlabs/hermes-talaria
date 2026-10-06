import Foundation

/// Durable content lives outside the snapshot cache. Never silently discard on
/// write failure, and never execute queued Asks from a reconnect callback.
@Observable final class OutboxStore {
    private let directory: URL
    private(set) var asks: [OutboxAsk] = []
    private(set) var captures: [CaptureRecord] = []
    private var syncing = false
    private(set) var loadError: String?
    init(directory: URL) {
        self.directory = directory
        do {
            let askFile = directory.appendingPathComponent("asks.json"), captureFile = directory.appendingPathComponent("captures.json")
            if FileManager.default.fileExists(atPath: askFile.path) { asks = try JSONDecoder().decode([OutboxAsk].self, from: Data(contentsOf: askFile)) }
            if FileManager.default.fileExists(atPath: captureFile.path) { captures = try JSONDecoder().decode([CaptureRecord].self, from: Data(contentsOf: captureFile)) }
        } catch { loadError = "Outbox could not be read. Your saved files have been kept; no new writes will overwrite them." }
        // A process death while sending an Ask has an uncertain outcome.
        for i in asks.indices where asks[i].state == .sending { asks[i].state = .uncertain }
        for i in captures.indices where captures[i].state == .sending { captures[i].state = .queued }
    }
    func hasPending(host: String) -> Bool { asks.contains { $0.hostID == host && $0.state != .confirmed } || captures.contains { $0.hostID == host && $0.state != .confirmed } }
    func summary(host: String) -> String {
        let a = asks.filter { $0.hostID == host && $0.state != .confirmed }, c = captures.filter { $0.hostID == host && $0.state != .confirmed }
        return "\(c.count) captures waiting · \(a.filter { $0.state != .uncertain }.count) asks not sent · \(a.filter { $0.state == .uncertain }.count) uncertain"
    }
    func enqueue(_ incoming: OutboxAsk) throws { var ask = incoming; try persist(&ask.media); var next = asks; next.append(ask); try write(next, name: "asks"); asks = next }
    func enqueue(_ incoming: CaptureRecord) throws { var capture = incoming; try persist(&capture.media); var next = captures; next.append(capture); try write(next, name: "captures"); captures = next }
    func update(_ ask: OutboxAsk) throws { var next = asks; if let i = next.firstIndex(where: { $0.id == ask.id }) { next[i] = ask }; try write(next, name: "asks"); asks = next }
    func update(_ capture: CaptureRecord) throws { var next = captures; if let i = next.firstIndex(where: { $0.id == capture.id }) { next[i] = capture }; try write(next, name: "captures"); captures = next }
    func deleteAsk(_ id: UUID) throws { let next = asks.filter { $0.id != id }; try write(next, name: "asks"); asks = next }
    func deleteCapture(_ id: UUID) throws { let next = captures.filter { $0.id != id }; try write(next, name: "captures"); captures = next }
    private func persist(_ media: inout [LocalMedia]) throws {
        let folder = directory.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for i in media.indices { try media[i].persist(in: folder) }
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        guard loadError == nil else { throw HermesError.rejected(loadError!) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(name + ".json")
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    /// Only called by an explicit user Send action. Receipts remain durable even
    /// if the sheet closes or the phone backgrounds during acceptance.
    func sendAsk(_ id: UUID, environment: AppEnvironment) async throws -> String {
        guard var ask = asks.first(where: { $0.id == id }), ask.hostID == environment.connection.activeHostID,
              [.queued,.failed].contains(ask.state) else { throw HermesError.rejected("Check the uncertain command before sending again.") }
        ask.state = .sending; ask.error = nil; try update(ask)
        do {
            if ask.conversationID == nil {
                let c = try await environment.client.conversations.createConversation(configuration: ask.configuration, commandID: ask.createCommandID)
                ask.conversationID = c.id; try update(ask)
                environment.conversations.apply(.conversationUpserted(c))
            }
            guard ask.media.allSatisfy({ !$0.data.isEmpty }) else { throw HermesError.rejected("A saved attachment is unavailable. Keep this Ask and restore the file before sending.") }
            let files = ask.media.map { FileAttachment(id: $0.id.uuidString, name: $0.name, byteCount: $0.data.count, fileExtension: URL(fileURLWithPath: $0.name).pathExtension, data: $0.data, contentType: $0.contentType) }
            let run = try await environment.client.conversations.send(OutgoingMessage(text: ask.text, attachments: files), conversationID: ask.conversationID!, configuration: ask.configuration, commandID: ask.sendCommandID)
            environment.activity.apply(.runUpserted(run))
            ask.state = .confirmed; try update(ask)
            return ask.conversationID!
        } catch {
            if case .commandUncertain = error as? HermesError { ask.state = .uncertain }
            else if let e = error as? HermesError, e.isConnectivity { ask.state = .uncertain }
            else { ask.state = .failed; if ask.conversationID == nil { ask.createCommandID = UUID() } else { ask.sendCommandID = UUID() } }
            ask.error = error.localizedDescription; try update(ask); throw error
        }
    }
    /// A receipt check is read-only. Resend becomes available only when the
    /// bridge journal proves the command was never accepted (or rejected).
    func checkAsk(_ id: UUID, environment: AppEnvironment) async throws {
        guard var ask = asks.first(where: { $0.id == id }), ask.state == .uncertain,
              ask.hostID == environment.connection.activeHostID else { return }
        if ask.conversationID == nil {
            switch try await environment.client.conversations.commandObservation(ask.createCommandID, creating: true) {
            case .conversation(let c): ask.conversationID = c.id; environment.conversations.apply(.conversationUpserted(c)); try update(ask)
            case .notReceived: ask.state = .queued; ask.error = "Bridge confirms this Ask was not received. Send now requires your tap."; try update(ask); return
            case .rejected(let message): ask.state = .failed; ask.error = message; ask.createCommandID = UUID(); try update(ask); return
            default: ask.error = "Creation outcome is still unknown. Check on your Mac."; try update(ask); return
            }
        }
        switch try await environment.client.conversations.commandObservation(ask.sendCommandID, creating: false) {
        case .run(let r): ask.state = .confirmed; ask.error = nil; environment.activity.apply(.runUpserted(r))
        case .notReceived: ask.state = .queued; ask.error = "Bridge confirms this message was not received. Send now requires your tap."
        case .rejected(let message): ask.state = .failed; ask.sendCommandID = UUID(); ask.error = message
        default: ask.error = "Outcome is still unknown. Check on your Mac before asking again."
        }
        try update(ask)
    }
    func syncCaptures(environment: AppEnvironment) async {
        guard !syncing, let service = environment.client.conversations as? any CaptureService else { return }
        guard environment.connection.connection.isConnected || environment.connection.connection == .hermesOffline else { return }
        guard environment.connection.supports(.captures) else { return }
        syncing = true; defer { syncing = false }
        let host = environment.connection.activeHostID
        for var capture in captures.filter({ $0.hostID == host && ($0.state == .queued || $0.state == .failed) }).sorted(by: { $0.createdAt < $1.createdAt }) {
            do {
                capture.state = .sending; try update(capture)
                for i in capture.media.indices where capture.media[i].uploadID == nil {
                    guard !capture.media[i].data.isEmpty else { throw HermesError.rejected("A saved capture attachment is unavailable.") }
                    capture.media[i].uploadID = try await service.uploadCaptureMedia(capture.media[i]); try update(capture)
                }
                capture.bridgeID = try await service.saveCapture(capture)
                capture.state = .confirmed; capture.error = nil; try update(capture)
            } catch {
                capture.state = .failed; capture.error = error.localizedDescription
                try? update(capture)
                break
            }
        }
    }
}
