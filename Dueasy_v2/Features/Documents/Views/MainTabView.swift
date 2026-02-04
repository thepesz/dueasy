import SwiftUI
import UIKit

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
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: Tab = .home
    @State private var showingAddDocument = false

    /// Counter to trigger document list refresh after adding a document.
    /// This ensures the list reloads and any NavigationStack state is reset.
    @State private var documentListRefreshTrigger = 0

    /// Counter to trigger home view refresh after adding a document.
    @State private var homeRefreshTrigger = 0

    /// Initial filter to apply to the document list (e.g., .overdue from Home Check button)
    @State private var documentListInitialFilter: DocumentFilter?

    /// Tracks if initial appearance configuration has been completed.
    /// This prevents the color loop bug by only configuring once on first appear.
    @State private var hasConfiguredAppearance = false

    /// Since the app is now locked to Midnight Aurora style, we configure once and never change.
    /// This eliminates any potential for state loops from style changes.
    private let isAuroraStyle = true

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Home (Glance Dashboard) - default landing
            HomeView(
                refreshTrigger: homeRefreshTrigger,
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
        .onAppear {
            // Configure appearance only ONCE on first appear.
            // Since the app is now locked to Midnight Aurora style, we never need to reconfigure.
            if !hasConfiguredAppearance {
                hasConfiguredAppearance = true
                // Configure synchronously on main thread to avoid any timing issues
                configureTabBarAppearance(forAurora: isAuroraStyle)
                configureNavigationBarAppearance(forAurora: isAuroraStyle)
            }
        }
    }

    // MARK: - Tab Bar Appearance Configuration

    /// Configures the tab bar appearance for Aurora and other styles.
    /// Parameter forAurora: Whether Aurora style is active.
    private func configureTabBarAppearance(forAurora: Bool) {
        let appearance = UITabBarAppearance()

        if forAurora {
            // Aurora: Dark transparent background with glass effect
            appearance.configureWithTransparentBackground()

            // Tab bar backing color - slightly darker than main background for visual separation
            // Matches AuroraPalette.tabBarBackground
            let bgColor = UIColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 0.98)
            appearance.backgroundColor = bgColor

            // Normal state: white with 0.5 opacity
            let normalColor = UIColor.white.withAlphaComponent(0.5)
            appearance.stackedLayoutAppearance.normal.iconColor = normalColor
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: normalColor,
                .font: UIFont.systemFont(ofSize: 10, weight: .medium)
            ]

            // Selected state: accent blue
            let selectedColor = UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0)
            appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: selectedColor,
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
            ]

            // Compact layouts (iPad, landscape)
            appearance.compactInlineLayoutAppearance.normal.iconColor = normalColor
            appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: normalColor
            ]
            appearance.compactInlineLayoutAppearance.selected.iconColor = selectedColor
            appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: selectedColor
            ]

            appearance.inlineLayoutAppearance.normal.iconColor = normalColor
            appearance.inlineLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: normalColor
            ]
            appearance.inlineLayoutAppearance.selected.iconColor = selectedColor
            appearance.inlineLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: selectedColor
            ]
        } else {
            // Standard appearance for other styles
            appearance.configureWithDefaultBackground()
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    /// Configures the navigation bar appearance for Aurora and other styles.
    /// Parameter forAurora: Whether Aurora style is active.
    private func configureNavigationBarAppearance(forAurora: Bool) {
        let appearance = UINavigationBarAppearance()

        if forAurora {
            // Aurora: Transparent with white text
            appearance.configureWithTransparentBackground()

            // Navigation bar backing color - matches the main background gradient start
            // for seamless blending. Uses AuroraPalette.navigationBackgroundUIColor values.
            let bgColor = UIColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 0.95)
            appearance.backgroundColor = bgColor

            // Title styling: white text
            appearance.titleTextAttributes = [
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
            ]
            appearance.largeTitleTextAttributes = [
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: 34, weight: .bold)
            ]

            // Button styling: accent blue
            let accentBlue = UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0)
            let buttonAppearance = UIBarButtonItemAppearance()
            buttonAppearance.normal.titleTextAttributes = [
                .foregroundColor: accentBlue
            ]
            appearance.buttonAppearance = buttonAppearance
            appearance.backButtonAppearance = buttonAppearance
            appearance.doneButtonAppearance = buttonAppearance
        } else {
            // Standard appearance for other styles
            appearance.configureWithDefaultBackground()
        }

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        if #available(iOS 15.0, *) {
            UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
        }

        // Set tint color for back buttons and bar items
        if forAurora {
            UINavigationBar.appearance().tintColor = UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0)
        } else {
            UINavigationBar.appearance().tintColor = nil
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
