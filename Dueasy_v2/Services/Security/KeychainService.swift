import Foundation
import Security
import os.log

/// Service for secure storage in iOS Keychain.
/// Used for security-sensitive settings that should not be stored in UserDefaults.
///
/// Security Properties:
/// - Data is encrypted using the device's Secure Enclave
/// - Protected with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
/// - Not backed up to iCloud or iTunes
/// - Survives app reinstallation (by design)
///
/// Use Cases:
/// - Cloud analysis consent flags
/// - API tokens (Iteration 2)
/// - User authentication state (Iteration 2)
final class KeychainService: @unchecked Sendable {

    private let serviceName: String
    private let logger = Logger(subsystem: "com.dueasy.app", category: "Keychain")

    /// Default service name for DuEasy app
    static let defaultServiceName = "com.dueasy.app.keychain"

    init(serviceName: String = KeychainService.defaultServiceName) {
        self.serviceName = serviceName
    }

    // MARK: - String Storage

    /// Saves a string value to the Keychain.
    /// - Parameters:
    ///   - key: The key to store the value under
    ///   - value: The string value to store
    /// - Throws: AppError if the operation fails
    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw AppError.unknown("Failed to encode string for Keychain")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing value first (update pattern)
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            logger.error("Keychain save failed for key '\(key)': status \(status)")
            throw AppError.unknown("Keychain save failed: \(status)")
        }

        logger.debug("Saved value to Keychain for key '\(key)'")
    }

    /// Loads a string value from the Keychain.
    /// - Parameter key: The key to load the value for
    /// - Returns: The stored string value, or nil if not found
    /// - Throws: AppError if the operation fails (other than item not found)
    func load(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                return nil
            }
            return string

        case errSecItemNotFound:
            return nil

        default:
            logger.error("Keychain load failed for key '\(key)': status \(status)")
            throw AppError.unknown("Keychain load failed: \(status)")
        }
    }

    /// Deletes a value from the Keychain.
    /// - Parameter key: The key to delete
    /// - Throws: AppError if the operation fails (other than item not found)
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed for key '\(key)': status \(status)")
            throw AppError.unknown("Keychain delete failed: \(status)")
        }

        logger.debug("Deleted value from Keychain for key '\(key)'")
    }

    // MARK: - Boolean Storage (Convenience)

    /// Saves a boolean value to the Keychain.
    /// - Parameters:
    ///   - key: The key to store the value under
    ///   - value: The boolean value to store
    func save(key: String, value: Bool) throws {
        try save(key: key, value: value ? "true" : "false")
    }

    /// Loads a boolean value from the Keychain.
    /// - Parameter key: The key to load the value for
    /// - Returns: The stored boolean value, or nil if not found
    func loadBool(key: String) throws -> Bool? {
        guard let stringValue = try load(key: key) else {
            return nil
        }
        return stringValue == "true"
    }

    // MARK: - Existence Check

    /// Checks if a value exists in the Keychain for the given key.
    /// - Parameter key: The key to check
    /// - Returns: True if a value exists
    func exists(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Batch Operations

    /// Deletes all values stored by this service.
    /// Use with caution - this cannot be undone.
    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain deleteAll failed: status \(status)")
            throw AppError.unknown("Keychain deleteAll failed: \(status)")
        }

        logger.info("Deleted all values from Keychain")
    }
}

// MARK: - Keychain Keys

/// Keys for security-sensitive settings stored in Keychain.
/// Keep all Keychain key definitions here for discoverability.
extension KeychainService {

    /// Keys for cloud analysis settings
    enum CloudKeys {
        /// Whether user has consented to cloud analysis
        static let cloudAnalysisEnabled = "security.cloudAnalysisEnabled"

        /// Whether high accuracy mode is enabled
        static let highAccuracyMode = "security.highAccuracyMode"

        /// Whether cloud vault backup is enabled
        static let cloudVaultEnabled = "security.cloudVaultEnabled"
    }

    /// Keys for authentication (Iteration 2)
    enum AuthKeys {
        /// User's authentication token
        static let authToken = "auth.token"

        /// User's refresh token
        static let refreshToken = "auth.refreshToken"
    }
}
