import Foundation

/// Typed API errors with user-facing descriptions. The `.unauthorized` case triggers
/// automatic logout in calling code (see ClientListView.fetchClients).
enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .serverError(let code):
            return "Server error (\(code))"
        case .decodingError:
            // Don't expose raw decoding errors to users — they're not actionable
            return "Failed to read server response"
        case .networkError(let error):
            return error.localizedDescription
        }
    }
}

// DEBUG-only: accepts any server certificate, needed for the internal LAN server
// which uses a self-signed cert. Compiled out entirely in release builds.
#if DEBUG
private class SSLBypassDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
#endif

/// Generic HTTP client for the Opus PM backend. Uses an enum (not class) since all
/// methods are static and no instances are needed.
enum APIClient {
    // The SSL bypass session is lazily initialised once and reused for all requests
    #if DEBUG
    private static let sslBypassSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: SSLBypassDelegate(), delegateQueue: nil)
    }()
    #endif

    /// Selects the appropriate URLSession: bypass session if SSL skip is enabled (debug only),
    /// otherwise the default shared session.
    private static var session: URLSession {
        #if DEBUG
        Config.skipSSLValidation ? sslBypassSession : .shared
        #else
        .shared
        #endif
    }

    /// Generic JSON request with automatic retry for transient errors.
    /// Retries up to 2 times (3 total attempts) with exponential backoff for network errors,
    /// HTTP 429 (Too Many Requests), and HTTP 503 (Service Unavailable).
    /// Non-retryable errors (401, other 4xx/5xx, decoding errors) fail immediately.
    static func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        token: String? = nil
    ) async throws -> T {
        guard let url = URL(string: Config.apiBaseURL + path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = body
        }

        let maxRetries = 2
        let backoffDelays: [TimeInterval] = [1, 3]
        var lastError: APIError?
        var retryAfterDelay: TimeInterval?

        for attempt in 0...maxRetries {
            if attempt > 0 {
                let delay = retryAfterDelay ?? backoffDelays[attempt - 1]
                retryAfterDelay = nil
                try await Task.sleep(for: .seconds(delay))
            }

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                lastError = .networkError(error)
                if attempt == maxRetries { throw lastError! }
                continue
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(URLError(.badServerResponse))
            }

            // 401 — fail immediately, AuthService handles token recovery
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }

            // 429/503 — retryable; respect Retry-After header if present
            if [429, 503].contains(httpResponse.statusCode) {
                lastError = .serverError(httpResponse.statusCode)
                if attempt == maxRetries { throw lastError! }
                if let retryHeader = httpResponse.value(forHTTPHeaderField: "Retry-After"),
                   let seconds = TimeInterval(retryHeader) {
                    retryAfterDelay = min(seconds, 30)
                }
                continue
            }

            // Other non-2xx — fail immediately
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.serverError(httpResponse.statusCode)
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        }

        throw lastError!
    }
}
