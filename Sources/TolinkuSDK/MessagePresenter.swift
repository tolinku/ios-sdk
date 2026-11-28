#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit
import os.log

/// Handles presenting in-app messages using a WebView-based renderer.
///
/// The server provides a fully rendered HTML document at
/// `GET /v1/api/messages/:id/render`. This class loads that HTML in a
/// transparent WKWebView presented modally over the current content.
///
/// Communication from the HTML back to native code happens via a
/// JavaScript bridge named "tolinku". The JS sends JSON payloads such as
/// `{"action":"close"}` or `{"action":"navigate","url":"https://..."}`.
public final class TolinkuMessagePresenter: NSObject {

    // MARK: - UserDefaults Keys

    private static let dismissedKeyPrefix = "tolinku_dismissed_"
    private static let impressionCountPrefix = "tolinku_impressions_"
    private static let lastShownPrefix = "tolinku_last_shown_"

    // MARK: - Dismissal Tracking

    /// Check whether a message has been dismissed and is still within its
    /// suppression window (based on `dismiss_days`).
    ///
    /// A message with no `dismiss_days` (or 0) doesn't remember a close, so it
    /// is never hidden by one; a number hides it for that many days.
    ///
    /// - Parameter message: The message to check.
    /// - Returns: `true` if the message was dismissed recently enough to remain hidden.
    public static func isMessageDismissed(message: Message) -> Bool {
        let key = dismissedKeyPrefix + message.id
        let dismissedAt = UserDefaults.standard.string(forKey: key).flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        return MessageTiming.stillDismissed(dismissedAt: dismissedAt, dismissDays: message.dismissDays)
    }

    /// Record the current date as the dismissal timestamp for a message.
    ///
    /// - Parameter messageId: The ID of the message being dismissed.
    public static func markDismissed(messageId: String) {
        let key = dismissedKeyPrefix + messageId
        let formatter = ISO8601DateFormatter()
        UserDefaults.standard.set(formatter.string(from: Date()), forKey: key)
    }

    /// Check whether a message should be suppressed based on max impressions
    /// or minimum interval between displays.
    ///
    /// - Parameter message: The message to check.
    /// - Returns: `true` if the message should be suppressed (not shown).
    public static func isMessageSuppressed(message: Message) -> Bool {
        let defaults = UserDefaults.standard

        // Check max impressions
        if let maxImpressions = message.maxImpressions, maxImpressions > 0 {
            let key = impressionCountPrefix + message.id
            let count = defaults.integer(forKey: key)
            if count >= maxImpressions { return true }
        }

        // Check min interval
        if let minIntervalHours = message.minIntervalHours, minIntervalHours > 0 {
            let key = lastShownPrefix + message.id
            if let dateString = defaults.string(forKey: key) {
                let formatter = ISO8601DateFormatter()
                if let lastShown = formatter.date(from: dateString) {
                    let intervalSeconds = Double(minIntervalHours) * 3600.0
                    if Date().timeIntervalSince(lastShown) < intervalSeconds { return true }
                }
            }
        }

        return false
    }

    /// Record that a message was shown (increment impression count and update last-shown time).
    ///
    /// - Parameter messageId: The ID of the message that was shown.
    public static func recordImpression(messageId: String) {
        let defaults = UserDefaults.standard

        // Increment impression count
        let countKey = impressionCountPrefix + messageId
        let count = defaults.integer(forKey: countKey)
        defaults.set(count + 1, forKey: countKey)

        // Update last-shown timestamp
        let shownKey = lastShownPrefix + messageId
        let formatter = ISO8601DateFormatter()
        defaults.set(formatter.string(from: Date()), forKey: shownKey)
    }

    // MARK: - Show

    /// Present a message in a modal WebView overlay.
    ///
    /// - Parameters:
    ///   - message: The message to display.
    ///   - viewController: The view controller to present from.
    ///   - onAction: Called when the user taps a navigation action in the message.
    ///     Receives the destination URL string. If nil, the URL is opened via
    ///     `UIApplication.shared.open`.
    ///   - onDismiss: Called after the message is dismissed (by close button or JS bridge).
    public static func show(
        message: Message,
        from viewController: UIViewController,
        onAction: ((String) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        guard let tolinku = Tolinku.shared else {
            os_log(.error, log: .default, "TolinkuSDK is not configured. Call Tolinku.configure() before presenting messages.")
            return
        }

        let baseURL = tolinku.client.baseURL
        let encodedId = message.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? message.id

        // Fetch a render token, then load the WebView with the token in the URL
        Task {
            let token: String
            do {
                token = try await tolinku.messages.renderToken(messageId: message.id)
            } catch {
                os_log(.error, log: .default, "Failed to fetch render token: %{public}@", error.localizedDescription)
                return
            }

            let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
            let renderURL = "\(baseURL)/v1/api/messages/\(encodedId)/render?token=\(encodedToken)"

            await MainActor.run {
                let presenter = MessageViewController(
                    renderURLString: renderURL,
                    messageId: message.id,
                    onAction: onAction,
                    onDismiss: onDismiss
                )
                presenter.modalPresentationStyle = .overFullScreen
                presenter.modalTransitionStyle = .crossDissolve
                viewController.present(presenter, animated: true)
            }
        }
    }
}

// MARK: - MessageViewController

/// A view controller that hosts a transparent WKWebView for rendering message HTML.
private final class MessageViewController: UIViewController, WKScriptMessageHandler {

