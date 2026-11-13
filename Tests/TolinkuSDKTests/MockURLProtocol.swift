import Foundation

/// A mock URLProtocol subclass for testing that lets you control HTTP responses.
///
/// Set `MockURLProtocol.requestHandler` before each test to define the response
/// for any request. The handler receives the URLRequest and returns a tuple of
/// (HTTPURLResponse, Data?) or throws an error to simulate network failures.
final class MockURLProtocol: URLProtocol {

    // Both of these are static because URLProtocol subclasses are instantiated
    // by Foundation, not by us, so there is no instance to hand a handler to.
    //
    // nonisolated(unsafe) rather than a lock or an actor. Under the Swift 6
    // language mode these are rejected as nonisolated global shared mutable
    // state, which is a fair description of what they are. They are safe here
    // for a reason that is about the tests rather than about the type: each
    // test sets the handler, drives requests through one URLSession, and reads
    // the log, all on its own thread, and reset() clears both between tests.
    // Guarding them would make this double look thread-safe in a way that
    // would not survive two tests sharing it concurrently anyway.

    /// Handler that determines the response for each intercepted request.
    /// Must be set before starting any request.
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    /// Records all requests made during a test, in order.
    nonisolated(unsafe) static var requestLog: [URLRequest] = []

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
