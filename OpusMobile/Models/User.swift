import Foundation

/// POST /api/auth/login response — includes the JWT and user profile fields
struct LoginResponse: Codable {
    let id: String
    let username: String
    let email: String
    let role: String
    let token: String       // JWT for subsequent authenticated requests
}

/// GET /api/auth/me response — lighter than LoginResponse (no token or email)
struct MeResponse: Codable {
    let id: String
    let username: String
    let role: String
}
