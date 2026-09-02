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

    /// Where a completed claim attempt is remembered.
    ///
    /// Same key the React Native, Flutter and web SDKs use, so an app sharing
    /// code across them reads one name rather than four.
    /// Internal rather than private so a test can clear it between cases;
    /// UserDefaults outlives a single test and a leftover value would make the
    /// second case pass for the wrong reason.
    static let claimedKey = "tolinku_deferred_claimed"

    /// Recover the link that led to this install, once.
    ///
    /// There is no Play Install Referrer on iOS, so this is signal matching with
    /// the bookkeeping that makes calling it safe. That bookkeeping is the
    /// point: a claim is consumed the first time it succeeds, so an app calling
    /// ``claimBySignals(appspaceId:)`` on every launch asks again after the
    /// answer is already spent, and every one of those asks is recorded as a
    /// miss. The match rate in the dashboard then falls towards zero while the
    /// integration is working correctly, which is hard to diagnose from outside.
    ///
    /// Call it once on first launch. Calling it again is free after the first.
    ///
    /// Named to match the Android, React Native and Flutter SDKs, where the same
    /// call also tries the install referrer before falling back to signals.
    ///
    /// - Parameters:
    ///   - appspaceId: The Appspace ID to match against.
    ///   - force: Claim again even if an attempt was already recorded. For tests.
    /// - Returns: The matched deep link info, or nil if there was no match or an
    ///   attempt was already made.
    /// - Throws: ``TolinkuError/invalidConfiguration(_:)`` if `appspaceId` is
    ///   blank, or whatever ``claimBySignals(appspaceId:)`` throws. A throw
    ///   leaves the attempt unrecorded, so the next launch is free to try again:
    ///   losing an install's attribution to one bad connection, or to an
    ///   `appspaceId` that is about to be corrected, is worse than one extra
    ///   request.
    @discardableResult
    public func claimDeferredLink(
        appspaceId: String,
        force: Bool = false
    ) async throws -> DeferredDeepLinkResponse? {
        guard !appspaceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TolinkuError.invalidConfiguration("appspaceId must not be blank for claimDeferredLink")
        }

        if !force && Self.alreadyAttempted() { return nil }

        // A nil here is the 404 that claimBySignals already turns into "nothing
        // waiting for this device". That is a real answer and worth remembering.
        // Anything else throws out of here without recording, which is what
        // leaves the next launch free to retry.
        let link = try await claimBySignals(appspaceId: appspaceId)
        Self.rememberAttempt()
        return link
    }

    private static func alreadyAttempted() -> Bool {
        UserDefaults.standard.string(forKey: claimedKey) != nil
    }

    private static func rememberAttempt() {
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: Date()), forKey: claimedKey)
    }

    /// Claim a deferred deep link by matching device signals.
    ///
    /// The signals are collected from the device, so nothing needs passing. Pass
    /// one only where you hold a better value than the SDK can read, and pass it
    /// in the form matching compares against: an IANA timezone (`Asia/Seoul`),
    /// a BCP-47 language tag with its region (`ko-KR`), screen size in points,
    /// and a version starting with a digit (`17.1`).
    ///
    /// A signal that is absent is skipped rather than counted as a failed
    /// comparison, so leaving one out is safe. One in the wrong shape is worse
    /// than none, which is why these are overrides rather than the only source.
    ///
    /// - Parameters:
    ///   - appspaceId: The Appspace ID to match against.
    ///   - timezone: IANA identifier, overriding the device's.
    ///   - language: BCP-47 tag with region, overriding the device's.
    ///   - screenWidth: Screen width in points.
    ///   - screenHeight: Screen height in points.
    ///   - devicePixelRatio: Ratio of physical pixels to points.
    ///   - osVersion: Version compared on its leading digits.
    /// - Returns: The matched deep link info, or nil if no match was found.
    public func claimBySignals(
        appspaceId: String,
        timezone: String? = nil,
        language: String? = nil,
        screenWidth: Int? = nil,
        screenHeight: Int? = nil,
        devicePixelRatio: Double? = nil,
        osVersion: String? = nil
    ) async throws -> DeferredDeepLinkResponse? {
        let collectedTimezone = TimeZone.current.identifier

        // Must be a full BCP-47 tag with region ("ko-KR"), because the value this
        // is matched against is the landing page's `navigator.language`, which
        // always carries one. Sending the bare primary subtag ("ko") meant the
        // language signal could never score, capping every iOS match.
        let collectedLanguage: String = {
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

        let collectedWidth: Int
        let collectedHeight: Int
        #if canImport(UIKit)
        if #available(iOS 16, *) {
            let bounds = await MainActor.run {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?
                    .screen
                    .bounds ?? .zero
            }
            collectedWidth = Int(bounds.width)
            collectedHeight = Int(bounds.height)
        } else {
            let bounds = await MainActor.run { UIScreen.main.bounds }
            collectedWidth = Int(bounds.width)
            collectedHeight = Int(bounds.height)
        }
        #else
        collectedWidth = 0
        collectedHeight = 0
        #endif

        // Pixel ratio separates models that report the same logical size, and the
        // OS version is compared on its major component only.
        var pixelRatio: Double = 0
        #if canImport(UIKit)
        pixelRatio = await MainActor.run { Double(UIScreen.main.scale) }
        #endif

        var collectedOsVersion = ""
        #if canImport(UIKit)
        collectedOsVersion = await MainActor.run { UIDevice.current.systemVersion }
        #endif

        // Anything the caller passed wins. A value from their own lookup is
        // better than one inferred here, and passing one must not discard the
        // rest, which is the mistake that makes a partial override worse than
        // none at all.
        let body = ClaimBySignalsRequest(
            appspaceId: appspaceId,
            timezone: timezone ?? collectedTimezone,
            language: language ?? collectedLanguage,
            screenWidth: screenWidth ?? collectedWidth,
            screenHeight: screenHeight ?? collectedHeight,
            devicePixelRatio: devicePixelRatio ?? (pixelRatio > 0 ? pixelRatio : nil),
            osVersion: osVersion ?? (collectedOsVersion.isEmpty ? nil : collectedOsVersion)
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
