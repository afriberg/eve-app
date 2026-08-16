import Foundation
import Observation

/// Polls the Gateway's `GET /health` to drive Features/Connection. Will grow
/// into a WebSocket-session-aware monitor once GW-M2+ conversation streaming
/// exists (eve-os `docs/voice-gateway.md`).
@Observable
final class ConnectionMonitor {
    private(set) var state: ConnectionState = .unknown

    private let client: GatewayAPIClient

    init(client: GatewayAPIClient) {
        self.client = client
    }

    func refresh() async {
        do {
            let healthy = try await client.checkHealth()
            state = healthy ? .connected : .offline
        } catch GatewayAPIClient.GatewayAPIError.notConfigured {
            state = .unauthenticated
        } catch {
            state = .offline
        }
    }
}
