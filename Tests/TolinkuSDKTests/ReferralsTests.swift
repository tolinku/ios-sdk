import XCTest
@testable import TolinkuSDK

final class ReferralsTests: XCTestCase {

    private var session: URLSession!
    private var client: Client!
    private var referrals: Referrals!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = makeMockSession()
        client = Client(apiKey: "tolk_pub_test", baseURL: "https://api.example.com", session: session)
        referrals = Referrals(client: client)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    /// Returns valid ReferralDetails JSON with the given referrer ID.
    private func makeReferralJSON(referrerId: String = "user_1") -> String {
        return """
        {
            "referrer_id": "\(referrerId)",
            "status": "active",
            "milestone": null,
            "milestone_history": [],
            "reward_type": null,
            "reward_value": null,
            "reward_claimed": false,
            "created_at": "2026-01-01T00:00:00Z"
        }
        """
    }

    // MARK: - URL Encoding of Referral Codes

    func testReferralCodeWithSpaces() async throws {
        MockURLProtocol.requestHandler = { request in
            // Verify the URL path is correctly encoded
            let path = request.url?.path ?? ""
            XCTAssertTrue(path.contains("hello%20world") || path.contains("hello+world"),
                          "Expected URL-encoded space in path, got: \(path)")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = self.makeReferralJSON(referrerId: "user_1").data(using: .utf8)!
            return (response, data)
        }

        let result = try await referrals.get(code: "hello world")
        XCTAssertEqual(result.referrerId, "user_1")
    }

    func testReferralCodeWithSpecialCharacters() async throws {
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.absoluteString ?? ""
            // The code "a+b/c=d" should be percent-encoded in the URL
            XCTAssertFalse(path.contains("a+b/c=d"),
                           "Special characters should be percent-encoded in the URL path")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = self.makeReferralJSON(referrerId: "user_2").data(using: .utf8)!
            return (response, data)
        }

        let result = try await referrals.get(code: "a+b/c=d")
        XCTAssertEqual(result.referrerId, "user_2")
    }

    func testReferralCodeWithUnicodeCharacters() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = self.makeReferralJSON(referrerId: "user_3").data(using: .utf8)!
            return (response, data)
        }

        // The accent character should be percent-encoded
        let result = try await referrals.get(code: "cafe\u{0301}")
        XCTAssertNotNil(result)
    }

    func testReferralCodeWithAmpersandAndHash() async throws {
        MockURLProtocol.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            // '#' and '&' must be encoded so they are not interpreted as fragment/query separators
            XCTAssertFalse(urlString.contains("#"), "Hash should be percent-encoded")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = self.makeReferralJSON(referrerId: "user_4").data(using: .utf8)!
            return (response, data)
        }

        let result = try await referrals.get(code: "code#1&2")
        XCTAssertEqual(result.referrerId, "user_4")
    }

    func testReferralCodeWithPercentSign() async throws {
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.absoluteString ?? ""
            // A literal "%" should be encoded as "%25"
            XCTAssertTrue(path.contains("%25"), "Percent sign should be encoded as %25, got: \(path)")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = self.makeReferralJSON(referrerId: "user_5").data(using: .utf8)!
            return (response, data)
        }

        let result = try await referrals.get(code: "50%OFF")
        XCTAssertEqual(result.referrerId, "user_5")
    }
}
