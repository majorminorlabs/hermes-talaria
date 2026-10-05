import Foundation

/// Saved hosts, the active host, and live bridge status/capabilities.
@Observable
final class ConnectionStore {
    private let client: HermesClient
    private let savedHosts: SavedHostStore
    private let cache: SnapshotCache

    private(set) var hosts: [Host]
    private(set) var activeHostID: String
    private(set) var statuses: [String: HostStatus]
    private(set) var runOptions: RunOptions = .empty
    private var reconnectAttempt = 0
    var onHostSwitch: (() async -> Void)?
    let credentials = KeychainBridgeCredentialStore()

    init(client: HermesClient, savedHosts: SavedHostStore, cache: SnapshotCache, defaultHosts: [Host]) {
        self.client = client
        self.savedHosts = savedHosts
        self.cache = cache
        let stored = savedHosts.load()
        let hosts = stored.isEmpty ? defaultHosts : stored
        self.hosts = hosts
        let activeHostID = savedHosts.activeHostID.flatMap { id in hosts.first { $0.id == id }?.id } ?? hosts.first?.id ?? ""
        self.activeHostID = activeHostID
        // Last-known status, marked as reconnecting until the bridge answers.
        var restored = cache.load([String: HostStatus].self, key: .hostStatuses)?.value ?? [:]
        for key in restored.keys where restored[key]?.connection.isConnected == true {
            restored[key]?.connection = .connecting
        }
        // Never-seen hosts start as "connecting" rather than "offline".
        if !activeHostID.isEmpty, restored[activeHostID] == nil {
            var placeholder = HostStatus.unknown(activeHostID)
            placeholder.connection = .connecting
            restored[activeHostID] = placeholder
        }
        statuses = restored
        if stored.isEmpty { savedHosts.save(hosts) }
    }

    var activeHost: Host? { hosts.first { $0.id == activeHostID } }

    var status: HostStatus { statuses[activeHostID] ?? .unknown(activeHostID) }

    var connection: ConnectionState { status.connection }

    var capabilities: Set<HermesCapability> { status.capabilities }
    var canControlChat: Bool { status.permissionScopes?.contains("chat.control") ?? true }
    var canManageTasks: Bool { status.permissionScopes?.contains("tasks.manage") ?? true }

    func supports(_ capability: HermesCapability) -> Bool { capabilities.contains(capability) }

    func status(for hostID: String) -> HostStatus { statuses[hostID] ?? .unknown(hostID) }

    // MARK: Connection

    func connect() async {
        guard let host = activeHost else { return }
        await client.hosts.connect(to: host)
        if connection.isConnected {
            reconnectAttempt = 0
            await loadRunOptions()
        }
    }

    func reconnect() async {
        reconnectAttempt += 1
        var status = self.status
        status.connection = .reconnecting(attempt: reconnectAttempt)
        statuses[activeHostID] = status
        await connect()
    }

    func switchHost(to id: String) async {
        guard id != activeHostID, hosts.contains(where: { $0.id == id }) else { return }
        await client.hosts.disconnect(hostID: activeHostID)
        activeHostID = id
        await onHostSwitch?()
        savedHosts.activeHostID = id
        runOptions = .empty
        await connect()
    }

    func loadRunOptions() async {
        if let options = try? await client.hosts.runOptions(hostID: activeHostID) {
            runOptions = options
        }
    }

    func refreshStatuses() async {
        for host in hosts where host.id != activeHostID {
            if let status = try? await client.hosts.status(hostID: host.id) {
                statuses[host.id] = status
            }
        }
    }

    // MARK: Saved hosts (local only)

    func save(_ host: Host) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        savedHosts.save(hosts)
    }

    func remove(hostID: String) async throws {
        if !(client.hosts is MockHermesBackend) { try credentials.remove(forHostID: hostID) }
        let wasActive = hostID == activeHostID
        if wasActive { await client.hosts.disconnect(hostID: hostID) }
        hosts.removeAll { $0.id == hostID }
        statuses[hostID] = nil
        savedHosts.save(hosts)
        if wasActive {
            activeHostID = hosts.first?.id ?? ""
            savedHosts.activeHostID = activeHostID
            await onHostSwitch?()
            await connect()
        }
    }

    func pair(_ host: Host, token: String) async throws {
        guard let url = host.bridgeURL else { throw HermesError.rejected("Enter a bridge HTTPS URL without credentials or query parameters") }
        _ = try BridgeTransport(baseURL: url, hostID: host.id, credentialStore: credentials)
        if !token.isEmpty { try credentials.save(token, forHostID: host.id) }
        guard try credentials.token(forHostID: host.id) != nil else { throw HermesError.unauthorized }
        save(host)
        if activeHostID.isEmpty { activeHostID = host.id; savedHosts.activeHostID = host.id; await onHostSwitch?() }
        if activeHostID == host.id { await onHostSwitch?(); await reconnect() } else { await switchHost(to: host.id) }
        if connection == .authenticationRequired { throw HermesError.unauthorized }
    }

    func forgetActiveCredential() async throws {
        if !(client.hosts is MockHermesBackend) { try credentials.remove(forHostID: activeHostID) }
        await client.hosts.disconnect(hostID: activeHostID)
        var state = status; state.connection = .authenticationRequired
        apply(.hostStatus(state))
    }

    // MARK: Events

    func apply(_ event: HermesEvent) {
        guard case .hostStatus(var incoming) = event else { return }
        // A degraded status may arrive without capabilities; keep the last
        // known set so the UI can keep presenting cached features.
        if incoming.connection.isDegraded, incoming.capabilities.isEmpty, let previous = statuses[incoming.hostID] {
            incoming.capabilities = previous.capabilities
            incoming.defaultModel = incoming.defaultModel ?? previous.defaultModel
            incoming.hermesVersion = incoming.hermesVersion ?? previous.hermesVersion
            incoming.bridgeVersion = incoming.bridgeVersion ?? previous.bridgeVersion
            incoming.lastSeen = incoming.lastSeen ?? previous.lastSeen
        }
        statuses[incoming.hostID] = incoming
        cache.save(statuses, key: .hostStatuses)
    }
}
