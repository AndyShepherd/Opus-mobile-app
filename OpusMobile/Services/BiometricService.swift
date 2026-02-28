import Foundation
import LocalAuthentication
import Security

enum BiometricService {
    private static let service = "com.opus.mobile.biometric"

    private static let tokenKey = "biometric_token"
    private static let usernameKey = "biometric_username"
    private static let passwordKey = "biometric_password"

    // MARK: - Availability

    enum BiometricType {
        case faceID
        case touchID
        case none
    }

    static var biometricType: BiometricType {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    static var isAvailable: Bool {
        biometricType != .none
    }

    static var systemImageName: String {
        switch biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock.shield"
        }
    }

    static var displayName: String {
        switch biometricType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .none: return "Biometrics"
        }
    }

    // MARK: - Credential Check (no biometric prompt)

    static var hasStoredCredentials: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: usernameKey,
            kSecUseAuthenticationContext as String: context,
            kSecReturnData as String: false
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    // MARK: - Read All (single biometric prompt)

    struct StoredCredentials {
        let token: String
        let username: String
        let password: String
    }

    static func authenticateAndReadAll() throws -> StoredCredentials {
        let context = LAContext()
        context.localizedReason = "Sign in to Opus"

        guard let token = readItem(key: tokenKey, context: context),
              let username = readItem(key: usernameKey, context: context),
              let password = readItem(key: passwordKey, context: context) else {
            throw BiometricError.credentialsNotFound
        }

        return StoredCredentials(token: token, username: username, password: password)
    }

    // MARK: - Save

    static func saveCredentials(token: String, username: String, password: String) {
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ) else { return }

        saveItem(key: tokenKey, value: token, accessControl: accessControl)
        saveItem(key: usernameKey, value: username, accessControl: accessControl)
        saveItem(key: passwordKey, value: password, accessControl: accessControl)
    }

    // MARK: - Clear

    static func clearAll() {
        deleteItem(key: tokenKey)
        deleteItem(key: usernameKey)
        deleteItem(key: passwordKey)
    }

    // MARK: - Private Helpers

    private static func readItem(key: String, context: LAContext) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseAuthenticationContext as String: context,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func saveItem(key: String, value: String, accessControl: SecAccessControl) {
        guard let data = value.data(using: .utf8) else { return }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessControl as String: accessControl,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func deleteItem(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum BiometricError: LocalizedError {
    case credentialsNotFound
    case authenticationFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .credentialsNotFound: return "No stored credentials found. Please sign in manually."
        case .authenticationFailed: return "Biometric authentication failed."
        case .cancelled: return "Authentication was cancelled."
        }
    }
}
