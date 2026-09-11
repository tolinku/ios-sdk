import Foundation

/// Working out what a link the system handed the app actually means.
///
/// An app receives the URL that was tapped, exactly as it was written. That is
/// fine while the URL is readable: `/order/4821` says "order" and the app can
/// route it. It is not fine for a short link, which is the same route written as
/// a code:
///
/// ```
/// https://links.example.com/s7k2p9q/4821
/// ```
///
/// Nothing in that URL says "order", and nothing about the code can be worked
/// out on the device. An app parsing the path itself sees a first component it
/// has never heard of and does nothing, so the link opens the app and then
/// appears to fail: no error, no screen, no clue. Short links are what the
/// dashboard offers for sharing and what a QR code carries, so this is not a
/// rare path.
///
/// ``resolve(_:)`` asks the platform, which answers with the route, the token
/// and the canonical path, and the app can route that the way it routes
/// anything else. A readable URL comes back unchanged, so an app can simply
/// resolve everything rather than guessing which kind it has.
public final class Links: Sendable {

    private let client: Client

    init(client: Client) {
        self.client = client
    }

    /// What this link means, or nil if it means nothing here.
    ///
    /// - Parameter url: A whole link, as the app received it.
    /// - Returns: The route, token and canonical path, or nil.
    ///
    /// The question goes to the link's own host, because that is how the
    /// platform knows which Appspace is being asked about, which also means a
    /// link on a domain that is not yours simply answers nothing.
    ///
    /// Never throws. A link that cannot be resolved, for a bad network or any
    /// other reason, is one the app should fall back to its own handling for,
    /// and an error thrown in the middle of a cold start is no way to say so.
    public func resolve(_ url: URL) async -> ResolvedLink? {
        // http and https only. A custom scheme link already carries the path the
        // app wants, and anything else is not a link this could answer for.
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host else { return nil }

        var origin = "\(scheme)://\(host)"
        if let port = url.port { origin += ":\(port)" }

        // The percent-encoded path, not `url.path`, which decodes. A token may
        // contain an encoded slash, and decoding first turns "/promo/a%2Fb"
        // into a path three deep rather than a token of "a/b" on "promo",
        // which resolves to a different route or to nothing.
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let rawPath = components?.percentEncodedPath ?? ""
        let path = rawPath.isEmpty ? "/" : rawPath

        do {
            let resolved: ResolvedLink = try await client.post(
                path: "/v1/api/path",
                body: ["path": path],
                authenticated: false,
                origin: origin
            )
            // The answer went to a host taken from the URL this was given, so an
            // app resolving a link from somewhere it does not control is talking
            // to a stranger. The contract is a path: a full URL, or a protocol
            // relative "//host" that reads as one, is a redirect waiting to
            // happen in whatever the app does next.
            guard resolved.deepLinkPath.hasPrefix("/"),
                  !resolved.deepLinkPath.hasPrefix("//") else { return nil }
            return resolved
        } catch {
            return nil
        }
    }

    /// The same, for a link held as a string.
    public func resolve(_ url: String) async -> ResolvedLink? {
        guard let parsed = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return await resolve(parsed)
    }
}
