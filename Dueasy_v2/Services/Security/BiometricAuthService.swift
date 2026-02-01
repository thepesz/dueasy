import LocalAuthentication
import Foundation
import os

/// Service for biometric authentication (Face ID / Touch ID).
/// Provides device capability detection and authentication execution.
///
/// SECURITY NOTES:
/// - Uses LocalAuthentication framework which is hardware-backed
/// - Biometric data never leaves the device (Secure Enclave)
/// - Falls back to device passcode if biometrics fail
enum BiometricAuthService {

    // MARK: - Types

    /// Available biometric authentication types
    enum BiometricType: String, Sendable {
        case faceID = "Face ID"
        case touchID = "Touch ID"
        case none = "None"

        /// SF Symbol name for this biometric type
        var iconName: String {
            switch self {
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            case .none: return "lock"
            }
        }
    }

    /// Errors that can occur during biometric authentication
    enum BiometricError: LocalizedError, Sendable {
        case notAvailable
        case notEnrolled
        case lockout
        case userCancel
        case systemCancel
        case failed(String)
        case passcodeNotSet

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Biometric authentication is not available on this device"
            case .notEnrolled:
                return "No biometric data is enrolled. Please set up Face ID or Touch ID in Settings."
            case .lockout:
                return "Biometric authentication is locked due to too many failed attempts. Please try again later."
            case .userCancel:
                return "Authentication was cancelled"
            case .systemCancel:
                return "Authentication was interrupted by the system"
            case .failed(let reason):
                return "Authentication failed: \(reason)"
            case .passcodeNotSet:
                return "Device passcode is not set. Please set a passcode in Settings."
            }
        }
    }

    // MARK: - Device Capability

    /// Returns the available biometric type on this device
    /// - Returns: BiometricType indicating Face ID, Touch ID, or none
    static func availableBiometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            // Vision Pro - treat as Face ID equivalent
            return .faceID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }

    /// Checks if biometric authentication is available and enrolled
    /// - Returns: Tuple of (isAvailable, biometricType, errorMessage)
    static func checkAvailability() -> (available: Bool, type: BiometricType, error: BiometricError?) {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let laError = error as? LAError {
                switch laError.code {
                case .biometryNotAvailable:
                    return (false, .none, .notAvailable)
                case .biometryNotEnrolled:
                    let type = BiometricType(from: context.biometryType)
                    return (false, type, .notEnrolled)
                case .biometryLockout:
                    let type = BiometricType(from: context.biometryType)
                    return (false, type, .lockout)
                case .passcodeNotSet:
                    return (false, .none, .passcodeNotSet)
                default:
                    return (false, .none, .notAvailable)
                }
            }
            return (false, .none, .notAvailable)
        }

        let type = BiometricType(from: context.biometryType)
        return (true, type, nil)
    }

    // MARK: - Authentication

    /// Authenticates the user using biometrics
    /// - Parameter reason: Localized reason string shown to user
    /// - Returns: true if authentication succeeded
    /// - Throws: BiometricError if authentication fails
    static func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "" // Hide fallback button (use default passcode)

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            PrivacyLogger.logSecurityEvent(event: "biometric_auth", success: success)
            return success

        } catch let error as LAError {
            PrivacyLogger.logSecurityEvent(event: "biometric_auth", success: false)

            switch error.code {
            case .userCancel:
                throw BiometricError.userCancel
            case .userFallback:
                // User chose to use passcode - let them try again
                return try await authenticateWithPasscode(reason: reason)
            case .systemCancel:
                throw BiometricError.systemCancel
            case .biometryNotAvailable:
                throw BiometricError.notAvailable
            case .biometryNotEnrolled:
                throw BiometricError.notEnrolled
            case .biometryLockout:
                // When locked out, offer passcode as alternative
                return try await authenticateWithPasscode(reason: reason)
            case .passcodeNotSet:
                throw BiometricError.passcodeNotSet
            case .authenticationFailed:
                throw BiometricError.failed("Biometric did not match")
            default:
                throw BiometricError.failed(error.localizedDescription)
            }
        } catch {
            PrivacyLogger.logSecurityEvent(event: "biometric_auth", success: false)
            throw BiometricError.failed(error.localizedDescription)
        }
    }

    /// Authenticates using device passcode (fallback when biometrics locked out)
    /// - Parameter reason: Localized reason string
    /// - Returns: true if authentication succeeded
    static func authenticateWithPasscode(reason: String) async throws -> Bool {
        let context = LAContext()

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, // Includes passcode fallback
                localizedReason: reason
            )

            PrivacyLogger.logSecurityEvent(event: "passcode_auth", success: success)
            return success

        } catch let error as LAError {
            PrivacyLogger.logSecurityEvent(event: "passcode_auth", success: false)

            switch error.code {
            case .userCancel:
                throw BiometricError.userCancel
            case .systemCancel:
                throw BiometricError.systemCancel
            case .passcodeNotSet:
                throw BiometricError.passcodeNotSet
            default:
                throw BiometricError.failed(error.localizedDescription)
            }
        } catch {
            PrivacyLogger.logSecurityEvent(event: "passcode_auth", success: false)
            throw BiometricError.failed(error.localizedDescription)
        }
    }
}

// MARK: - BiometricType Extension

private extension BiometricAuthService.BiometricType {
    init(from biometryType: LABiometryType) {
        switch biometryType {
        case .faceID:
            self = .faceID
        case .touchID:
            self = .touchID
        case .opticID:
            self = .faceID // Treat Vision Pro as Face ID equivalent
        case .none:
            self = .none
        @unknown default:
            self = .none
        }
    }
}
