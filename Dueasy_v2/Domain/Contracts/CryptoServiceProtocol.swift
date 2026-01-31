import Foundation

/// Protocol for encryption services.
/// Iteration 1: Wrapper around iOS Data Protection (file attributes).
/// Iteration 2: Optional CryptoKit encryption for client-side encryption before upload.
protocol CryptoServiceProtocol: Sendable {

    /// Encrypts data.
    /// Iteration 1: Returns data as-is (relies on iOS file protection).
    /// Iteration 2: Optional AES-GCM encryption.
    /// - Parameter data: Data to encrypt
    /// - Returns: Encrypted data (or original if using system protection)
    func encrypt(_ data: Data) async throws -> Data

    /// Decrypts data.
    /// Iteration 1: Returns data as-is.
    /// Iteration 2: Decrypts AES-GCM encrypted data.
    /// - Parameter data: Data to decrypt
    /// - Returns: Decrypted data
    func decrypt(_ data: Data) async throws -> Data

    /// Ensures a file has proper iOS Data Protection attributes.
    /// - Parameter url: File URL to protect
    func applyFileProtection(to url: URL) throws

    /// Whether encryption is currently enabled beyond system protection.
    var isEncryptionEnabled: Bool { get }

    /// The encryption method identifier.
    var encryptionMethod: String { get }
}

// MARK: - iOS Data Protection Implementation for Iteration 1

/// iOS Data Protection wrapper for Iteration 1.
/// Relies on iOS file protection attributes (NSFileProtectionComplete).
final class IOSDataProtectionCryptoService: CryptoServiceProtocol, @unchecked Sendable {

    var isEncryptionEnabled: Bool { false } // Using system protection only

    var encryptionMethod: String { "ios-data-protection" }

    func encrypt(_ data: Data) async throws -> Data {
        // Return as-is; iOS file protection handles encryption at rest
        data
    }

    func decrypt(_ data: Data) async throws -> Data {
        // Return as-is; iOS file protection handles decryption
        data
    }

    func applyFileProtection(to url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }
}
