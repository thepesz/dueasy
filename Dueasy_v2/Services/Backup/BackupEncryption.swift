import Foundation
import CryptoKit
import os.log

/// Handles encryption and decryption of backup data using industry-standard cryptography.
///
/// Security Properties:
/// - Key Derivation: PBKDF2 with 100,000 iterations for strong password stretching
/// - Encryption: AES-256-GCM for authenticated encryption
/// - Salt: 32-byte random salt per backup (prevents rainbow table attacks)
/// - Nonce: 12-byte random nonce per encryption (ensures unique ciphertext)
/// - Authentication: GCM provides built-in integrity verification
///
/// All operations are synchronous and CPU-bound. For large backups,
/// consider calling from a background queue.
struct BackupEncryption: Sendable {

    private static let logger = Logger(subsystem: "com.dueasy.app", category: "BackupEncryption")

    // MARK: - Constants

    /// Number of PBKDF2 iterations for key derivation.
    /// 100,000 provides good security while remaining usable on mobile devices.
    /// Apple recommends at least 10,000 for sensitive data.
    private static let pbkdf2Iterations = 100_000

    /// Salt size in bytes (256 bits)
    private static let saltSize = 32

    /// AES-GCM nonce size in bytes (96 bits, standard for GCM)
    private static let nonceSize = 12

    /// Minimum password length for backup encryption
    static let minimumPasswordLength = 8

    // MARK: - Public Interface

    /// Encrypts backup data using a password.
    ///
    /// Process:
    /// 1. Generate random salt and nonce
    /// 2. Derive AES-256 key from password using PBKDF2
    /// 3. Encrypt data using AES-GCM
    /// 4. Package salt, nonce, and ciphertext into container
    ///
    /// - Parameters:
    ///   - data: The plaintext data to encrypt
    ///   - password: User-provided password (minimum 8 characters)
    /// - Returns: Encrypted container with all data needed for decryption
    /// - Throws: BackupError if encryption fails
    static func encrypt(data: Data, password: String) throws -> Data {
        // Validate password strength
        guard password.count >= minimumPasswordLength else {
            logger.warning("Password too short: \(password.count) characters")
            throw BackupError.passwordTooWeak
        }

        // Generate cryptographically secure random salt
        var saltBytes = [UInt8](repeating: 0, count: saltSize)
        let saltStatus = SecRandomCopyBytes(kSecRandomDefault, saltSize, &saltBytes)
        guard saltStatus == errSecSuccess else {
            logger.error("Failed to generate random salt: \(saltStatus)")
            throw BackupError.encryptionFailed("Failed to generate random salt")
        }
        let salt = Data(saltBytes)

        // Derive encryption key from password
        let key = try deriveKey(from: password, salt: salt)

        // Generate random nonce for AES-GCM
        let nonce = try generateNonce()

        // Encrypt data
        let ciphertext = try encryptData(data, with: key, nonce: nonce)

        // Package into container
        let container = EncryptedBackupContainer(
            salt: salt,
            nonce: nonce,
            ciphertext: ciphertext
        )

        // Encode container to JSON
        let encoder = JSONEncoder()
        let containerData = try encoder.encode(container)

        // Prepend magic bytes for file identification
        var result = Data(EncryptedBackupContainer.magicBytes)
        result.append(containerData)

        logger.info("Encrypted \(data.count) bytes of backup data")
        return result
    }

