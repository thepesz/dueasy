import Foundation
import AuthenticationServices
import CryptoKit
import os

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

// Import domain protocols
import SwiftData

/// Firebase-based authentication service for Pro tier.
/// Supports anonymous sign-in and Sign in with Apple with account linking.
///
/// ## User Flow
/// 1. Anonymous user created on first launch (via AuthBootstrapper)
/// 2. User can link Apple credential to preserve usage counters
/// 3. Linked users get CloudKit sync and cross-device experience
///
/// ## Security
/// - Uses secure nonce for Apple Sign In
/// - Credentials stored securely by Firebase SDK
/// - Supports token refresh for API calls
@MainActor
final class FirebaseAuthService: NSObject, AuthServiceProtocol {

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.dueasy.app", category: "FirebaseAuth")

    /// Current nonce for Sign in with Apple (used for replay protection)
    private var currentNonce: String?

    /// Continuation for async Sign in with Apple flow
    private var appleSignInContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

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

    func signInAnonymously() async throws {
        #if canImport(FirebaseAuth)
        _ = try await Auth.auth().signInAnonymously()
        logger.info("Signed in anonymously")
        #else
        throw AppError.featureUnavailable("Firebase SDK not available")
        #endif
    }

    func signInWithApple() async throws {
        #if canImport(FirebaseAuth)
        // Get Apple credential
        let appleCredential = try await getAppleCredential()

        // Convert to Firebase credential
        guard let idTokenString = String(data: appleCredential.identityToken ?? Data(), encoding: .utf8) else {
            throw AuthError.appleSignInFailed("Unable to fetch identity token")
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: currentNonce,
            fullName: appleCredential.fullName
        )

        // Sign in with Firebase
        _ = try await Auth.auth().signIn(with: firebaseCredential)
        logger.info("Signed in with Apple")
        #else
        throw AppError.featureUnavailable("Firebase SDK not available")
        #endif
    }

    func linkAppleCredential() async throws {
        #if canImport(FirebaseAuth)
        guard let currentUser = Auth.auth().currentUser else {
            logger.error("linkAppleCredential called but no user is signed in")
            throw AuthError.notSignedIn
        }

        // Check if already linked
        let isAlreadyLinked = currentUser.providerData.contains { $0.providerID == "apple.com" }
        if isAlreadyLinked {
            logger.info("Apple credential already linked to this user")
            return
        }

        logger.info("Starting Apple credential linking for user: \(currentUser.uid, privacy: .private)")

        // Get Apple credential
        let appleCredential = try await getAppleCredential()

        // Convert to Firebase credential
        guard let idTokenString = String(data: appleCredential.identityToken ?? Data(), encoding: .utf8) else {
            throw AuthError.appleSignInFailed("Unable to fetch identity token")
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: currentNonce,
            fullName: appleCredential.fullName
        )

        // Link to existing user (preserves uid and usage counters)
        do {
            _ = try await currentUser.link(with: firebaseCredential)
            logger.info("Successfully linked Apple credential to existing user")
        } catch let error as NSError {
            // Check for credential already in use
            if error.domain == AuthErrorDomain {
                switch error.code {
                case AuthErrorCode.credentialAlreadyInUse.rawValue:
                    logger.warning("Apple account already linked to another Firebase user")
                    // Do NOT sign out the anonymous user here.
                    // The onboarding flow will offer the user a choice:
                    // 1. Sign in to existing account (via signInWithApple())
                    // 2. Continue as guest (keeps current anonymous session)
                    // Signing out prematurely would destroy the anonymous session
                    // and force a re-bootstrap, which is unnecessary if the user
                    // chooses to continue as guest.
                    throw AuthError.credentialAlreadyLinked
                case AuthErrorCode.providerAlreadyLinked.rawValue:
                    logger.info("Apple provider already linked (no action needed)")
                    return
                default:
                    logger.error("Firebase link error: \(error.localizedDescription)")
                    throw AuthError.appleSignInFailed(error.localizedDescription)
                }
            }
            throw AuthError.appleSignInFailed(error.localizedDescription)
        }
        #else
        throw AppError.featureUnavailable("Firebase SDK not available")
        #endif
    }

    func signOut() async throws {
        #if canImport(FirebaseAuth)
        try Auth.auth().signOut()
        logger.info("Signed out")
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
        logger.info("Account deleted")
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

    // MARK: - Sign in with Apple Flow

    /// Gets Apple ID credential using ASAuthorizationController.
    /// Uses secure nonce for replay attack protection.
    private func getAppleCredential() async throws -> ASAuthorizationAppleIDCredential {
        // Generate nonce for replay protection
        let nonce = randomNonceString()
        currentNonce = nonce

        // Create request
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        // Perform authorization
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.appleSignInContinuation = continuation
            authorizationController.performRequests()
        }
    }

    // MARK: - Nonce Generation

    /// Generates a random nonce string for Sign in with Apple.
    /// Used to prevent replay attacks.
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }

        return String(nonce)
    }

    /// Hashes the nonce using SHA256.
    /// Required for Sign in with Apple nonce verification.
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()

        return hashString
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension FirebaseAuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                logger.info("Apple Sign In completed successfully")
                appleSignInContinuation?.resume(returning: appleIDCredential)
                appleSignInContinuation = nil
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                logger.info("Apple Sign In cancelled by user")
                appleSignInContinuation?.resume(throwing: AuthError.appleSignInCancelled)
            } else {
                logger.error("Apple Sign In failed: \(error.localizedDescription)")
                appleSignInContinuation?.resume(throwing: AuthError.appleSignInFailed(error.localizedDescription))
            }
            appleSignInContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension FirebaseAuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Get the key window for presenting the Sign in with Apple sheet
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            // Fallback to first window
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first as? UIWindowScene
            return windowScene?.windows.first ?? UIWindow()
        }
        return window
    }
}
