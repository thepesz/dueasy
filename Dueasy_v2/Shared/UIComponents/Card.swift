import SwiftUI

/// Reusable card component supporting glass and solid modes.
/// Automatically adapts to accessibility settings (Reduce Transparency).
struct Card<Content: View>: View {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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

/// Glass background using system materials
struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Use ultraThinMaterial for Liquid Glass effect
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .fill(.ultraThinMaterial)

            // Subtle border for definition
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .strokeBorder(
                    colorScheme == .light
                        ? Color.white.opacity(0.3)
                        : Color.white.opacity(0.1),
                    lineWidth: 0.5
                )
        }
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
                Text("This is a glass effect card")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    .padding()
    .background(Color.blue.gradient)
}
