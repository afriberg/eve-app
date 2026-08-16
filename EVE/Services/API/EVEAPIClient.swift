import Foundation

/// Talks to the EVE/Hermes backend. This is the only type in the app allowed
/// to construct a `URLRequest` — see docs/architecture.md, "Client architecture".
///
/// `checkHealth()` is the only call that reflects a real backend endpoint
/// today (`GET /health` in eve-os). The conversation/voice calls below are
/// declared as the target shape this client will use once the backend gap
/// described in docs/backend-api.md is closed; they intentionally throw
/// `.notImplementedByBackend` rather than pretending to work.
actor EVEAPIClient {
    enum EVEAPIError: Error, Equatable {
        case notConfigured
        case notImplementedByBackend
        case unauthorized
        case server(status: Int)
        case transport(String)
    }

    private let session: URLSession
    private var baseURL: URL?
    private var deviceCredential: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func configure(baseURL: URL, deviceCredential: String?) {
        self.baseURL = baseURL
        self.deviceCredential = deviceCredential
    }

    /// `GET /health` — see eve-os `eve/api/main.py`. Unauthenticated by design
    /// on the backend, used here purely for Features/Connection reachability.
    func checkHealth() async throws -> Bool {
        guard let baseURL else { throw EVEAPIError.notConfigured }
        let url = baseURL.appendingPathComponent("health")
        do {
            let (_, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw EVEAPIError.transport("no HTTP response")
            }
            return http.statusCode == 200
        } catch let error as EVEAPIError {
            throw error
        } catch {
            throw EVEAPIError.transport(error.localizedDescription)
        }
    }

    /// Milestone 2 target call. Not implemented on the backend yet —
    /// see docs/backend-api.md, gap item 1.
    func sendConversationTurn(text: String) async throws -> ConversationTurn {
        throw EVEAPIError.notImplementedByBackend
    }
}
