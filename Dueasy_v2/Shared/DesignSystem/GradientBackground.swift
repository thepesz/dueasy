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

/// Premium sophisticated background for the Home screen.
/// Features a multi-layer gradient with subtle noise texture and depth effects.
/// Designed to be elegant and professional without being distracting.
///
/// Accessibility:
/// - Respects reduceTransparency: falls back to solid background
/// - Respects reduceMotion: disables animated shimmer effects
/// - Works in both light and dark mode with appropriate color schemes
struct PremiumHomeBackground: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Subtle shimmer animation state
    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        if reduceTransparency {
            // Solid fallback for accessibility
            AppColors.background
                .ignoresSafeArea()
        } else {
            ZStack {
                // Layer 1: Base gradient (primary depth)
                baseGradient

                // Layer 2: Radial highlight for depth perception
                radialHighlight

                // Layer 3: Subtle top vignette for hierarchy
                topVignette

                // Layer 4: Ambient glow orbs (subtle depth)
                ambientGlowLayer

                // Layer 5: Optional shimmer effect (motion-dependent)
                if !reduceMotion {
                    shimmerOverlay
                }
            }
            .ignoresSafeArea()
            .onAppear {
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                        shimmerPhase = 1
                    }
                }
            }
        }
    }

    // MARK: - Layer Components

    /// Primary base gradient - sets the foundational color tone
    private var baseGradient: some View {
        LinearGradient(
            colors: colorScheme == .light
                ? [
                    Color(red: 0.95, green: 0.96, blue: 0.99),  // Soft blue-white
                    Color(red: 0.96, green: 0.95, blue: 0.98),  // Lavender tint
                    Color(red: 0.97, green: 0.96, blue: 0.98)   // Warm base
                ]
                : [
                    Color(red: 0.06, green: 0.06, blue: 0.12),  // Deep navy
                    Color(red: 0.08, green: 0.07, blue: 0.14),  // Purple undertone
                    Color(red: 0.07, green: 0.08, blue: 0.13)   // Dark base
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Radial highlight for center depth
    private var radialHighlight: some View {
        RadialGradient(
            colors: colorScheme == .light
                ? [
                    Color.white.opacity(0.6),
                    Color.white.opacity(0.2),
                    Color.clear
                ]
                : [
                    Color.white.opacity(0.04),
                    Color.white.opacity(0.01),
                    Color.clear
                ],
            center: .top,
            startRadius: 0,
            endRadius: 400
        )
    }

    /// Top vignette for navigation bar area depth
    private var topVignette: some View {
        LinearGradient(
            colors: colorScheme == .light
                ? [
                    Color(red: 0.94, green: 0.95, blue: 1.0).opacity(0.5),
                    Color.clear
                ]
                : [
                    Color(red: 0.1, green: 0.1, blue: 0.18).opacity(0.6),
                    Color.clear
                ],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.35)
        )
    }

    /// Subtle ambient glow orbs for premium depth effect
    private var ambientGlowLayer: some View {
        ZStack {
            // Primary accent orb - upper right
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppColors.primary.opacity(colorScheme == .light ? 0.08 : 0.15),
                            AppColors.primary.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 120, y: -80)

            // Secondary accent orb - lower left
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.purple.opacity(colorScheme == .light ? 0.05 : 0.10),
                            Color.purple.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .offset(x: -80, y: 60)

            // Tertiary warm orb - center
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.9, green: 0.8, blue: 0.6).opacity(colorScheme == .light ? 0.04 : 0.06),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: 100)
        }
    }

    /// Subtle shimmer overlay for premium feel
    private var shimmerOverlay: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.white.opacity(colorScheme == .light ? 0.03 : 0.015),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: geometry.size.width * 2)
            .offset(x: -geometry.size.width + (geometry.size.width * 2 * shimmerPhase))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Premium Home Background Modifier

/// Applies the premium home background to any view
struct PremiumHomeBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                PremiumHomeBackground()
            }
    }
}

extension View {
    /// Applies the premium sophisticated background for Home screen
    func premiumHomeBackground() -> some View {
        modifier(PremiumHomeBackgroundModifier())
    }
}

// MARK: - Luxury Home Background

