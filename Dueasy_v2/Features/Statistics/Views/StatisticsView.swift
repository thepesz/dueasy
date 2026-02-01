import SwiftUI

/// Statistics view showing document insights and analytics.
/// Currently a blank placeholder for future implementation.
struct StatisticsView: View {

    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                ListGradientBackground()
                    .ignoresSafeArea()

                // Blank content area for future implementation
                Color.clear
            }
            .navigationTitle(L10n.Common.statistics.localized)
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Preview

#Preview {
    StatisticsView()
}
