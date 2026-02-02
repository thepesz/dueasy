import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// Configures Firebase for the application.
/// Handles Firebase initialization and lifecycle.
@MainActor
final class FirebaseConfigurator {

    // MARK: - Singleton

    static let shared = FirebaseConfigurator()

    private init() {}

    // MARK: - Configuration

    /// Configure Firebase on app launch.
    /// Must be called before any Firebase services are used.
    /// - Parameter tier: Application tier to determine if Firebase is needed
    func configure(for tier: AppTier) {
        #if canImport(FirebaseCore)
        guard tier == .pro else {
            // Firebase not needed for free tier
            return
        }

        // Check if GoogleService-Info.plist exists
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            #if DEBUG
            print("Firebase: GoogleService-Info.plist not found. Firebase will not be initialized.")
            print("   To enable Firebase:")
            print("   1. Create a Firebase project at https://console.firebase.google.com")
            print("   2. Add an iOS app to your project")
            print("   3. Download GoogleService-Info.plist")
            print("   4. Add it to your Xcode project")
            #endif
            return
        }

        // Configure Firebase
        FirebaseApp.configure()
        #if DEBUG
        print("Firebase configured successfully")
        #endif

        // Optional: Configure Firebase settings
        #if DEBUG
        // Development settings (if needed)
        // e.g., enable emulators, debug logging, etc.
        #endif

        #else
        // Firebase SDK not available
        #if DEBUG
        if tier == .pro {
            print("Firebase: SDK not available. Add Firebase packages to enable Pro features.")
            print("   To add Firebase SDK:")
            print("   1. In Xcode, go to File > Add Package Dependencies")
            print("   2. Add https://github.com/firebase/firebase-ios-sdk")
            print("   3. Select: FirebaseAuth, FirebaseFunctions")
        }
        #endif
        #endif
    }

    /// Check if Firebase is properly configured
    var isConfigured: Bool {
        #if canImport(FirebaseCore)
        return FirebaseApp.app() != nil
        #else
        return false
        #endif
    }
}
