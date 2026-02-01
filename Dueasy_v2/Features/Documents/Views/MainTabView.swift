import SwiftUI

/// Main tab navigation for the app.
/// Contains Home (Documents), Calendar, and Settings tabs.
struct MainTabView: View {

    @Environment(AppEnvironment.self) private var environment
    @State private var selectedTab: Tab = .documents
    @State private var showingAddDocument = false

    var body: some View {
        TabView(selection: $selectedTab) {
            DocumentListView()
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
