import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

/// Provides access to in-app messages.
///
/// Use ``fetch(trigger:triggerValue:)`` to retrieve raw message data, or ``show(trigger:triggerValue:from:onAction:onDismiss:)``
/// to fetch and automatically present the highest-priority undismissed message in a WebView overlay.
public final class Messages: Sendable {

    private let client: Client

    init(client: Client) {
        self.client = client
    }

    /// Fetch messages for a given trigger.
    ///
    /// - Parameters:
    ///   - trigger: Optional trigger: "manual", "milestone" or "event". If nil,
    ///     the server returns manual messages.
    ///   - triggerValue: Optional event or milestone name. When set, only
    ///     messages for that name, plus messages of the trigger that name none,
    ///     are returned. Filtered here as well, so a server that predates
    ///     `trigger_value` gives the same answer.
    /// - Returns: An array of ``Message`` objects.
    public func fetch(trigger: String? = nil, triggerValue: String? = nil) async throws -> [Message] {
        var queryItems: [URLQueryItem] = []
        if let trigger {
            queryItems.append(URLQueryItem(name: "trigger", value: trigger))
        }
        if let triggerValue, !triggerValue.isEmpty {
            queryItems.append(URLQueryItem(name: "trigger_value", value: triggerValue))
        }
        if let userId = Tolinku.shared?.userId {
            queryItems.append(URLQueryItem(name: "user_id", value: userId))
        }
        let response: MessagesResponse = try await client.get(
            path: "/v1/api/messages",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        return response.messages.filter { messageMatches($0, triggerValue: triggerValue) }
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
    ///   - trigger: Optional trigger: "manual", "milestone" or "event". If nil,
    ///     the server returns manual messages.
    ///   - triggerValue: Optional event or milestone name, such as "purchase"
    ///     or "installed". Narrows the messages to that name, plus messages of
    ///     the trigger that name none.
    ///   - viewController: The view controller to present the message from.
    ///   - onAction: Called when the user taps a navigation action. Receives
    ///     the destination URL string. If nil, the URL is opened via
    ///     `UIApplication.shared.open`.
    ///   - onDismiss: Called after the message is dismissed.
    @MainActor
    public func show(
        trigger: String? = nil,
        triggerValue: String? = nil,
        from viewController: UIViewController,
        onAction: ((String) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) async {
        do {
            let allMessages = try await fetch(trigger: trigger, triggerValue: triggerValue)

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

/// Whether a message belongs to a request for `triggerValue`: always when no
/// name was asked for; otherwise when the message names that one, or names
/// none (a message for any event or milestone of its trigger). The same rule
/// the server applies to `trigger_value`, repeated here for servers older than it.
func messageMatches(_ message: Message, triggerValue: String?) -> Bool {
    guard let triggerValue, !triggerValue.isEmpty else { return true }
    guard let own = message.triggerValue, !own.isEmpty else { return true }
    return own == triggerValue
}
