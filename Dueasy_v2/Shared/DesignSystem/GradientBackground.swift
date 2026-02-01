import SwiftUI

/// Modern gradient background with floating orbs for depth.
/// Automatically adapts to light/dark mode and respects accessibility settings.
struct GradientBackground: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Animation state for subtle orb movement
    @State private var animateOrbs = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base gradient
                baseGradient

                // Floating orbs for depth (only if transparency is enabled)
                if !reduceTransparency {
                    orbsLayer(in: geometry.size)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if !reduceMotion {
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

    private func orbsLayer(in size: CGSize) -> some View {
        ZStack {
            // Primary orb - top right
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.orbPrimary, AppColors.orbPrimary.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.width * 0.4
                    )
                )
                .frame(width: size.width * 0.8, height: size.width * 0.8)
                .offset(
                    x: size.width * 0.3 + (animateOrbs ? 20 : 0),
                    y: -size.height * 0.15 + (animateOrbs ? 10 : 0)
                )

            // Secondary orb - bottom left
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.orbSecondary, AppColors.orbSecondary.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.width * 0.35
                    )
                )
                .frame(width: size.width * 0.7, height: size.width * 0.7)
                .offset(
                    x: -size.width * 0.35 + (animateOrbs ? -15 : 0),
                    y: size.height * 0.25 + (animateOrbs ? -10 : 0)
                )

            // Tertiary orb - center
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.orbTertiary, AppColors.orbTertiary.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.width * 0.25
                    )
                )
                .frame(width: size.width * 0.5, height: size.width * 0.5)
                .offset(
                    x: size.width * 0.1 + (animateOrbs ? 10 : 0),
                    y: size.height * 0.4 + (animateOrbs ? 15 : 0)
                )
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