/// Luxury sophisticated background for the Home screen with rich visual depth.
/// Features multiple gradient layers, animated ambient orbs, shimmer effects,
/// and particle-like overlays for a premium iOS app experience.
///
/// Inspired by Apple Card, Apple Fitness+, and premium banking apps.
///
/// Accessibility:
/// - Respects reduceTransparency: falls back to solid background
/// - Respects reduceMotion: disables all animations
/// - Works in both light and dark mode
struct LuxuryHomeBackground: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Animation states
    @State private var orbAnimation1: CGFloat = 0
    @State private var orbAnimation2: CGFloat = 0
    @State private var orbAnimation3: CGFloat = 0
    @State private var shimmerPhase: CGFloat = 0
    @State private var particlePhase: CGFloat = 0

    var body: some View {
        if reduceTransparency {
            // Solid fallback for accessibility
            AppColors.background
                .ignoresSafeArea()
        } else {
            ZStack {
                // Layer 1: Deep base gradient with multiple color stops
                deepBaseGradient

                // Layer 2: Secondary diagonal gradient for depth
                diagonalOverlayGradient

                // Layer 3: Radial highlight for center focus
                radialCenterHighlight

                // Layer 4: Animated ambient light orbs
                if !reduceMotion {
                    animatedAmbientOrbs
                } else {
                    staticAmbientOrbs
                }

                // Layer 5: Top vignette for navigation area
                topVignette

                // Layer 6: Subtle noise texture overlay
                noiseTextureOverlay

                // Layer 7: Animated shimmer sweep
                if !reduceMotion {
                    shimmerSweep
                }

                // Layer 8: Floating particle dots
                if !reduceMotion {
                    floatingParticles
                }
            }
            .ignoresSafeArea()
            .onAppear {
                startAnimations()
            }
        }
    }

    // MARK: - Layer Components

    /// Deep multi-stop base gradient
    private var deepBaseGradient: some View {
        LinearGradient(
            stops: colorScheme == .light
                ? [
                    .init(color: Color(red: 0.94, green: 0.95, blue: 1.0), location: 0.0),
                    .init(color: Color(red: 0.95, green: 0.94, blue: 0.99), location: 0.3),
                    .init(color: Color(red: 0.96, green: 0.95, blue: 0.98), location: 0.6),
                    .init(color: Color(red: 0.97, green: 0.96, blue: 0.99), location: 1.0)
                ]
                : [
                    .init(color: Color(red: 0.04, green: 0.04, blue: 0.10), location: 0.0),
                    .init(color: Color(red: 0.06, green: 0.05, blue: 0.12), location: 0.3),
                    .init(color: Color(red: 0.07, green: 0.06, blue: 0.14), location: 0.6),
                    .init(color: Color(red: 0.05, green: 0.05, blue: 0.11), location: 1.0)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Diagonal gradient overlay for additional depth
    private var diagonalOverlayGradient: some View {
        LinearGradient(
            colors: colorScheme == .light
                ? [
                    Color.purple.opacity(0.03),
                    Color.clear,
                    Color.blue.opacity(0.04)
                ]
                : [
                    Color.purple.opacity(0.08),
                    Color.clear,
                    Color.blue.opacity(0.10)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Radial highlight emanating from center-top
    private var radialCenterHighlight: some View {
        RadialGradient(
            colors: colorScheme == .light
                ? [
                    Color.white.opacity(0.7),
                    Color.white.opacity(0.3),
                    Color.clear
                ]
                : [
                    Color.white.opacity(0.06),
                    Color.white.opacity(0.02),
                    Color.clear
                ],
            center: UnitPoint(x: 0.5, y: 0.15),
            startRadius: 0,
            endRadius: 500
        )
    }

    /// Animated ambient orbs with floating motion
    private var animatedAmbientOrbs: some View {
        ZStack {
            // Primary orb - large blue, top-right
            ambientOrb(
                color: colorScheme == .light
                    ? Color(red: 0.3, green: 0.5, blue: 0.9)
                    : Color(red: 0.3, green: 0.5, blue: 0.95),
                size: 500,
                opacity: colorScheme == .light ? 0.12 : 0.20,
                blur: 80
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .offset(
                x: 100 + sin(orbAnimation1 * .pi * 2) * 30,
                y: -120 + cos(orbAnimation1 * .pi * 2) * 20
            )

            // Secondary orb - medium purple, bottom-left
            ambientOrb(
                color: colorScheme == .light
                    ? Color(red: 0.6, green: 0.4, blue: 0.8)
                    : Color(red: 0.6, green: 0.3, blue: 0.9),
                size: 400,
                opacity: colorScheme == .light ? 0.10 : 0.18,
                blur: 70
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .offset(
                x: -80 + cos(orbAnimation2 * .pi * 2) * 25,
                y: 100 + sin(orbAnimation2 * .pi * 2) * 30
            )

            // Tertiary orb - small cyan, center
            ambientOrb(
                color: colorScheme == .light
                    ? Color(red: 0.3, green: 0.7, blue: 0.8)
                    : Color(red: 0.2, green: 0.6, blue: 0.9),
                size: 300,
                opacity: colorScheme == .light ? 0.08 : 0.15,
                blur: 60
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(
                x: 50 + sin(orbAnimation3 * .pi * 2) * 20,
                y: 200 + cos(orbAnimation3 * .pi * 2) * 25
            )

            // Quaternary orb - warm accent, top-left
            ambientOrb(
                color: colorScheme == .light
                    ? Color(red: 0.95, green: 0.7, blue: 0.5)
                    : Color(red: 0.9, green: 0.5, blue: 0.3),
                size: 250,
                opacity: colorScheme == .light ? 0.06 : 0.12,
                blur: 50
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(
                x: -60 + cos(orbAnimation1 * .pi * 2 + 1) * 15,
                y: 80 + sin(orbAnimation2 * .pi * 2 + 1) * 20
            )
        }
    }

    /// Static orbs for reduce motion mode
    private var staticAmbientOrbs: some View {
        ZStack {
            ambientOrb(
                color: AppColors.primary,
                size: 500,
                opacity: colorScheme == .light ? 0.10 : 0.18,
                blur: 80
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .offset(x: 100, y: -120)

            ambientOrb(
                color: Color.purple,
                size: 400,
                opacity: colorScheme == .light ? 0.08 : 0.14,
                blur: 70
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .offset(x: -80, y: 100)
        }
    }

    /// Creates a single ambient orb
    private func ambientOrb(color: Color, size: CGFloat, opacity: Double, blur: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(opacity),
                        color.opacity(opacity * 0.5),
                        color.opacity(0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: blur)
    }

    /// Top vignette for navigation area depth
    private var topVignette: some View {
        LinearGradient(
            colors: colorScheme == .light
                ? [
                    Color(red: 0.93, green: 0.94, blue: 1.0).opacity(0.6),
                    Color.clear
                ]
                : [
                    Color(red: 0.08, green: 0.08, blue: 0.15).opacity(0.7),
                    Color.clear
                ],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.3)
        )
    }

    /// Subtle noise texture for premium feel
    private var noiseTextureOverlay: some View {
        Rectangle()
            .fill(
                Color.gray.opacity(colorScheme == .light ? 0.015 : 0.03)
            )
            .blendMode(.overlay)
    }

    /// Animated shimmer sweep across the screen
    private var shimmerSweep: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.white.opacity(colorScheme == .light ? 0.04 : 0.02),
                    Color.white.opacity(colorScheme == .light ? 0.08 : 0.04),
                    Color.white.opacity(colorScheme == .light ? 0.04 : 0.02),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: geometry.size.width * 1.5, height: geometry.size.height * 2)
            .rotationEffect(.degrees(30))
            .offset(
                x: -geometry.size.width * 0.5 + (geometry.size.width * 2 * shimmerPhase),
                y: -geometry.size.height * 0.25
            )
        }
        .allowsHitTesting(false)
    }

    /// Floating particle dots for depth
    private var floatingParticles: some View {
        GeometryReader { geometry in
            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(
                        colorScheme == .light
                            ? Color.white.opacity(0.3)
                            : Color.white.opacity(0.15)
                    )
                    .frame(width: CGFloat.random(in: 2...4), height: CGFloat.random(in: 2...4))
                    .position(
                        x: particlePosition(index: index, size: geometry.size.width, phase: particlePhase).x,
                        y: particlePosition(index: index, size: geometry.size.height, phase: particlePhase).y
                    )
                    .blur(radius: 0.5)
            }
        }
        .allowsHitTesting(false)
    }

    /// Calculates particle position with subtle animation
    private func particlePosition(index: Int, size: CGFloat, phase: CGFloat) -> CGPoint {
        let baseX = CGFloat(index % 4) / 3.0 * size
        let baseY = CGFloat(index / 4) / 2.0 * size + size * 0.2
        let offsetX = sin(phase * .pi * 2 + Double(index) * 0.5) * 10
        let offsetY = cos(phase * .pi * 2 + Double(index) * 0.7) * 8
        return CGPoint(x: baseX + offsetX, y: baseY + offsetY)
    }

    // MARK: - Animations

    private func startAnimations() {
        guard !reduceMotion else { return }

        // Orb floating animations with different durations for organic feel
        withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
            orbAnimation1 = 1
        }
        withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true).delay(2)) {
            orbAnimation2 = 1
        }
        withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true).delay(1)) {
            orbAnimation3 = 1
        }

        // Shimmer sweep animation
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            shimmerPhase = 1
        }

        // Particle floating animation
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
            particlePhase = 1
        }
    }
}