    private let renderURLString: String
    private let messageId: String
    private let onAction: ((String) -> Void)?
    private let onDismiss: (() -> Void)?

    private var webView: WKWebView!
    private var closeButton: UIButton!

    init(
        renderURLString: String,
        messageId: String,
        onAction: ((String) -> Void)?,
        onDismiss: (() -> Void)?
    ) {
        self.renderURLString = renderURLString
        self.messageId = messageId
        self.onAction = onAction
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        // Configure WKWebView with JS bridge.
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(self, name: "tolinku")
        config.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Native close button overlaid on the top-right corner. A white X on
        // a dark disc, because it sits over the message itself and a message
        // can be any colour: the white mark it used to be vanished on a white
        // one, which is the default. The button is 44pt, Apple's minimum tap
        // target; the disc drawn inside it is 32pt.
        closeButton = UIButton(type: .custom)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let disc = UIView()
        disc.translatesAutoresizingMaskIntoConstraints = false
        disc.isUserInteractionEnabled = false
        disc.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        disc.layer.cornerRadius = 16
        closeButton.addSubview(disc)

        let xView = UIImageView(image: UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        ))
        xView.translatesAutoresizingMaskIntoConstraints = false
        xView.tintColor = .white
        xView.isUserInteractionEnabled = false
        disc.addSubview(xView)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            disc.centerXAnchor.constraint(equalTo: closeButton.centerXAnchor),
            disc.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            disc.widthAnchor.constraint(equalToConstant: 32),
            disc.heightAnchor.constraint(equalToConstant: 32),
            xView.centerXAnchor.constraint(equalTo: disc.centerXAnchor),
            xView.centerYAnchor.constraint(equalTo: disc.centerYAnchor),
        ])

        loadRenderedHTML()
    }

    private func loadRenderedHTML() {
        guard let url = URL(string: renderURLString) else {
            os_log(.error, log: .default, "Invalid render URL: %{public}@", renderURLString)
            dismissMessage()
            return
        }
        let request = URLRequest(url: url)
        webView.load(request)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "tolinku" else { return }
        guard let bodyString = message.body as? String,
              let data = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String
        else {
            return
        }

        switch action {
        case "close":
            dismissMessage()

        case "navigate":
            guard let urlString = json["url"] as? String else { return }
            dismissAndNavigate(to: urlString)

        default:
            os_log(.default, log: .default, "Unknown JS bridge action: %{public}@", action)
        }
    }

    // MARK: - Dismissal

    @objc private func closeTapped() {
        dismissMessage()
    }

    private func dismissMessage() {
        TolinkuMessagePresenter.markDismissed(messageId: messageId)
        dismiss(animated: true) { [onDismiss] in
            onDismiss?()
        }
    }

    private func dismissAndNavigate(to urlString: String) {
        // A message's call to action is the one place a custom scheme belongs:
        // on a deep linking product the natural button opens a screen in the
        // host app, `myapp://order/4821`. So this denies the schemes that can
        // run code and leaves the rest to the app, rather than allowlisting http
        // the way an image source does. The decision itself lives beside the
        // rest of the URL rules, where the test suite can reach it: this file
        // needs UIKit and WebKit, so nothing in it is exercised by a test.
        guard case let .follow(destination, url) = messageAction(for: urlString) else {
            os_log(.default, log: .default, "Blocked a message action naming a scheme that can run code, or no scheme at all: %{public}@", urlString)
            dismissMessage()
            return
        }

        TolinkuMessagePresenter.markDismissed(messageId: messageId)
        dismiss(animated: true) { [onAction] in
            if let onAction {
                onAction(destination)
            } else if let url {
                UIApplication.shared.open(url)
            } else {
                // The scheme was fine and the app named no handler of its own,
                // so there is nothing left to open it with. Worth saying plainly,
                // because it is a different problem from a refused scheme and
                // the one thing that fixes it is the app adopting `onAction`.
                os_log(.default, log: .default, "Could not build a URL from a message action, and no onAction handler is set: %{public}@", destination)
            }
        }
    }
}
#endif
