import Foundation
import SwiftData

/// Preview helpers for AppEnvironment
extension AppEnvironment {
    /// Creates a preview environment with in-memory storage
    @MainActor
    static var preview: AppEnvironment {
        do {
            let schema = Schema([
                FinanceDocument.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
            let modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            return AppEnvironment(modelContext: modelContainer.mainContext)
        } catch {
            fatalError("Failed to create preview ModelContainer: \(error)")
        }
    }
}
