import SwiftUI
import SwiftData
import os

#if canImport(RevenueCat)
import RevenueCat
#endif

/// Main entry point for DuEasy application.
/// Architecture: SwiftUI Views -> MVVM ViewModels -> Use Cases -> Protocol-based Services -> SwiftData
///
/// SECURITY FEATURES:
/// - App lock with Face ID / Touch ID authentication
/// - iOS Data Protection on all stored files
/// - Automatic lock on background transition
/// - SwiftData database encryption
@main
struct DuEasyApp: App {

    /// Shared app environment containing all dependencies
    @State private var appEnvironment: AppEnvironment

    /// App lock manager for biometric authentication
    @State private var appLockManager = AppLockManager()

    /// SwiftData model container
    private let modelContainer: ModelContainer

    /// Track language changes to force view updates
    @AppStorage("appLanguage") private var appLanguage: String = "pl"

    /// Track scene phase for app lock management
    @Environment(\.scenePhase) private var scenePhase

    /// Check if running in UI test mode
    private static var isUITestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestMode")
    }

    /// Check if database should be reset (UI tests)
    private static var shouldResetDatabase: Bool {
        ProcessInfo.processInfo.arguments.contains("-ResetDatabase")
    }

    init() {
        // Initialize Firebase for cloud integration (Pro tier)
        // Note: This will only configure Firebase if GoogleService-Info.plist is present
        FirebaseConfigurator.shared.configure(for: .pro)

        // Initialize RevenueCat for subscription management
        // CRITICAL: Must be called before any purchase operations
        #if canImport(RevenueCat)
        RevenueCatSubscriptionService.configure()
        PrivacyLogger.app.info("RevenueCat SDK configured")
        #endif

        // Initialize localization early
        LocalizationManager.shared.updateLanguage()

        // UI Test Mode: Reset database if requested
        if Self.isUITestMode && Self.shouldResetDatabase {
            Self.resetDatabaseForTesting()
        }

        // Initialize SwiftData container
        // In UI test mode, use in-memory storage for isolation
        let useInMemory = Self.isUITestMode && Self.shouldResetDatabase
        do {
            let schema = Schema([
                FinanceDocument.self,
                LearningData.self,
                VendorProfile.self,
                VendorProfileV2.self,
                GlobalKeywordConfig.self,
                KeywordStats.self,
                RecurringTemplate.self,
                RecurringInstance.self,
                RecurringCandidate.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: useInMemory,
                allowsSave: true
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )

            // PRIVACY: Apply file protection to SwiftData store files
            Self.applySwiftDataFileProtection()

            // Initialize GlobalKeywordConfig v1 on first launch
            let mainContext = modelContainer.mainContext
            let configDescriptor = FetchDescriptor<GlobalKeywordConfig>()
            if let existingConfigs = try? mainContext.fetch(configDescriptor), existingConfigs.isEmpty {
                let defaultConfig = GlobalKeywordConfig.createDefaultV1()
                mainContext.insert(defaultConfig)
                try? mainContext.save()
            }
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }

        // Initialize app environment with all services
        // Production: Use .free tier by default
        // DEBUG: Use .pro tier for testing cloud features
        #if DEBUG
        let environment = AppEnvironment(modelContext: modelContainer.mainContext, tier: .pro)
        #else
        let environment = AppEnvironment(modelContext: modelContainer.mainContext, tier: .free)
        #endif
        _appEnvironment = State(initialValue: environment)

        #if DEBUG
        // TESTING: Force enable cloud analysis for testing
        environment.settingsManager.cloudAnalysisEnabled = true
        PrivacyLogger.app.info("TESTING: Cloud analysis force-enabled")
        #endif

        PrivacyLogger.app.info("DuEasy app initialized")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(appEnvironment)
                    .modelContainer(modelContainer)
                    .environment(\.locale, .init(identifier: appLanguage == "pl" ? "pl-PL" : "en-US"))
                    .environment(\.appLockManager, appLockManager)
                    .id(appLanguage) // Force view rebuild when language changes
                    .task {
                        // Bootstrap authentication first - ensures Firebase user exists
                        // before any cloud extraction requests
                        await appEnvironment.authBootstrapper.bootstrap()

                        // Run vendor migrations after auth is ready
                        do {
                            try await appEnvironment.runStartupMigrations()
                        } catch {
                            PrivacyLogger.app.error("Failed to run startup migrations: \(error.localizedDescription)")
                        }
                    }

                // App lock overlay - shown when app is locked
                if appLockManager.isLocked && appLockManager.isEnabled {
                    AppLockView()
                        .environment(\.appLockManager, appLockManager)
                        .transition(.opacity)
                        .zIndex(1000) // Ensure it's always on top
                }
            }
            .animation(.easeInOut(duration: 0.3), value: appLockManager.isLocked)
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(from: oldPhase, to: newPhase)
            }
        }
    }

    // MARK: - Scene Phase Handling

    /// Handles scene phase transitions for app lock management
    /// - Parameters:
    ///   - oldPhase: Previous scene phase
    ///   - newPhase: New scene phase
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // App is going to background - record time for timeout calculation
            appLockManager.handleBackgroundTransition()
            PrivacyLogger.app.debug("App entered background")

        case .inactive:
            // App is inactive (e.g., app switcher, notification center)
            // Don't lock yet - user might be just checking something
            break

        case .active:
            // App is becoming active
            if oldPhase == .background {
                // Coming from background - check if we should lock
                appLockManager.handleForegroundTransition()
            }
            PrivacyLogger.app.debug("App became active")

        @unknown default:
            break
        }
    }

    // MARK: - UI Testing Support

    /// Resets the database by deleting all SwiftData store files.
    /// TESTING ONLY: Called before app launch in UI test mode.
    private static func resetDatabaseForTesting() {
        let fileManager = FileManager.default

        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        // Find and delete all SwiftData-related files
        guard let enumerator = fileManager.enumerator(
            at: appSupportURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            let name = fileURL.lastPathComponent.lowercased()

            if ext == "sqlite" || name.hasSuffix(".sqlite-shm") || name.hasSuffix(".sqlite-wal") ||
               name.contains("default.store") {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        // Also reset UserDefaults for clean test state
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
        }

        #if DEBUG
        print("[UITest] Database reset completed")
        #endif
    }

    // MARK: - Privacy & Security

    /// Apply file protection to SwiftData store files
    /// PRIVACY: Ensures database is encrypted and requires device unlock to access
    private static func applySwiftDataFileProtection() {
        let fileManager = FileManager.default

        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            PrivacyLogger.security.warning("Could not find Application Support directory for file protection")
            return
        }

        // Enumerate all files in Application Support
        guard let enumerator = fileManager.enumerator(
            at: appSupportURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            PrivacyLogger.security.warning("Could not enumerate Application Support directory")
            return
        }

        var protectedCount = 0
        var excludedCount = 0

        for case let fileURL as URL in enumerator {
            // Apply protection to SQLite database files
            let ext = fileURL.pathExtension.lowercased()
            let name = fileURL.lastPathComponent.lowercased()

            if ext == "sqlite" || name.hasSuffix(".sqlite-shm") || name.hasSuffix(".sqlite-wal") ||
               name.contains("default.store") || name.hasSuffix(".store") {
                do {
                    // Apply file protection
                    try fileManager.setAttributes(
                        [.protectionKey: FileProtectionType.complete],
                        ofItemAtPath: fileURL.path
                    )
                    protectedCount += 1

                    // Also exclude from backup
                    var mutableURL = fileURL
                    var resourceValues = URLResourceValues()
                    resourceValues.isExcludedFromBackup = true
                    try mutableURL.setResourceValues(resourceValues)
                    excludedCount += 1
                } catch {
                    PrivacyLogger.security.warning("Failed to apply file protection to database file: \(error.localizedDescription)")
                }
            }
        }

        if protectedCount > 0 {
            PrivacyLogger.security.info("Applied file protection to \(protectedCount) database files, excluded \(excludedCount) from backup")
        }
    }
}
