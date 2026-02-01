import Foundation
import os

/// No-op authentication service for free tier.
/// Returns unauthenticated state for all operations.
///
/// Used when:
/// - User is on free tier
/// - Testing without Firebase
/// - Offline mode
///
/// In Iteration 2, replace with FirebaseAuthService for Pro tier.
final class NoOpAuthService: AuthServiceProtocol {

    // MARK: - Properties

    var isSignedIn: Bool {
        get async { false }
    }

    var currentUserId: String? {
        get async { nil }
    }

    var currentUserEmail: String? {
        get async { nil }
    }

    // MARK: - Methods

    func getIDToken(forceRefresh: Bool) async throws -> String {
        PrivacyLogger.security.debug("NoOpAuthService: getIDToken called - not signed in")
        throw AuthError.notSignedIn
    }

    func signInWithApple() async throws {
        PrivacyLogger.security.debug("NoOpAuthService: signInWithApple called - not available in free tier")
        throw AuthError.notSignedIn
    }

    func signOut() async throws {
        // No-op - nothing to sign out
        PrivacyLogger.security.debug("NoOpAuthService: signOut called - no session to clear")
    }

    func deleteAccount() async throws {
        PrivacyLogger.security.debug("NoOpAuthService: deleteAccount called - no account exists")
        throw AuthError.notSignedIn
    }

    func authStateChanges() -> AsyncStream<(isSignedIn: Bool, userId: String?)> {
        // Return a stream that immediately completes with not signed in
        AsyncStream { continuation in
            continuation.yield((isSignedIn: false, userId: nil))
            // Keep stream open but never emit again (no auth changes in no-op)
        }
    }
}
