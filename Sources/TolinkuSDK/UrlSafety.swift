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
private let executableSchemes: Set<String> = ["javascript", "vbscript", "data", "blob", "file"]

/// A URL's scheme, lowercased, or nil when it carries none.
///
/// Deliberately not `URL(string:)?.scheme`. Tabs and newlines inside a scheme
/// are stripped by the things that actually follow a URL, so `java<TAB>script:`
/// runs as `javascript:`, and a parser that rejects it as unparseable would
/// leave the caller deciding what to do with a string it never understood.
/// Stripping them here first means the scheme is read the same way the thing
/// that opens the URL reads it.
private func urlScheme(_ url: String) -> String? {
    let cleaned = url
        .filter { $0 != "\t" && $0 != "\n" && $0 != "\r" }
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let colon = cleaned.firstIndex(of: ":") else { return nil }
    let scheme = cleaned[cleaned.startIndex..<colon]

    // RFC 3986: a scheme is a letter followed by letters, digits, "+", "-", ".".
    // Anything else before the first colon is not a scheme at all, it is a path
    // or a host and port.
    guard let first = scheme.first, first.isASCII, first.isLetter else { return nil }
    let rest = scheme.dropFirst()
    guard rest.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "+" || $0 == "-" || $0 == "." }) else {
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
