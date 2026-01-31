import SwiftUI
import SwiftData

/// Main entry point for DuEasy application.
/// Architecture: SwiftUI Views -> MVVM ViewModels -> Use Cases -> Protocol-based Services -> SwiftData
@main
struct DuEasyApp: App {

    /// Shared app environment containing all dependencies
    @State private var appEnvironment: AppEnvironment

    /// SwiftData model container
    private let modelContainer: ModelContainer

    /// Track language changes to force view updates
    @AppStorage("appLanguage") private var appLanguage: String = "pl"

    init() {
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
                KeywordStats.self
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

        // Initialize app environment with all services
        let environment = AppEnvironment(modelContext: modelContainer.mainContext)
        _appEnvironment = State(initialValue: environment)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appEnvironment)
                .modelContainer(modelContainer)
                .environment(\.locale, .init(identifier: appLanguage == "pl" ? "pl-PL" : "en-US"))
                .id(appLanguage) // Force view rebuild when language changes
                .task {
                    // Run vendor migrations on first appear
                    do {
                        try await appEnvironment.runStartupMigrations()
                    } catch {
                        print("Failed to run startup migrations: \(error)")
                    }
                }
        }
    }

    // MARK: - Privacy & Security

    /// Apply file protection to SwiftData store files
    /// PRIVACY: Ensures database is encrypted and requires device unlock to access
    private static func applySwiftDataFileProtection() {
        let fileManager = FileManager.default

        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("WARNING: Could not find Application Support directory for file protection")
            return
        }

        // Enumerate all files in Application Support
        guard let enumerator = fileManager.enumerator(
            at: appSupportURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("WARNING: Could not enumerate Application Support directory")
            return
        }

        var protectedCount = 0
        for case let fileURL as URL in enumerator {
            // Apply protection to SQLite database files
            let ext = fileURL.pathExtension.lowercased()
            let name = fileURL.lastPathComponent.lowercased()

            if ext == "sqlite" || name.hasSuffix(".sqlite-shm") || name.hasSuffix(".sqlite-wal") ||
               name.contains("default.store") || name.hasSuffix(".store") {
                do {
                    try fileManager.setAttributes(
                        [.protectionKey: FileProtectionType.complete],
                        ofItemAtPath: fileURL.path
                    )
                    protectedCount += 1
                } catch {
                    print("WARNING: Failed to apply file protection to \(fileURL.lastPathComponent): \(error)")
                }
            }
        }

        if protectedCount > 0 {
            print("PRIVACY: Applied FileProtectionType.complete to \(protectedCount) SwiftData store files")
        }
    }
}