/// Applies the luxury home background to any view
struct LuxuryHomeBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background { LuxuryHomeBackground() }
    }
}

extension View {
    /// Applies the luxury sophisticated background for Home screen
    func luxuryHomeBackground() -> some View {
        modifier(LuxuryHomeBackgroundModifier())
    }
}

// MARK: - Luxury Card Background

/// Multi-layer card background with glass morphism, gradient overlays, and depth effects.
/// Designed for premium card styling with inner highlights and ambient tinting.
struct LuxuryCardBackground: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let accentColor: Color?
    let style: CardStyle

    enum CardStyle {
        case hero      // Large primary card with more effects
        case tile      // Medium tiles with moderate effects
        case standard  // Standard cards with subtle effects
    }

    var body: some View {
        let cornerRadius: CGFloat = style == .hero ? CornerRadius.xl : CornerRadius.lg
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency {
            // Solid fallback
            shape.fill(accentColor?.opacity(0.08) ?? AppColors.secondaryBackground)
        } else {
            ZStack {
                // Layer 1: Base glass color
                shape.fill(baseColor)

                // Layer 2: Accent tint (if provided)
                if let accent = accentColor {
                    shape.fill(accent.opacity(accentOpacity))
                }

                // Layer 3: Top-to-bottom gradient for depth
                shape.fill(verticalGradient)

                // Layer 4: Inner highlight at top
                shape.fill(innerHighlight)

                // Layer 5: Subtle radial glow (hero only)
                if style == .hero, let accent = accentColor {
                    RadialGradient(
                        colors: [
                            accent.opacity(colorScheme == .light ? 0.06 : 0.10),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 200
                    )
                    .clipShape(shape)
                }
            }
        }
    }

    private var baseColor: Color {
        colorScheme == .light
            ? Color(white: 0.99, opacity: 0.92)
            : Color(white: 0.12, opacity: 0.92)
    }

    private var accentOpacity: Double {
        switch style {
        case .hero:
            return colorScheme == .light ? 0.08 : 0.15
        case .tile:
            return colorScheme == .light ? 0.05 : 0.10
        case .standard:
            return colorScheme == .light ? 0.03 : 0.08
        }
    }

    private var verticalGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .light ? 0.5 : 0.08),
                Color.white.opacity(colorScheme == .light ? 0.15 : 0.02)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var innerHighlight: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .light ? 0.4 : 0.06),
                Color.clear
            ],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.15)
        )
    }
}

