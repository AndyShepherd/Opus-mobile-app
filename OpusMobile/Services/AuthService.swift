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
        guard let token else {
            isAuthenticated = false
            return
        }

        do {
            let _: MeResponse = try await APIClient.request(
                path: "/api/auth/me",
                token: token
            )
            isAuthenticated = true
        } catch {
            logout()
        }
    }

    func login(username: String, password: String) async throws {
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
    }

    func logout() {
        KeychainHelper.delete(key: Self.tokenKey)
        currentUser = nil
        isAuthenticated = false
    }
}
