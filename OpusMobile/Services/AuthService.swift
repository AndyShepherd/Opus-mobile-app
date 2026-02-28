import Foundation

@MainActor
final class AuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: LoginResponse?

    private static let tokenKey = "jwt_token"

    var token: String? {
        KeychainHelper.read(key: Self.tokenKey)
    }

    func checkAuth() async {
        // 1. Try standard token
        if let token {
            do {
                let _: MeResponse = try await APIClient.request(
                    path: "/api/auth/me",
                    token: token
                )
                isAuthenticated = true
                return
            } catch {
                KeychainHelper.delete(key: Self.tokenKey)
            }
        }

        // 2. Try biometric if enabled and credentials exist
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

    func attemptBiometricLogin() async throws {
        let creds = try BiometricService.authenticateAndReadAll()

        // Try the stored token first
        do {
            let _: MeResponse = try await APIClient.request(
                path: "/api/auth/me",
                token: creds.token
            )
            KeychainHelper.save(key: Self.tokenKey, value: creds.token)
            isAuthenticated = true
            return
        } catch {
            // Token expired — re-authenticate with stored credentials
        }

        try await login(username: creds.username, password: creds.password)
    }

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

        if updateBiometric && Config.biometricLoginEnabled {
            BiometricService.saveCredentials(
                token: response.token,
                username: username,
                password: password
            )
        }
    }

    func logout() {
        KeychainHelper.delete(key: Self.tokenKey)
        BiometricService.clearAll()
        currentUser = nil
        isAuthenticated = false
    }
}
