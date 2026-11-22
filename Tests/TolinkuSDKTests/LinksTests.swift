import XCTest
@testable import TolinkuSDK

/// Turning a link the system handed the app into something routable.
///
/// The URL an app receives is the one that was tapped, exactly as written. A
/// short link is an opaque code, `/s7k2p9q/4821`, and nothing on the device
/// can say what the code stands for. An app parsing the path itself sees a
/// first component it has never heard of and does nothing, so the link opens
/// the app and appears to fail with no error and no screen.
///
/// The question has to go to the link's own host, because that is how the
/// platform knows which Appspace is being asked about. The client here is
/// deliberately configured with a different base URL, so a request sent to that
/// one instead shows up as a failure rather than passing by accident.
final class LinksTests: XCTestCase {

    private var session: URLSession!
    private var links: Links!

    private let answer = """
    {
        "route": {
            "prefix": "order/{token}/receipt",
            "name": "Order Receipt",
            "template": "none",
            "link_type": "dynamic"
        },
        "token": "4821",
        "deep_link_path": "/order/4821/receipt",
        "appspace": {"name": "Example App", "slug": "example"}
    }
    """

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = makeMockSession()
        let client = Client(
            apiKey: "tolk_pub_test",
            baseURL: "https://somewhere-else.example.com",
            session: session
        )
        links = Links(client: client)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func respond(_ body: String, status: Int = 200) {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body.data(using: .utf8))
        }
    }

    private func sentBody(_ index: Int = 0) -> [String: String]? {
        guard MockURLProtocol.requestLog.indices.contains(index) else { return nil }
        let request = MockURLProtocol.requestLog[index]
        guard let data = request.httpBody ?? request.httpBodyStream.map({ stream -> Data in
                  stream.open()
                  var data = Data()
                  let size = 1024
                  let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
                  defer { buffer.deallocate(); stream.close() }
                  while stream.hasBytesAvailable {
                      let read = stream.read(buffer, maxLength: size)
                      if read <= 0 { break }
                      data.append(buffer, count: read)
                  }
                  return data
              })
        else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    func testAsksTheLinkItsOwnHostWithJustThePath() async throws {
        respond(answer)

        let link = await links.resolve("https://links.example.com/s7k2p9q/4821")

        XCTAssertEqual(MockURLProtocol.requestLog.count, 1)
        XCTAssertEqual(
            MockURLProtocol.requestLog.first?.url?.absoluteString,
            "https://links.example.com/v1/api/path"
        )
        XCTAssertEqual(sentBody()?["path"], "/s7k2p9q/4821")

        let resolved = try XCTUnwrap(link)
        XCTAssertEqual(resolved.token, "4821")
        XCTAssertEqual(resolved.deepLinkPath, "/order/4821/receipt")
        XCTAssertEqual(resolved.route.prefix, "order/{token}/receipt")
        XCTAssertEqual(resolved.route.name, "Order Receipt")
        XCTAssertEqual(resolved.route.linkType, "dynamic")
    }

    func testAsksWithoutTheAPIKeySinceTheHostIsNotNecessarilyOurs() async {
        // The origin comes from the URL this was handed. An app resolving a
        // link from somewhere it does not control would otherwise send the
        // Appspace's key to a stranger.
        respond(answer)

        _ = await links.resolve("https://links.example.com/s7k2p9q/4821")

        let headers = MockURLProtocol.requestLog.first?.allHTTPHeaderFields ?? [:]
        XCTAssertNil(headers["X-API-Key"])
        XCTAssertNil(headers["Authorization"])
    }

    func testLeavesTheQueryStringOutOfTheQuestion() async {
        // A tapped link usually carries utm parameters, and they say nothing
        // about which route it is.
        respond(answer)

        _ = await links.resolve("https://links.example.com/s7k2p9q/4821?utm_source=qr")

        XCTAssertEqual(sentBody()?["path"], "/s7k2p9q/4821")
    }

    func testKeepsAnEncodedSlashInTheTokenEncoded() async {
        // Decoding first turns "/promo/a%2Fb" into a path three deep rather
        // than a token of "a/b" on "promo", which resolves to a different route
        // or to nothing.
        respond(answer)

        _ = await links.resolve("https://links.example.com/promo/a%2Fb")

        XCTAssertEqual(sentBody()?["path"], "/promo/a%2Fb")
    }

    /// resolve sends its question to a host taken from the URL it was given, so
    /// an app resolving a link from somewhere it does not control is talking to
    /// a stranger. Anything but a path is a redirect waiting to happen.
    ///
    /// Both questions get the same unsafe answer here, so this covers both:
    /// the host's answer is not a Tolinku "error" reply, so the API is asked
    /// too, and its answer is held to the same rule.
    private func assertRefuses(path badPath: String) async {
        respond(answer.replacingOccurrences(of: "/order/4821/receipt", with: badPath))
        let link = await links.resolve("https://links.example.com/s7k2p9q/4821")
        XCTAssertNil(link)
        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
    }

    func testRefusesAnAnswerThatIsAFullURL() async {
        await assertRefuses(path: "https://evil.example.com/take-over")
    }

    func testRefusesAnAnswerThatIsProtocolRelative() async {
        await assertRefuses(path: "//evil.example.com/take-over")
    }

    func testRefusesAnAnswerThatIsABareWord() async {
        await assertRefuses(path: "order/4821")
    }

    func testRefusesAnAnswerThatIsNothing() async {
        await assertRefuses(path: "")
    }

    func testSaysNothingForACustomSchemeLink() async {
        // That one already carries the path the app wants.
        respond(answer)

        let link = await links.resolve("example://order/4821/receipt")

        XCTAssertNil(link)
        XCTAssertTrue(MockURLProtocol.requestLog.isEmpty)
    }

    func testSaysNothingForSomethingThatIsNotALink() async {
        respond(answer)

        // Bound first: XCTAssertNil takes an autoclosure, which cannot await.
        let path = await links.resolve("/order/4821")
        let empty = await links.resolve("")
        XCTAssertNil(path)
        XCTAssertNil(empty)
        XCTAssertTrue(MockURLProtocol.requestLog.isEmpty)
    }

    func testReturnsNilRatherThanThrowingIntoAColdStart() async {
        // This runs while the app is opening. An error thrown here is the
        // difference between a link that did not route and an app that did not
        // start.
        respond(#"{"error": "Route not found"}"#, status: 404)

        let link = await links.resolve("https://links.example.com/s7k2p9q/4821")

        XCTAssertNil(link)
    }

    func testReturnsNilForALinkThisAppspaceDoesNotOwn() async {
        respond("{}")

        let link = await links.resolve("https://links.example.com/whatever/1")
        XCTAssertNil(link)
    }

    // MARK: - Links from emails

    /// Answers the two questions separately. `host` answers the link's own
    /// host, `api` answers Tolinku's API; either may throw to stand for a
    /// network failure.
    private func respond(
        host: @escaping (URLRequest) throws -> (Int, String),
        api: @escaping (URLRequest) throws -> (Int, String)
    ) {
        MockURLProtocol.requestHandler = { request in
            let isAPI = request.url?.path == "/v1/api/links/resolve"
            let (status, body) = try (isAPI ? api : host)(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body.data(using: .utf8))
        }
    }

    private func requests(to path: String) -> [URLRequest] {
        MockURLProtocol.requestLog.filter { $0.url?.path == path }
    }

    func testSendsTheWholeLinkAlongWithThePath() async {
        // A wrapped email link keeps where it really goes in the query, which
        // the path alone leaves behind. The encoding stays as written.
        respond(answer)

        let wrapped = "https://url1234.email.example.com/uni/ls/click?upn=XYZ%2Babc"
        _ = await links.resolve(wrapped)

        XCTAssertEqual(sentBody()?["path"], "/uni/ls/click")
        XCTAssertEqual(sentBody()?["url"], wrapped)
    }

    func testNormalisesTheLinkBeforeAskingAboutIt() async {
        respond(answer)

        _ = await links.resolve("  HTTP://Links.Example.COM:80/S7k2p9q/a%2Fb?Utm=QR&x=%41#Section  ")

        XCTAssertEqual(
            MockURLProtocol.requestLog.first?.url?.absoluteString,
            "https://links.example.com/v1/api/path"
        )
        XCTAssertEqual(sentBody()?["path"], "/S7k2p9q/a%2Fb")
        XCTAssertEqual(sentBody()?["url"], "https://links.example.com/S7k2p9q/a%2Fb?Utm=QR&x=%41")
    }

    func testNormalisationTable() throws {
        let cases: [(String, String?)] = [
            ("http://links.example.com/a", "https://links.example.com/a"),
            ("https://links.example.com:443/a", "https://links.example.com/a"),
            ("https://links.example.com:80/a", "https://links.example.com/a"),
            ("https://links.example.com:8443/a?b=1", "https://links.example.com:8443/a?b=1"),
            ("HTTPS://LINKS.example.com", "https://links.example.com/"),
            ("https://links.example.com/a?#top", "https://links.example.com/a"),
            ("ftp://links.example.com/a", nil),
            ("example://order/1", nil),
        ]
        for (input, expected) in cases {
            let url = try XCTUnwrap(URL(string: input), input)
            XCTAssertEqual(Links.normalise(url)?.whole, expected, input)
        }

        let link = try XCTUnwrap(Links.normalise(XCTUnwrap(URL(string: "http://Links.Example.com:8080/x"))))
        XCTAssertEqual(link.origin, "https://links.example.com:8080")
        XCTAssertEqual(link.host, "links.example.com")
        XCTAssertEqual(link.path, "/x")
    }

    func testAsksTheAPIWithTheKeyWhenTheLinksOwnHostGivesNoTolinkuAnswer() async throws {
        // A click domain that does not lead to Tolinku: a 404 page, not JSON.
        respond(host: { _ in (404, "<html>Not Found</html>") }, api: { [answer = self.answer] _ in (200, answer) })

        let wrapped = "https://trk.example.com/c/abc123?q=1"
        let link = await links.resolve(wrapped)

        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
        XCTAssertEqual(
            MockURLProtocol.requestLog.first?.url?.absoluteString,
            "https://trk.example.com/v1/api/path"
        )
        XCTAssertNil(MockURLProtocol.requestLog.first?.value(forHTTPHeaderField: "X-API-Key"))

        let fallback = MockURLProtocol.requestLog[1]
        XCTAssertEqual(
            fallback.url?.absoluteString,
            "https://somewhere-else.example.com/v1/api/links/resolve"
        )
        XCTAssertEqual(fallback.httpMethod, "POST")
        XCTAssertEqual(fallback.value(forHTTPHeaderField: "X-API-Key"), "tolk_pub_test")
        XCTAssertEqual(sentBody(1), ["url": wrapped])

        let resolved = try XCTUnwrap(link)
        XCTAssertEqual(resolved.token, "4821")
        XCTAssertEqual(resolved.deepLinkPath, "/order/4821/receipt")
    }

    func testSendsTheNormalisedLinkToTheAPIToo() async {
        respond(host: { _ in (404, "") }, api: { [answer = self.answer] _ in (200, answer) })

        _ = await links.resolve("http://Trk.Example.com:443/c/X?u=1#frag")

        XCTAssertEqual(sentBody(1), ["url": "https://trk.example.com/c/X?u=1"])
    }

    func testFallsBackWhenTheLinksOwnHostCannotBeReached() async throws {
        respond(
            host: { _ in throw URLError(.cannotFindHost) },
            api: { [answer = self.answer] _ in (200, answer) }
        )

        let link = await links.resolve("https://trk.example.com/c/abc123")

        XCTAssertEqual(try XCTUnwrap(link).deepLinkPath, "/order/4821/receipt")
        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
    }

    func testFallsBackOnJSONWithoutAnError() async throws {
        respond(host: { _ in (404, #"{"message": "nope"}"#) }, api: { [answer = self.answer] _ in (200, answer) })

        let link = await links.resolve("https://trk.example.com/c/abc123")

        XCTAssertNotNil(link)
        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
    }

    func testFallsBackOnAnErrorThatIsNotAString() async throws {
        respond(host: { _ in (404, #"{"error": {"code": 1}}"#) }, api: { [answer = self.answer] _ in (200, answer) })

        let link = await links.resolve("https://trk.example.com/c/abc123")

        XCTAssertNotNil(link)
        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
    }

    /// The host is Tolinku and has answered. Asking the API too would count
    /// the email click twice.
    private func assertNoFallback(afterHostSays body: String, status: Int) async {
        respond(host: { _ in (status, body) }, api: { [answer = self.answer] _ in (200, answer) })

        let link = await links.resolve("https://trk.example.com/c/abc123")

        XCTAssertNil(link)
        XCTAssertEqual(MockURLProtocol.requestLog.count, 1)
        XCTAssertTrue(requests(to: "/v1/api/links/resolve").isEmpty)
    }

    func testATolinkuNotFoundStopsThere() async {
        await assertNoFallback(afterHostSays: #"{"error": "Route not found"}"#, status: 404)
    }

    func testATolinkuNotFoundWithAWebURLStopsThere() async {
        await assertNoFallback(
            afterHostSays: #"{"error": "Route not found", "web_url": "https://example.com/"}"#,
            status: 404
        )
    }

    func testATolinkuErrorWithAnyStatusStopsThere() async {
        await assertNoFallback(afterHostSays: #"{"error": "Internal error"}"#, status: 500)
    }

    func testNeverRetriesEitherQuestion() async {
        // A 503 and a network error are both retried by the SDK's other
        // requests. Here each question is asked exactly once.
        respond(
            host: { _ in (503, "Service Unavailable") },
            api: { _ in throw URLError(.timedOut) }
        )

        let link = await links.resolve("https://trk.example.com/c/abc123")

        XCTAssertNil(link)
        XCTAssertEqual(requests(to: "/v1/api/path").count, 1)
        XCTAssertEqual(requests(to: "/v1/api/links/resolve").count, 1)
        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
    }

    func testNeverRetriesTheAPIOnA5xx() async {
        respond(host: { _ in throw URLError(.notConnectedToInternet) }, api: { _ in (500, "oops") })

        let link = await links.resolve("https://trk.example.com/c/abc123")

        XCTAssertNil(link)
        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
    }

    func testBothQuestionsHaveAFiveSecondLimit() async {
        respond(host: { _ in (404, "") }, api: { [answer = self.answer] _ in (200, answer) })

        _ = await links.resolve("https://trk.example.com/c/abc123")

        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
        for request in MockURLProtocol.requestLog {
            XCTAssertEqual(request.timeoutInterval, 5, request.url?.absoluteString ?? "")
        }
    }

    func testDoesNotAskTheAPIAgainWhenTheLinkIsOnTheAPIHost() async {
        // The same host twice gets the same answer twice. Case and port do not
        // make it a different host.
        respond(host: { _ in (404, "") }, api: { [answer = self.answer] _ in (200, answer) })

        for link in [
            "https://somewhere-else.example.com/s7k2p9q/4821",
            "https://SomeWhere-Else.Example.COM/s7k2p9q/4821",
            "https://somewhere-else.example.com:8443/s7k2p9q/4821",
            "http://somewhere-else.example.com/s7k2p9q/4821",
        ] {
            MockURLProtocol.requestLog = []
            let resolved = await links.resolve(link)
            XCTAssertNil(resolved, link)
            XCTAssertEqual(MockURLProtocol.requestLog.count, 1, link)
            XCTAssertEqual(MockURLProtocol.requestLog.first?.url?.path, "/v1/api/path", link)
        }
    }

    func testComparesWithAnAPIBaseURLThatHasCapitalsAndAPort() async {
        respond(host: { _ in (404, "") }, api: { [answer = self.answer] _ in (200, answer) })
        let client = Client(
            apiKey: "tolk_pub_test",
            baseURL: "https://API.Example.com:8443/",
            session: session
        )
        let links = Links(client: client)

        let skipped = await links.resolve("https://api.example.com/s7k2p9q/4821")
        XCTAssertNil(skipped)
        XCTAssertEqual(MockURLProtocol.requestLog.count, 1)

        MockURLProtocol.requestLog = []
        let asked = await links.resolve("https://trk.example.com/c/abc123")
        XCTAssertNotNil(asked)
        XCTAssertEqual(
            MockURLProtocol.requestLog.last?.url?.absoluteString.lowercased(),
            "https://api.example.com:8443/v1/api/links/resolve"
        )
    }

    func testDoesNotAskTheAPIWithoutAKey() async {
        respond(host: { _ in (404, "") }, api: { [answer = self.answer] _ in (200, answer) })
        let links = Links(client: Client(apiKey: "", baseURL: "https://somewhere-else.example.com", session: session))

        let link = await links.resolve("https://trk.example.com/c/abc123")

        XCTAssertNil(link)
        XCTAssertEqual(MockURLProtocol.requestLog.count, 1)
    }

    func testRefusesAnUnsafeAnswerFromTheAPIToo() async {
        let unsafe = answer.replacingOccurrences(of: "/order/4821/receipt", with: "//evil.example.com/take-over")
        respond(host: { _ in (404, "") }, api: { _ in (200, unsafe) })

        let link = await links.resolve("https://trk.example.com/c/abc123")

        XCTAssertNil(link)
        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
    }

    func testRefusesAnUnsafeAnswerFromTheHostEvenWhenTheAPIFails() async {
        let unsafe = answer.replacingOccurrences(of: "/order/4821/receipt", with: "https://evil.example.com/")
        respond(host: { _ in (200, unsafe) }, api: { _ in (404, #"{"error": "Not found"}"#) })

        let link = await links.resolve("https://trk.example.com/c/abc123")

        XCTAssertNil(link)
        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
    }
}
