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
