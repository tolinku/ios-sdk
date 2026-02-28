import Foundation

/// A mock URLProtocol subclass for testing that lets you control HTTP responses.
///
/// Set `MockURLProtocol.requestHandler` before each test to define the response
/// for any request. The handler receives the URLRequest and returns a tuple of
/// (HTTPURLResponse, Data?) or throws an error to simulate network failures.
final class MockURLProtocol: URLProtocol {

    /// Handler that determines the response for each intercepted request.
    /// Must be set before starting any request.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    /// Records all requests made during a test, in order.
    static var requestLog: [URLRequest] = []

    /// Reset all state between tests.
    static func reset() {
        requestHandler = nil
        requestLog = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockURLProtocol.requestLog.append(request)

        guard let handler = MockURLProtocol.requestHandler else {
            let error = URLError(.unknown)
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op
    }
}

/// Helper to create a URLSession that uses MockURLProtocol.
func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}
