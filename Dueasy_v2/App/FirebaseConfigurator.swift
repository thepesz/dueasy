import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

/// Configures Firebase for the application.
/// Handles Firebase initialization and lifecycle.
///
/// ## Crashlytics
///
/// Crashlytics is automatically enabled to help identify and fix app crashes.
/// Crash reports include device info and stack traces but NO personal data
/// from your documents or invoices.
@MainActor
final class FirebaseConfigurator {

    // MARK: - Singleton

    static let shared = FirebaseConfigurator()

    private init() {}

    // MARK: - Configuration

    /// Configure Firebase on app launch.
    /// Must be called before any Firebase services are used.
    ///
    /// Firebase is required for BOTH free and pro tiers:
    /// - Free tier: Anonymous auth + 3 cloud extractions/month
    /// - Pro tier: Apple auth + unlimited cloud extractions
    func configure() {
        #if canImport(FirebaseCore)
        // Firebase is required for ALL tiers (free and pro)
        // Free tier uses anonymous auth, Pro tier uses Apple Sign In
        // Backend enforces monthly limits (3 for free, 100 for pro)

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

        #if canImport(FirebaseCrashlytics)
        // Configure Crashlytics for crash reporting
        // Note: Requires "Run Script" build phase for proper symbol upload
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

        #if DEBUG
        print("Firebase Crashlytics enabled")
        #endif
        #endif

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
        print("Firebase: SDK not available. Add Firebase packages to enable cloud extraction.")
        print("   To add Firebase SDK:")
        print("   1. In Xcode, go to File > Add Package Dependencies")
        print("   2. Add https://github.com/firebase/firebase-ios-sdk")
        print("   3. Select: FirebaseAuth, FirebaseFunctions, FirebaseCrashlytics")
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
