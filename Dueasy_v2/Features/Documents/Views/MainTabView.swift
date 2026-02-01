import SwiftUI

/// Main tab navigation for the app.
/// Contains Home (Documents), Calendar, and Settings tabs.
///
/// ARCHITECTURE NOTE: This view manages the add-document sheet presentation.
/// The documentListRefreshTrigger is used to notify DocumentListView to refresh
/// after a document is added, ensuring proper layout recalculation.
struct MainTabView: View {

    @Environment(AppEnvironment.self) private var environment
    @State private var selectedTab: Tab = .documents
    @State private var showingAddDocument = false

    /// Counter to trigger document list refresh after adding a document.
    /// This ensures the list reloads and any NavigationStack state is reset.
    @State private var documentListRefreshTrigger = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DocumentListView(refreshTrigger: documentListRefreshTrigger)
                .environment(environment)
                .tag(Tab.documents)
                .tabItem {
                    Label(L10n.Common.documents.localized, systemImage: "doc.text")
                }

            CalendarView()
                .environment(environment)
                .tag(Tab.calendar)
                .tabItem {
                    Label(L10n.CalendarView.title.localized, systemImage: "calendar")
                }

            Color.clear
                .tag(Tab.addDocument)
                .tabItem {
                    Label(L10n.Documents.addNew.localized, systemImage: "plus.circle.fill")
                }

            SettingsView()
                .environment(environment)
                .tag(Tab.settings)
                .tabItem {
                    Label(L10n.Common.settings.localized, systemImage: "gear")
                }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .addDocument {
                showingAddDocument = true
                // Reset to previous tab
                selectedTab = oldValue
            }
        }
        .sheet(isPresented: $showingAddDocument) {
            AddDocumentView(environment: environment)
                .environment(environment)
        }
        .onChange(of: showingAddDocument) { oldValue, newValue in
            // When sheet dismisses (was true, now false), trigger list refresh
            if oldValue && !newValue {
                print("📱 MainTabView: Add document sheet dismissed, triggering refresh")
                documentListRefreshTrigger += 1
            }
        }
    }

    enum Tab: Hashable {
        case documents
        case calendar
        case addDocument
        case settings
    }
}

#Preview {
    MainTabView()
        .environment(AppEnvironment.preview)
}
