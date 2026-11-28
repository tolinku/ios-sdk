import XCTest
@testable import TolinkuSDK

final class MessagesTests: XCTestCase {

    private var messages: Messages!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let client = Client(apiKey: "tolk_pub_test", baseURL: "https://api.example.com", session: makeMockSession())
        messages = Messages(client: client)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func message(id: String, trigger: String = "event", triggerValue: String?, dismissDays: Int? = nil) -> String {
        let value = triggerValue.map { "\"\($0)\"" } ?? "null"
        let days = dismissDays.map(String.init) ?? "null"
        return """
        {"id":"\(id)","name":"\(id)","title":"T","trigger":"\(trigger)","trigger_value":\(value),
         "background_color":"#ffffff","priority":1,"dismiss_days":\(days)}
        """
    }

    private func respond(with items: [String]) {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{\"messages\":[\(items.joined(separator: ","))]}".data(using: .utf8)!)
        }
    }

    private func query(_ name: String) -> String? {
        guard let url = MockURLProtocol.requestLog.last?.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        return items.first { $0.name == name }?.value
    }

    // MARK: - trigger_value

    func testTriggerValueIsSentAsQueryParameter() async throws {
        respond(with: [])
        _ = try await messages.fetch(trigger: "event", triggerValue: "purchase")
        XCTAssertEqual(query("trigger"), "event")
        XCTAssertEqual(query("trigger_value"), "purchase")
    }

    func testNoTriggerValueSendsNoParameter() async throws {
        respond(with: [])
        _ = try await messages.fetch(trigger: "event")
        XCTAssertEqual(query("trigger"), "event")
        XCTAssertNil(query("trigger_value"))
    }

    /// An older server ignores trigger_value and returns every message of the
    /// trigger, so the SDK narrows them itself, the same way the server does.
    func testTriggerValueFiltersWhatAnOlderServerReturns() async throws {
        respond(with: [
            message(id: "purchase", triggerValue: "purchase"),
            message(id: "signup", triggerValue: "signup"),
            message(id: "any", triggerValue: nil),
            message(id: "empty", triggerValue: ""),
        ])
        let ids = try await messages.fetch(trigger: "event", triggerValue: "purchase").map(\.id)
        XCTAssertEqual(ids, ["purchase", "any", "empty"])
    }

    func testWithoutTriggerValueNothingIsFiltered() async throws {
        respond(with: [
            message(id: "purchase", triggerValue: "purchase"),
            message(id: "signup", triggerValue: "signup"),
        ])
        let ids = try await messages.fetch(trigger: "event").map(\.id)
        XCTAssertEqual(ids, ["purchase", "signup"])
    }

    // MARK: - Close memory

    private let day: TimeInterval = 86_400

    func testNoDismissDaysDoesNotRememberTheClose() {
        let now = Date()
        XCTAssertFalse(MessageTiming.stillDismissed(dismissedAt: now, dismissDays: nil, now: now))
        XCTAssertFalse(MessageTiming.stillDismissed(dismissedAt: now.addingTimeInterval(-1), dismissDays: nil, now: now))
    }

    func testZeroDismissDaysDoesNotRememberTheClose() {
        let now = Date()
        XCTAssertFalse(MessageTiming.stillDismissed(dismissedAt: now, dismissDays: 0, now: now))
    }

    func testDismissDaysHidesForThatManyDays() {
        let now = Date()
        XCTAssertTrue(MessageTiming.stillDismissed(dismissedAt: now.addingTimeInterval(-2 * day), dismissDays: 3, now: now))
        XCTAssertFalse(MessageTiming.stillDismissed(dismissedAt: now.addingTimeInterval(-4 * day), dismissDays: 3, now: now))
    }

    func testNeverClosedIsNotDismissed() {
        XCTAssertFalse(MessageTiming.stillDismissed(dismissedAt: nil, dismissDays: 7))
    }
}
