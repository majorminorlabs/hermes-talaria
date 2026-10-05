import Foundation
import Testing
@testable import Hermes

/// Opt-in check of the real configured Studio HTTPS path using iOS URLSession
/// and Keychain. The private fixture is outside the repo; no token launch args.
@Suite(.serialized)
struct StudioTransportTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HERMES_STUDIO_FIXTURE"] != nil))
    func productionStudioHTTPS() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["HERMES_STUDIO_FIXTURE"])
        let fixture = try JSONDecoder().decode(BridgeJSON.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let url = try #require(fixture["url"].string)
        #expect(URL(string: url)?.scheme == "https")
        let token = try #require(fixture["token"].string)
        let namespace = "studio-validation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: namespace))
        defer { defaults.removePersistentDomain(forName: namespace) }
        let credentials = KeychainBridgeCredentialStore(service: "xyz.majorminor.talaria.\(namespace)")
        let host = Host(id: namespace, name: "Studio HTTPS validation", address: url, network: .tailscale)
        try credentials.save(token, forHostID: host.id)
        defer { try? credentials.remove(forHostID: host.id) }
        let client = BridgeHermesClient(credentials: credentials, defaults: defaults)
        await client.connect(to: host)
        #expect(try await client.status(hostID: host.id).connection == .connected)
        _ = try await client.listConversations()
        #expect(try await client.listProfiles().contains { $0.id == "default" })
        _ = try await client.listRoutines()
        _ = try await client.listTasks()
        _ = try await client.usage(period: .day)
        #expect(try await client.homeSummary().host.connection == .connected)
        await client.disconnect(hostID: host.id)
    }
}
