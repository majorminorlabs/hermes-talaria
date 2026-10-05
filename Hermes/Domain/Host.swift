import Foundation

/// A machine running Hermes Agent. The phone never executes Hermes itself;
/// it connects to a host over a private network (Tailscale, LAN, …).
nonisolated struct Host: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    /// Network address as entered by the user, e.g. `your-mac.your-tailnet.ts.net`.
    var address: String
    var port: Int?
    var network: HostNetwork
    var symbol: String

    init(id: String, name: String, address: String, port: Int? = nil,
         network: HostNetwork = .tailscale, symbol: String = "macstudio") {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.network = network
        self.symbol = symbol
    }

    /// Validated by the transport; only non-secret URL metadata is saved.
    var bridgeURL: URL? {
        let raw = address.contains("://") ? address : "https://" + address
        guard var components = URLComponents(string: raw), components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        if let port { components.port = port }
        return components.url
    }

    var displayAddress: String {
        if let port { return "\(address):\(port)" }
        return address
    }
}

nonisolated enum HostNetwork: String, Codable, Sendable, CaseIterable {
    case tailscale, lan, custom

    var label: String {
        switch self {
        case .tailscale: "Tailscale"
        case .lan: "Local network"
        case .custom: "Custom"
        }
    }
}

/// Phone → bridge → Hermes link state.
///
/// The phone talks to `hermes-mobile-bridge` on the host, never to Hermes
/// directly, so "bridge unreachable" and "bridge up but Hermes down" are
/// distinct states.
nonisolated enum ConnectionState: Hashable, Codable, Sendable {
    case connected
    case connecting
    case reconnecting(attempt: Int)
    /// The bridge can't be reached (host asleep, off the tailnet, bridge stopped).
    case bridgeOffline
    /// The bridge answers but Hermes on the host isn't running or responding.
    case hermesOffline
    case authenticationRequired

    var isConnected: Bool { self == .connected }

    var isTransitioning: Bool {
        switch self {
        case .connecting, .reconnecting: true
        default: false
        }
    }

    /// Whether the UI should treat data as last-known rather than live.
    var isDegraded: Bool { !isConnected }

    var label: String { label(host: nil) }

    /// Plain-language state. Names the host when known ("Mac Studio unavailable").
    func label(host: String?) -> String {
        switch self {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .reconnecting: "Reconnecting…"
        case .bridgeOffline: "\(host ?? "Studio") unavailable"
        case .hermesOffline: "Hermes not responding"
        case .authenticationRequired: "Pairing required"
        }
    }

    var explanation: String {
        switch self {
        case .connected: "Live"
        case .connecting: "Contacting your Mac"
        case .reconnecting: "Talaria lost contact with your Mac and is trying again."
        case .bridgeOffline: "Talaria can't reach your Mac. It may be asleep, offline or off your tailnet."
        case .hermesOffline: "Your Mac is reachable, but Hermes isn't responding."
        case .authenticationRequired: "Your Mac no longer recognizes this iPhone. Pair again to continue."
        }
    }

    /// The underlying condition, for Details and diagnostics.
    var diagnosticCode: String? {
        switch self {
        case .bridgeOffline: "bridge_unreachable"
        case .hermesOffline: "hermes_offline"
        case .authenticationRequired: "unauthorized"
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .connecting, .reconnecting: "arrow.triangle.2.circlepath"
        case .bridgeOffline: "wifi.slash"
        case .hermesOffline: "exclamationmark.triangle.fill"
        case .authenticationRequired: "lock.fill"
        }
    }
}

nonisolated enum HermesProcessState: String, Codable, Sendable {
    case running, stopped, unknown

    var label: String {
        switch self {
        case .running: "Running"
        case .stopped: "Stopped"
        case .unknown: "Unknown"
        }
    }
}

/// Live status for a host. Produced by `HostService`; cached locally so the
/// app can show last-known state while reconnecting.
nonisolated struct HostStatus: Hashable, Codable, Sendable {
    var hostID: String
    var connection: ConnectionState
    var hermesState: HermesProcessState
    var bridgeVersion: String?
    var hermesVersion: String?
    var defaultModel: ModelRef?
    var activeRunCount: Int
    var latencyMilliseconds: Int?
    var lastSeen: Date?
    var capabilities: Set<HermesCapability>
    var resources: HostResources?
    var permissionScopes: Set<String>? = nil

    static func unknown(_ hostID: String) -> HostStatus {
        HostStatus(hostID: hostID, connection: .bridgeOffline, hermesState: .unknown, bridgeVersion: nil,
                   hermesVersion: nil, defaultModel: nil, activeRunCount: 0,
                   latencyMilliseconds: nil, lastSeen: nil, capabilities: [], resources: nil)
    }
}

/// Optional resource indicators. Hosts may not report these.
nonisolated struct HostResources: Hashable, Codable, Sendable {
    var cpuLoad: Double       // 0…1
    var memoryUsed: Double    // 0…1
    var uptime: TimeInterval
}

/// Options a host offers when starting a run.
nonisolated struct RunOptions: Hashable, Codable, Sendable {
    var models: [ModelRef]
    var reasoningLevels: [ReasoningLevel]
    var projects: [ProjectContext]

    static let empty = RunOptions(models: [], reasoningLevels: ReasoningLevel.allCases, projects: [])
}
