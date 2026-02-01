import SwiftUI

/// Modern gradient background with floating orbs for depth.
/// Automatically adapts to light/dark mode and respects accessibility settings.
///
/// IMPORTANT: This background is designed to be used with `.background()` modifier
/// and does NOT use GeometryReader to avoid interfering with ScrollView layout.
/// The orbs use fixed positions relative to screen bounds instead.
struct GradientBackground: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Animation state for subtle orb movement
    @State private var animateOrbs = false

    var body: some View {
        ZStack {
            // Base gradient - fills entire available space
            baseGradient

            // Floating orbs for depth (only if transparency is enabled)
            // Uses fixed sizes based on typical screen dimensions to avoid GeometryReader
            if !reduceTransparency {
                orbsLayer
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if !reduceMotion && !animateOrbs {
                withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                    animateOrbs = true
                }
            }
        }
    }

    private var baseGradient: some View {
        LinearGradient(
            colors: colorScheme == .light
                ? [AppColors.gradientStartLight, AppColors.gradientEndLight]
                : [AppColors.gradientStartDark, AppColors.gradientEndDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Orbs layer using fixed positioning to avoid GeometryReader layout interference.
    /// Uses frame alignment and offset for positioning instead of geometry-based calculations.
    private var orbsLayer: some View {
        ZStack {
            // Primary orb - top right area
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.orbPrimary, AppColors.orbPrimary.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 160
                    )
                )
                .frame(width: 320, height: 320)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 80 + (animateOrbs ? 20 : 0), y: -60 + (animateOrbs ? 10 : 0))

            // Secondary orb - bottom left area
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.orbSecondary, AppColors.orbSecondary.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .offset(x: -100 + (animateOrbs ? -15 : 0), y: 80 + (animateOrbs ? -10 : 0))

            // Tertiary orb - center area
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.orbTertiary, AppColors.orbTertiary.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(x: 40 + (animateOrbs ? 10 : 0), y: 120 + (animateOrbs ? 15 : 0))
        }
    }
}

/// Fixed gradient background specifically for ScrollView backgrounds.
/// Unlike GradientBackground, this does NOT use ignoresSafeArea() which can
/// interfere with ScrollView layout calculations in NavigationStack.
///
/// USAGE: Apply via .background { GradientBackgroundFixed() } on ScrollView
/// IMPORTANT: Use with .scrollContentBackground(.hidden) on the ScrollView
struct GradientBackgroundFixed: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            AppColors.background
                .ignoresSafeArea()
        } else {
            // Simple gradient without orbs for better performance and layout stability
            LinearGradient(
                colors: colorScheme == .light
                    ? [AppColors.gradientStartLight, AppColors.gradientEndLight]
                    : [AppColors.gradientStartDark, AppColors.gradientEndDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

/// Simplified gradient background for lists and scrollable content.
struct ListGradientBackground: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            AppColors.background
        } else {
            LinearGradient(
                colors: colorScheme == .light
                    ? [AppColors.gradientStartLight, AppColors.gradientEndLight]
                    : [AppColors.gradientStartDark, AppColors.gradientEndDark],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

/// Mesh gradient background for hero sections (iOS 18+).
struct MeshGradientBackground: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            AppColors.background.ignoresSafeArea()
        } else {
            // Use standard gradient as fallback
            LinearGradient(
                colors: colorScheme == .light
                    ? [
                        Color(red: 0.95, green: 0.96, blue: 1.0),
                        Color(red: 0.98, green: 0.95, blue: 0.98),
                        Color(red: 0.96, green: 0.98, blue: 0.98)
                    ]
                    : [
                        Color(red: 0.08, green: 0.08, blue: 0.14),
                        Color(red: 0.10, green: 0.08, blue: 0.16),
                        Color(red: 0.08, green: 0.10, blue: 0.14)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - View Modifier

/// Applies the gradient background to any view.
struct GradientBackgroundModifier: ViewModifier {

    let style: BackgroundStyle

    func body(content: Content) -> some View {
        content
            .background {
                switch style {
                case .gradient:
                    GradientBackground()
                case .list:
                    ListGradientBackground()
                case .mesh:
                    MeshGradientBackground()
                }
            }
    }

    enum BackgroundStyle {
        case gradient
        case list
        case mesh
    }
}

extension View {
    /// Applies a modern gradient background.
    func gradientBackground(style: GradientBackgroundModifier.BackgroundStyle = .gradient) -> some View {
        modifier(GradientBackgroundModifier(style: style))
    }
}

// MARK: - Preview

#Preview("Gradient Backgrounds") {
    TabView {
        VStack {
            Text("Gradient Background")
                .font(.title)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gradientBackground(style: .gradient)
        .tabItem { Label("Gradient", systemImage: "1.circle") }

        VStack {
            Text("List Background")
                .font(.title)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gradientBackground(style: .list)
        .tabItem { Label("List", systemImage: "2.circle") }

        VStack {
            Text("Mesh Background")
                .font(.title)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gradientBackground(style: .mesh)
        .tabItem { Label("Mesh", systemImage: "3.circle") }
    }
}
