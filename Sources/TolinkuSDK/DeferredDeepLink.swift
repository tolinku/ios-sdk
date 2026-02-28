import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Provides deferred deep link claiming.
///
/// Deferred deep links allow a user who installs the app via a link to be
/// routed to the correct content on first open, even though the app was not
/// installed when the link was clicked.
public final class DeferredDeepLink: Sendable {

    private let client: Client

    init(client: Client) {
        self.client = client
    }

    /// Claim a deferred deep link using a token (from a URL query parameter).
    ///
    /// - Parameter token: The deferred link token.
    /// - Returns: The claimed deep link info, or nil if no match was found.
    public func claimByToken(_ token: String) async throws -> DeferredDeepLinkResponse? {
        let queryItems = [URLQueryItem(name: "token", value: token)]
        do {
            let response: DeferredDeepLinkResponse = try await client.get(
                path: "/v1/api/deferred/claim",
                queryItems: queryItems,
                authenticated: false
            )
            return response
        } catch TolinkuError.httpError(let statusCode, _, _) where statusCode == 404 {
            return nil
        }
    }

    /// Claim a deferred deep link by matching device signals.
    ///
    /// This automatically collects timezone, language, and screen dimensions
    /// from the current device and sends them to the server for fingerprint matching.
    ///
    /// - Parameter appspaceId: The Appspace ID to match against.
    /// - Returns: The matched deep link info, or nil if no match was found.
    public func claimBySignals(appspaceId: String) async throws -> DeferredDeepLinkResponse? {
        let timezone = TimeZone.current.identifier

        let language: String
        if #available(iOS 16, *) {
            language = Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            language = Locale.current.languageCode ?? "en"
        }

        let screenWidth: Int
        let screenHeight: Int
        #if canImport(UIKit)
        if #available(iOS 16, *) {
            let bounds = await MainActor.run {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?
                    .screen
                    .bounds ?? .zero
            }
            screenWidth = Int(bounds.width)
            screenHeight = Int(bounds.height)
        } else {
            let bounds = await MainActor.run { UIScreen.main.bounds }
            screenWidth = Int(bounds.width)
            screenHeight = Int(bounds.height)
        }
        #else
        screenWidth = 0
        screenHeight = 0
        #endif

        let body = ClaimBySignalsRequest(
            appspaceId: appspaceId,
            timezone: timezone,
            language: language,
            screenWidth: screenWidth,
            screenHeight: screenHeight
        )

        do {
            let response: DeferredDeepLinkResponse = try await client.post(
                path: "/v1/api/deferred/claim-by-signals",
                body: body,
                authenticated: false
            )
            return response
        } catch TolinkuError.httpError(let statusCode, _, _) where statusCode == 404 {
            return nil
        }
    }
}
