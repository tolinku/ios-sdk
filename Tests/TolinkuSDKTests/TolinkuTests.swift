import XCTest
@testable import TolinkuSDK

final class TolinkuTests: XCTestCase {

    override func tearDown() async throws {
        await Tolinku.shutdown()
        try await super.tearDown()
    }

    // MARK: - Configuration

    func testConfigureSetsSharedInstance() throws {
        try Tolinku.configure(apiKey: "tolk_pub_test_123", baseURL: "https://links.example.com")
        let instance = try Tolinku.requireShared()
        XCTAssertEqual(instance.client.apiKey, "tolk_pub_test_123")
        XCTAssertEqual(instance.client.baseURL, "https://links.example.com")
    }

    func testConfigureStripsTrailingSlash() throws {
        try Tolinku.configure(apiKey: "tolk_pub_test", baseURL: "https://links.example.com/")
        let instance = try Tolinku.requireShared()
        XCTAssertEqual(instance.client.baseURL, "https://links.example.com")
    }

    func testConfigureRejectsEmptyApiKey() {
        XCTAssertThrowsError(try Tolinku.configure(apiKey: "", baseURL: "https://links.example.com")) { error in
            guard case TolinkuError.invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration error, got \(error)")
            }
        }
    }

    func testConfigureRejectsEmptyBaseURL() {
        XCTAssertThrowsError(try Tolinku.configure(apiKey: "tolk_pub_test", baseURL: "")) { error in
            guard case TolinkuError.invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration error, got \(error)")
            }
        }
    }

    func testConfigureRejectsWhitespaceOnlyApiKey() {
        XCTAssertThrowsError(try Tolinku.configure(apiKey: "   ", baseURL: "https://links.example.com")) { error in
            guard case TolinkuError.invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration error, got \(error)")
            }
        }
    }

    // MARK: - Universal Link Handling

    func testHandleUniversalLink() {
        let url = URL(string: "https://links.example.com/product/123?ref=abc")!
        let result = Tolinku.handleUniversalLink(url)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.path, "/product/123")
        XCTAssertEqual(result?.queryItems.first(where: { $0.name == "ref" })?.value, "abc")
    }

    // MARK: - Model Encoding

    func testTrackEventRequestEncoding() throws {
        let request = TrackEventRequest(
            eventType: "custom.signup",
            properties: ["source": .string("ios"), "count": .int(5)]
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["event_type"] as? String, "custom.signup")
        let props = json?["properties"] as? [String: Any]
        XCTAssertEqual(props?["source"] as? String, "ios")
        XCTAssertEqual(props?["count"] as? Int, 5)
    }

    func testTrackEventRequestEncodingNilProperties() throws {
        let request = TrackEventRequest(eventType: "custom.open", properties: nil)
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["event_type"] as? String, "custom.open")
        XCTAssertNil(json?["properties"])
    }

    // MARK: - Model Decoding

    func testCreateReferralResponseDecoding() throws {
        let json = """
        {
            "referral_code": "ABC123",
            "referral_url": "https://example.com/ref/ABC123",
            "referral_id": "doc_123"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CreateReferralResponse.self, from: json)
        XCTAssertEqual(response.referralCode, "ABC123")
        XCTAssertEqual(response.referralUrl, "https://example.com/ref/ABC123")
        XCTAssertEqual(response.referralId, "doc_123")
    }

    func testReferralDetailsDecoding() throws {
        let json = """
        {
            "referrer_id": "user_1",
            "status": "pending",
            "milestone": "signed_up",
            "milestone_history": [],
            "reward_type": "credit",
            "reward_value": "10",
            "reward_claimed": false,
            "created_at": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ReferralDetails.self, from: json)
        XCTAssertEqual(response.referrerId, "user_1")
        XCTAssertEqual(response.status, "pending")
        XCTAssertEqual(response.milestone, "signed_up")
        XCTAssertEqual(response.rewardType, "credit")
        XCTAssertEqual(response.rewardValue, "10")
        XCTAssertEqual(response.rewardClaimed, false)
        XCTAssertEqual(response.createdAt, "2025-01-01T00:00:00Z")
    }

    func testDeferredDeepLinkResponseDecoding() throws {
        let json = """
        {
            "deep_link_path": "/product/12345",
            "appspace_id": "asp_abc"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DeferredDeepLinkResponse.self, from: json)
        XCTAssertEqual(response.deepLinkPath, "/product/12345")
        XCTAssertEqual(response.appspaceId, "asp_abc")
    }

    func testLeaderboardEntryDecoding() throws {
        let json = """
        {
            "referrer_id": "user_42",
            "referrer_name": "Bob",
            "total": 15,
            "completed": 10,
            "pending": 5,
            "total_reward_value": "150"
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(LeaderboardEntry.self, from: json)
        XCTAssertEqual(entry.referrerId, "user_42")
        XCTAssertEqual(entry.referrerName, "Bob")
        XCTAssertEqual(entry.total, 15)
        XCTAssertEqual(entry.completed, 10)
        XCTAssertEqual(entry.pending, 5)
        XCTAssertEqual(entry.totalRewardValue, "150")
    }

    func testMessagesResponseDecoding() throws {
        let json = """
        {
            "messages": [
                {
                    "id": "msg_1",
                    "name": "welcome_message",
                    "title": "Welcome",
                    "body": "Thanks for joining!",
                    "trigger": "welcome",
                    "background_color": "#FFFFFF",
                    "priority": 1
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MessagesResponse.self, from: json)
        XCTAssertEqual(response.messages.count, 1)
        XCTAssertEqual(response.messages[0].id, "msg_1")
        XCTAssertEqual(response.messages[0].title, "Welcome")
        XCTAssertEqual(response.messages[0].trigger, "welcome")
    }

    func testCompleteReferralRequestEncoding() throws {
        let request = CompleteReferralRequest(
            referralCode: "REF001",
            referredUserId: "new_user",
            milestone: "signup"
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["referral_code"] as? String, "REF001")
        XCTAssertEqual(json?["referred_user_id"] as? String, "new_user")
        XCTAssertEqual(json?["milestone"] as? String, "signup")
    }

    func testClaimBySignalsRequestEncoding() throws {
        let request = ClaimBySignalsRequest(
            appspaceId: "asp_123",
            timezone: "America/New_York",
            language: "en",
            screenWidth: 390,
            screenHeight: 844
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["appspace_id"] as? String, "asp_123")
        XCTAssertEqual(json?["timezone"] as? String, "America/New_York")
        XCTAssertEqual(json?["language"] as? String, "en")
        XCTAssertEqual(json?["screen_width"] as? Int, 390)
        XCTAssertEqual(json?["screen_height"] as? Int, 844)
    }

    // MARK: - AnyCodableValue

    func testAnyCodableValueRoundTrip() throws {
        let values: [String: AnyCodableValue] = [
            "str": .string("hello"),
            "num": .int(42),
            "dbl": .double(3.14),
            "flag": .bool(true),
            "empty": .null
        ]

        let data = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode([String: AnyCodableValue].self, from: data)

        XCTAssertEqual(decoded["str"], .string("hello"))
        XCTAssertEqual(decoded["num"], .int(42))
        XCTAssertEqual(decoded["dbl"], .double(3.14))
        // After the fix, true encodes as true (not 1), but decoding tries Int first.
        // Since JSON true is not a valid Int, it falls through to Bool correctly.
        XCTAssertEqual(decoded["flag"], .bool(true))
        XCTAssertEqual(decoded["empty"], .null)
    }

    func testAnyCodableValueIntNotDecodedAsBool() throws {
        // Verify that integer 1 is decoded as .int(1), not .bool(true)
        let json = """
        {"count": 1, "zero": 0}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode([String: AnyCodableValue].self, from: json)
        XCTAssertEqual(decoded["count"], .int(1))
        XCTAssertEqual(decoded["zero"], .int(0))
    }

    // MARK: - TolinkuError

    func testTolinkuErrorDescriptions() {
        let errors: [(TolinkuError, String)] = [
            (.invalidURL("bad://url"), "Invalid URL: bad://url"),
            (.invalidResponse, "The server returned an invalid (non-HTTP) response."),
            (.httpError(statusCode: 401, message: "Unauthorized"), "HTTP 401: Unauthorized"),
            (.httpError(statusCode: 500, message: nil), "HTTP 500"),
            (.notConfigured, "TolinkuSDK has not been configured. Call Tolinku.configure(apiKey:baseURL:) first."),
            (.invalidConfiguration("apiKey must not be empty."), "Invalid configuration: apiKey must not be empty."),
        ]

        for (error, expected) in errors {
            XCTAssertEqual(error.errorDescription, expected)
        }
    }

    func testNetworkErrorDescription() {
        let urlError = URLError(.notConnectedToInternet)
        let error = TolinkuError.networkError(urlError)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("Network error") ?? false)
    }
}
