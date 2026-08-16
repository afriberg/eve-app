import Foundation

/// Client side of the device-pairing flow (docs/security.md, "Device
/// enrollment"). Implemented as three separate calls, matching the real
/// Gateway protocol (eve-os `eve/gateway/api.py`, `credential_claims.py`) —
/// approve and claim are different principals (the owner approving over
/// curl/CLI is not this phone), so the credential is never handed back in
/// the approval response; it is collected here, separately, via `claim(_:)`.
struct DevicePairingService {
    enum PairingError: Error {
        /// The owner hasn't approved (or denied) this request yet. Expected,
        /// routine — callers poll `claim(requestId:)` and treat this as
        /// "keep waiting," not a failure to surface as an error banner.
        case notYetApproved
    }

    private let client: GatewayAPIClient
    private let keychain: KeychainStore

    init(client: GatewayAPIClient, keychain: KeychainStore = KeychainStore()) {
        self.client = client
        self.keychain = keychain
    }

    var hasStoredCredential: Bool {
        (try? keychain.read()) != nil
    }

    /// Step 1 of 3: ask the Gateway to create a pairing request. Returns the
    /// request id the caller polls `claim(requestId:)` with.
    func requestPairing(deviceName: String, deviceModel: String) async throws -> String {
        let view = try await client.requestPairing(deviceName: deviceName, deviceModel: deviceModel)
        return view.id
    }

    /// Step 3 of 3 (step 2, owner approval, happens out of band — currently
    /// CLI-only on the Gateway side, see eve-os `docs/deployment.md`).
    /// Callers should call this repeatedly (e.g. every few seconds) until it
    /// succeeds or the user cancels; `.notYetApproved` is the expected
    /// result while waiting, not an error condition.
    func claim(requestId: String) async throws {
        do {
            let credential = try await client.claimPairingCredential(requestId: requestId)
            try keychain.save(credential)
            await client.setDeviceCredential(credential)
        } catch GatewayAPIClient.GatewayAPIError.http(let status, _) where status == 404 {
            throw PairingError.notYetApproved
        }
    }

    func forget() throws {
        try keychain.delete()
    }
}
