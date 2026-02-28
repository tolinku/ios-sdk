import Foundation

/// Low-level HTTP client that powers all SDK network calls.
///
/// Uses URLSession with async/await. Authenticated endpoints include the
/// X-API-Key header automatically. Retries failed requests with exponential
/// backoff for network errors, HTTP 429, and HTTP 5xx responses.
final class Client: Sendable {

    // MARK: - Properties

    /// The API key sent as the X-API-Key header on authenticated requests.
    let apiKey: String

    /// The base URL (no trailing slash) for all API requests.
    let baseURL: String

    private let session: URLSession

    // MARK: - Retry Configuration

    /// Maximum number of retry attempts before giving up.
    private let maxRetries = 3

    /// Base delay in seconds for exponential backoff (multiplied by 2^attempt).
    private let baseDelay: TimeInterval = 0.5

    /// Maximum jitter in seconds added to each retry delay.
    private let maxJitter: TimeInterval = 0.25

    // MARK: - Initialization

    /// Create a new client.
    ///
    /// - Parameters:
    ///   - apiKey: Your Tolinku API key.
    ///   - baseURL: The base URL of your Tolinku instance.
    ///   - session: An optional URLSession (defaults to `.shared`).
    init(apiKey: String, baseURL: String, session: URLSession = .shared) {
        // Strip trailing slash if present
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.session = session
    }

    // MARK: - Request Helpers

    /// Perform an authenticated GET request and decode the response.
    ///
    /// - Parameters:
    ///   - path: The URL path (e.g. "/v1/api/referral/leaderboard").
    ///   - queryItems: Optional query parameters.
    /// - Returns: The decoded response of type `T`.
    func get<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let request = try buildRequest(method: "GET", path: path, queryItems: queryItems, authenticated: authenticated)
        return try await performWithRetry(request)
    }

    /// Perform an authenticated POST request with a JSON body and decode the response.
    ///
    /// - Parameters:
    ///   - path: The URL path.
    ///   - body: An Encodable value to send as JSON.
    /// - Returns: The decoded response of type `T`.
    func post<B: Encodable, T: Decodable>(
        path: String,
        body: B,
        authenticated: Bool = true
    ) async throws -> T {
        let encoder = JSONEncoder()
        var request = try buildRequest(method: "POST", path: path, authenticated: authenticated)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await performWithRetry(request)
    }

    /// Perform a POST request that returns no meaningful body (expects success status).
    func postVoid<B: Encodable>(
        path: String,
        body: B,
        authenticated: Bool = true
    ) async throws {
        let encoder = JSONEncoder()
        var request = try buildRequest(method: "POST", path: path, authenticated: authenticated)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        try await performVoidWithRetry(request)
    }

    // MARK: - Internal

    private func buildRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        authenticated: Bool = true
    ) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + path) else {
            throw TolinkuError.invalidURL(baseURL + path)
        }
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw TolinkuError.invalidURL(components.string ?? path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("TolinkuiOSSDK/\(Tolinku.sdkVersion)", forHTTPHeaderField: "User-Agent")
        if authenticated {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        return request
    }

    /// Execute a raw URLRequest and return the data, HTTP response, and any Retry-After hint.
    /// Throws TolinkuError.networkError for URLErrors.
    private func executeRaw(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, TimeInterval?) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw TolinkuError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TolinkuError.invalidResponse
        }
        let retryAfter = extractRetryAfter(from: httpResponse)
        return (data, httpResponse, retryAfter)
    }

    /// Validate an HTTP response and throw TolinkuError.httpError for non-2xx status codes.
    private func validateHTTPResponse(data: Data, httpResponse: HTTPURLResponse) throws {
        guard (200...299).contains(httpResponse.statusCode) else {
            let decoder = JSONDecoder()
            let errorBody = try? decoder.decode(APIErrorResponse.self, from: data)
            let message = errorBody?.error ?? errorBody?.message ?? String(data: data, encoding: .utf8)
            throw TolinkuError.httpError(statusCode: httpResponse.statusCode, message: message, code: errorBody?.code)
        }
    }

    /// Extracts the Retry-After header value (in seconds) from an HTTP response, if present.
    private func extractRetryAfter(from httpResponse: HTTPURLResponse) -> TimeInterval? {
        guard let retryAfterValue = httpResponse.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        // Retry-After can be a number of seconds or an HTTP-date. We support seconds only.
        return TimeInterval(retryAfterValue)
    }

    // MARK: - Retry Logic

    /// Determines whether the given error is eligible for a retry attempt.
    ///
    /// Retries on:
    /// - Network errors (URLError)
    /// - HTTP 429 (Too Many Requests)
    /// - HTTP 5xx (server errors)
    ///
    /// Does NOT retry on:
    /// - 4xx errors (except 429)
    /// - Successful responses
    /// - Decoding errors
    private func shouldRetry(_ error: Error) -> Bool {
        switch error {
        case is URLError:
            return true
        case TolinkuError.networkError:
            return true
        case TolinkuError.httpError(let statusCode, _, _):
            return statusCode == 429 || (statusCode >= 500 && statusCode <= 599)
        default:
            return false
        }
    }

    /// Computes the retry delay for a given attempt.
    ///
    /// Uses exponential backoff: baseDelay * 2^attempt, plus random jitter (0 to 0.25s).
    /// If the server returned a Retry-After header, that value is used as the base instead.
    private func retryDelay(attempt: Int, retryAfterHint: TimeInterval?) -> TimeInterval {
        if let retryAfter = retryAfterHint {
            return retryAfter + TimeInterval.random(in: 0...maxJitter)
        }
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt))
        let jitter = TimeInterval.random(in: 0...maxJitter)
        return exponentialDelay + jitter
    }

    /// Perform a request with retry logic, returning a decoded response.
    ///
    /// Wraps the raw request execution with exponential backoff retries
    /// for transient failures (network errors, 429, 5xx).
    private func performWithRetry<T: Decodable>(_ request: URLRequest) async throws -> T {
        var lastError: Error?

        for attempt in 0...maxRetries {
            var retryAfterHint: TimeInterval? = nil

            do {
                let (data, httpResponse, retryAfter) = try await executeRaw(request)
                retryAfterHint = retryAfter
                try validateHTTPResponse(data: data, httpResponse: httpResponse)

                do {
                    let decoder = JSONDecoder()
                    return try decoder.decode(T.self, from: data)
                } catch {
                    throw TolinkuError.decodingFailed(error)
                }
            } catch {
                lastError = error

                guard shouldRetry(error), attempt < maxRetries else {
                    throw error
                }

                let delay = retryDelay(attempt: attempt, retryAfterHint: retryAfterHint)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? TolinkuError.invalidResponse
    }

    /// Perform a void request with retry logic.
    ///
    /// Wraps the raw request execution with exponential backoff retries
    /// for transient failures (network errors, 429, 5xx).
    private func performVoidWithRetry(_ request: URLRequest) async throws {
        var lastError: Error?

        for attempt in 0...maxRetries {
            var retryAfterHint: TimeInterval? = nil

            do {
                let (data, httpResponse, retryAfter) = try await executeRaw(request)
                retryAfterHint = retryAfter
                try validateHTTPResponse(data: data, httpResponse: httpResponse)
                return
            } catch {
                lastError = error

                guard shouldRetry(error), attempt < maxRetries else {
                    throw error
                }

                let delay = retryDelay(attempt: attempt, retryAfterHint: retryAfterHint)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? TolinkuError.invalidResponse
    }
}
