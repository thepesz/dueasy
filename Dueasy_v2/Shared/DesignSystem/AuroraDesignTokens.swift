import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Aurora Design Tokens
//
// Single source of truth for all Aurora Midnight design values.
// This file consolidates all colors, gradients, shadows, and other visual tokens
// to ensure consistency across the entire Aurora Midnight theme.
//
// DESIGN PRINCIPLES:
// 1. High contrast for sunlight readability (brighter backgrounds than original)
// 2. Multi-layer glass card system with solid backing
// 3. Vibrant accent gradients (blue -> purple -> pink)
// 4. Consistent border treatments with gradient highlights
// 5. Dual shadow system (black depth + colored glow)

// MARK: - Aurora Color Palette

/// Centralized color palette for Aurora Midnight theme.
/// All Aurora-specific colors should reference these values.
struct AuroraPalette {

    // MARK: - Background Colors

    /// Primary background gradient start (top-left)
    /// Brighter than original for better sunlight readability
    static let backgroundGradientStart = Color(red: 0.10, green: 0.10, blue: 0.18)

    /// Primary background gradient end (bottom-right)
    static let backgroundGradientEnd = Color(red: 0.14, green: 0.08, blue: 0.22)

    /// Alternative background (for navigation bars, headers)
    /// Matches backgroundGradientStart for seamless blending
    static let navigationBackground = Color(red: 0.10, green: 0.10, blue: 0.18)

    /// UIColor version for UIKit appearance configuration
    static let navigationBackgroundUIColor = UIColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1.0)

    /// Tab bar background (slightly more opaque for better contrast)
    static let tabBarBackground = UIColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 0.98)

    // MARK: - Card Colors

    /// Layer 1: Solid dark backing for cards (sunlight readability)
    static let cardBacking = Color(red: 0.06, green: 0.06, blue: 0.12)

    /// Layer 2: Subtle glass layer on top of backing
    static let cardGlass = Color.white.opacity(0.10)

    /// Layer 3 base: Default accent gradient overlay
    static let cardAccentBlue = Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.15)
    static let cardAccentPurple = Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.10)

    /// Layer 4: Border gradient colors
    static let cardBorderHighlight = Color.white.opacity(0.40)
    static let cardBorderBase = Color.white.opacity(0.15)

    /// Card border width
    static let cardBorderWidth: CGFloat = 1.0

    /// Card corner radius
    static let cardCornerRadius: CGFloat = 20

    // MARK: - Section/List Card Colors (slightly different for list contexts)

    /// Section card backing (slightly lighter than main cards)
    static let sectionBacking = Color(red: 0.08, green: 0.08, blue: 0.14)

    /// Section glass layer
    static let sectionGlass = Color.white.opacity(0.08)

    /// Section border
    static let sectionBorder = Color.white.opacity(0.15)

    // MARK: - Accent Colors

    /// Primary accent - electric blue
    static let accentBlue = Color(red: 0.3, green: 0.5, blue: 1.0)

    /// Secondary accent - vibrant purple
    static let accentPurple = Color(red: 0.6, green: 0.3, blue: 0.9)

    /// Tertiary accent - soft pink
    static let accentPink = Color(red: 0.95, green: 0.4, blue: 0.6)

    /// Teal accent (for variety)
    static let accentTeal = Color(red: 0.2, green: 0.8, blue: 0.7)

    /// UIColor version for UIKit tint color
    static let accentBlueUIColor = UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0)

    // MARK: - Text Colors

    /// Primary text - pure white for maximum contrast
    static let textPrimary = Color.white

    /// Secondary text - white with 0.75 opacity
    static let textSecondary = Color.white.opacity(0.75)

    /// Tertiary text - white with 0.5 opacity
    static let textTertiary = Color.white.opacity(0.50)

    /// Quaternary text - white with 0.35 opacity (hints, placeholders)
    static let textQuaternary = Color.white.opacity(0.35)

    // MARK: - Status Colors

    /// Success - bright mint green
    static let success = Color(red: 0.3, green: 0.9, blue: 0.6)

    /// Warning - bright amber
    static let warning = Color(red: 1.0, green: 0.75, blue: 0.3)

    /// Error - bright coral red
    static let error = Color(red: 1.0, green: 0.4, blue: 0.45)

    /// Info - accent blue
    static let info = accentBlue

    // MARK: - Separator/Divider Colors

    /// Standard separator
    static let separator = Color.white.opacity(0.12)

    /// Stronger separator (for sections)
    static let separatorStrong = Color.white.opacity(0.18)

    // MARK: - Orb/Glow Colors (for animated backgrounds)

    /// Blue orb color
    static let orbBlue = Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.15)

    /// Purple orb color
    static let orbPurple = Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.12)

    /// Pink orb color
    static let orbPink = Color(red: 0.95, green: 0.4, blue: 0.6).opacity(0.08)
}

