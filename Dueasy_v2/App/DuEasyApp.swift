import SwiftUI
import SwiftData
import os

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

    init() {
        // Initialize Firebase for cloud integration (Pro tier)
        // Note: This will only configure Firebase if GoogleService-Info.plist is present
        FirebaseConfigurator.shared.configure(for: .pro)

        // Initialize localization early
        LocalizationManager.shared.updateLanguage()

        // Initialize SwiftData container
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
                isStoredInMemoryOnly: false,
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

        // Initialize app environment with all services (Pro tier for testing)
        let environment = AppEnvironment(modelContext: modelContainer.mainContext, tier: .pro)
        _appEnvironment = State(initialValue: environment)

        // TESTING: Force enable cloud analysis for testing
        environment.settingsManager.cloudAnalysisEnabled = true
        PrivacyLogger.app.info("🧪 TESTING: Cloud analysis force-enabled")

        // Sign in anonymously for testing (Pro tier)
        Task { @MainActor in
            do {
                try await environment.authService.signInAnonymously()
                if let userId = await environment.authService.currentUserId {
                    PrivacyLogger.app.info("✅ Signed in anonymously: \(userId)")
                }
            } catch {
                PrivacyLogger.app.error("Failed to sign in anonymously: \(error.localizedDescription)")
            }
        }

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
                        // Run vendor migrations on first appear
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