    /// Decrypts backup data using a password.
    ///
    /// Process:
    /// 1. Verify magic bytes
    /// 2. Parse container to extract salt, nonce, ciphertext
    /// 3. Derive key from password using stored salt
    /// 4. Decrypt and authenticate using AES-GCM
    ///
    /// - Parameters:
    ///   - data: The encrypted container data
    ///   - password: User-provided password
    /// - Returns: Decrypted plaintext data
    /// - Throws: BackupError if decryption fails (wrong password, corrupted data, etc.)
    static func decrypt(data: Data, password: String) throws -> Data {
        let magicBytes = Data(EncryptedBackupContainer.magicBytes)

        // Verify magic bytes
        guard data.count > magicBytes.count else {
            logger.warning("Data too short to contain magic bytes")
            throw BackupError.invalidBackupFormat
        }

        let fileMagic = data.prefix(magicBytes.count)
        guard fileMagic == magicBytes else {
            logger.warning("Invalid magic bytes - not a DuEasy backup file")
            throw BackupError.invalidBackupFormat
        }

        // Extract container JSON
        let containerData = data.dropFirst(magicBytes.count)

        // Parse container
        let decoder = JSONDecoder()
        let container: EncryptedBackupContainer
        do {
            container = try decoder.decode(EncryptedBackupContainer.self, from: containerData)
        } catch {
            logger.error("Failed to parse backup container: \(error.localizedDescription)")
            throw BackupError.invalidBackupFormat
        }

        // Verify container version
        guard container.containerVersion <= EncryptedBackupContainer.currentContainerVersion else {
            logger.warning("Container version \(container.containerVersion) is newer than supported \(EncryptedBackupContainer.currentContainerVersion)")
            throw BackupError.versionMismatch(
                expected: "\(EncryptedBackupContainer.currentContainerVersion)",
                found: "\(container.containerVersion)"
            )
        }

        // Validate salt and nonce sizes
        guard container.salt.count == saltSize else {
            logger.error("Invalid salt size: \(container.salt.count) (expected \(saltSize))")
            throw BackupError.invalidSalt
        }

        guard container.nonce.count == nonceSize else {
            logger.error("Invalid nonce size: \(container.nonce.count) (expected \(nonceSize))")
            throw BackupError.invalidNonce
        }

        // Derive key using stored salt
        let key = try deriveKey(from: password, salt: container.salt)

        // Decrypt data
        let plaintext = try decryptData(container.ciphertext, with: key, nonce: container.nonce)

        logger.info("Decrypted \(plaintext.count) bytes of backup data")
        return plaintext
    }

    /// Validates password meets minimum requirements.
    /// - Parameter password: Password to validate
    /// - Returns: true if password meets requirements
    static func isPasswordValid(_ password: String) -> Bool {
        password.count >= minimumPasswordLength
    }

    // MARK: - Private Methods

    /// Derives an AES-256 key from a password using PBKDF2.
    ///
    /// Uses SHA-256 as the PRF (Pseudo-Random Function) for PBKDF2.
    /// Produces a 256-bit (32-byte) key suitable for AES-256.
    private static func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw BackupError.encryptionFailed("Failed to encode password")
        }

        // Use CommonCrypto's PBKDF2 implementation via CryptoKit
        // CryptoKit doesn't have direct PBKDF2, so we use the password-based key derivation
        let derivedKey = try passwordData.withUnsafeBytes { passwordBytes -> SymmetricKey in
            try salt.withUnsafeBytes { saltBytes -> SymmetricKey in
                var derivedKeyData = Data(count: 32) // 256 bits for AES-256

                let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(pbkdf2Iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }

                guard result == kCCSuccess else {
                    throw BackupError.encryptionFailed("PBKDF2 key derivation failed with status \(result)")
                }

                return SymmetricKey(data: derivedKeyData)
            }
        }

        return derivedKey
    }

    /// Generates a cryptographically secure random nonce for AES-GCM.
    private static func generateNonce() throws -> Data {
        var nonceBytes = [UInt8](repeating: 0, count: nonceSize)
        let status = SecRandomCopyBytes(kSecRandomDefault, nonceSize, &nonceBytes)
        guard status == errSecSuccess else {
            throw BackupError.encryptionFailed("Failed to generate random nonce")
        }
        return Data(nonceBytes)
    }

    /// Encrypts data using AES-256-GCM.
    private static func encryptData(_ data: Data, with key: SymmetricKey, nonce: Data) throws -> Data {
        do {
            let gcmNonce = try AES.GCM.Nonce(data: nonce)
            let sealedBox = try AES.GCM.seal(data, using: key, nonce: gcmNonce)

            // Combined format includes ciphertext + authentication tag
            guard let combined = sealedBox.combined else {
                throw BackupError.encryptionFailed("Failed to create sealed box")
            }

            return combined
        } catch let error as BackupError {
            throw error
        } catch {
            logger.error("AES-GCM encryption failed: \(error.localizedDescription)")
            throw BackupError.encryptionFailed(error.localizedDescription)
        }
    }

    /// Decrypts data using AES-256-GCM.
    private static func decryptData(_ ciphertext: Data, with key: SymmetricKey, nonce: Data) throws -> Data {
        do {
            // The nonce is embedded in the combined format of the sealed box,
            // so we don't need to use the separate nonce parameter.
            // It's kept for API consistency and potential future validation.
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)

            let plaintext = try AES.GCM.open(sealedBox, using: key)
            return plaintext
        } catch CryptoKitError.authenticationFailure {
            // This is the most likely error for wrong password
            logger.warning("Authentication failed - likely wrong password")
            throw BackupError.decryptionFailed("Wrong password or corrupted data")
        } catch {
            logger.error("AES-GCM decryption failed: \(error.localizedDescription)")
            throw BackupError.decryptionFailed(error.localizedDescription)
        }
    }
}

// MARK: - CommonCrypto Import

import CommonCrypto
