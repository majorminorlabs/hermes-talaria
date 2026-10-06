import Foundation

/// Host definitions the user has added. Local-only.
final class SavedHostStore {
    private let defaults: UserDefaults
    private let key = "local.savedHosts"
    private let activeKey = "local.activeHost"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [Host] {
        guard let data = defaults.data(forKey: key),
              let hosts = try? JSONDecoder().decode([Host].self, from: data) else { return [] }
        return hosts
    }

    func save(_ hosts: [Host]) {
        if let data = try? JSONEncoder().encode(hosts) { defaults.set(data, forKey: key) }
    }

    var activeHostID: String? {
        get { defaults.string(forKey: activeKey) }
        set { defaults.set(newValue, forKey: activeKey) }
    }
}

/// Last-known snapshots of host state so the app launches instantly and can
/// show something meaningful while reconnecting. Never treated as canonical.
final class SnapshotCache {
    private var directory: URL
    private let base: URL
    private let isTemporary: Bool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.isTemporary = base.path.hasPrefix(FileManager.default.temporaryDirectory.path)
        self.base = base
        self.directory = base.appendingPathComponent("HermesSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    var queueDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Named/ephemeral environments keep isolated queues beside their caches.
        return isTemporary ? base.appendingPathComponent("VNextOutbox") : support.appendingPathComponent("TalariaOutbox")
    }

    func scope(to hostID: String) {
        let safe = hostID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        directory = base.appendingPathComponent(safe.isEmpty ? "unpaired" : safe, isDirectory: true)
            .appendingPathComponent("HermesSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load<Value: Decodable>(_ type: Value.Type, key: SnapshotKey) -> Snapshot<Value>? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? decoder.decode(Snapshot<Value>.self, from: data)
    }

    func save<Value: Encodable>(_ value: Value, key: SnapshotKey) {
        let snapshot = Snapshot(value: value, savedAt: .now)
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url(for: key), options: .atomic)
    }

    func commit(_ value: AppliedBridgeState) throws {
        let snapshot = Snapshot(value: value, savedAt: Date.now)
        let data = try encoder.encode(snapshot)
        try data.write(to: url(for: .appliedBridgeState), options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var sizeInBytes: Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func url(for key: SnapshotKey) -> URL {
        directory.appendingPathComponent("\(key.rawValue).json")
    }
}

nonisolated struct Snapshot<Value> {
    var value: Value
    var savedAt: Date
}

extension Snapshot: Encodable where Value: Encodable {}
extension Snapshot: Decodable where Value: Decodable {}

nonisolated enum SnapshotKey: String {
    case hostStatuses, home, runs, approvals, conversations, transcripts, profiles, tasks, routines, eventCursor, appliedBridgeState
}

/// Unsent composer text per conversation.
final class DraftStore {
    private let defaults: UserDefaults
    private let prefix = "local.draft."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func draft(for conversationID: String) -> String {
        defaults.string(forKey: prefix + conversationID) ?? ""
    }

    func setDraft(_ text: String, for conversationID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: prefix + conversationID)
        } else {
            defaults.set(text, forKey: prefix + conversationID)
        }
    }
}

/// One atomic checkpoint ties applied UI state to its cursor. Restoring separate
/// snapshots with a newer cursor could otherwise lose a response after a crash.
nonisolated struct AppliedBridgeState: Codable {
    var cursor: EventCursor
    var hostID: String
    var home: HomeSummary?
    var runs: [Run]
    var approvals: [ApprovalRequest]
    var conversations: [Conversation]
    var transcripts: [String:[Message]]
    var profiles: [Profile]
    var tasks: [HermesTask]
    var routines: [Routine]
}
