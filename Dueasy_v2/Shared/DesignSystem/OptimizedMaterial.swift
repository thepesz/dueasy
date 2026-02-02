import SwiftUI

// MARK: - Performance-Optimized Material System
//
// This file provides a centralized, performance-optimized approach to material backgrounds.
// It addresses the "Requesting visual style in an implementation that has disabled it" warning
// by:
// 1. Caching material views to prevent excessive recreation
// 2. Properly respecting accessibility settings (reduceTransparency)
// 3. Providing single-layer alternatives to stacked ZStack materials
// 4. Using static views where possible to minimize GPU blur layer count

/// A performance-optimized material background that respects accessibility settings.
///
/// VISUAL STYLE FIX: This component now uses solid colors that simulate glass appearance
/// instead of actual material effects (.ultraThinMaterial, .thinMaterial, .regularMaterial).
/// This prevents "Requesting visual style in an implementation that has disabled it" errors
/// that occur when materials are used in views within NavigationStacks that have hidden
/// navigation bars (which disables the visual style system).
///
/// This view automatically:
/// - Falls back to solid colors when Reduce Transparency is enabled
/// - Uses solid glass simulation instead of actual blur materials
/// - Provides consistent styling across the app without visual style conflicts
struct OptimizedMaterial<S: Shape>: View {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let shape: S
    let style: MaterialStyle
    let addGlassHighlight: Bool

    init(
        _ shape: S = RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous),
        style: MaterialStyle = .thin,
        addGlassHighlight: Bool = true
    ) {
        self.shape = shape
        self.style = style
        self.addGlassHighlight = addGlassHighlight
    }

    var body: some View {
        if reduceTransparency {
            // Solid fallback for accessibility
            shape.fill(solidFallbackColor)
        } else {
            // VISUAL STYLE FIX: Use solid glass simulation instead of material
            shape
                .fill(glassSimulationColor)
                .overlay {
                    if addGlassHighlight {
                        shape.fill(highlightGradient)
                    }
                }
        }
    }

    // MARK: - Private Computed Properties

    /// Solid color that simulates the glass/frosted appearance of materials
    private var glassSimulationColor: Color {
        switch style {
        case .ultraThin:
            return colorScheme == .light
                ? Color(white: 0.98, opacity: 0.85)
                : Color(white: 0.12, opacity: 0.85)
        case .thin:
            return colorScheme == .light
                ? Color(white: 0.97, opacity: 0.88)
                : Color(white: 0.14, opacity: 0.88)
        case .regular:
            return colorScheme == .light
                ? Color(white: 0.96, opacity: 0.92)
                : Color(white: 0.16, opacity: 0.92)
        }
    }

    private var solidFallbackColor: Color {
        switch style {
        case .ultraThin:
            return AppColors.secondaryBackground
        case .thin:
            return AppColors.secondaryBackground
        case .regular:
            return AppColors.tertiaryBackground
        }
    }

    private var highlightGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .light ? 0.4 : 0.08),
                Color.white.opacity(colorScheme == .light ? 0.15 : 0.02)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Material style options
enum MaterialStyle {
    case ultraThin
    case thin
    case regular
}

// MARK: - Specialized Material Shapes

/// Circle material background optimized for icons and loading indicators
///
/// VISUAL STYLE FIX: Uses solid colors that simulate glass appearance instead of
/// .ultraThinMaterial to prevent "Requesting visual style in an implementation that
/// has disabled it" errors when used in views with hidden navigation bars.
struct CircleMaterial: View {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let addHighlight: Bool

    init(addHighlight: Bool = true) {
        self.addHighlight = addHighlight
    }

    var body: some View {
        if reduceTransparency {
            Circle().fill(AppColors.secondaryBackground)
        } else {
            // VISUAL STYLE FIX: Use solid glass simulation instead of material
            Circle()
                .fill(colorScheme == .light
                      ? Color(white: 0.98, opacity: 0.9)
                      : Color(white: 0.15, opacity: 0.9))
                .overlay {
                    if addHighlight {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .light ? 0.4 : 0.1),
                                        Color.white.opacity(0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                }
        }
    }
}

/// Capsule material background for pills and chips
///
/// VISUAL STYLE FIX: Uses solid colors that simulate glass appearance instead of
/// .ultraThinMaterial to prevent visual style conflicts with hidden navigation bars.
struct CapsuleMaterial: View {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let addHighlight: Bool

    init(addHighlight: Bool = false) {
        self.addHighlight = addHighlight
    }

