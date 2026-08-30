import XCTest
@testable import TolinkuSDK

/// `claimDeferredLink` exists on iOS for the bookkeeping rather than for the
/// install referrer, which has no iOS equivalent.
///
/// A claim is consumed the first time it succeeds, so an app calling
/// `claimBySignals` on every launch asks again after the answer is already
/// spent, and each of those is recorded as a miss. The match rate in the
/// dashboard then falls towards zero while the integration is working, which is
/// close to impossible to diagnose from outside.
final class DeferredClaimOnceTests: XCTestCase {

    private var session: URLSession!
    private var client: Client!
    private var deferred: DeferredDeepLink!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: DeferredDeepLink.claimedKey)
        session = makeMockSession()
        client = Client(apiKey: "tolk_pub_test", baseURL: "https://api.example.com", session: session)
        deferred = DeferredDeepLink(client: client)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: DeferredDeepLink.claimedKey)
        super.tearDown()
    }

    // MARK: - Helpers

    private func respond(status: Int, body: String = "{}") {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body.data(using: .utf8)!)
        }
    }

    private var linkJSON: String {
        """
        {"deep_link_path": "/product/42", "appspace_id": "app123"}
        """
    }

    // MARK: - Claiming once

    func testClaimsOnceAndDoesNotAskAgain() async throws {
        respond(status: 200, body: linkJSON)

        let first = try await deferred.claimDeferredLink(appspaceId: "app123")
        XCTAssertEqual(first?.deepLinkPath, "/product/42")

        let second = try await deferred.claimDeferredLink(appspaceId: "app123")
        XCTAssertNil(second, "A second call should return nil without asking again")
        XCTAssertEqual(MockURLProtocol.requestLog.count, 1)
    }

    func testRemembersANotFoundBecauseNothingWaitingIsARealAnswer() async throws {
        respond(status: 404, body: "{\"error\":\"not found\"}")

        let first = try await deferred.claimDeferredLink(appspaceId: "app123")
        XCTAssertNil(first)

        _ = try await deferred.claimDeferredLink(appspaceId: "app123")
        XCTAssertEqual(MockURLProtocol.requestLog.count, 1)
    }

    func testDoesNotSpendTheAttemptWhenTheRequestFails() async throws {
        // A server error is not an answer. Burning the install's one chance on
        // it is worse than one extra request on the next launch.
        respond(status: 500, body: "{\"error\":\"boom\"}")

        do {
            _ = try await deferred.claimDeferredLink(appspaceId: "app123")
            XCTFail("Expected the error to surface rather than be swallowed")
        } catch {
            // Expected.
        }

        respond(status: 200, body: linkJSON)
        let retried = try await deferred.claimDeferredLink(appspaceId: "app123")
        XCTAssertEqual(retried?.deepLinkPath, "/product/42", "The next launch must be free to try again")
    }

    func testForceClaimsAgain() async throws {
        respond(status: 200, body: linkJSON)

        _ = try await deferred.claimDeferredLink(appspaceId: "app123")
        let forced = try await deferred.claimDeferredLink(appspaceId: "app123", force: true)

        XCTAssertEqual(forced?.deepLinkPath, "/product/42")
        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
    }

    func testRejectsABlankAppspaceId() async throws {
        respond(status: 200, body: linkJSON)

        do {
            _ = try await deferred.claimDeferredLink(appspaceId: "   ")
            XCTFail("Expected a blank appspaceId to be rejected")
        } catch TolinkuError.invalidConfiguration {
            // Expected.
        }
        XCTAssertEqual(MockURLProtocol.requestLog.count, 0, "Nothing should be sent for a blank id")
    }

    func testClaimBySignalsStillAsksEveryTime() async throws {
        // The older call is unchanged: calling it once is the caller's job.
        respond(status: 200, body: linkJSON)

        _ = try await deferred.claimBySignals(appspaceId: "app123")
        _ = try await deferred.claimBySignals(appspaceId: "app123")

        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
    }
}
