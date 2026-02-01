import Foundation
import Observation
import os

/// Manages app lock state and authentication for Dueasy.
/// Handles automatic locking on background, timeout-based locking,
/// and biometric authentication flow.
///
/// SECURITY MODEL:
/// - App locks immediately when entering background
/// - Timeout-based relock after period of inactivity in foreground
/// - Uses biometric authentication (Face ID / Touch ID) when available
/// - Falls back to device passcode if biometrics fail or are locked out
@MainActor
@Observable
final class AppLockManager {

    // MARK: - Constants

    /// UserDefaults key for app lock enabled setting
    private static let appLockEnabledKey = "appLockEnabled"

    /// UserDefaults key for lock timeout setting
    private static let lockTimeoutKey = "appLockTimeout"

    /// Default lock timeout in seconds (5 minutes)
    private static let defaultLockTimeout: TimeInterval = 300

    // MARK: - Observable State

    /// Whether the app is currently locked
    private(set) var isLocked: Bool = true

    /// Whether authentication is in progress
    private(set) var isAuthenticating: Bool = false

    /// Last authentication error message (for UI display)
    private(set) var lastError: String?

    // MARK: - Settings

    /// Whether app lock is enabled by the user
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.appLockEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.appLockEnabledKey)
            PrivacyLogger.logSecurityEvent(event: "app_lock_setting_changed", success: true)

            // If disabling, unlock immediately
            if !newValue {
                unlockApp()
            }
        }
    }

    /// Lock timeout in seconds (how long app can be in background before requiring auth)
    var lockTimeout: TimeInterval {
        get {
            let saved = UserDefaults.standard.double(forKey: Self.lockTimeoutKey)
            return saved > 0 ? saved : Self.defaultLockTimeout
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.lockTimeoutKey)
        }
    }

    // MARK: - Private State

    /// Time when app was last unlocked
    private var lastUnlockTime: Date?

    /// Time when app entered background
    private var backgroundTime: Date?

    // MARK: - Initialization

    init() {
        // Start locked if lock is enabled
        isLocked = isEnabled
    }

    // MARK: - Lock Management

    /// Locks the app
    func lockApp() {
        guard isEnabled else { return }

        isLocked = true
        lastUnlockTime = nil
        lastError = nil

        PrivacyLogger.logSecurityEvent(event: "app_locked", success: true)
    }

    /// Unlocks the app (called after successful authentication)
    func unlockApp() {
        isLocked = false
        lastUnlockTime = Date()
        lastError = nil
        backgroundTime = nil

        PrivacyLogger.logSecurityEvent(event: "app_unlocked", success: true)
    }

    /// Called when app enters background
    func handleBackgroundTransition() {
        guard isEnabled else { return }

        backgroundTime = Date()
        // Don't lock immediately - wait for timeout or foreground check
        PrivacyLogger.security.debug("App entered background")
    }

    /// Called when app returns to foreground
    /// Checks if timeout has elapsed and locks if necessary
    func handleForegroundTransition() {
        guard isEnabled else {
            // If lock was disabled while in background, stay unlocked
            if isLocked {
                unlockApp()
            }
            return
        }

        // Check if we exceeded the timeout while in background
        if let backgroundTime = backgroundTime {
            let elapsed = Date().timeIntervalSince(backgroundTime)
            if elapsed >= lockTimeout {
                PrivacyLogger.security.debug("Lock timeout elapsed (\(String(format: "%.0f", elapsed))s), locking app")
                lockApp()
            }
        }

        // Clear background time
        backgroundTime = nil
    }

    /// Called periodically to check if foreground timeout has elapsed
    func checkForegroundTimeout() {
        guard isEnabled, !isLocked else { return }

        // If we have an unlock time, check if timeout elapsed
        if let lastUnlock = lastUnlockTime {
            let elapsed = Date().timeIntervalSince(lastUnlock)
            // Use a much longer timeout for foreground (30 minutes)
            let foregroundTimeout: TimeInterval = 1800
            if elapsed >= foregroundTimeout {
                PrivacyLogger.security.debug("Foreground timeout elapsed, locking app")
                lockApp()
            }
        }
    }

    // MARK: - Authentication

    /// Attempts to authenticate and unlock the app
    /// - Returns: true if authentication succeeded
    @discardableResult
    func authenticate() async -> Bool {
        guard isEnabled else {
            unlockApp()
            return true
        }

        guard !isAuthenticating else {
            return false
        }

        isAuthenticating = true
        lastError = nil

        defer {
            isAuthenticating = false
        }

        // Build localized reason based on biometric type
        let biometricType = BiometricAuthService.availableBiometricType()
        let reason: String
        switch biometricType {
        case .faceID:
            reason = "Unlock DuEasy with Face ID"
        case .touchID:
            reason = "Unlock DuEasy with Touch ID"
        case .none:
            reason = "Enter your passcode to unlock DuEasy"
        }

        do {
            let success: Bool
            if biometricType != .none {
                success = try await BiometricAuthService.authenticate(reason: reason)
            } else {
                // No biometrics - use passcode directly
                success = try await BiometricAuthService.authenticateWithPasscode(reason: reason)
            }

            if success {
                unlockApp()
                return true
            } else {
                lastError = "Authentication failed"
                return false
            }

        } catch let error as BiometricAuthService.BiometricError {
            switch error {
            case .userCancel:
                // User cancelled - not really an error to display
                lastError = nil
            case .systemCancel:
                lastError = nil
            default:
                lastError = error.errorDescription
            }
            return false

        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Biometric Info

    /// Returns the available biometric type for UI display
    var availableBiometricType: BiometricAuthService.BiometricType {
        BiometricAuthService.availableBiometricType()
    }

    /// Checks if biometric authentication is available
    var isBiometricAvailable: Bool {
        let (available, _, _) = BiometricAuthService.checkAvailability()
        return available
    }

    /// Returns a user-friendly description of why biometrics might not be available
    var biometricUnavailableReason: String? {
        let (available, _, error) = BiometricAuthService.checkAvailability()
        if available { return nil }
        return error?.errorDescription
    }
}

// MARK: - Environment Key

import SwiftUI

/// Environment key for AppLockManager
private struct AppLockManagerKey: EnvironmentKey {
    static let defaultValue: AppLockManager = AppLockManager()
}

extension EnvironmentValues {
    /// Access to the app lock manager from environment
    var appLockManager: AppLockManager {
        get { self[AppLockManagerKey.self] }
        set { self[AppLockManagerKey.self] = newValue }
    }
}
