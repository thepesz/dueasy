import SwiftUI

/// Reusable card component supporting glass and solid modes.
/// Automatically adapts to accessibility settings (Reduce Transparency).
struct Card<Content: View>: View {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let style: CardStyle
    let content: () -> Content

    init(
        style: CardStyle = .solid,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.style = style
        self.content = content
    }

    var body: some View {
        content()
            .cardPadding()
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .strokeBorder(borderGradient, lineWidth: style == .glass ? 1 : 0.5)
            }
            .elevation(style.elevation)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if reduceTransparency || style == .solid {
            // Solid fallback for accessibility
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .fill(AppColors.secondaryBackground)
        } else {
            // Glass effect
            GlassBackground()
        }
    }

    private var borderGradient: LinearGradient {
        if colorScheme == .light {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.8),
                    Color.white.opacity(0.2),
                    Color.white.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.25),
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

/// Card style options
enum CardStyle {
    case solid
    case glass

    var elevation: ElevationStyle {
        switch self {
        case .solid:
            return Elevation.low
        case .glass:
            return Elevation.medium
        }
    }
}

/// Glass background using system materials with enhanced styling
/// PERFORMANCE: Now uses CardMaterial for optimized single-layer blur
struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // PERFORMANCE: Replaced ZStack with CardMaterial to reduce blur layers
        CardMaterial(cornerRadius: CornerRadius.lg, addHighlight: true)
    }
}

/// Premium glass card with enhanced styling for hero sections
struct PremiumGlassCard<Content: View>: View {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let accentColor: Color
    let content: () -> Content

    init(
        accentColor: Color = AppColors.primary,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.accentColor = accentColor
        self.content = content
    }

    var body: some View {
        // PERFORMANCE: Uses CardMaterial for optimized single-layer blur
        content()
            .cardPadding()
            .background {
                CardMaterial(
                    cornerRadius: CornerRadius.lg,
                    addHighlight: true,
                    accentColor: accentColor
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay {
                GlassBorder(
                    cornerRadius: CornerRadius.lg,
                    lineWidth: 1,
                    accentColor: accentColor
                )
            }
            .shadow(
                color: accentColor.opacity(colorScheme == .light ? 0.15 : 0.25),
                radius: 12,
                x: 0,
                y: 6
            )
    }
}

// MARK: - Convenience Initializers

extension Card {
    /// Creates a solid card
    static func solid(@ViewBuilder content: @escaping () -> Content) -> Card {
        Card(style: .solid, content: content)
    }

    /// Creates a glass card
    static func glass(@ViewBuilder content: @escaping () -> Content) -> Card {
        Card(style: .glass, content: content)
    }
}

// MARK: - Preview

#Preview("Card Styles") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            Card.solid {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Solid Card")
                        .font(Typography.headline)
                    Text("This is a solid background card")
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Card.glass {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Glass Card")
                        .font(Typography.headline)
                    Text("This is a glass effect card with enhanced borders")
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PremiumGlassCard(accentColor: .blue) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Premium Glass Card")
                        .font(Typography.headline)
                    Text("This is a premium card with accent color glow")
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PremiumGlassCard(accentColor: .purple) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Purple Accent")
                        .font(Typography.headline)
                    Text("Premium card with purple accent")
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
    .gradientBackground()
}
