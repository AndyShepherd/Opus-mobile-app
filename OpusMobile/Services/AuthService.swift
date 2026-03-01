import Foundation

/// Manages authentication state. @MainActor because isAuthenticated drives UI transitions
/// and must be updated on the main thread.
@MainActor
final class AuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: LoginResponse?

    private static let tokenKey = "jwt_token"

    /// Reads the JWT from the Keychain on each access (not cached) so it always reflects
    /// the latest saved state after login/logout.
    var token: String? {
        KeychainHelper.read(key: Self.tokenKey)
    }

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
        KeychainHelper.delete(key: Self.tokenKey)
        BiometricService.clearAll()
        currentUser = nil
        isAuthenticated = false
    }
}
