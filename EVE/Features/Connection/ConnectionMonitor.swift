import Foundation
import Observation

/// Polls the one endpoint that exists on the backend today (`GET /health`) to
/// drive Features/Connection. Will grow into a WebSocket-session-aware
/// monitor once the backend gap in docs/backend-api.md (items 1-2) is closed.
@Observable
final class ConnectionMonitor {
    private(set) var state: ConnectionState = .unknown

    private let client: EVEAPIClient

    init(client: EVEAPIClient) {
        self.client = client
    }

    func refresh() async {
        do {
            let healthy = try await client.checkHealth()
            state = healthy ? .connected : .offline
        } catch EVEAPIClient.EVEAPIError.notConfigured {
            state = .unauthenticated
        } catch {
            state = .offline
        }
    }
}
