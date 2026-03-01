import XCTest
@testable import TolinkuSDK

final class AnalyticsTests: XCTestCase {

    private var session: URLSession!
    private var client: Client!
    private var analytics: Analytics!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = makeMockSession()
        client = Client(apiKey: "tolk_pub_test", baseURL: "https://api.example.com", session: session)
        analytics = Analytics(client: client)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Track Queues Events

    func testTrackQueuesEvents() async throws {
        // Set up a handler that succeeds, but we do not expect it to be called
        // until we flush (tracking fewer than 10 events should not trigger a send).
        var batchCallCount = 0
        MockURLProtocol.requestHandler = { request in
            batchCallCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        // Track 3 events (below the batch threshold of 10)
        await analytics.track("custom.event1")
        await analytics.track("custom.event2")
        await analytics.track("custom.event3", properties: ["key": .string("value")])

        // Give a small amount of time for any unexpected immediate flush
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // No batch should have been sent yet (below threshold, timer not yet expired)
        XCTAssertEqual(batchCallCount, 0)
    }

    // MARK: - Batch Flushes at 10 Events

    func testBatchFlushesAt10Events() async throws {
        var batchRequestReceived = false

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.hasSuffix("/v1/api/analytics/batch") == true {
                batchRequestReceived = true
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        // Track exactly 10 events to trigger automatic flush
        for i in 1...10 {
            await analytics.track("custom.event\(i)")
        }

        // Allow time for the batch to be sent
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Verify a batch request was sent
        XCTAssertTrue(batchRequestReceived, "Expected a batch request to be sent after 10 events")
    }

    // MARK: - Manual Flush

    func testManualFlush() async throws {
        var batchRequestReceived = false

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.hasSuffix("/v1/api/analytics/batch") == true {
                batchRequestReceived = true
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        await analytics.track("custom.manual_event", properties: ["source": .string("test")])
        await analytics.flush()

        // Allow a moment for the async operation to complete
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Verify a batch request was sent
        XCTAssertTrue(batchRequestReceived, "Expected a batch request after manual flush")
    }

    // MARK: - Event Format

    func testEventFormat() async throws {
        var receivedBatchBody: Data?

        MockURLProtocol.requestHandler = { request in
            // Read body from httpBody or httpBodyStream
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: 4096)
                    if read > 0 { data.append(buffer, count: read) }
                    else { break }
                }
                stream.close()
                body = data.isEmpty ? nil : data
            }
            receivedBatchBody = body
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        await analytics.track("custom.signup", properties: ["plan": .string("standard"), "count": .int(3)])
        await analytics.flush()

        // Allow a moment for the async operation to complete
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        guard let body = receivedBatchBody else {
            return XCTFail("Expected batch body to be present")
        }

        // Parse the JSON body
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertNotNil(json)

        let events = json?["events"] as? [[String: Any]]
        XCTAssertNotNil(events)
        XCTAssertEqual(events?.count, 1)

        let event = events?.first
        XCTAssertEqual(event?["event_type"] as? String, "custom.signup")

        // Verify properties
        let props = event?["properties"] as? [String: Any]
        XCTAssertEqual(props?["plan"] as? String, "standard")
        XCTAssertEqual(props?["count"] as? Int, 3)
    }

    // MARK: - Empty Flush Does Nothing

    func testEmptyFlushDoesNotSendRequest() async throws {
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        // Flush with no events queued
        await analytics.flush()

        XCTAssertEqual(requestCount, 0, "Flushing an empty queue should not send any requests")
    }

    // MARK: - BatchEventsRequest Encoding

    func testBatchEventsRequestEncoding() throws {
        let events = [
            BatchEvent(
                eventType: "custom.test",
                properties: ["key": .string("val")]
            ),
            BatchEvent(
                eventType: "custom.other",
                properties: nil
            )
        ]
        let request = BatchEventsRequest(events: events)
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let encodedEvents = json?["events"] as? [[String: Any]]
        XCTAssertEqual(encodedEvents?.count, 2)
        XCTAssertEqual(encodedEvents?[0]["event_type"] as? String, "custom.test")
        XCTAssertEqual(encodedEvents?[1]["event_type"] as? String, "custom.other")
        XCTAssertNil(encodedEvents?[1]["properties"])
    }
}
