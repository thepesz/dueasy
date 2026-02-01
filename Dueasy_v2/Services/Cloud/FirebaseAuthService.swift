import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

// Import domain protocols
import SwiftData

/// Firebase-based authentication service for Pro tier
@MainActor
final class FirebaseAuthService: AuthServiceProtocol {

    // MARK: - AuthServiceProtocol

    var isSignedIn: Bool {
        get async {
            #if canImport(FirebaseAuth)
            return Auth.auth().currentUser != nil
            #else
            return false
            #endif
        }
    }

    var currentUserId: String? {
        get async {
            #if canImport(FirebaseAuth)
            return Auth.auth().currentUser?.uid
            #else
            return nil
            #endif
        }
    }

    var currentUserEmail: String? {
        get async {
            #if canImport(FirebaseAuth)
            return Auth.auth().currentUser?.email
            #else
            return nil
            #endif
        }
    }

    func getIDToken(forceRefresh: Bool) async throws -> String {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notSignedIn
        }
        return try await user.getIDToken(forcingRefresh: forceRefresh)
        #else
        throw AppError.featureUnavailable("Firebase SDK not available")
        #endif
    }

    func signInWithApple() async throws {
        #if canImport(FirebaseAuth)
        // Implementation would use Sign in with Apple flow + Firebase Auth
        // For now, throw not implemented
        throw AppError.featureUnavailable("Sign in with Apple not yet implemented")
        #else
        throw AppError.featureUnavailable("Firebase SDK not available")
        #endif
    }

    func signOut() async throws {
        #if canImport(FirebaseAuth)
        try Auth.auth().signOut()
        #else
        throw AppError.featureUnavailable("Firebase SDK not available")
        #endif
    }

    func deleteAccount() async throws {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notSignedIn
        }
        try await user.delete()
        #else
        throw AppError.featureUnavailable("Firebase SDK not available")
        #endif
    }

    func authStateChanges() -> AsyncStream<(isSignedIn: Bool, userId: String?)> {
        #if canImport(FirebaseAuth)
        return AsyncStream { continuation in
            let handle = Auth.auth().addStateDidChangeListener { _, user in
                continuation.yield((isSignedIn: user != nil, userId: user?.uid))
            }

            continuation.onTermination = { @Sendable _ in
                Auth.auth().removeStateDidChangeListener(handle)
            }
        }
        #else
        return AsyncStream { continuation in
            continuation.yield((isSignedIn: false, userId: nil))
            continuation.finish()
        }
        #endif
    }
}
