import Foundation

/// Minimal `URLProtocol` stub for exercising `GatewayAPIClient` against
/// scripted responses instead of a live Gateway. Standard `URLSession`
/// testing technique — install via
/// `URLSessionConfiguration.ephemeral` + `.protocolClasses = [MockURLProtocol.self]`.
final class MockURLProtocol: URLProtocol {
    struct Stub {
        let status: Int
        let body: Data
    }

    /// Keyed by "`METHOD path`", e.g. "POST /v1/pairing/request".
    static var stubs: [String: Stub] = [:]
    static var requestLog: [URLRequest] = []

    static func reset() {
        stubs = [:]
        requestLog = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.requestLog.append(request)
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        guard let stub = MockURLProtocol.stubs[key], let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: stub.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
