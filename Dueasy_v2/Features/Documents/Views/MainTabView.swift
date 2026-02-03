import SwiftUI

/// Main tab navigation for the app.
///
/// Tab order (updated for user preference):
/// 1. Home - At-a-glance dashboard (Glance Dashboard) - default landing
/// 2. Documents - Full document list with search and filters
/// 3. Add Document - Center tab, modal trigger for adding new documents
/// 4. Calendar - Quick access to due dates and scheduling
/// 5. Settings - App configuration
///
/// ARCHITECTURE NOTE: This view manages the add-document sheet presentation.
/// The documentListRefreshTrigger is used to notify DocumentListView to refresh
/// after a document is added, ensuring proper layout recalculation.
struct MainTabView: View {

    @Environment(AppEnvironment.self) private var environment
    @State private var selectedTab: Tab = .home
    @State private var showingAddDocument = false

    /// Counter to trigger document list refresh after adding a document.
    /// This ensures the list reloads and any NavigationStack state is reset.
    @State private var documentListRefreshTrigger = 0

    /// Counter to trigger home view refresh after adding a document.
    @State private var homeRefreshTrigger = 0

    /// Initial filter to apply to the document list (e.g., .overdue from Home Check button)
    @State private var documentListInitialFilter: DocumentFilter?

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Home (Glance Dashboard) - default landing
            HomeView(
                onNavigateToDocuments: {
                    documentListInitialFilter = nil
                    selectedTab = .documents
                },
                onNavigateToOverdue: {
                    documentListInitialFilter = .overdue
                    documentListRefreshTrigger += 1  // Force refresh to apply new filter
                    selectedTab = .documents
                },
                onNavigateToScan: {
                    showingAddDocument = true
                }
            )
                .environment(environment)
                .tag(Tab.home)
                .tabItem {
                    Label(L10n.Home.title.localized, systemImage: "house.fill")
                }

            // Tab 2: Documents
            DocumentListView(refreshTrigger: documentListRefreshTrigger, initialFilter: documentListInitialFilter)
                .environment(environment)
                .tag(Tab.documents)
                .tabItem {
                    Label(L10n.Common.documents.localized, systemImage: "doc.text")
                }

            // Tab 3: Add Document (Modal Trigger) - center position
            Color.clear
                .tag(Tab.addDocument)
                .tabItem {
                    Label(L10n.Common.add.localized, systemImage: "plus.circle.fill")
                }

            // Tab 4: Calendar
            CalendarView()
                .environment(environment)
                .tag(Tab.calendar)
                .tabItem {
                    Label(L10n.CalendarView.title.localized, systemImage: "calendar")
                }

            // Tab 5: Settings
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
            // When sheet dismisses (was true, now false), trigger refreshes
            if oldValue && !newValue {
                #if DEBUG
                print("MainTabView: Add document sheet dismissed, triggering refresh")
                #endif
                documentListRefreshTrigger += 1
                homeRefreshTrigger += 1
            }
        }
    }

    /// Tab identifiers for the main navigation.
    /// Order: Home (1), Documents (2), Add (3-center), Calendar (4), Settings (5)
    enum Tab: Hashable {
        /// Home glance dashboard with at-a-glance metrics (default tab)
        case home

        /// Full document list with search and filters
        case documents

        /// Add document modal trigger (center position, not a real tab)
        case addDocument

        /// Calendar view showing documents by due date
        case calendar

        /// Settings and app configuration
        case settings
    }
}

#Preview {
    MainTabView()
        .environment(AppEnvironment.preview)
}
