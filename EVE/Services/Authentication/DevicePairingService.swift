import Foundation

/// Client side of the device-enrollment flow described in docs/security.md,
/// "Device enrollment (pairing)". The backend pairing endpoint this depends
/// on does not exist yet (docs/backend-api.md, gap item 5) — this type
/// defines the shape Features/Settings will call once it does, and fails
/// honestly rather than faking success.
struct DevicePairingService {
    enum PairingError: Error {
        case notImplementedByBackend
    }

    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    var hasStoredCredential: Bool {
        (try? keychain.read()) != nil
    }

    /// Exchanges a one-time pairing token for a device credential.
    func pair(pairingToken: String, serverURL: URL) async throws {
        throw PairingError.notImplementedByBackend
    }

    func forget() throws {
        try keychain.delete()
    }
}
