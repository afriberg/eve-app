import Foundation
import Security

/// The only type in this app allowed to read or write the Keychain.
/// See docs/security.md, "Keychain usage". Items are stored
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and are never synced via
/// iCloud Keychain — a credential bound to this device should not silently
/// reappear on another one.
struct KeychainStore {
    enum KeychainError: Error {
        case unhandled(OSStatus)
    }

    private let service: String
    private let account = "device-credential"

    init(service: String = "pw.friberg.eve.device-credential") {
        self.service = service
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        SecItemDelete(baseQuery() as CFDictionary)

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    func read() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unhandled(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
