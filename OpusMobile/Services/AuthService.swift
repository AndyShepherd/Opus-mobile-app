import Foundation

/// Manages authentication state. @MainActor because isAuthenticated drives UI transitions
/// and must be updated on the main thread.
@MainActor
final class AuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: LoginResponse?

    private static let tokenKey = "jwt_token"

    /// Tracked after every login, refresh, or checkAuth so we can proactively refresh
    /// before the token expires (the backend rejects expired tokens on /api/auth/refresh).
    private var tokenExpiryDate: Date?

    /// Deduplicates concurrent refresh calls — all callers await the same in-flight task
    private var activeRefreshTask: Task<Bool, Never>?

    /// Reads the JWT from the Keychain on each access (not cached) so it always reflects
    /// the latest saved state after login/logout.
    var token: String? {
        KeychainHelper.read(key: Self.tokenKey)
    }

    // MARK: - JWT Expiry Decoding

    /// Decodes the `exp` claim from a JWT payload without external libraries.
    /// JWTs are three Base64URL-encoded segments separated by dots; the second is the payload.
    private static func expiryDate(from token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }

        // Base64URL → Base64: replace URL-safe characters and pad to a multiple of 4
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    /// Whether the token is within 24 hours of expiry (or already expired)
    private var tokenNeedsRefresh: Bool {
        guard let expiry = tokenExpiryDate else { return false }
        return expiry.timeIntervalSinceNow < 24 * 60 * 60
    }

    /// Whether the token has already expired
    private var tokenIsExpired: Bool {
        guard let expiry = tokenExpiryDate else { return false }
        return expiry <= Date()
    }

    // MARK: - Token Refresh

    /// Calls POST /api/auth/refresh with the current token. Returns true on success.
    /// Concurrent callers share the same in-flight task to avoid duplicate requests.
    func refreshToken() async -> Bool {
        // If a refresh is already in flight, piggyback on it
        if let existing = activeRefreshTask {
            return await existing.value
        }

        let task = Task<Bool, Never> { @MainActor in
            defer { activeRefreshTask = nil }

            guard let currentToken = token else { return false }

            do {
                let response: RefreshResponse = try await APIClient.request(
                    path: "/api/auth/refresh",
                    method: "POST",
                    token: currentToken
                )
                KeychainHelper.save(key: Self.tokenKey, value: response.token)
                tokenExpiryDate = Self.expiryDate(from: response.token)

                if Config.biometricLoginEnabled && BiometricService.hasStoredCredentials {
                    BiometricService.updateToken(response.token)
                }
                return true
            } catch {
                return false
            }
        }

        activeRefreshTask = task
        return await task.value
    }

    // MARK: - Authenticated Request Wrapper

    /// Wrapper that views should call instead of `APIClient.request` directly.
    /// Handles proactive refresh, 401 retry with refresh, and biometric re-login fallback.
    func authenticatedRequest<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        // 1. Proactive refresh if within 24 hours of expiry
        if tokenNeedsRefresh && !tokenIsExpired {
            _ = await refreshToken()
        }

        // 2. Make the request with the current token
        guard let currentToken = token else { throw APIError.unauthorized }

        do {
            return try await APIClient.request(
                path: path,
                method: method,
                body: body,
                token: currentToken
            )
        } catch APIError.unauthorized {
            // 3. 401 retry chain
            // 3a. Try refreshing the token
            if await refreshToken(), let refreshedToken = token {
                do {
                    return try await APIClient.request(
                        path: path,
                        method: method,
                        body: body,
                        token: refreshedToken
                    )
                } catch APIError.unauthorized {
                    // Refresh succeeded but request still 401 — fall through to biometric
                }
            }

            // 3b. Try biometric re-login
            if Config.biometricLoginEnabled && BiometricService.hasStoredCredentials {
                do {
                    try await attemptBiometricLogin()
                    if let newToken = token {
                        return try await APIClient.request(
                            path: path,
                            method: method,
                            body: body,
                            token: newToken
                        )
                    }
                } catch {
                    // Biometric failed — fall through to logout
                }
            }

            // 3c. All recovery attempts failed
            logout()
            throw APIError.unauthorized
        }
    }

    // MARK: - Foreground Check

    /// Called when the app returns to foreground. Detects expired or near-expiry tokens
    /// and attempts recovery before any API call fails.
    func checkTokenOnForeground() async {
        guard isAuthenticated, token != nil else { return }

        if tokenIsExpired {
            // Token expired while backgrounded — try biometric re-login
            if Config.biometricLoginEnabled && BiometricService.hasStoredCredentials {
                do {
                    try await attemptBiometricLogin()
                } catch {
                    logout()
                }
            } else {
                logout()
            }
        } else if tokenNeedsRefresh {
            _ = await refreshToken()
        }
    }

    // MARK: - Auth Flow

    /// Called on app launch to restore a session. Two-step fallback:
    /// 1. Validate the stored JWT against /api/auth/me
    /// 2. If no JWT (or expired), try biometric login with stored credentials
    func checkAuth() async {
        // 1. Try the plain JWT from Keychain
        if let token {
            do {
                let _: MeResponse = try await APIClient.request(
                    path: "/api/auth/me",
                    token: token
                )
                tokenExpiryDate = Self.expiryDate(from: token)
                isAuthenticated = true
                return
            } catch {
                // Token invalid/expired — clear it and fall through to biometric
                KeychainHelper.delete(key: Self.tokenKey)
            }
        }

        // 2. Try biometric login if the user has opted in and credentials are stored
        if Config.biometricLoginEnabled && BiometricService.hasStoredCredentials {
            do {
                try await attemptBiometricLogin()
            } catch {
                isAuthenticated = false
            }
        } else {
            isAuthenticated = false
        }
    }

    /// Biometric login flow: first tries the stored token (avoids an unnecessary network
    /// round-trip if it's still valid), then falls back to re-authenticating with the
    /// stored username/password if the token has expired.
    func attemptBiometricLogin() async throws {
        // This triggers the Face ID / Touch ID prompt via BiometricService
        let creds = try BiometricService.authenticateAndReadAll()

        // Try the stored token first to avoid a login round-trip
        do {
            let _: MeResponse = try await APIClient.request(
                path: "/api/auth/me",
                token: creds.token
            )
            // Token is still valid — promote it to the active Keychain slot
            KeychainHelper.save(key: Self.tokenKey, value: creds.token)
            tokenExpiryDate = Self.expiryDate(from: creds.token)
            isAuthenticated = true
            return
        } catch {
            // Token expired — fall through to re-login with stored credentials
        }

        try await login(username: creds.username, password: creds.password)
    }

    /// Standard username/password login. Saves the new JWT and optionally updates the
    /// biometric credential store so future biometric logins use the fresh token.
    func login(username: String, password: String, updateBiometric: Bool = true) async throws {
        let credentials = ["username": username, "password": password]
        let body = try JSONEncoder().encode(credentials)

        let response: LoginResponse = try await APIClient.request(
            path: "/api/auth/login",
            method: "POST",
            body: body
        )

        KeychainHelper.save(key: Self.tokenKey, value: response.token)
        tokenExpiryDate = Self.expiryDate(from: response.token)
        currentUser = response
        isAuthenticated = true

        // Keep biometric credentials in sync with the latest token
        if updateBiometric && Config.biometricLoginEnabled {
            BiometricService.saveCredentials(
                token: response.token,
                username: username,
                password: password
            )
        }
    }

    /// Clears all stored credentials (both plain JWT and biometric) and resets UI state
    func logout() {
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        tokenExpiryDate = nil
        KeychainHelper.delete(key: Self.tokenKey)
        BiometricService.clearAll()
        ClientCache.clear()
        currentUser = nil
        isAuthenticated = false
    }
}
