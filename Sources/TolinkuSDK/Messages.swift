import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

/// Provides access to in-app messages.
///
/// Use ``fetch(trigger:)`` to retrieve raw message data, or ``show(trigger:from:onAction:onDismiss:)``
/// to fetch and automatically present the highest-priority undismissed message in a WebView overlay.
public final class Messages: Sendable {

    private let client: Client

    init(client: Client) {
        self.client = client
    }

    /// Fetch messages for a given trigger.
    ///
    /// - Parameter trigger: Optional trigger filter (e.g. "milestone", "welcome").
    ///   If nil, all messages are returned.
    /// - Returns: An array of ``Message`` objects.
    public func fetch(trigger: String? = nil) async throws -> [Message] {
        var queryItems: [URLQueryItem] = []
        if let trigger {
            queryItems.append(URLQueryItem(name: "trigger", value: trigger))
        }
        if let userId = Tolinku.shared?.userId {
            queryItems.append(URLQueryItem(name: "user_id", value: userId))
        }
        let response: MessagesResponse = try await client.get(
            path: "/v1/api/messages",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        return response.messages
    }

    /// Request a short-lived render token for loading message HTML in a WebView.
    ///
    /// The token is scoped to the given message and expires after 5 minutes.
    /// Use it to load the render URL without exposing the API key.
    ///
    /// - Parameter messageId: The ID of the message to render.
    /// - Returns: A render token string.
    public func renderToken(messageId: String) async throws -> String {
        let encodedId = messageId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageId
        let response: RenderTokenResponse = try await client.post(
            path: "/v1/api/messages/\(encodedId)/render-token",
            body: EmptyBody()
        )
        return response.token
    }

    #if canImport(UIKit) && canImport(WebKit)
    /// Fetch messages, filter out dismissed ones, and present the highest-priority
    /// message in a WebView overlay.
    ///
    /// This is a convenience method that combines fetching, filtering, sorting,
    /// and presenting into a single call.
    ///
    /// - Parameters:
    ///   - trigger: Optional trigger filter. If nil, all messages are fetched.
    ///   - viewController: The view controller to present the message from.
    ///   - onAction: Called when the user taps a navigation action. Receives
    ///     the destination URL string. If nil, the URL is opened via
    ///     `UIApplication.shared.open`.
    ///   - onDismiss: Called after the message is dismissed.
    @MainActor
    public func show(
        trigger: String? = nil,
        from viewController: UIViewController,
        onAction: ((String) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) async {
        do {
            let allMessages = try await fetch(trigger: trigger)

            // Filter out messages that have been dismissed and are still within
            // their suppression window.
            let eligible = allMessages
                .filter { !TolinkuMessagePresenter.isMessageDismissed(message: $0) }
                .filter { !TolinkuMessagePresenter.isMessageSuppressed(message: $0) }

            // Sort by priority descending (highest priority first).
            let sorted = eligible.sorted { $0.priority > $1.priority }

            guard let topMessage = sorted.first else {
                return
            }

            TolinkuMessagePresenter.recordImpression(messageId: topMessage.id)
            TolinkuMessagePresenter.show(
                message: topMessage,
                from: viewController,
                onAction: onAction,
                onDismiss: onDismiss
            )
        } catch {
            os_log(.error, log: .default, "Failed to fetch or show messages: %{public}@", error.localizedDescription)
        }
    }
    #endif
}
