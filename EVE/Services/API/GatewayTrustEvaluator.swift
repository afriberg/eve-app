import Foundation
import Security

/// Pins every connection to the EVE Voice Gateway — HTTPS and WSS alike,
/// since `URLSessionWebSocketTask` shares the same `URLSession` delegate —
/// to the bundled EVE root CA, never the system trust store. See
/// docs/security.md, "TLS": the Gateway's certificate is signed by a
/// private, EVE-owner-controlled CA that has no business being in (and
/// correctly isn't in) any public trust store, so the system default would
/// simply and correctly reject it. Pinning to the CA **root**, not the
/// Gateway's leaf certificate, means routine leaf renewal
/// (`eve-os scripts/eve-gateway-tls-init.sh`) needs no app update — only a
/// root rotation (rare) does.
final class GatewayTrustEvaluator: NSObject, URLSessionDelegate {
    enum TrustError: Error, Equatable {
        /// The EVE root CA resource isn't bundled into this build. Fails
        /// loudly by design — see `GatewayEnvironment`, which must never
        /// fall back to unpinned trust when this is thrown.
        case rootCertificateNotBundled
    }

    private let anchorCertificate: SecCertificate

    init(bundle: Bundle = .main, resourceName: String = "EVERootCA", resourceExtension: String = "cer") throws {
        guard
            let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
            let data = try? Data(contentsOf: url),
            let certificate = SecCertificateCreateWithData(nil, data as CFData)
        else {
            throw TrustError.rootCertificateNotBundled
        }
        self.anchorCertificate = certificate
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        SecTrustSetAnchorCertificates(serverTrust, [anchorCertificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        if SecTrustEvaluateWithError(serverTrust, nil) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            // Fail closed: never .performDefaultHandling here, which would
            // silently fall back to the system trust store.
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
