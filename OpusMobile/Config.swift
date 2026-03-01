import Foundation

/// Available API server environments. Release builds are locked to production only.
enum ServerEnvironment: String, CaseIterable, Identifiable {
    case local = "Local"
    case `internal` = "Internal"
    case production = "Production"
    case custom = "Custom"

    var id: String { rawValue }

    var defaultURL: String {
        switch self {
        case .local: return "http://localhost:8080"           // Docker Compose backend
        case .internal: return "http://172.16.16.142:4200"    // Office LAN server
        case .production: return "https://pm-api.opus-accountancy.co.uk"
        case .custom: return ""
        }
    }

    /// Release builds only expose production — prevents shipping with dev servers accessible
    static var availableCases: [ServerEnvironment] {
        #if DEBUG
        return allCases
        #else
        return [.production]
        #endif
    }
}

/// Central configuration backed by UserDefaults. Uses an enum (not struct) to prevent instantiation.
enum Config {
    private static let environmentKey = "server_environment"
    private static let customURLKey = "custom_api_url"
    private static let skipSSLKey = "skip_ssl_validation"
    private static let biometricKey = "biometric_login_enabled"

    static var selectedEnvironment: ServerEnvironment {
        get {
            guard let raw = UserDefaults.standard.string(forKey: environmentKey),
                  let env = ServerEnvironment(rawValue: raw) else {
                // Default to local for dev, production for release
                #if DEBUG
                return .local
                #else
                return .production
                #endif
            }
            return env
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: environmentKey)
        }
    }

    static var customURL: String {
        get { UserDefaults.standard.string(forKey: customURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: customURLKey) }
    }

    /// SSL bypass is DEBUG-only — compiled out entirely in release to prevent MITM in production
    static var skipSSLValidation: Bool {
        get {
            #if DEBUG
            return UserDefaults.standard.bool(forKey: skipSSLKey)
            #else
            return false
            #endif
        }
        set {
            #if DEBUG
            UserDefaults.standard.set(newValue, forKey: skipSSLKey)
            #endif
        }
    }

    static var biometricLoginEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: biometricKey) }
        set { UserDefaults.standard.set(newValue, forKey: biometricKey) }
    }

    /// Resolved API URL — uses the custom URL if that environment is selected, otherwise the preset
    static var apiBaseURL: String {
        let env = selectedEnvironment
        if env == .custom {
            return customURL
        }
        return env.defaultURL
    }
}
