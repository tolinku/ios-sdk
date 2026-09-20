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

    func testRefusesTheSchemesThatReadLocalStorageOrWrapAnotherUrl() {
        // These do nothing on iOS. They are refused here because the four SDKs
        // are documented as applying one rule, and a rule that differs per
        // platform is one nobody can check.
        XCTAssertFalse(isNavigableUrl("content://com.host/secret"))
        XCTAssertFalse(isNavigableUrl("jar:file:///x!/y"))
        XCTAssertFalse(isNavigableUrl("filesystem:file:///persistent/x"))
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
        // URL, so these navigate as javascript: unless they are stripped first,
        // after which every one of them reads as the denied scheme it is.
        XCTAssertFalse(isNavigableUrl("  javascript:alert(1)"))
        XCTAssertFalse(isNavigableUrl("javascript:alert(1)  "))
        XCTAssertFalse(isNavigableUrl("java\tscript:alert(1)"))
        XCTAssertFalse(isNavigableUrl("java\nscript:alert(1)"))
        XCTAssertFalse(isNavigableUrl("java\r\nscript:alert(1)"))
        XCTAssertFalse(isNavigableUrl("\tjavascript:alert(1)"))
        XCTAssertFalse(isNavigableUrl("  Java\tScript:alert(1)"))
    }

    func testStripsACrlfTheWayTheOtherSdksDo() {
        // Swift reads "\r\n" as a single Character, so stripping by character
        // left the pair in place and a URL carrying one was refused as
        // unparseable rather than normalised. Android, Flutter and React Native
        // all strip it and open the link, and a denied scheme spelt across one
        // has to be caught for the same reason a tab is.
        XCTAssertTrue(isNavigableUrl("my\r\napp://order/4821"))
        XCTAssertTrue(isNavigableUrl("https://example.com/pro\r\nmo"))
        XCTAssertFalse(isNavigableUrl("ja\r\nva\r\nscript:alert(1)"))
    }

    func testAllowsAnUnderscoreInAScheme() {
        // RFC 3986 has no "_" in a scheme, but iOS registers one happily in
        // `CFBundleURLSchemes` and apps ship with it, so refusing it is the
        // silent drop this denylist exists to undo, narrowed to the customers
        // whose scheme happens to carry one.
        XCTAssertTrue(isNavigableUrl("my_app://order/4821"))
        XCTAssertTrue(isNavigableUrl("my_app_://order/4821"))
        XCTAssertTrue(isNavigableUrl("  My_App://order/4821  "))
        // Still a scheme, so a denied one written with an underscore beside it
        // is a different scheme rather than a way through.
        XCTAssertTrue(isNavigableUrl("java_script:alert(1)"))
        // And a leading underscore is still not a scheme at all.
        XCTAssertFalse(isNavigableUrl("_app://order/4821"))
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

/// What tapping a message's call to action actually does.
///
/// The presenter itself needs UIKit and WebKit, so no test in this suite can
/// reach it and a change there is asserted nowhere. The decision it makes lives
/// on its own for that reason, and this is where it is held to account.
final class MessageActionTests: XCTestCase {

    private func followedUrl(_ urlString: String?) -> URL? {
        guard case let .follow(_, url) = messageAction(for: urlString) else { return nil }
        return url
    }

    func testFollowsADeepLinkIntoTheHostApp() {
        XCTAssertEqual(
            messageAction(for: "myapp://order/4821"),
            .follow(urlString: "myapp://order/4821", url: URL(string: "myapp://order/4821"))
        )
    }

    func testFollowsADeepLinkWhoseSchemeCarriesAnUnderscore() {
        // Whether Foundation builds a URL out of one of these depends on the iOS
        // version, so this asserts only the part that is ours: the action is
        // followed, and the app's own handler hears about it either way.
        guard case .follow = messageAction(for: "my_app://order/4821") else {
            return XCTFail("expected my_app://order/4821 to be followed")
        }
    }

    func testRefusesASchemeThatCanRunCode() {
        for urlString in [
            "javascript:alert(1)",
            "JavaScript:alert(1)",
            "java\tscript:alert(1)",
            "data:text/html,<script>alert(1)</script>",
            "file:///etc/passwd",
        ] {
            XCTAssertEqual(messageAction(for: urlString), .refuse, "expected \(urlString) to be refused")
        }
    }

    func testRefusesSomethingThatNamesNoSchemeAtAll() {
        XCTAssertEqual(messageAction(for: nil), .refuse)
        XCTAssertEqual(messageAction(for: ""), .refuse)
        XCTAssertEqual(messageAction(for: "   "), .refuse)
        XCTAssertEqual(messageAction(for: "/promo"), .refuse)
        XCTAssertEqual(messageAction(for: "#section"), .refuse)
    }

    func testBuildsAUrlForALinkTheDirectInitialiserRefuses() {
        // `Package.swift` declares iOS 15, where URL(string:) returns nil for any
        // raw space or non-ASCII character. These are working deep links, and
        // handing them to the initialiser alone dropped them.
        XCTAssertEqual(followedUrl("myapp://open now/order/4821")?.absoluteString, "myapp://open%20now/order/4821")
        XCTAssertEqual(followedUrl("myapp://search?q=café")?.absoluteString, "myapp://search?q=caf%C3%A9")
        XCTAssertEqual(followedUrl("https://example.com/promo")?.absoluteString, "https://example.com/promo")
    }

    func testDoesNotEncodeAnAlreadyEncodedUrlTwice() {
        // `%` stays legal on the repair pass, or `%20` becomes `%2520` and the
        // app receives a path nobody wrote.
        XCTAssertEqual(
            followedUrl("myapp://open now/a%20b")?.absoluteString,
            "myapp://open%20now/a%20b"
        )
    }

    func testKeepsTheQueryAndFragmentWhoseCharactersItCouldHaveEncoded() {
        XCTAssertEqual(
            followedUrl("myapp://open now/order?ref=promo#top")?.absoluteString,
            "myapp://open%20now/order?ref=promo#top"
        )
    }

    func testOpensTheSameUrlWhoseSchemeWasVetted() {
        // The scheme is read from the normalised string, so the URL has to be
        // built from that same string. Encoding the raw text instead would turn
        // the wrapping spaces into %20 and open something with no scheme at all.
        XCTAssertEqual(followedUrl("  myapp://order/4821  ")?.absoluteString, "myapp://order/4821")
        XCTAssertEqual(followedUrl("my\r\napp://order/4821")?.absoluteString, "myapp://order/4821")
        XCTAssertEqual(followedUrl("my\tapp://order/4821")?.absoluteString, "myapp://order/4821")
    }

    func testHandsTheHostAppTheStringItWasGiven() {
        // Whatever repair the URL needed, the app's own handler reads its own
        // deep links and gets them exactly as the message wrote them.
        guard case let .follow(urlString, _) = messageAction(for: "  myapp://order/4821  ") else {
            return XCTFail("expected the action to be followed")
        }
        XCTAssertEqual(urlString, "  myapp://order/4821  ")
    }

    func testStillFollowsALinkNoUrlCanBeBuiltFrom() {
        // A scheme worth allowing whose string Foundation will not parse is not
        // the same thing as a scheme worth refusing. The host app's handler
        // takes the string and knows what to do with it, and only the branch
        // that needs a URL of its own has nothing to work with.
        XCTAssertEqual(messageAction(for: "myapp://[bad"), .follow(urlString: "myapp://[bad", url: nil))
    }
}
