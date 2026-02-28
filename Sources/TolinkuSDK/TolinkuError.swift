import Foundation

/// Errors that can occur when using the Tolinku SDK.
public enum TolinkuError: Error, LocalizedError, Sendable {

    /// The constructed URL was invalid.
    case invalidURL(String)

    /// The server returned a non-HTTP response.
    case invalidResponse

    /// The server returned an HTTP error status code.
    case httpError(statusCode: Int, message: String?, code: String? = nil)

    /// Failed to decode the response body.
    case decodingFailed(Error)

    /// The SDK has not been configured. Call ``Tolinku/configure(apiKey:baseURL:)`` first.
    case notConfigured

    /// A network-level error occurred (e.g. no connectivity, timeout, DNS failure).
    case networkError(URLError)

    /// The provided configuration is invalid (e.g. empty API key or base URL).
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "The server returned an invalid (non-HTTP) response."
        case .httpError(let statusCode, let message, let code):
            var desc = "HTTP \(statusCode)"
            if let code {
                desc += " [\(code)]"
            }
            if let message {
                desc += ": \(message)"
            }
            return desc
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .notConfigured:
            return "TolinkuSDK has not been configured. Call Tolinku.configure(apiKey:baseURL:) first."
        case .networkError(let urlError):
            return "Network error: \(urlError.localizedDescription)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        }
    }
}