    var body: some View {
        if reduceTransparency {
            Capsule().fill(AppColors.secondaryBackground)
        } else {
            // VISUAL STYLE FIX: Use solid glass simulation instead of material
            Capsule()
                .fill(colorScheme == .light
                      ? Color(white: 0.98, opacity: 0.9)
                      : Color(white: 0.15, opacity: 0.9))
                .overlay {
                    if addHighlight {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .light ? 0.3 : 0.08),
                                        Color.white.opacity(0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
        }
    }
}

/// Rounded rectangle material background for cards
///
/// VISUAL STYLE FIX: Uses solid colors that simulate glass appearance instead of
/// .ultraThinMaterial to prevent "Requesting visual style in an implementation that
/// has disabled it" errors. This is critical for:
/// - DocumentListView filter bar and cards
/// - AddDocumentView input method cards
/// - DocumentDetailView (uses .navigationBarHidden(true))
/// - Any view in NavigationStack with hidden navigation bars
struct CardMaterial: View {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let addHighlight: Bool
    let accentColor: Color?

    init(
        cornerRadius: CGFloat = CornerRadius.lg,
        addHighlight: Bool = true,
        accentColor: Color? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.addHighlight = addHighlight
        self.accentColor = accentColor
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency {
            shape.fill(accentColor?.opacity(0.08) ?? AppColors.secondaryBackground)
        } else {
            // VISUAL STYLE FIX: Use solid glass simulation instead of material
            shape
                .fill(colorScheme == .light
                      ? Color(white: 0.98, opacity: 0.9)
                      : Color(white: 0.15, opacity: 0.9))
                .overlay {
                    if let accent = accentColor {
                        shape.fill(accent.opacity(0.1))
                    }
                }
                .overlay {
                    if addHighlight {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .light ? 0.4 : 0.08),
                                    Color.white.opacity(colorScheme == .light ? 0.15 : 0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
        }
    }
}

// MARK: - Optimized Borders

/// Glass-style border with gradient
struct GlassBorder: View {

    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let accentColor: Color?

    init(
        cornerRadius: CGFloat = CornerRadius.lg,
        lineWidth: CGFloat = 0.5,
        accentColor: Color? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.accentColor = accentColor
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(borderGradient, lineWidth: lineWidth)
    }

    private var borderGradient: LinearGradient {
        if let accent = accentColor {
            return LinearGradient(
                colors: [
                    accent.opacity(0.5),
                    Color.white.opacity(colorScheme == .light ? 0.4 : 0.15),
                    accent.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .light ? 0.6 : 0.2),
                    Color.white.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - View Modifiers

/// Applies an optimized glass card background
struct OptimizedGlassCardModifier: ViewModifier {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let accentColor: Color?
    let shadowRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                CardMaterial(
                    cornerRadius: cornerRadius,
                    addHighlight: true,
                    accentColor: accentColor
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                GlassBorder(
                    cornerRadius: cornerRadius,
                    lineWidth: 0.5,
                    accentColor: accentColor
                )
            }
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowRadius / 2
            )
    }

    private var shadowColor: Color {
        if let accent = accentColor {
            return accent.opacity(colorScheme == .light ? 0.15 : 0.25)
        } else {
            return Color.black.opacity(colorScheme == .light ? 0.06 : 0.15)
        }
    }
}

extension View {
    /// Applies an optimized glass card styling with proper accessibility fallback
    func optimizedGlassCard(
        cornerRadius: CGFloat = CornerRadius.lg,
        accentColor: Color? = nil,
        shadowRadius: CGFloat = 8
    ) -> some View {
        modifier(OptimizedGlassCardModifier(
            cornerRadius: cornerRadius,
            accentColor: accentColor,
            shadowRadius: shadowRadius
        ))
    }
}

// MARK: - Preview

#Preview("Optimized Materials") {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            // Card Material
            Text("Card Material")
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { CardMaterial() }
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                .overlay { GlassBorder() }

            // With accent
            Text("Accent Card")
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { CardMaterial(accentColor: .blue) }
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                .overlay { GlassBorder(accentColor: .blue) }

            // Capsule Material
            HStack {
                Text("Chip")
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background { CapsuleMaterial() }
                    .clipShape(Capsule())
            }

            // Circle Material
            HStack {
                ZStack {
                    CircleMaterial()
                        .frame(width: 60, height: 60)

                    Image(systemName: "doc.text")
                        .font(.title2)
                }
            }

            // Using modifier
            Text("Using Modifier")
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .optimizedGlassCard()

            Text("Accent Modifier")
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .optimizedGlassCard(accentColor: .purple)
        }
        .padding()
    }
    .gradientBackground(style: .gradient)
}
