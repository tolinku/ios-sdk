import Foundation

/// Whether a URL is safe to open or hand to app code.
///
/// Only `http` and `https`. An in-app message is rendered in a WebView and can
/// ask the app to navigate, so the URL it names crosses from page content into
/// native code. Every other scheme a URL can carry is a way of doing something
/// besides opening a web page: `javascript:` executes, `file:` reads local
/// storage, and a custom scheme reaches another app.
///
/// The same rule the Android, Flutter, React Native and web SDKs apply, so a
/// message button behaves the same wherever it is tapped.
func isSafeUrl(_ url: String?) -> Bool {
    guard let url else { return false }

    // Leading whitespace would otherwise let " javascript:..." past a prefix
    // check, and is never meaningful in a URL.
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let parsed = URL(string: trimmed),
          let scheme = parsed.scheme?.lowercased() else { return false }

    return scheme == "http" || scheme == "https"
}

/// The schemes that can run code or forge an origin when something follows them.
/// The schemes that run code, read local storage, or hide another scheme.
///
/// The last three do nothing on iOS: they are here because the Android, React
/// Native and Flutter SDKs need them, and the four are documented as applying
/// one rule. A rule that differs per platform is one nobody can check.
private let executableSchemes: Set<String> = [
    "javascript",
    "vbscript",
    "data",
    "blob",
    "file",
    "content",
    "jar",
    "filesystem",
]

/// A URL with the characters removed that whatever follows it ignores anyway.
///
/// Tabs and newlines inside a scheme are dropped by the things that actually
/// follow a URL, so `java<TAB>script:` runs as `javascript:`, and surrounding
/// whitespace is never meaningful. Removing them here means the scheme is read
/// the same way the thing that opens the URL reads it, and, just as important,
/// that the URL finally opened is the one whose scheme was vetted.
///
/// The filter runs over unicode scalars rather than characters. Swift treats
/// `\r\n` as one `Character`, so filtering characters left a CRLF in place and
/// `java\r\nscript:` reached the scheme check as something unparseable instead
/// of as the `javascript:` it navigates as. That also refused `my\r\napp://x`,
/// which the Android, Flutter and React Native SDKs all normalise and allow.
private func normalizedUrl(_ url: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in url.unicodeScalars where scalar != "\t" && scalar != "\n" && scalar != "\r" {
        scalars.append(scalar)
    }
    return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// A normalised URL's scheme, lowercased, or nil when it carries none.
///
/// Deliberately not `URL(string:)?.scheme`. A parser that rejects a string as
/// unparseable would leave the caller deciding what to do with something it
/// never understood, and the strings worth deciding about here are exactly the
/// ones a parser refuses.
private func urlScheme(_ url: String) -> String? {
    let cleaned = normalizedUrl(url)

    guard let colon = cleaned.firstIndex(of: ":") else { return nil }
    let scheme = cleaned[cleaned.startIndex..<colon]

    // RFC 3986: a scheme is a letter followed by letters, digits, "+", "-", ".".
    // Anything else before the first colon is not a scheme at all, it is a path
    // or a host and port. "_" is allowed on top of that set because iOS accepts
    // it in `CFBundleURLSchemes` and apps ship with it, so `my_app://order/4821`
    // is a working deep link that RFC 3986 would have this drop silently, which
    // is the defect this whole denylist exists to undo.
    guard let first = scheme.first, first.isASCII, first.isLetter else { return nil }
    let rest = scheme.dropFirst()
    guard rest.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "+" || $0 == "-" || $0 == "." || $0 == "_" }) else {
        return nil
    }

    return scheme.lowercased()
}

/// Whether a URL is safe to follow when someone taps a message's call to action.
///
/// Deliberately not `isSafeUrl`. That one allows http and https only, which is
/// right for something the SDK fetches or renders and wrong for a call to
/// action: this is a deep linking product, so the most natural button in an
/// in-app message is one that opens a screen in the host app,
/// `myapp://order/4821`. An allowlist dropped exactly that, silently, without
/// even calling the host app's own `onAction` handler, while the platform that
/// authored the message has always permitted it.
///
/// Every customer's scheme is different, so there is no list to allow. The
/// small, known set of dangerous schemes is named instead, matching the
/// platform's rule in `safe-url.ts`, the Android SDK's `isNavigableUrl` and the
/// React Native SDK's `isSafeActionUrl`, and everything else is left to open.
func isNavigableUrl(_ url: String?) -> Bool {
    guard let url, let scheme = urlScheme(url) else {
        // No scheme means relative or a fragment. There is no base to resolve it
        // against on a device, so it is not something to open.
        return false
    }

    return !executableSchemes.contains(scheme)
}

// MARK: - Message Actions

/// What tapping a message's call to action should do.
///
/// Separate from the presenter because the presenter needs UIKit and WebKit and
/// so cannot be exercised by the test suite, while this decision is the part
/// that a customer feels when it is wrong.
enum MessageAction: Equatable {

    /// Follow the action.
    ///
    /// `urlString` is what the host app's own `onAction` handler receives,
    /// exactly as the message named it, since the app knows best how to read
    /// its own deep links. `url` is what the SDK opens when the app gave it no
    /// handler, and is nil when the scheme is one to allow but Foundation will
    /// build no URL out of the string. A handler still gets called in that case:
    /// dropping the action because `URL` is fussier than the app is exactly the
    /// silent drop this rule was written to stop.
    case follow(urlString: String, url: URL?)

    /// The scheme runs code or forges an origin, so nothing happens.
    case refuse
}

/// Everything a URL may legally carry anywhere in it, plus `%` and `#`.
///
/// Each of these sets covers one component, and a whole URL is all of them at
/// once, so the union is "what a URL parser would not have objected to". `%` is
/// in it so a URL that is already encoded is not encoded a second time, turning
/// `%20` into `%2520`, and `#` so a fragment stays a fragment instead of being
/// swallowed into the path.
private let urlLegalCharacters: CharacterSet = {
    var allowed = CharacterSet.urlFragmentAllowed
    allowed.formUnion(.urlHostAllowed)
    allowed.formUnion(.urlPathAllowed)
    allowed.formUnion(.urlQueryAllowed)
    allowed.formUnion(.urlUserAllowed)
    allowed.formUnion(.urlPasswordAllowed)
    allowed.insert(charactersIn: "#%")
    return allowed
}()

/// A URL built from a string the same way on every iOS this package supports.
///
/// `Package.swift` declares iOS 15, and before iOS 17 `URL(string:)` returns nil
/// for any string holding a raw space or a character outside ASCII. So
/// `myapp://search?q=café` is a working deep link that the direct initialiser
/// alone refuses. Whatever it would not take is percent-encoded and parsed
/// again, which is what the URL was going to have to become anyway.
private func buildUrl(_ normalized: String) -> URL? {
    if let url = URL(string: normalized) { return url }

    guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: urlLegalCharacters) else {
        return nil
    }
    return URL(string: encoded)
}

/// Decide what a message's call to action does, given the URL it names.
///
/// The URL is normalised once and both halves of the answer come from that same
/// string, so the URL that ends up being opened is the one whose scheme was
/// vetted rather than a second reading of the raw text.
func messageAction(for urlString: String?) -> MessageAction {
    guard let urlString else { return .refuse }

    let normalized = normalizedUrl(urlString)
    guard isNavigableUrl(normalized) else { return .refuse }

    return .follow(urlString: urlString, url: buildUrl(normalized))
}
