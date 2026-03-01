import Foundation
import LocalAuthentication
import Security

/// Manages biometric (Face ID / Touch ID) credential storage and retrieval.
/// Uses a separate Keychain service from KeychainHelper so biometric-protected items
/// don't interfere with the plain JWT store.
enum BiometricService {
    // Separate service identifier from KeychainHelper to isolate biometric items
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

    /// Cached once on first access — the device's biometric hardware doesn't change
    /// while the app is running, so there's no need to create a new LAContext and
    /// evaluate policy on every SwiftUI body re-render.
    private static let cachedBiometricType: BiometricType = {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }()

    static var biometricType: BiometricType {
        cachedBiometricType
    }

    static var isAvailable: Bool {
        biometricType != .none
    }

    /// SF Symbol name matching the device's biometric type, for use in buttons/labels
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

    /// Cached credential existence check. The initial value is resolved lazily via a
    /// Keychain query, then kept in sync by saveCredentials() and clearAll() — avoiding
    /// a Keychain round-trip on every SwiftUI body evaluation.
    private static var cachedHasCredentials: Bool?

    static var hasStoredCredentials: Bool {
        if let cached = cachedHasCredentials { return cached }
        let result = checkKeychainForCredentials()
        cachedHasCredentials = result
        return result
    }

    /// Performs the actual Keychain query. Only called once per app session — subsequent
    /// reads come from the cache.
    private static func checkKeychainForCredentials() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: usernameKey,
            kSecUseAuthenticationContext as String: context,
            kSecReturnData as String: false     // We only care about existence, not the value
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // errSecInteractionNotAllowed means "item exists but needs biometric" — that's a yes
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    // MARK: - Read All (single biometric prompt)

    struct StoredCredentials {
        let token: String
        let username: String
        let password: String
    }

    /// Reads all three credentials using a single LAContext. Because the context is reused,
    /// the user only sees one Face ID / Touch ID prompt for all three Keychain reads.
    static func authenticateAndReadAll() throws -> StoredCredentials {
        let context = LAContext()
        context.localizedReason = "Sign in to Opus"

        // Reusing the same context across reads means one biometric prompt, not three
        guard let token = readItem(key: tokenKey, context: context),
              let username = readItem(key: usernameKey, context: context),
              let password = readItem(key: passwordKey, context: context) else {
            throw BiometricError.credentialsNotFound
        }

        return StoredCredentials(token: token, username: username, password: password)
    }

    // MARK: - Save

    /// Stores credentials with biometric protection. Uses `.biometryCurrentSet` so that
    /// if the user adds/removes a fingerprint or re-enrols Face ID, the items are invalidated
    /// (preventing a new biometric user from accessing the old credentials).
    /// `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` ensures items never leave the device
    /// via backup and require a device passcode to exist.
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
        cachedHasCredentials = true
    }

    // MARK: - Token Update

    /// Updates only the stored token without touching username/password.
    /// Writing to biometric-protected Keychain doesn't require a Face ID prompt (only reads do),
    /// so this is completely silent. Called after a token refresh to keep the biometric store in sync.
    static func updateToken(_ token: String) {
        guard hasStoredCredentials else { return }
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ) else { return }
        saveItem(key: tokenKey, value: token, accessControl: accessControl)
    }

    // MARK: - Clear

    /// Removes all biometric credentials (called on logout or when biometric login is disabled)
    static func clearAll() {
        deleteItem(key: tokenKey)
        deleteItem(key: usernameKey)
        deleteItem(key: passwordKey)
        cachedHasCredentials = false
    }

    // MARK: - Private Helpers

    /// Reads a single Keychain item using the provided LAContext. The context carries
    /// the biometric authentication state, so subsequent reads won't re-prompt.
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

        // Delete first to avoid errSecDuplicateItem (same pattern as KeychainHelper)
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
