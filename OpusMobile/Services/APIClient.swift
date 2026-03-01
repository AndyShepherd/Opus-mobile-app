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

    /// Generic JSON request. The return type is inferred from the call site, so callers
    /// write e.g. `let users: [Customer] = try await APIClient.request(path: "/api/customers")`.
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        // 401 is handled specially — callers use this to trigger logout
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
