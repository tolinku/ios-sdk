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

    func testStaysAnAllowlistNowThatASecondRuleExistsBesideIt() {
        // The two rules are for different jobs, and widening a call to action
        // must not widen anything the SDK fetches or renders.
        XCTAssertTrue(isSafeUrl("https://example.com/promo"))
        XCTAssertTrue(isSafeUrl("http://example.com/promo"))
        XCTAssertFalse(isSafeUrl("myapp://order/4821"))
        XCTAssertFalse(isSafeUrl("market://details?id=com.example.app"))
        XCTAssertFalse(isSafeUrl("itms-apps://apps.apple.com/app/id123456789"))
        XCTAssertFalse(isSafeUrl("tel:+18005550199"))
        XCTAssertFalse(isSafeUrl("mailto:hi@example.com"))
    }
}

/// The rule for a message's call to action, which is a denylist on purpose.
///
/// A deep linking SDK whose in-app message cannot link into its own app is the
/// defect this covers: `myapp://order/4821` was dropped by the http/https
/// allowlist, silently, before the host app's own `onAction` handler was
/// called. There is no list of schemes to allow, since every customer has their
/// own, so only the schemes that can run code or forge an origin are named.
final class NavigableUrlTests: XCTestCase {

    func testAllowsACustomSchemeIntoTheHostApp() {
        // The defect: the most natural call to action on a deep linking product.
        XCTAssertTrue(isNavigableUrl("myapp://order/4821"))
        XCTAssertTrue(isNavigableUrl("com.example.app://profile"))
        XCTAssertTrue(isNavigableUrl("myapp://order/4821?ref=promo#top"))
    }

    func testAllowsTheSchemesThatReachAnotherApp() {
        XCTAssertTrue(isNavigableUrl("market://details?id=com.example.app"))
        XCTAssertTrue(isNavigableUrl("itms-apps://apps.apple.com/app/id123456789"))
        XCTAssertTrue(isNavigableUrl("intent://scan/#Intent;scheme=zxing;end"))
        XCTAssertTrue(isNavigableUrl("tel:+18005550199"))
        XCTAssertTrue(isNavigableUrl("mailto:hi@example.com"))
    }

    func testStillAllowsTheWeb() {
        XCTAssertTrue(isNavigableUrl("https://example.com/promo"))
        XCTAssertTrue(isNavigableUrl("http://example.com/promo"))
        XCTAssertTrue(isNavigableUrl("HTTPS://example.com/promo"))
    }

    func testRefusesEverySchemeThatCanRunCodeOrForgeAnOrigin() {
        for url in [
            "javascript:alert(1)",
            "vbscript:msgbox(1)",
            "data:text/html,<script>alert(1)</script>",
            "blob:https://example.com/abc-123",
            "file:///etc/passwd",
        ] {
            XCTAssertFalse(isNavigableUrl(url), "expected \(url) to be refused")
        }
    }

    func testIsNotFooledByTheCaseOfADeniedScheme() {
        XCTAssertFalse(isNavigableUrl("JavaScript:alert(1)"))
        XCTAssertFalse(isNavigableUrl("JAVASCRIPT:alert(1)"))
        XCTAssertFalse(isNavigableUrl("DaTa:text/html,x"))
    }

    func testIsNotFooledByWhitespaceAroundOrInsideADeniedScheme() {
        // Tabs and newlines inside a scheme are ignored by whatever follows the
        // URL, so these navigate as javascript: unless they are stripped first.
        XCTAssertFalse(isNavigableUrl("  javascript:alert(1)"))
        XCTAssertFalse(isNavigableUrl("javascript:alert(1)  "))
        XCTAssertFalse(isNavigableUrl("java\tscript:alert(1)"))
        XCTAssertFalse(isNavigableUrl("java\nscript:alert(1)"))
        XCTAssertFalse(isNavigableUrl("java\r\nscript:alert(1)"))
        XCTAssertFalse(isNavigableUrl("\tjavascript:alert(1)"))
        XCTAssertFalse(isNavigableUrl("  Java\tScript:alert(1)"))
    }

    func testStillAllowsACustomSchemeBehindWhitespace() {
        XCTAssertTrue(isNavigableUrl("  myapp://order/4821  "))
    }

    func testRefusesAUrlWithNoScheme() {
        // Relative or a fragment. There is no base to resolve it against here.
        XCTAssertFalse(isNavigableUrl("example.com"))
        XCTAssertFalse(isNavigableUrl("//example.com"))
        XCTAssertFalse(isNavigableUrl("/promo"))
        XCTAssertFalse(isNavigableUrl("#section"))
        XCTAssertFalse(isNavigableUrl("not a url"))
    }

    func testTreatsAbsentOrEmptyAsNotNavigable() {
        XCTAssertFalse(isNavigableUrl(nil))
        XCTAssertFalse(isNavigableUrl(""))
        XCTAssertFalse(isNavigableUrl("   "))
    }

    func testReadsTheSchemeOfAUrlThatFoundationWillNotParse() {
        // URL(string:) refuses an unencoded space, so relying on it alone would
        // refuse a working deep link and, worse, wave a dangerous one through as
        // unrecognised.
        XCTAssertFalse(isNavigableUrl("javascript:alert(1, 2)"))
        XCTAssertTrue(isNavigableUrl("myapp://order/4821 promo"))
    }
}
