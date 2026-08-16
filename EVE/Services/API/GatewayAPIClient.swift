import Foundation

/// Talks to the EVE Voice Gateway (eve-os `eve/gateway/`) — and only ever the
/// Gateway. This app never calls EVE's or Hermes' APIs directly; the Gateway
/// is the sole trust boundary reachable from the phone (docs/architecture.md,
/// locked decision #1). Renamed from the Milestone-0 `EVEAPIClient` now that
/// the Gateway is a real, implemented backend rather than a documented gap.
///
/// The `session` this client is constructed with must be one whose delegate
/// pins to the bundled EVE root CA (`GatewayTrustEvaluator`) — this type does
/// not itself do any TLS trust handling.
actor GatewayAPIClient {
    enum GatewayAPIError: Error, Equatable {
        case notConfigured
        case http(status: Int, body: String)
        case transport(String)
        case decoding(String)
    }

    private let session: URLSession
    private var baseURL: URL?
    private var deviceCredential: String?

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    init(session: URLSession) {
        self.session = session
    }

    func configure(baseURL: URL) {
        self.baseURL = baseURL
    }

    func setDeviceCredential(_ credential: String?) {
        self.deviceCredential = credential
    }

    var currentBaseURL: URL? { baseURL }

    // MARK: - Health (GET /health, open)

    /// Distinguishes "not configured" (propagated) from "configured but
    /// unreachable/unhealthy" (returns false) — Features/Connection relies on
    /// this to show the right state.
    func checkHealth() async throws -> Bool {
        do {
            _ = try await request(path: "health", method: "GET", body: nil, authorized: false)
            return true
        } catch GatewayAPIError.notConfigured {
            throw GatewayAPIError.notConfigured
        } catch {
            return false
        }
    }

    // MARK: - Pairing (see docs/security.md; eve-os docs/voice-gateway.md)

    /// Step 1 of 3. Unauthenticated — the device has no credential yet.
    func requestPairing(deviceName: String, deviceModel: String) async throws -> PairingRequestView {
        struct Input: Encodable {
            let deviceName: String
            let deviceModel: String
        }
        let body = try encoder.encode(Input(deviceName: deviceName, deviceModel: deviceModel))
        let (data, _) = try await request(path: "v1/pairing/request", method: "POST", body: body, authorized: false)
        return try decode(PairingRequestView.self, from: data)
    }

    /// Step 3 of 3 (step 2, owner approval, happens out of band). Also
    /// unauthenticated — proof of continuity is the request id, not a
    /// credential (eve-os `eve/gateway/credential_claims.py`). Callers should
    /// expect this to fail with `.http(status: 404, ...)` until the owner has
    /// approved, and poll accordingly (`DevicePairingService`).
    func claimPairingCredential(requestId: String) async throws -> String {
        let (data, _) = try await request(
            path: "v1/pairing/\(requestId)/claim", method: "POST", body: nil, authorized: false
        )
        return try decode(PairingClaimResult.self, from: data).credential
    }

    // MARK: - Sessions (GW-M1: lifecycle foundation only, no conversation yet)

    func createSession() async throws -> SessionTicket {
        let (data, _) = try await request(path: "v1/sessions", method: "POST", body: nil, authorized: true)
        return try decode(SessionTicket.self, from: data)
    }

    // MARK: - Plumbing

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GatewayAPIError.decoding(String(describing: error))
        }
    }

    private func request(
        path: String, method: String, body: Data?, authorized: Bool
    ) async throws -> (Data, URLResponse) {
        guard let baseURL else { throw GatewayAPIError.notConfigured }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = method
        if let body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            guard let deviceCredential else { throw GatewayAPIError.notConfigured }
            urlRequest.setValue("Bearer \(deviceCredential)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw GatewayAPIError.transport("no HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw GatewayAPIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
            }
            return (data, response)
        } catch let error as GatewayAPIError {
            throw error
        } catch {
            throw GatewayAPIError.transport(error.localizedDescription)
        }
    }
}