// MARK: - Luxury Card Border Modifier

/// Adds a sophisticated gradient border with light edge on top and dark on bottom
struct LuxuryCardBorderModifier: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let accentColor: Color?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
        } else {
            content.overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderGradient, lineWidth: 1)
            }
        }
    }

    private var borderGradient: LinearGradient {
        let topColor: Color
        let bottomColor: Color

        if let accent = accentColor {
            topColor = colorScheme == .light
                ? Color.white.opacity(0.7)
                : accent.opacity(0.4)
            bottomColor = colorScheme == .light
                ? accent.opacity(0.2)
                : Color.white.opacity(0.08)
        } else {
            topColor = colorScheme == .light
                ? Color.white.opacity(0.7)
                : Color.white.opacity(0.15)
            bottomColor = colorScheme == .light
                ? Color.gray.opacity(0.15)
                : Color.white.opacity(0.05)
        }

        return LinearGradient(
            colors: [topColor, bottomColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    /// Adds a luxury gradient border to a card
    func luxuryCardBorder(accentColor: Color?, cornerRadius: CGFloat) -> some View {
        modifier(LuxuryCardBorderModifier(accentColor: accentColor, cornerRadius: cornerRadius))
    }
}

// MARK: - Luxury Card Shadow Modifier

/// Adds multi-layer shadows with optional accent color glow
struct LuxuryCardShadowModifier: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme

    let accentColor: Color?
    let intensity: ShadowIntensity

    enum ShadowIntensity {
        case low, medium, high
    }

    func body(content: Content) -> some View {
        content
            // Layer 1: Soft outer shadow
            .shadow(
                color: Color.black.opacity(outerShadowOpacity),
                radius: outerShadowRadius,
                y: outerShadowY
            )
            // Layer 2: Accent color glow (if provided)
            .shadow(
                color: (accentColor ?? .clear).opacity(accentGlowOpacity),
                radius: accentGlowRadius,
                y: accentGlowY
            )
            // Layer 3: Tight contact shadow
            .shadow(
                color: Color.black.opacity(contactShadowOpacity),
                radius: 2,
                y: 1
            )
    }

    private var outerShadowOpacity: Double {
        switch intensity {
        case .low: return colorScheme == .light ? 0.04 : 0.15
        case .medium: return colorScheme == .light ? 0.06 : 0.20
        case .high: return colorScheme == .light ? 0.08 : 0.25
        }
    }

    private var outerShadowRadius: CGFloat {
        switch intensity {
        case .low: return 8
        case .medium: return 12
        case .high: return 20
        }
    }

    private var outerShadowY: CGFloat {
        switch intensity {
        case .low: return 4
        case .medium: return 6
        case .high: return 10
        }
    }

    private var accentGlowOpacity: Double {
        guard accentColor != nil else { return 0 }
        switch intensity {
        case .low: return colorScheme == .light ? 0.08 : 0.15
        case .medium: return colorScheme == .light ? 0.12 : 0.20
        case .high: return colorScheme == .light ? 0.18 : 0.30
        }
    }

    private var accentGlowRadius: CGFloat {
        switch intensity {
        case .low: return 6
        case .medium: return 10
        case .high: return 16
        }
    }

    private var accentGlowY: CGFloat {
        switch intensity {
        case .low: return 2
        case .medium: return 4
        case .high: return 8
        }
    }

    private var contactShadowOpacity: Double {
        colorScheme == .light ? 0.02 : 0.10
    }
}

extension View {
    /// Adds luxury multi-layer shadows to a card
    func luxuryCardShadow(accentColor: Color?, intensity: LuxuryCardShadowModifier.ShadowIntensity) -> some View {
        modifier(LuxuryCardShadowModifier(accentColor: accentColor, intensity: intensity))
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

        VStack {
            Text("Premium Home Background")
                .font(.title)
            Text("Sophisticated multi-layer gradient")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .premiumHomeBackground()
        .tabItem { Label("Premium", systemImage: "4.circle") }

        ZStack {
            LuxuryHomeBackground()

            VStack(spacing: 20) {
                Text("Luxury Home Background")
                    .font(.title)
                    .foregroundStyle(.primary)

                Text("Premium app-quality visuals")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Sample card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sample Card")
                        .font(.headline)
                    Text("With luxury styling")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background {
                    LuxuryCardBackground(accentColor: .blue, style: .hero)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .luxuryCardBorder(accentColor: .blue, cornerRadius: 16)
                .luxuryCardShadow(accentColor: .blue, intensity: .high)
                .padding(.horizontal, 20)
            }
        }
        .tabItem { Label("Luxury", systemImage: "5.circle") }
    }
}
