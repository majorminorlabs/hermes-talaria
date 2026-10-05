import Foundation
import Security

/// Secure storage for the bridge's per-host mobile token.
///
/// The token is deliberately independent of `Host`, UserDefaults, and snapshot
/// storage. Keychain items are tied to this device and become available after
/// the first unlock following a restart.
nonisolated protocol BridgeCredentialStore: Sendable {
    func token(forHostID hostID: String) throws -> String?
    func save(_ token: String, forHostID hostID: String) throws
    func remove(forHostID hostID: String) throws
}

nonisolated enum BridgeCredentialError: Error, Equatable, Sendable {
    case invalidHost
    case unavailable
    case invalidToken
}

/// Keychain implementation used by the production bridge client.
nonisolated final class KeychainBridgeCredentialStore: BridgeCredentialStore, @unchecked Sendable {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "xyz.majorminor.talaria") {
        self.service = service
    }

    func token(forHostID hostID: String) throws -> String? {
        let query = try baseQuery(forHostID: hostID)
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        switch SecItemCopyMatching(lookup as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
                throw BridgeCredentialError.invalidToken
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw BridgeCredentialError.unavailable
        }
    }

    func save(_ token: String, forHostID hostID: String) throws {
        guard !token.isEmpty, !token.contains("\n"), !token.contains("\r"),
              let data = token.data(using: .utf8) else {
            throw BridgeCredentialError.invalidToken
        }

        let query = try baseQuery(forHostID: hostID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, newValue in newValue }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw BridgeCredentialError.unavailable
            }
        } else if status != errSecSuccess {
            throw BridgeCredentialError.unavailable
        }
    }

    func remove(forHostID hostID: String) throws {
        let status = SecItemDelete(try baseQuery(forHostID: hostID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BridgeCredentialError.unavailable
        }
    }

    private func baseQuery(forHostID hostID: String) throws -> [String: Any] {
        guard !hostID.isEmpty, hostID.utf8.count <= 256 else {
            throw BridgeCredentialError.invalidHost
        }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID
        ]
    }
}
