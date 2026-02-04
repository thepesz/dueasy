import Foundation

/// Authentication service for backend access.
/// Provides user identity and tokens for API calls.
///
/// Iteration 1: No-op implementation (free tier, no auth).
/// Iteration 2: Firebase Authentication with Sign in with Apple.
///
/// Security requirements:
/// - Tokens must be refreshed before expiry
/// - Secure storage of credentials (Keychain)
/// - Support for biometric authentication unlock
protocol AuthServiceProtocol: Sendable {

    /// Current authentication state.
    /// Returns true if user has a valid session.
    var isSignedIn: Bool { get async }

    /// Current user ID (nil if not signed in).
    /// This is a stable, unique identifier for the user.
    var currentUserId: String? { get async }

    /// Current user email (nil if not signed in or not provided).
    var currentUserEmail: String? { get async }

    /// Get authentication token for API calls.
    /// - Parameter forceRefresh: Force token refresh even if not expired
    /// - Returns: Valid ID token for backend authentication
    /// - Throws: `AuthError` if not signed in or refresh fails
    func getIDToken(forceRefresh: Bool) async throws -> String

    /// Sign in anonymously (for testing and free tier).
    /// Creates an anonymous Firebase user session.
    /// - Throws: `AuthError` on failure
    func signInAnonymously() async throws

    /// Sign in with Apple.
    /// Initiates the Apple sign-in flow and creates/links Firebase user.
    /// - Throws: `AuthError` on failure
    func signInWithApple() async throws

    /// Link Apple credential to existing anonymous user.
    /// Preserves the existing user ID and usage counters.
    /// - Throws: `AuthError.credentialAlreadyLinked` if Apple account is already linked to another user
    /// - Throws: `AuthError.notSignedIn` if no user is currently signed in
    /// - Throws: `AuthError` on other failures
    func linkAppleCredential() async throws

    /// Sign out current user.
    /// Clears local credentials and Firebase session.
    /// - Throws: `AuthError` on failure
    func signOut() async throws

    /// Delete user account and all associated data.
    /// Requires recent authentication - may throw `AuthError.reauthenticationRequired`.
    /// - Throws: `AuthError` on failure
    func deleteAccount() async throws

    /// Listen for authentication state changes.
    /// Returns an async stream that emits when auth state changes.
    /// - Returns: Stream of (isSignedIn, userId) tuples
    func authStateChanges() -> AsyncStream<(isSignedIn: Bool, userId: String?)>
}

// MARK: - Authentication Errors

/// Errors specific to authentication operations.
enum AuthError: LocalizedError, Equatable {
    case notSignedIn
    case tokenExpired
    case tokenRefreshFailed
    case invalidCredentials
    case accountDisabled
    case accountNotFound
    case emailAlreadyInUse
    case reauthenticationRequired
    case appleSignInCancelled
    case appleSignInFailed(String)
    case credentialAlreadyLinked
    case networkError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in"
        case .tokenExpired:
            return "Session expired. Please sign in again."
        case .tokenRefreshFailed:
            return "Failed to refresh session. Please sign in again."
        case .invalidCredentials:
            return "Invalid credentials"
        case .accountDisabled:
            return "Account has been disabled"
        case .accountNotFound:
            return "Account not found"
        case .emailAlreadyInUse:
            return "Email is already in use by another account"
        case .reauthenticationRequired:
            return "Please sign in again to continue"
        case .appleSignInCancelled:
            return "Sign in was cancelled"
        case .appleSignInFailed(let reason):
            return "Apple Sign In failed: \(reason)"
        case .credentialAlreadyLinked:
            return "This Apple account is already linked to another user"
        case .networkError(let message):
            return "Network error: \(message)"
        case .unknown(let message):
            return "Authentication error: \(message)"
        }
    }

    /// Whether the error requires user action to resolve
    var requiresUserAction: Bool {
        switch self {
        case .notSignedIn, .tokenExpired, .tokenRefreshFailed, .reauthenticationRequired:
            return true
        case .accountDisabled, .accountNotFound:
            return true
        default:
            return false
        }
    }

    static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}
