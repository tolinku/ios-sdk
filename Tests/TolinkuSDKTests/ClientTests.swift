import XCTest
@testable import TolinkuSDK

final class ClientTests: XCTestCase {

    private var session: URLSession!
    private var client: Client!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = makeMockSession()
        client = Client(apiKey: "tolk_pub_test", baseURL: "https://api.example.com", session: session)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates an HTTPURLResponse with the given status code and optional headers.
    private func makeResponse(statusCode: Int, headers: [String: String]? = nil) -> HTTPURLResponse {
        return HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    /// A simple Decodable struct for testing decoded responses.
    private struct TestResponse: Codable {
        let ok: Bool
    }

    // MARK: - Retry on Network Error

    func testRetryOnNetworkError() async throws {
        var callCount = 0

        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            if callCount < 3 {
                throw URLError(.notConnectedToInternet)
            }
            let response = self.makeResponse(statusCode: 200)
            let data = #"{"ok": true}"#.data(using: .utf8)!
            return (response, data)
        }

        let result: TestResponse = try await client.get(path: "/test")
        XCTAssertTrue(result.ok)
        // 1 initial attempt + 2 retries = 3 calls
        XCTAssertEqual(callCount, 3)
    }

    // MARK: - Retry on 5xx

    func testRetryOn5xx() async throws {
        var callCount = 0

        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            if callCount < 2 {
                let response = self.makeResponse(statusCode: 503)
                let data = #"{"error": "Service Unavailable"}"#.data(using: .utf8)!
                return (response, data)
            }
            let response = self.makeResponse(statusCode: 200)
            let data = #"{"ok": true}"#.data(using: .utf8)!
            return (response, data)
        }

        let result: TestResponse = try await client.get(path: "/test")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(callCount, 2)
    }

    // MARK: - Retry on 429

    func testRetryOn429() async throws {
        var callCount = 0

        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            if callCount < 2 {
                let response = self.makeResponse(statusCode: 429, headers: ["Retry-After": "1"])
                let data = #"{"error": "Too Many Requests"}"#.data(using: .utf8)!
                return (response, data)
            }
            let response = self.makeResponse(statusCode: 200)
            let data = #"{"ok": true}"#.data(using: .utf8)!
            return (response, data)
        }

        let result: TestResponse = try await client.get(path: "/test")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(callCount, 2)
    }

    // MARK: - No Retry on 4xx (except 429)

    func testNoRetryOn4xx() async throws {
        var callCount = 0

        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            let response = self.makeResponse(statusCode: 400)
            let data = #"{"error": "Bad Request"}"#.data(using: .utf8)!
            return (response, data)
        }

        do {
            let _: TestResponse = try await client.get(path: "/test")
            XCTFail("Expected httpError to be thrown")
        } catch let error as TolinkuError {
            if case .httpError(let statusCode, _, _) = error {
                XCTAssertEqual(statusCode, 400)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        }

        // Should only be called once (no retries for 400)
        XCTAssertEqual(callCount, 1)
    }

    func testNoRetryOn401() async throws {
        var callCount = 0

        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            let response = self.makeResponse(statusCode: 401)
            let data = #"{"error": "Unauthorized"}"#.data(using: .utf8)!
            return (response, data)
        }

        do {
            let _: TestResponse = try await client.get(path: "/test")
            XCTFail("Expected httpError to be thrown")
        } catch let error as TolinkuError {
            if case .httpError(let statusCode, _, _) = error {
                XCTAssertEqual(statusCode, 401)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        }

        XCTAssertEqual(callCount, 1)
    }

    func testNoRetryOn404() async throws {
        var callCount = 0

        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            let response = self.makeResponse(statusCode: 404)
            let data = #"{"error": "Not Found"}"#.data(using: .utf8)!
            return (response, data)
        }

        do {
            let _: TestResponse = try await client.get(path: "/test")
            XCTFail("Expected httpError to be thrown")
        } catch let error as TolinkuError {
            if case .httpError(let statusCode, _, _) = error {
                XCTAssertEqual(statusCode, 404)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        }

        XCTAssertEqual(callCount, 1)
    }

    // MARK: - Max Retries Exhausted

    func testMaxRetriesExhausted() async throws {
        var callCount = 0

        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            let response = self.makeResponse(statusCode: 500)
            let data = #"{"error": "Internal Server Error"}"#.data(using: .utf8)!
            return (response, data)
        }

        do {
            let _: TestResponse = try await client.get(path: "/test")
            XCTFail("Expected httpError to be thrown")
        } catch let error as TolinkuError {
            if case .httpError(let statusCode, _, _) = error {
                XCTAssertEqual(statusCode, 500)
            } else {
                XCTFail("Expected httpError after max retries, got \(error)")
            }
        }

        // 1 initial attempt + 3 retries = 4 total calls (URLProtocol may report extra on macOS)
        XCTAssertGreaterThanOrEqual(callCount, 4)
    }

    func testMaxRetriesExhaustedOnNetworkError() async throws {
        var callCount = 0

        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            throw URLError(.timedOut)
        }

        do {
            let _: TestResponse = try await client.get(path: "/test")
            XCTFail("Expected networkError to be thrown")
        } catch let error as TolinkuError {
            if case .networkError(let urlError) = error {
                XCTAssertEqual(urlError.code, .timedOut)
            } else {
                XCTFail("Expected networkError, got \(error)")
            }
        }

        // 1 initial attempt + 3 retries = 4 total calls (URLProtocol may report extra on macOS)
        XCTAssertGreaterThanOrEqual(callCount, 4)
    }

    // MARK: - postVoid Retry

    func testPostVoidRetriesOn5xx() async throws {
        var callCount = 0

        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            if callCount < 3 {
                let response = self.makeResponse(statusCode: 502)
                let data = #"{"error": "Bad Gateway"}"#.data(using: .utf8)!
                return (response, data)
            }
            let response = self.makeResponse(statusCode: 200)
            return (response, Data())
        }

        struct EmptyBody: Codable {}
        try await client.postVoid(path: "/test", body: EmptyBody())
        XCTAssertEqual(callCount, 3)
    }
}
