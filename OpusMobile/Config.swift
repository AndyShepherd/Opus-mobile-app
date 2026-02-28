import Foundation

enum Config {
    #if DEBUG
    static let apiBaseURL = "http://localhost:8080"
    #else
    static let apiBaseURL = "https://your-production-url.com"
    #endif
}
