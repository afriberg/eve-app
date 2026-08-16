import Foundation
import Observation

/// Constructs the app's one pinned `URLSession` and the clients built on it.
/// This is the only place `GatewayTrustEvaluator` is instantiated — every
/// other type receives an already-configured `GatewayAPIClient`/
/// `GatewayWebSocketClient`, never a raw `URLSession`.
@Observable
final class GatewayEnvironment {
    let apiClient: GatewayAPIClient
    let webSocketSession: URLSession

    /// Set when the EVE root CA couldn't be loaded from the app bundle. When
    /// this is non-nil, `apiClient`/`webSocketSession` still exist but use
    /// the *system* trust store instead of the pinned one — which will
    /// correctly and safely reject the Gateway's private-CA certificate on
    /// every request. This is a deliberate fail-closed fallback, not a
    /// security downgrade: no request the app makes can ever succeed against
    /// an unpinned trust evaluation of a certificate this evaluator doesn't
    /// vouch for. Surfaced in Settings/Diagnostics so misconfiguration is
    /// visible rather than a silent string of failed connections.
    private(set) var trustConfigurationError: Error?

    private let pairingKeychain = KeychainStore()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        do {
            let evaluator = try GatewayTrustEvaluator()
            self.webSocketSession = URLSession(configuration: configuration, delegate: evaluator, delegateQueue: nil)
        } catch {
            self.trustConfigurationError = error
            self.webSocketSession = URLSession(configuration: configuration)
        }
        self.apiClient = GatewayAPIClient(session: webSocketSession)
    }

    /// Loads any previously-paired device credential from the Keychain into
    /// the API client. Call once at app start.
    func restoreStoredCredential() async {
        guard let credential = try? pairingKeychain.read() else { return }
        await apiClient.setDeviceCredential(credential)
    }

    func configureServer(baseURL: URL) async {
        await apiClient.configure(baseURL: baseURL)
    }

    func makeWebSocketClient() -> GatewayWebSocketClient {
        GatewayWebSocketClient(session: webSocketSession)
    }

    func makePairingService() -> DevicePairingService {
        DevicePairingService(client: apiClient, keychain: pairingKeychain)
    }
}
