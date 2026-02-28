import Foundation
import os.log

/// The main entry point for the Tolinku SDK.
///
/// Call ``configure(apiKey:)`` once at app launch, then use
/// ``shared`` to access analytics, referrals, deferred deep links, and messages.
public final class Tolinku: Sendable {

    /// The current SDK version string.
    public static let sdkVersion = "1.0.0"

    // MARK: - Singleton

    /// Lock protecting access to the shared instance.
    private static let lock = NSLock()

    /// The backing storage for the shared instance.
    private nonisolated(unsafe) static var _shared: Tolinku?

    /// The shared instance. Only available after ``configure(apiKey:baseURL:)`` has been called.
    ///
    /// Returns nil if the SDK has not been configured yet. Use ``requireShared()`` for
    /// a throwing accessor that produces a clear error instead of returning nil.
    public static var shared: Tolinku? {
        lock.lock()
        defer { lock.unlock() }
        return _shared
    }

    /// Returns the shared instance, or throws ``TolinkuError/notConfigured`` if the SDK
    /// has not been configured yet.
    public static func requireShared() throws -> Tolinku {
        guard let instance = shared else {
            throw TolinkuError.notConfigured
        }
        return instance
    }

    // MARK: - Properties

    /// The underlying HTTP client used for all API calls.
    internal let client: Client

    /// The current user ID, used for segment targeting and analytics attribution.
    /// Set via ``setUserId(_:)`` and cleared by passing nil.
    private let _userIdLock = NSLock()
    private nonisolated(unsafe) var _userId: String?

    /// The current user ID, or nil if not set.
    public var userId: String? {
        _userIdLock.lock()
        defer { _userIdLock.unlock() }
        return _userId
    }

    /// Analytics tracking (custom events).
    public let analytics: Analytics

    /// Referral management (create, complete, milestones, leaderboard, rewards).
    public let referrals: Referrals

    /// Deferred deep link claiming.
    public let deferred: DeferredDeepLink

    /// In-app messages.
    public let messages: Messages

    // MARK: - Initialization

    private init(client: Client) {
        self.client = client
        self.analytics = Analytics(client: client)
        self.referrals = Referrals(client: client)
        self.deferred = DeferredDeepLink(client: client)
        self.messages = Messages(client: client)
    }

    /// Configure the SDK. Call this once, typically in your AppDelegate or @main App init.
    ///
    /// If the SDK has already been configured, subsequent calls are ignored and the
    /// existing instance is returned. To reconfigure, call ``shutdown()`` first.
    ///
    /// - Parameters:
    ///   - apiKey: Your Tolinku publishable API key (e.g. "tolk_pub_..."). Must not be empty.
    ///   - baseURL: The base URL of your Tolinku instance. Defaults to "https://api.tolinku.com".
    /// - Throws: ``TolinkuError/invalidConfiguration(_:)`` if apiKey is empty.
    @discardableResult
    public static func configure(apiKey: String, baseURL: String = "https://api.tolinku.com") throws -> Tolinku {
        lock.lock()
        defer { lock.unlock() }

        // If already configured, log a warning and return the existing instance
        if let existing = _shared {
            os_log(.default, log: .default, "Warning: Tolinku.configure() called more than once. Ignoring subsequent call. Call shutdown() first if you need to reconfigure.")
            return existing
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            throw TolinkuError.invalidConfiguration("apiKey must not be empty.")
        }
        guard !trimmedURL.isEmpty else {
            throw TolinkuError.invalidConfiguration("baseURL must not be empty.")
        }

        // Enforce HTTPS (with local development exceptions)
        let isLocalDev = trimmedURL.hasPrefix("http://localhost") ||
            trimmedURL.hasPrefix("http://127.0.0.1") ||
            trimmedURL.hasPrefix("http://10.") ||
            trimmedURL.hasPrefix("http://192.168.") ||
            Self.isPrivate172(trimmedURL)
        if !trimmedURL.hasPrefix("https://") && !isLocalDev {
            throw TolinkuError.invalidConfiguration(
                "baseURL must use HTTPS. HTTP is only allowed for local development " +
                "(localhost, 127.0.0.1, 10.x, 172.16-31.x, 192.168.x)."
            )
        }

        let client = Client(apiKey: trimmedKey, baseURL: trimmedURL)
        let instance = Tolinku(client: client)
        _shared = instance
        return instance
    }

    // MARK: - Universal Link Handling

    /// Convenience method for handling an incoming Universal Link.
    ///
    /// Parses the URL and returns its path and query parameters so your app can
    /// route the user to the appropriate content.
    ///
    /// - Parameter url: The Universal Link URL received by your app.
    /// - Returns: A tuple containing the path and query parameters, or nil if the URL could not be parsed.
    public static func handleUniversalLink(_ url: URL) -> (path: String, queryItems: [URLQueryItem])? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }
        let path = components.path
        let queryItems = components.queryItems ?? []
        return (path: path, queryItems: queryItems)
    }

    // MARK: - User Identity

    /// Set the user ID for segment targeting and analytics attribution.
    /// Pass nil to clear the user ID.
    ///
    /// - Parameter userId: The unique identifier for the current user.
    public func setUserId(_ userId: String?) {
        _userIdLock.lock()
        _userId = userId
        _userIdLock.unlock()
    }

    // MARK: - Convenience

    /// Track a custom event. Shorthand for ``analytics.track(_:properties:)``.
    ///
    /// The event is queued in memory and sent as part of a batch.
    /// If a userId has been set, it is automatically injected into event properties.
    ///
    /// - Parameters:
    ///   - eventType: The event name (should start with "custom.").
    ///   - properties: Optional dictionary of event properties.
    public func track(_ eventType: String, properties: [String: AnyCodableValue]? = nil) async {
        var mergedProperties = properties
        if let uid = userId {
            var props = mergedProperties ?? [:]
            props["user_id"] = .string(uid)
            mergedProperties = props
        }
        await analytics.track(eventType, properties: mergedProperties)
    }

    /// Flush all queued analytics events to the server immediately.
    /// Shorthand for ``analytics.flush()``.
    public func flush() async {
        await analytics.flush()
    }

    // MARK: - Private Helpers

    /// Checks whether a URL string targets the 172.16.0.0/12 private range (172.16.x - 172.31.x).
    private static func isPrivate172(_ url: String) -> Bool {
        guard url.hasPrefix("http://172.") else { return false }
        let afterPrefix = url.dropFirst("http://172.".count)
        guard let dotIndex = afterPrefix.firstIndex(of: ".") else { return false }
        guard let octet = Int(afterPrefix[afterPrefix.startIndex..<dotIndex]) else { return false }
        return octet >= 16 && octet <= 31
    }

    // MARK: - Shutdown

    /// Shuts down the SDK and releases all resources.
    ///
    /// This method flushes any remaining analytics events, cancels background tasks,
    /// removes notification observers, and clears the shared instance. After calling
    /// this, you can call ``configure(apiKey:baseURL:)`` again to reinitialize the SDK.
    public static func shutdown() async {
        lock.lock()
        let instance = _shared
        _shared = nil
        lock.unlock()

        guard let instance else { return }

        // Tear down analytics (flush events, cancel timer, remove observers)
        await instance.analytics.shutdown()
    }
}
