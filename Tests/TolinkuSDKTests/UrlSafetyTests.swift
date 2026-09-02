import XCTest
@testable import TolinkuSDK

/// The same rule the Android, Flutter, React Native and web SDKs apply, so a
/// message button behaves the same wherever it is tapped.
///
/// An in-app message is rendered in a WebView and can ask the app to navigate,
/// so the URL it names crosses from page content into native code.
final class UrlSafetyTests: XCTestCase {

    func testAllowsTheTwoWebSchemes() {
        XCTAssertTrue(isSafeUrl("https://example.com/promo"))
        XCTAssertTrue(isSafeUrl("http://example.com/promo"))
    }

    func testIsNotFooledByTheCaseOfTheScheme() {
        XCTAssertTrue(isSafeUrl("HTTPS://example.com/promo"))
        XCTAssertFalse(isSafeUrl("JavaScript:alert(1)"))
    }

    func testBlocksSchemesThatDoSomethingOtherThanOpenAPage() {
        for url in [
            "javascript:alert(1)",
            "file:///etc/passwd",
            "data:text/html,<script>alert(1)</script>",
            "myapp://promo",
        ] {
            XCTAssertFalse(isSafeUrl(url), "expected \(url) to be refused")
        }
    }

    func testBlocksASchemeHiddenBehindWhitespace() {
        XCTAssertFalse(isSafeUrl("  javascript:alert(1)"))
    }

    func testAllowsARealUrlBehindWhitespace() {
        XCTAssertTrue(isSafeUrl("  https://example.com/promo  "))
    }

    func testTreatsAbsentOrEmptyAsUnsafe() {
        XCTAssertFalse(isSafeUrl(nil))
        XCTAssertFalse(isSafeUrl(""))
        XCTAssertFalse(isSafeUrl("   "))
    }

    func testRequiresASchemeRatherThanAssumingOne() {
        XCTAssertFalse(isSafeUrl("example.com"))
        XCTAssertFalse(isSafeUrl("/promo"))
    }
}
