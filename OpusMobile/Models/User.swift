import Foundation

struct LoginResponse: Codable {
    let id: String
    let username: String
    let email: String
    let role: String
    let token: String
}

struct MeResponse: Codable {
    let id: String
    let username: String
    let role: String
}
