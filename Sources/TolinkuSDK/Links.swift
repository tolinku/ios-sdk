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
    /// The one exception is a link the host cannot answer for, which is what a
    /// link in an email usually is: the email platform wraps every link in its
    /// own click-tracking URL, on a domain that may not lead to Tolinku at all.
    /// When the host gives no answer of Tolinku's own, the whole link goes to
    /// Tolinku's API, with your key, and that unwraps it.
    ///
    /// Each question is asked once, with a 5 second limit, and never retried:
    /// the server unwraps an email link once, which is how the email platform
    /// counts the click (Tolinku records no click of its own), so asking again
    /// could count it twice, and this runs while the app is opening.
    ///
    /// Never throws. A link that cannot be resolved, for a bad network or any
    /// other reason, is one the app should fall back to its own handling for,
    /// and an error thrown in the middle of a cold start is no way to say so.
    public func resolve(_ url: URL) async -> ResolvedLink? {
        guard let link = Self.normalise(url) else { return nil }

        // The first question goes to the link's own host, without the key:
        // that host was taken from the URL this was handed, and an app
        // resolving a link from somewhere it does not control would otherwise
        // send the Appspace's key to a stranger.
        do {
            let (data, response) = try await client.postOnce(
                path: "/v1/api/path",
                body: ["path": link.path, "url": link.whole],
                authenticated: false,
                origin: link.origin,
                timeout: Self.timeout
            )
            if (200...299).contains(response.statusCode),
               let resolved = Self.safe(data) {
                return resolved
            }
            // An answer of Tolinku's own: the host is ours and has said what it
            // has to say, so asking again would only repeat the question.
            if isTolinkuReply(data, response, host: link.host) { return nil }
        } catch {
            // No answer at all (a bad network, a timeout). The next question
            // is for exactly the host that could not answer.
        }

        return await resolveThroughAPI(link)
    }

    /// How long each question may take, in seconds.
    static let timeout: TimeInterval = 5

    /// A link in the one form every question about it uses.
    struct NormalisedLink: Equatable {
        /// `https://host[:port]`, where the first question goes.
        let origin: String
        /// The host alone, lowercased, without the port.
        let host: String
        /// The percent-encoded path, "/" when there is none.
        let path: String
        /// The origin, the path and the query: the link without its fragment.
        let whole: String
    }

    /// The link, tidied the same way by every Tolinku SDK, or nil for anything
    /// but an http or https link.
    ///
    /// The scheme and host are lowercased, http becomes https (every Tolinku
    /// and click domain serves https, and App Transport Security blocks http
    /// anyway), a default port and the fragment are dropped, and the path and
    /// query are kept exactly as written.
    ///
    /// The path stays percent-encoded rather than going through `url.path`,
    /// which decodes. A token may contain an encoded slash, and decoding first
    /// turns "/promo/a%2Fb" into a path three deep rather than a token of "a/b"
    /// on "promo", which resolves to a different route or to nothing.
    static func normalise(_ url: URL) -> NormalisedLink? {
        // http and https only. A custom scheme link already carries the path
        // the app wants, and anything else is not a link this could answer for.
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let encodedHost = components.percentEncodedHost, !encodedHost.isEmpty,
              let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }

        components.scheme = "https"
        components.percentEncodedHost = encodedHost.lowercased()
        components.user = nil
        components.password = nil
        if components.port == 443 || components.port == 80 {
            components.port = nil
        }
        components.fragment = nil
        if components.percentEncodedPath.isEmpty {
            components.percentEncodedPath = "/"
        }
        // "?" with nothing after it is no query.
        if components.percentEncodedQuery?.isEmpty == true {
            components.percentEncodedQuery = nil
        }
        let path = components.percentEncodedPath

        var bare = components
        bare.percentEncodedPath = ""
        bare.percentEncodedQuery = nil
        guard let whole = components.string, let origin = bare.string else { return nil }

        return NormalisedLink(origin: origin, host: host, path: path, whole: whole)
    }

    /// The second question, asked of Tolinku itself rather than of the link's
    /// host.
    ///
    /// A wrapped email link lives on the email platform's click domain, which
    /// may not point at Tolinku at all, so asking that host gets no answer of
    /// Tolinku's. Tolinku's own API can still unwrap it and say which route it
    /// leads to. This one goes to the configured base URL, never to a host
    /// taken from the link, so sending the key with it is safe.
    private func resolveThroughAPI(_ link: NormalisedLink) async -> ResolvedLink? {
        // Without a key the API has no way to tell which Appspace is asking.
        guard !client.apiKey.isEmpty else { return nil }
        // Asking the same host twice gets the same answer twice. Hosts are
        // compared lowercased and without their ports.
        if let apiHost = URLComponents(string: client.baseURL)?.host?.lowercased(),
           apiHost == link.host {
            return nil
        }

        do {
            let (data, response) = try await client.postOnce(
                path: "/v1/api/links/resolve",
                body: ["url": link.whole],
                authenticated: true,
                timeout: Self.timeout
            )
            guard (200...299).contains(response.statusCode) else { return nil }
            return Self.safe(data)
        } catch {
            return nil
        }
    }

    /// Whether a reply is Tolinku's own: marked `X-Tolinku: 1`, which every
    /// answer of its API carries, or, from a server that predates the header,
    /// a JSON object with a string `error` (`{"error": "Route not found"}`)
    /// that came from Tolinku's own domain. An email platform's host can answer
    /// in JSON with an `error` too, so the body alone proves nothing.
    func isTolinkuReply(_ data: Data, _ response: HTTPURLResponse, host: String) -> Bool {
        if response.value(forHTTPHeaderField: "X-Tolinku") == "1" { return true }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["error"] is String else { return false }
        return isTolinkuDomain(host)
    }

    /// Whether a host is Tolinku's own: the configured API's host, or a host
    /// under its parent domain (an Appspace's tolinku.com subdomain).
    private func isTolinkuDomain(_ host: String) -> Bool {
        guard let apiHost = URLComponents(string: client.baseURL)?.host?.lowercased() else { return false }
        if host == apiHost { return true }
        let labels = apiHost.split(separator: ".")
        return labels.count > 2 && host.hasSuffix("." + labels.suffix(2).joined(separator: "."))
    }

    /// The answer in this body, if there is one and its path is one an app can
    /// safely route.
    ///
    /// The first answer came from a host taken from the URL this was given, so
    /// an app resolving a link from somewhere it does not control is talking to
    /// a stranger. The contract is a path: a full URL, or a protocol relative
    /// "//host" that reads as one, is a redirect waiting to happen in whatever
    /// the app does next. The API's answer is held to the same rule, since
    /// what it hands back came out of a link someone else wrote.
    private static func safe(_ data: Data) -> ResolvedLink? {
        guard let resolved = try? JSONDecoder().decode(ResolvedLink.self, from: data),
              resolved.deepLinkPath.hasPrefix("/"),
              !resolved.deepLinkPath.hasPrefix("//") else { return nil }
        return resolved
    }

    /// The same, for a link held as a string.
    public func resolve(_ url: String) async -> ResolvedLink? {
        guard let parsed = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return await resolve(parsed)
    }
}
