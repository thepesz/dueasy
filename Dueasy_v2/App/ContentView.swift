import SwiftUI

/// Root content view that manages app navigation and state.
/// Handles onboarding flow and main tab navigation.
struct ContentView: View {

    @Environment(AppEnvironment.self) private var environment
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Check if running in UI test mode (skip onboarding for tests)
    private var isUITestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestMode")
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding || isUITestMode {
                MainTabView()
            } else {
                OnboardingView(onComplete: {
                    hasCompletedOnboarding = true
                })
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppEnvironment.preview)
}
