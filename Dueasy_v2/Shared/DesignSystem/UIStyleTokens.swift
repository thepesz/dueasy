import SwiftUI

// MARK: - UI Style Tokens
//
// Design tokens for each UI style proposal. Each style has its own complete
// token set for colors, typography emphasis, spacing adjustments, corner radii,
// shadows, and materials.

/// Design tokens that vary by UI style
struct UIStyleTokens {

    let style: UIStyleProposal

    init(style: UIStyleProposal) {
        self.style = style
    }

    /// Normalized style for token lookup
    /// Maps .defaultStyle to .midnightAurora since they share the same tokens
    private var tokenStyle: UIStyleProposal {
        style == .defaultStyle ? .midnightAurora : style
    }

    // MARK: - Color Palette

    /// Primary brand/accent color
    func primaryColor(for colorScheme: ColorScheme) -> Color {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return colorScheme == .dark
                ? Color(red: 0.4, green: 0.6, blue: 1.0)  // Bright electric blue
                : Color(red: 0.3, green: 0.5, blue: 0.95) // Vibrant blue

        case .paperMinimal:
            return Color(red: 0.1, green: 0.1, blue: 0.1)  // Near black

        case .warmFinance:
            return colorScheme == .dark
                ? Color(red: 0.4, green: 0.65, blue: 0.6)  // Teal
                : Color(red: 0.2, green: 0.5, blue: 0.45)  // Deep teal
        }
    }

    /// Secondary accent color
    func secondaryAccent(for colorScheme: ColorScheme) -> Color {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return colorScheme == .dark
                ? Color(red: 0.8, green: 0.4, blue: 0.9)  // Purple-pink
                : Color(red: 0.6, green: 0.3, blue: 0.8)

        case .paperMinimal:
            return Color.gray

        case .warmFinance:
            return colorScheme == .dark
                ? Color(red: 0.9, green: 0.7, blue: 0.5)  // Warm amber
                : Color(red: 0.8, green: 0.55, blue: 0.3)
        }
    }

    /// Background color (primary surface)
    func backgroundColor(for colorScheme: ColorScheme) -> Color {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return colorScheme == .dark
                ? Color(red: 0.04, green: 0.04, blue: 0.08)  // Deep navy black
                : Color(red: 0.94, green: 0.95, blue: 0.98)

        case .paperMinimal:
            return colorScheme == .dark
                ? Color(red: 0.08, green: 0.08, blue: 0.08)  // Pure dark
                : Color(red: 0.99, green: 0.99, blue: 0.99)  // Pure white

        case .warmFinance:
            return colorScheme == .dark
                ? Color(red: 0.08, green: 0.07, blue: 0.06)  // Warm dark
                : Color(red: 0.98, green: 0.96, blue: 0.93)  // Warm cream
        }
    }

    /// Card/surface background color
    func cardBackgroundColor(for colorScheme: ColorScheme) -> Color {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return colorScheme == .dark
                ? Color(white: 0.12, opacity: 0.85)  // Glassmorphism
                : Color(white: 0.98, opacity: 0.85)

        case .paperMinimal:
            return colorScheme == .dark
                ? Color(red: 0.12, green: 0.12, blue: 0.12)  // Flat surface
                : Color.white

        case .warmFinance:
            return colorScheme == .dark
                ? Color(red: 0.14, green: 0.12, blue: 0.10)  // Warm surface
                : Color(red: 1.0, green: 0.99, blue: 0.97)   // Warm white
        }
    }

    /// Separator/divider color
    func separatorColor(for colorScheme: ColorScheme) -> Color {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return Color.white.opacity(colorScheme == .dark ? 0.1 : 0.15)

        case .paperMinimal:
            return colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.08)

        case .warmFinance:
            return colorScheme == .dark
                ? Color(red: 0.6, green: 0.5, blue: 0.4).opacity(0.2)
                : Color(red: 0.4, green: 0.35, blue: 0.3).opacity(0.12)
        }
    }

    // MARK: - Text Colors (Aurora-specific)

    /// Primary text color - for Aurora, this is always white regardless of color scheme
    func textPrimaryColor(for colorScheme: ColorScheme) -> Color {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            // Aurora: Always white for high contrast on dark backgrounds
            return Color.white

        case .paperMinimal:
            return colorScheme == .dark ? Color.white : Color.black

        case .warmFinance:
            return colorScheme == .dark ? Color.white : Color(red: 0.15, green: 0.12, blue: 0.10)
        }
    }

    /// Secondary text color - for Aurora, white with 0.75 opacity
    func textSecondaryColor(for colorScheme: ColorScheme) -> Color {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            // Aurora: White with 0.75 opacity (from demo)
            return Color.white.opacity(0.75)

        case .paperMinimal:
            return colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6)

        case .warmFinance:
            return colorScheme == .dark ? Color.white.opacity(0.7) : Color(red: 0.4, green: 0.35, blue: 0.30)
        }
    }

    /// Tertiary text color - for Aurora, white with 0.5 opacity
    func textTertiaryColor(for colorScheme: ColorScheme) -> Color {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return Color.white.opacity(0.5)

        case .paperMinimal:
            return colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4)

        case .warmFinance:
            return colorScheme == .dark ? Color.white.opacity(0.5) : Color(red: 0.5, green: 0.45, blue: 0.40)
        }
    }

    // MARK: - Status Colors

    /// Success color (paid, completed)
    func successColor(for colorScheme: ColorScheme) -> Color {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return colorScheme == .dark
                ? Color(red: 0.3, green: 0.9, blue: 0.6)  // Bright mint
                : Color(red: 0.2, green: 0.75, blue: 0.45)

        case .paperMinimal:
            return Color(red: 0.2, green: 0.65, blue: 0.35)  // Muted green

        case .warmFinance:
            return colorScheme == .dark
                ? Color(red: 0.45, green: 0.8, blue: 0.55)
                : Color(red: 0.3, green: 0.65, blue: 0.4)
        }
    }

    /// Warning color (due soon)
    func warningColor(for colorScheme: ColorScheme) -> Color {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return colorScheme == .dark
                ? Color(red: 1.0, green: 0.75, blue: 0.3)  // Bright amber
                : Color(red: 0.95, green: 0.6, blue: 0.1)

        case .paperMinimal:
            return Color(red: 0.85, green: 0.55, blue: 0.1)  // Muted orange

        case .warmFinance:
            return colorScheme == .dark
                ? Color(red: 0.95, green: 0.7, blue: 0.35)
                : Color(red: 0.85, green: 0.55, blue: 0.15)
        }
    }

    /// Error color (overdue)
    func errorColor(for colorScheme: ColorScheme) -> Color {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return colorScheme == .dark
                ? Color(red: 1.0, green: 0.4, blue: 0.45)  // Bright coral
                : Color(red: 0.95, green: 0.3, blue: 0.35)

        case .paperMinimal:
            return Color(red: 0.85, green: 0.25, blue: 0.25)  // Muted red

        case .warmFinance:
            return colorScheme == .dark
                ? Color(red: 0.95, green: 0.45, blue: 0.4)
                : Color(red: 0.85, green: 0.3, blue: 0.25)
        }
    }

    // MARK: - Typography

    /// Title font weight
    var titleWeight: Font.Weight {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return .bold
        case .paperMinimal: return .medium
        case .warmFinance: return .semibold
        }
    }

    /// Body font weight
    var bodyWeight: Font.Weight {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return .regular
        case .paperMinimal: return .regular
        case .warmFinance: return .regular
        }
    }

    /// Hero number font design
    var heroNumberDesign: Font.Design {
        switch tokenStyle {
        case .defaultStyle: return .rounded
        case .midnightAurora: return .default  // Demo uses .default, not .rounded
        case .paperMinimal: return .monospaced
        case .warmFinance: return .rounded
        }
    }

    /// Hero number font weight (different from titleWeight)
    var heroNumberWeight: Font.Weight {
        switch tokenStyle {
        case .defaultStyle: return .bold
        case .midnightAurora: return .light  // Demo uses .light for hero numbers
        case .paperMinimal: return .medium
        case .warmFinance: return .semibold
        }
    }

    /// Hero number font size
    var heroNumberSize: CGFloat {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return 48
        case .paperMinimal: return 42
        case .warmFinance: return 44
        }
    }

    // MARK: - Corner Radii

    /// Card corner radius
    var cardCornerRadius: CGFloat {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return 20  // Large, fluid
        case .paperMinimal: return 4     // Sharp, minimal
        case .warmFinance: return 16     // Soft, friendly
        }
    }

    /// Button corner radius
    var buttonCornerRadius: CGFloat {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return 14
        case .paperMinimal: return 4
        case .warmFinance: return 12
        }
    }

    /// Badge/pill corner radius
    var badgeCornerRadius: CGFloat {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return .infinity  // Full capsule
        case .paperMinimal: return 4
        case .warmFinance: return .infinity
        }
    }

    /// Input field corner radius
    var inputCornerRadius: CGFloat {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return 12
        case .paperMinimal: return 4
        case .warmFinance: return 10
        }
    }

    // MARK: - Shadows

    /// Whether shadows are used in this style
    var usesShadows: Bool {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return true
        case .paperMinimal: return false
        case .warmFinance: return true
        }
    }

    /// Card shadow configuration
    func cardShadow(for colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, y: CGFloat) {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return (
                color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.15),
                radius: 16,
                y: 8
            )

        case .paperMinimal:
            return (color: .clear, radius: 0, y: 0)

        case .warmFinance:
            return (
                color: Color(red: 0.3, green: 0.25, blue: 0.2).opacity(colorScheme == .dark ? 0.3 : 0.1),
                radius: 12,
                y: 6
            )
        }
    }

    /// Whether to use accent-colored glow shadows
    var usesAccentGlow: Bool {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return true
        case .paperMinimal: return false
        case .warmFinance: return false
        }
    }

    // MARK: - Borders

    /// Whether cards have visible borders
    var usesCardBorders: Bool {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return true   // Glass border
        case .paperMinimal: return true     // Subtle line
        case .warmFinance: return false     // Shadow only
        }
    }

    /// Card border color
    func cardBorderColor(for colorScheme: ColorScheme) -> Color {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return Color.white.opacity(colorScheme == .dark ? 0.15 : 0.3)

        case .paperMinimal:
            return colorScheme == .dark
                ? Color.white.opacity(0.06)
                : Color.black.opacity(0.06)

        case .warmFinance:
            return .clear
        }
    }

    /// Card border width
    var cardBorderWidth: CGFloat {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return 1
        case .paperMinimal: return 1
        case .warmFinance: return 0
        }
    }

    // MARK: - Gradients

    /// Whether the style uses gradient backgrounds
    var usesBackgroundGradients: Bool {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return true
        case .paperMinimal: return false
        case .warmFinance: return true
        }
    }

    /// Background gradient colors
    func backgroundGradientColors(for colorScheme: ColorScheme) -> [Color] {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return colorScheme == .dark
                ? [
                    Color(red: 0.04, green: 0.04, blue: 0.10),
                    Color(red: 0.06, green: 0.05, blue: 0.15),
                    Color(red: 0.08, green: 0.06, blue: 0.18)
                ]
                : [
                    Color(red: 0.94, green: 0.95, blue: 1.0),
                    Color(red: 0.96, green: 0.94, blue: 0.99),
                    Color(red: 0.97, green: 0.95, blue: 0.98)
                ]

        case .paperMinimal:
            let bg = backgroundColor(for: colorScheme)
            return [bg, bg]

        case .warmFinance:
            return colorScheme == .dark
                ? [
                    Color(red: 0.08, green: 0.07, blue: 0.06),
                    Color(red: 0.10, green: 0.08, blue: 0.06),
                    Color(red: 0.09, green: 0.07, blue: 0.05)
                ]
                : [
                    Color(red: 0.98, green: 0.96, blue: 0.93),
                    Color(red: 0.97, green: 0.95, blue: 0.91),
                    Color(red: 0.96, green: 0.93, blue: 0.88)
                ]
        }
    }

    /// Whether to show animated background orbs
    var usesAnimatedOrbs: Bool {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return true
        case .paperMinimal: return false
        case .warmFinance: return false
        }
    }

    /// Orb colors for animated backgrounds
    func orbColors(for colorScheme: ColorScheme) -> [Color] {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return colorScheme == .dark
                ? [
                    Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.25),
                    Color(red: 0.7, green: 0.3, blue: 0.9).opacity(0.2),
                    Color(red: 0.2, green: 0.8, blue: 0.7).opacity(0.15)
                ]
                : [
                    Color(red: 0.3, green: 0.5, blue: 0.9).opacity(0.15),
                    Color(red: 0.6, green: 0.3, blue: 0.8).opacity(0.12),
                    Color(red: 0.2, green: 0.7, blue: 0.6).opacity(0.1)
                ]

        case .paperMinimal:
            return []

        case .warmFinance:
            return []
        }
    }

    // MARK: - Card Styling

    /// Whether cards use glass/blur effect
    var usesGlassEffect: Bool {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return true
        case .paperMinimal: return false
        case .warmFinance: return false
        }
    }

    /// Card inner highlight gradient
    func cardHighlightGradient(for colorScheme: ColorScheme) -> LinearGradient? {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.1 : 0.5),
                    Color.white.opacity(colorScheme == .dark ? 0.02 : 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

        case .paperMinimal:
            return nil

        case .warmFinance:
            return LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.3),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.3)
            )
        }
    }

    // MARK: - Spacing Adjustments

    /// Horizontal screen margin
    var screenHorizontalPadding: CGFloat {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return 16
        case .paperMinimal: return 20
        case .warmFinance: return 16
        }
    }

    /// Card internal padding
    var cardPadding: CGFloat {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return 20
        case .paperMinimal: return 16
        case .warmFinance: return 18
        }
    }

    /// Section spacing
    var sectionSpacing: CGFloat {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return 20
        case .paperMinimal: return 24
        case .warmFinance: return 18
        }
    }

    // MARK: - Animation

    /// Primary animation spring
    var animationSpring: Animation {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora:
            return .spring(response: 0.4, dampingFraction: 0.75)
        case .paperMinimal:
            return .easeInOut(duration: 0.25)
        case .warmFinance:
            return .spring(response: 0.5, dampingFraction: 0.8)
        }
    }

    /// Stagger delay for list animations
    var staggerDelay: Double {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return 0.06
        case .paperMinimal: return 0.04
        case .warmFinance: return 0.05
        }
    }

    // MARK: - List/Row Styling

    /// Row background style
    var rowBackgroundStyle: RowBackgroundStyle {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return .glassMorphism
        case .paperMinimal: return .flat
        case .warmFinance: return .elevated
        }
    }

    /// Whether rows have visual separation
    var rowsHaveSeparators: Bool {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return false  // Cards are separate
        case .paperMinimal: return true     // Line separators
        case .warmFinance: return false     // Shadow separation
        }
    }

    /// Row vertical padding
    var rowVerticalPadding: CGFloat {
        switch tokenStyle {
        case .defaultStyle, .midnightAurora: return 14
        case .paperMinimal: return 12
        case .warmFinance: return 14
        }
    }
}

/// Row background styling options
enum RowBackgroundStyle {
    case glassMorphism   // Blurred/semi-transparent
    case flat            // Solid, no depth
    case elevated        // Solid with shadow
}

// MARK: - Convenience Extensions

extension UIStyleTokens {
    /// Get tokens for the given style
    static func tokens(for style: UIStyleProposal) -> UIStyleTokens {
        UIStyleTokens(style: style)
    }
}
