import XCTest
@testable import TolinkuSDK

/// Turning a link the system handed the app into something routable.
///
/// The URL an app receives is the one that was tapped, exactly as written. A
/// short link is an opaque code, `/imbwmum/1007100`, and nothing on the device
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
        "token": "1007100",
        "deep_link_path": "/order/1007100/receipt",
        "appspace": {"name": "Tasonic", "slug": "tasonic"}
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

    private func sentBody() -> [String: String]? {
        guard let request = MockURLProtocol.requestLog.first,
              let data = request.httpBody ?? request.httpBodyStream.map({ stream -> Data in
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

        let link = await links.resolve("https://links.tasonic.com/imbwmum/1007100")

        XCTAssertEqual(MockURLProtocol.requestLog.count, 1)
        XCTAssertEqual(
            MockURLProtocol.requestLog.first?.url?.absoluteString,
            "https://links.tasonic.com/v1/api/path"
        )
        XCTAssertEqual(sentBody()?["path"], "/imbwmum/1007100")

        let resolved = try XCTUnwrap(link)
        XCTAssertEqual(resolved.token, "1007100")
        XCTAssertEqual(resolved.deepLinkPath, "/order/1007100/receipt")
        XCTAssertEqual(resolved.route.prefix, "order/{token}/receipt")
        XCTAssertEqual(resolved.route.name, "Order Receipt")
        XCTAssertEqual(resolved.route.linkType, "dynamic")
    }

    func testLeavesTheQueryStringOutOfTheQuestion() async {
        // A tapped link usually carries utm parameters, and they say nothing
        // about which route it is.
        respond(answer)

        _ = await links.resolve("https://links.tasonic.com/imbwmum/1007100?utm_source=qr")

        XCTAssertEqual(sentBody()?["path"], "/imbwmum/1007100")
    }

    func testKeepsAnEncodedSlashInTheTokenEncoded() async {
        // Decoding first turns "/promo/a%2Fb" into a path three deep rather
        // than a token of "a/b" on "promo", which resolves to a different route
        // or to nothing.
        respond(answer)

        _ = await links.resolve("https://links.tasonic.com/promo/a%2Fb")

        XCTAssertEqual(sentBody()?["path"], "/promo/a%2Fb")
    }

    func testSaysNothingForACustomSchemeLink() async {
        // That one already carries the path the app wants.
        respond(answer)

        let link = await links.resolve("tasonic://order/1007100/receipt")

        XCTAssertNil(link)
        XCTAssertTrue(MockURLProtocol.requestLog.isEmpty)
    }

    func testSaysNothingForSomethingThatIsNotALink() async {
        respond(answer)

        // Bound first: XCTAssertNil takes an autoclosure, which cannot await.
        let path = await links.resolve("/order/1007100")
        let empty = await links.resolve("")
        XCTAssertNil(path)
        XCTAssertNil(empty)
        XCTAssertTrue(MockURLProtocol.requestLog.isEmpty)
    }

    func testReturnsNilRatherThanThrowingIntoAColdStart() async {
        // This runs while the app is opening. An error thrown here is the
        // difference between a link that did not route and an app that did not
        // start. 404 is not retried, so one response is enough.
        respond("{}", status: 404)

        let link = await links.resolve("https://links.tasonic.com/imbwmum/1007100")

        XCTAssertNil(link)
    }

    func testReturnsNilForALinkThisAppspaceDoesNotOwn() async {
        respond("{}")

        let link = await links.resolve("https://links.example.com/whatever/1")
        XCTAssertNil(link)
    }
}
