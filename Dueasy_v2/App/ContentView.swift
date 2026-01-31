import SwiftUI

/// Root content view that manages app navigation and state.
/// Handles onboarding flow and main tab navigation.
struct ContentView: View {

    @Environment(AppEnvironment.self) private var environment
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
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
