import Foundation

/// When a closed in-app message may show again.
///
/// Kept apart from the presenter, which needs UIKit and WebKit, so the rule is
/// something the test suite can reach.
enum MessageTiming {

    /// Whether a close still hides a message.
    ///
    /// "After closing, hide for" is the message's `dismiss_days`. Left empty
    /// (nil) or 0, a close isn't remembered and the message can show again the
    /// next time the app asks; a number hides it for that many days. This is
    /// what the web SDK and the docs have always done. Earlier versions of this
    /// SDK hid a message with no `dismiss_days` forever after one close.
    static func stillDismissed(dismissedAt: Date?, dismissDays: Int?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let dismissedAt else { return false }
        guard let dismissDays, dismissDays > 0 else { return false }
        guard let expiry = calendar.date(byAdding: .day, value: dismissDays, to: dismissedAt) else {
            return false
        }
        return now < expiry
    }
}
