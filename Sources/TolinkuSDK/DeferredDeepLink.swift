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

        // Must be a full BCP-47 tag with region ("ko-KR"), because the value this
        // is matched against is the landing page's `navigator.language`, which
        // always carries one. Sending the bare primary subtag ("ko") meant the
        // language signal could never score, capping every iOS match.
        let language: String = {
            if let preferred = Locale.preferredLanguages.first, !preferred.isEmpty {
                return preferred
            }
            if #available(iOS 16, *) {
                let code = Locale.current.language.languageCode?.identifier ?? "en"
                if let region = Locale.current.region?.identifier {
                    return "\(code)-\(region)"
                }
                return code
            }
            let code = Locale.current.languageCode ?? "en"
            if let region = Locale.current.regionCode {
                return "\(code)-\(region)"
            }
            return code
        }()

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

        // Pixel ratio separates models that report the same logical size, and the
        // OS version is compared on its major component only.
        var pixelRatio: Double = 0
        #if canImport(UIKit)
        pixelRatio = await MainActor.run { Double(UIScreen.main.scale) }
        #endif

        var osVersion = ""
        #if canImport(UIKit)
        osVersion = await MainActor.run { UIDevice.current.systemVersion }
        #endif

        let body = ClaimBySignalsRequest(
            appspaceId: appspaceId,
            timezone: timezone,
            language: language,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            devicePixelRatio: pixelRatio > 0 ? pixelRatio : nil,
            osVersion: osVersion.isEmpty ? nil : osVersion
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
