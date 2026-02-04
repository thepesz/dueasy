import Foundation
import Observation
import os

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

/// Bootstraps Firebase authentication on app launch.
/// Guarantees a Firebase user exists (anonymous or linked) before any extraction requests.
///
/// ## User Flow
/// 1. **First launch** - Create Firebase anonymous user automatically
/// 2. **Onboarding** - Offer "Continue with Apple" or "Skip"
/// 3. **Apple Sign In** - Link Apple credential to existing anonymous user (preserves usage counters)
/// 4. **Linked account** - Enables CloudKit sync and cross-device experience
///
/// ## Integration Points
/// - Call `bootstrap()` from `DueasyApp.init()` or `AppEnvironment.init()` - earliest safe point
/// - Call before any cloud extraction requests
///
/// ## Security
/// - Anonymous users have limited backend access (usage counters)
/// - Apple-linked users get full CloudKit sync capabilities
@MainActor
@Observable
final class AuthBootstrapper {

    // MARK: - Published State

    /// Whether a Firebase user exists (anonymous or linked)
    private(set) var isSignedIn: Bool = false

    /// Whether the current user has linked their Apple account
    private(set) var isAppleLinked: Bool = false

    /// Current Firebase user ID (nil if not signed in)
    private(set) var currentUserId: String?

    /// Current user email (nil if anonymous or not provided)
    private(set) var currentUserEmail: String?

    /// Whether bootstrap has completed (success or failure)
    private(set) var hasBootstrapped: Bool = false

    /// Last bootstrap error (nil if successful)
    private(set) var bootstrapError: Error?

    // MARK: - Dependencies

    private let authService: AuthServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "AuthBootstrap")

    #if canImport(FirebaseAuth)
    /// Auth state listener handle for cleanup
    /// Using nonisolated(unsafe) to allow access from deinit
    nonisolated(unsafe) private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    #endif

    // MARK: - Initialization

    init(authService: AuthServiceProtocol) {
        self.authService = authService
        setupAuthStateListener()
    }

    deinit {
        #if canImport(FirebaseAuth)
        if let handle = authStateListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        #endif
    }

    // MARK: - Auth State Listener

    /// Sets up a listener for auth state changes.
    /// Automatically updates state when user signs in/out externally.
    private func setupAuthStateListener() {
        #if canImport(FirebaseAuth)
        authStateListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let user = user {
                    self.updateState(user: user)
                    self.logger.debug("Auth state changed: user signed in")
                } else {
                    self.isSignedIn = false
                    self.isAppleLinked = false
                    self.currentUserId = nil
                    self.currentUserEmail = nil
                    self.logger.debug("Auth state changed: user signed out")
                }
            }
        }
        #endif
    }

    // MARK: - Bootstrap

    /// Bootstraps authentication on app launch.
    /// Ensures a Firebase user exists (creates anonymous if needed).
    ///
    /// This method is idempotent - safe to call multiple times.
    /// Should be called at the earliest safe point in app lifecycle.
    func bootstrap() async {
        guard !hasBootstrapped else {
            logger.debug("Auth already bootstrapped, skipping")
            return
        }

        logger.info("Starting auth bootstrap...")

        #if canImport(FirebaseAuth)
        // Check if user already exists
        if let user = Auth.auth().currentUser {
            logger.info("Existing user found")
            updateState(user: user)
            hasBootstrapped = true
            return
        }

        // No existing user - create anonymous user
        do {
            logger.info("No existing user, creating anonymous user...")
            let result = try await Auth.auth().signInAnonymously()
            updateState(user: result.user)
            logger.info("Anonymous user created successfully")
            hasBootstrapped = true
        } catch {
            logger.error("Failed to create anonymous user: \(error.localizedDescription)")
            bootstrapError = error
            hasBootstrapped = true
            // Don't block app - user can still use local features
        }
        #else
        // Firebase SDK not available - mark as bootstrapped without auth
        logger.warning("Firebase SDK not available, skipping auth bootstrap")
        hasBootstrapped = true
        #endif
    }

    // MARK: - State Updates

    #if canImport(FirebaseAuth)
    /// Updates observable state from Firebase user.
    /// Called after sign in, link, or on existing user detection.
    private func updateState(user: User) {
        isSignedIn = true
        currentUserId = user.uid
        currentUserEmail = user.email

        // Check if Apple is linked
        isAppleLinked = user.providerData.contains { provider in
            provider.providerID == "apple.com"
        }

        // Privacy-safe logging
        logger.info("Auth state updated - isAppleLinked: \(self.isAppleLinked)")
    }
    #endif

    /// Refreshes auth state from current Firebase user.
    /// Call after linking Apple account or signing out.
    func refreshState() async {
        #if canImport(FirebaseAuth)
        if let user = Auth.auth().currentUser {
            updateState(user: user)
        } else {
            isSignedIn = false
            isAppleLinked = false
            currentUserId = nil
            currentUserEmail = nil
        }
        #endif
    }

    // MARK: - Sign Out

    /// Signs out the current user.
    /// After sign out, call `bootstrap()` to create a new anonymous user if needed.
    func signOut() async throws {
        try await authService.signOut()

        // Reset state
        isSignedIn = false
        isAppleLinked = false
        currentUserId = nil
        currentUserEmail = nil

        logger.info("User signed out")
    }
}

// MARK: - Convenience Extension

extension AuthBootstrapper {
    /// Whether the user can access cloud sync features.
    /// Requires Apple account to be linked for full sync capabilities.
    var canSyncToCloud: Bool {
        isSignedIn && isAppleLinked
    }

    /// Whether the user is in anonymous-only mode.
    /// Anonymous users can still use cloud extraction within limits.
    var isAnonymous: Bool {
        isSignedIn && !isAppleLinked
    }

    /// Display name for the current user.
    /// Returns email if available, otherwise "Guest".
    var displayName: String {
        if let email = currentUserEmail {
            return email
        }
        return isSignedIn ? "Guest" : "Not signed in"
    }
}