// MARK: - Aurora Gradients

/// Pre-built gradients for Aurora Midnight theme
struct AuroraGradients {

    /// Background gradient (for full-screen backgrounds)
    static let background = LinearGradient(
        colors: [AuroraPalette.backgroundGradientStart, AuroraPalette.backgroundGradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Card accent gradient (blue to purple)
    static let cardAccent = LinearGradient(
        colors: [AuroraPalette.cardAccentBlue, AuroraPalette.cardAccentPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Card border gradient
    static let cardBorder = LinearGradient(
        colors: [AuroraPalette.cardBorderHighlight, AuroraPalette.cardBorderBase],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Logo gradient (Du portion)
    static let logoDu = LinearGradient(
        colors: [AuroraPalette.accentBlue, AuroraPalette.accentPurple],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Logo gradient (Easy portion)
    static let logoEasy = LinearGradient(
        colors: [AuroraPalette.accentPurple, AuroraPalette.accentPink],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Hero amount gradient
    static let heroAmount = LinearGradient(
        colors: [Color.white, AuroraPalette.accentBlue],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Primary button gradient
    static let primaryButton = LinearGradient(
        colors: [AuroraPalette.accentBlue, AuroraPalette.accentPurple],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Accent primary gradient (alias for primaryButton, used for selected states)
    static let accentPrimary = LinearGradient(
        colors: [AuroraPalette.accentBlue, AuroraPalette.accentPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Filter chip selected gradient
    static let filterChipSelected = LinearGradient(
        colors: [AuroraPalette.accentBlue, AuroraPalette.accentPurple],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Header fade gradient (for floating headers)
    static func headerFade(from backgroundColor: Color = AuroraPalette.backgroundGradientStart) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: backgroundColor.opacity(1.0), location: 0.0),
                .init(color: backgroundColor.opacity(0.95), location: 0.5),
                .init(color: backgroundColor.opacity(0.7), location: 0.85),
                .init(color: backgroundColor.opacity(0.0), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Aurora Shadows

/// Shadow configurations for Aurora Midnight theme
struct AuroraShadows {

    /// Card shadow - dual layer system
    struct Card {
        /// Black depth shadow (Layer 1)
        static let depthColor = Color.black.opacity(0.40)
        static let depthRadius: CGFloat = 12
        static let depthY: CGFloat = 6

        /// Colored glow shadow (Layer 2)
        static func glowColor(accent: Color) -> Color {
            accent.opacity(0.25)
        }
        static let glowRadius: CGFloat = 20
        static let glowY: CGFloat = 10
    }

    /// Row shadow - lighter than card
    struct Row {
        static let depthColor = Color.black.opacity(0.35)
        static let depthRadius: CGFloat = 10
        static let depthY: CGFloat = 5

        static func glowColor(accent: Color) -> Color {
            accent.opacity(0.20)
        }
        static let glowRadius: CGFloat = 15
        static let glowY: CGFloat = 8
    }

    /// Badge/Capsule shadow
    struct Badge {
        static func color(accent: Color) -> Color {
            accent.opacity(0.60)
        }
        static let radius: CGFloat = 2
    }

    /// Icon shadow (for icon backgrounds)
    struct Icon {
        static func color(accent: Color) -> Color {
            accent.opacity(0.40)
        }
        static let radius: CGFloat = 4
        static let y: CGFloat = 2
    }
}

// MARK: - Aurora Animation Constants

/// Animation parameters for Aurora Midnight theme
struct AuroraAnimations {

    /// Primary spring animation
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.75)

    /// Quick spring (for press states)
    static let quickSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Slow spring (for large elements)
    static let slowSpring = Animation.spring(response: 0.5, dampingFraction: 0.8)

    /// Stagger delay for list animations
    static let staggerDelay: Double = 0.06

    /// Orb animation duration
    static let orbDuration: Double = 10.0

    /// Shimmer animation duration
    static let shimmerDuration: Double = 8.0
}

// MARK: - Aurora Typography

/// Typography specifications for Aurora Midnight theme
struct AuroraTypography {

    /// Hero number specs
    struct HeroNumber {
        static let size: CGFloat = 48
        static let weight: Font.Weight = .light
        static let design: Font.Design = .default
    }

    /// Tile number specs (smaller hero)
    struct TileNumber {
        static let size: CGFloat = 24
        static let weight: Font.Weight = .medium
        static let design: Font.Design = .default
    }

    /// Section header tracking
    static let sectionHeaderTracking: CGFloat = 0.5

    /// Logo Du portion
    struct LogoDu {
        static let size: CGFloat = 42
        static let weight: Font.Weight = .medium
        static let design: Font.Design = .default
    }

    /// Logo Easy portion
    struct LogoEasy {
        static let size: CGFloat = 42
        static let weight: Font.Weight = .light
        static let design: Font.Design = .default
    }

    /// Tagline specs
    struct Tagline {
        static let size: CGFloat = 11
        static let weight: Font.Weight = .medium
        static let tracking: CGFloat = 3.0
    }
}

// MARK: - Aurora Spacing

/// Spacing adjustments specific to Aurora theme
struct AuroraSpacing {

    /// Card internal padding
    static let cardPadding: CGFloat = 20

    /// Section spacing
    static let sectionSpacing: CGFloat = 20

    /// Row vertical padding
    static let rowVerticalPadding: CGFloat = 14

    /// Screen horizontal margin
    static let screenMargin: CGFloat = 16
}

// MARK: - Aurora View Modifiers

/// Apply dual shadow system to any view
struct AuroraDualShadowModifier: ViewModifier {
    let accentColor: Color
    let intensity: Intensity

    enum Intensity {
        case card
        case row
        case light
    }

    func body(content: Content) -> some View {
        switch intensity {
        case .card:
            content
                .shadow(color: AuroraShadows.Card.depthColor, radius: AuroraShadows.Card.depthRadius, y: AuroraShadows.Card.depthY)
                .shadow(color: AuroraShadows.Card.glowColor(accent: accentColor), radius: AuroraShadows.Card.glowRadius, y: AuroraShadows.Card.glowY)
        case .row:
            content
                .shadow(color: AuroraShadows.Row.depthColor, radius: AuroraShadows.Row.depthRadius, y: AuroraShadows.Row.depthY)
                .shadow(color: AuroraShadows.Row.glowColor(accent: accentColor), radius: AuroraShadows.Row.glowRadius, y: AuroraShadows.Row.glowY)
        case .light:
            content
                .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)
        }
    }
}

extension View {
    /// Apply Aurora dual shadow system
    func auroraShadow(accent: Color, intensity: AuroraDualShadowModifier.Intensity = .card) -> some View {
        modifier(AuroraDualShadowModifier(accentColor: accent, intensity: intensity))
    }
}

// MARK: - Aurora Card Background Component

/// Standardized 4-layer card background for Aurora Midnight
/// Use this for all Aurora cards to ensure consistency
struct AuroraCardBackground: View {
    let accentColor: Color?
    let cornerRadius: CGFloat

    init(accent: Color? = nil, cornerRadius: CGFloat = AuroraPalette.cardCornerRadius) {
        self.accentColor = accent
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // Layer 1: Solid dark backing
            shape.fill(AuroraPalette.cardBacking)

            // Layer 2: Glass layer
            shape.fill(AuroraPalette.cardGlass)

            // Layer 3: Accent gradient overlay
            if let accent = accentColor {
                shape.fill(
                    LinearGradient(
                        colors: [accent.opacity(0.20), accent.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else {
                // Default blue-purple gradient
                shape.fill(AuroraGradients.cardAccent)
            }

            // Layer 4: Border gradient
            shape.strokeBorder(
                AuroraGradients.cardBorder,
                lineWidth: AuroraPalette.cardBorderWidth
            )
        }
    }
}

// MARK: - Aurora Section Background Component

/// Standardized section background for Aurora list views
struct AuroraSectionBackground: View {
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // Layer 1: Solid backing
            shape.fill(AuroraPalette.sectionBacking)

            // Layer 2: Glass layer
            shape.fill(AuroraPalette.sectionGlass)

            // Layer 3: Border
            shape.strokeBorder(AuroraPalette.sectionBorder, lineWidth: 1)
        }
    }
}

// MARK: - Aurora Status Capsule Component

/// Standardized status capsule for Aurora Midnight
struct AuroraStatusCapsule: View {
    let text: String
    let color: Color
    let showDot: Bool

    init(_ text: String, color: Color, showDot: Bool = true) {
        self.text = text
        self.color = color
        self.showDot = showDot
    }

    var body: some View {
        HStack(spacing: 4) {
            if showDot {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .shadow(color: AuroraShadows.Badge.color(accent: color), radius: AuroraShadows.Badge.radius)
            }

            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.5))
                .overlay {
                    Capsule()
                        .fill(color.opacity(0.25))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(color.opacity(0.6), lineWidth: 1.5)
                }
        }
    }
}

// MARK: - Aurora Background Component

/// Standardized full-screen background for Aurora Midnight
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let showOrbs: Bool

    init(showOrbs: Bool = true) {
        self.showOrbs = showOrbs
    }

    var body: some View {
        ZStack {
            // Base gradient
            AuroraGradients.background
                .ignoresSafeArea()

            // Ambient orbs (if enabled and accessibility allows)
            if showOrbs && !reduceTransparency {
                AuroraOrbsLayer()
            }
        }
    }
}

/// Animated orbs layer for Aurora background
struct AuroraOrbsLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animate = false

    var body: some View {
        ZStack {
            // Blue orb - top right
            Circle()
                .fill(AuroraPalette.orbBlue)
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: reduceMotion ? 100 : 100 + (animate ? 20 : 0),
                        y: reduceMotion ? -200 : -200 + (animate ? 15 : 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Purple orb - bottom left
            Circle()
                .fill(AuroraPalette.orbPurple)
                .frame(width: 250, height: 250)
                .blur(radius: 60)
                .offset(x: reduceMotion ? -100 : -100 + (animate ? -15 : 0),
                        y: reduceMotion ? 100 : 100 + (animate ? 20 : 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // Pink orb - center
            Circle()
                .fill(AuroraPalette.orbPink)
                .frame(width: 200, height: 200)
                .blur(radius: 50)
                .offset(x: reduceMotion ? -50 : -50 + (animate ? 10 : 0),
                        y: reduceMotion ? 300 : 300 + (animate ? -10 : 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: AuroraAnimations.orbDuration).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Aurora Design Tokens") {
    ZStack {
        AuroraBackground()

        ScrollView {
            VStack(spacing: 24) {
                // Logo demo
                HStack(alignment: .bottom, spacing: 2) {
                    Text("Du")
                        .font(.system(
                            size: AuroraTypography.LogoDu.size,
                            weight: AuroraTypography.LogoDu.weight,
                            design: AuroraTypography.LogoDu.design
                        ))
                        .foregroundStyle(AuroraGradients.logoDu)

                    Text("Easy")
                        .font(.system(
                            size: AuroraTypography.LogoEasy.size,
                            weight: AuroraTypography.LogoEasy.weight,
                            design: AuroraTypography.LogoEasy.design
                        ))
                        .foregroundStyle(AuroraGradients.logoEasy)
                }

                // Card demo
                VStack(alignment: .leading, spacing: 12) {
                    Text("DEMO CARD")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(AuroraTypography.sectionHeaderTracking)
                        .foregroundStyle(AuroraPalette.textSecondary)

                    Text("$1,234.56")
                        .font(.system(
                            size: AuroraTypography.HeroNumber.size,
                            weight: AuroraTypography.HeroNumber.weight,
                            design: AuroraTypography.HeroNumber.design
                        ))
                        .foregroundStyle(AuroraGradients.heroAmount)

                    AuroraStatusCapsule("2 overdue", color: AuroraPalette.error)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AuroraSpacing.cardPadding)
                .background(AuroraCardBackground(accent: AuroraPalette.accentBlue))
                .auroraShadow(accent: AuroraPalette.accentBlue)
                .padding(.horizontal, AuroraSpacing.screenMargin)

                // Section demo
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        HStack {
                            Text("Row \(index + 1)")
                                .foregroundStyle(AuroraPalette.textPrimary)
                            Spacer()
                            Text("Value")
                                .foregroundStyle(AuroraPalette.textSecondary)
                        }
                        .padding(16)

                        if index < 2 {
                            Rectangle()
                                .fill(AuroraPalette.separator)
                                .frame(height: 0.5)
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(AuroraSectionBackground())
                .padding(.horizontal, AuroraSpacing.screenMargin)
            }
            .padding(.top, 32)
        }
    }
}
