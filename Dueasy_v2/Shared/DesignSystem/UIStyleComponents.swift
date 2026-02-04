import SwiftUI

// MARK: - Styled Components
//
// UI components that automatically adapt their appearance based on the
// current UIStyleProposal. These wrap the base components and apply
// style-specific tokens.

// MARK: - Styled Background

/// Background view that adapts to the current UI style
struct StyledBackground: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var orbAnimation1: CGFloat = 0
    @State private var orbAnimation2: CGFloat = 0
    @State private var orbAnimation3: CGFloat = 0

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        ZStack {
            // Base gradient or solid
            if tokens.usesBackgroundGradients && !reduceTransparency {
                LinearGradient(
                    colors: tokens.backgroundGradientColors(for: colorScheme),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                tokens.backgroundColor(for: colorScheme)
            }

            // Animated orbs (Midnight Aurora only)
            if tokens.usesAnimatedOrbs && !reduceTransparency && !reduceMotion {
                orbsLayer(tokens: tokens)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if !reduceMotion && style == .midnightAurora {
                startOrbAnimations()
            }
        }
    }

    @ViewBuilder
    private func orbsLayer(tokens: UIStyleTokens) -> some View {
        let orbColors = tokens.orbColors(for: colorScheme)
        if orbColors.count >= 3 {
            ZStack {
            // Primary orb - top right
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbColors[0], orbColors[0].opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .blur(radius: 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(
                    x: 80 + sin(orbAnimation1 * .pi * 2) * 30,
                    y: -100 + cos(orbAnimation1 * .pi * 2) * 20
                )

            // Secondary orb - bottom left
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbColors[1], orbColors[1].opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 50)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .offset(
                    x: -60 + cos(orbAnimation2 * .pi * 2) * 25,
                    y: 80 + sin(orbAnimation2 * .pi * 2) * 30
                )

            // Tertiary orb - center
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbColors[2], orbColors[2].opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)
                .blur(radius: 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(
                    x: 30 + sin(orbAnimation3 * .pi * 2) * 20,
                    y: 150 + cos(orbAnimation3 * .pi * 2) * 25
                )
            }
        }
    }

    private func startOrbAnimations() {
        withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
            orbAnimation1 = 1
        }
        withAnimation(.easeInOut(duration: 13).repeatForever(autoreverses: true).delay(1)) {
            orbAnimation2 = 1
        }
        withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true).delay(2)) {
            orbAnimation3 = 1
        }
    }
}

// MARK: - Styled Card

/// Card component that adapts to the current UI style
struct StyledCard<Content: View>: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let accentColor: Color?
    let content: () -> Content

    init(
        accentColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.accentColor = accentColor
        self.content = content
    }

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        content()
            .padding(tokens.cardPadding)
            .background {
                cardBackground(tokens: tokens)
            }
            .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
            .overlay {
                if tokens.usesCardBorders {
                    cardBorder(tokens: tokens)
                }
            }
            .shadow(
                color: tokens.cardShadow(for: colorScheme).color,
                radius: tokens.cardShadow(for: colorScheme).radius,
                y: tokens.cardShadow(for: colorScheme).y
            )
            .modifier(AccentGlowModifier(
                color: accentColor,
                enabled: tokens.usesAccentGlow,
                colorScheme: colorScheme
            ))
    }

    @ViewBuilder
    private func cardBackground(tokens: UIStyleTokens) -> some View {
        let bgColor = tokens.cardBackgroundColor(for: colorScheme)
        let shape = RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)

        if reduceTransparency {
            shape.fill(bgColor)
        } else {
            ZStack {
                // Base fill
                shape.fill(bgColor)

                // Accent tint
                if let accent = accentColor {
                    shape.fill(accent.opacity(colorScheme == .dark ? 0.15 : 0.08))
                }

                // Inner highlight
                if let gradient = tokens.cardHighlightGradient(for: colorScheme) {
                    shape.fill(gradient)
                }
            }
        }
    }

    @ViewBuilder
    private func cardBorder(tokens: UIStyleTokens) -> some View {
        let shape = RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)

        if style == .midnightAurora {
            // Gradient border for glass effect
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.2 : 0.5),
                        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: tokens.cardBorderWidth
            )
        } else {
            shape.strokeBorder(
                tokens.cardBorderColor(for: colorScheme),
                lineWidth: tokens.cardBorderWidth
            )
        }
    }
}

/// Modifier for accent glow effect
private struct AccentGlowModifier: ViewModifier {
    let color: Color?
    let enabled: Bool
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if enabled, let accentColor = color {
            content
                .shadow(
                    color: accentColor.opacity(colorScheme == .dark ? 0.3 : 0.15),
                    radius: 12,
                    y: 4
                )
        } else {
            content
        }
    }
}

// MARK: - Styled Status Badge

/// Status badge that adapts to the current UI style
struct StyledStatusBadge: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let statusType: StatusType
    let size: BadgeSize

    enum StatusType {
        case success
        case warning
        case error
        case info
        case neutral

        func color(tokens: UIStyleTokens, colorScheme: ColorScheme) -> Color {
            switch self {
            case .success: return tokens.successColor(for: colorScheme)
            case .warning: return tokens.warningColor(for: colorScheme)
            case .error: return tokens.errorColor(for: colorScheme)
            case .info: return tokens.primaryColor(for: colorScheme)
            case .neutral: return Color.secondary
            }
        }
    }

    init(_ text: String, status: StatusType, size: BadgeSize = .regular) {
        self.text = text
        self.statusType = status
        self.size = size
    }

    var body: some View {
        let tokens = UIStyleTokens(style: style)
        let statusColor = statusType.color(tokens: tokens, colorScheme: colorScheme)

        HStack(spacing: 4) {
            // Status indicator dot (Midnight Aurora)
            if style == .midnightAurora {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor.opacity(0.6), radius: 2)
            }

            Text(text)
                .font(size.textFont)
                .fontWeight(style == .paperMinimal ? .medium : .semibold)
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background {
            badgeBackground(tokens: tokens, statusColor: statusColor)
        }
    }

    @ViewBuilder
    private func badgeBackground(tokens: UIStyleTokens, statusColor: Color) -> some View {
        let cornerRadius = tokens.badgeCornerRadius

        switch style {
        case .defaultStyle, .midnightAurora:
            // Gradient fill with border
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            statusColor.opacity(colorScheme == .dark ? 0.25 : 0.15),
                            statusColor.opacity(colorScheme == .dark ? 0.15 : 0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    Capsule()
                        .strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
                }

        case .paperMinimal:
            // Simple background with sharp corners
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(statusColor.opacity(0.12))

        case .warmFinance:
            // Soft pill
            Capsule()
                .fill(statusColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
        }
    }
}

// MARK: - Styled Button

/// Primary button that adapts to the current UI style
struct StyledPrimaryButton: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 17, weight: tokens.titleWeight))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                buttonBackground(tokens: tokens)
            }
            .clipShape(RoundedRectangle(cornerRadius: tokens.buttonCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .shadow(
            color: tokens.primaryColor(for: colorScheme).opacity(tokens.usesAccentGlow ? 0.3 : 0),
            radius: 8,
            y: 4
        )
    }

    @ViewBuilder
    private func buttonBackground(tokens: UIStyleTokens) -> some View {
        let primary = tokens.primaryColor(for: colorScheme)

        switch style {
        case .defaultStyle, .midnightAurora:
            // Vibrant gradient
            LinearGradient(
                colors: [
                    primary,
                    primary.opacity(0.85),
                    tokens.secondaryAccent(for: colorScheme).opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .paperMinimal:
            // Solid black/dark
            primary

        case .warmFinance:
            // Soft gradient
            LinearGradient(
                colors: [primary, primary.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Styled Section Header

/// Section header that adapts to the current UI style
struct StyledSectionHeader: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        HStack(spacing: Spacing.xs) {
            if let iconName = icon {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.primaryColor(for: colorScheme).opacity(0.7))
            }

            Text(title)
                .font(headerFont)
                .foregroundStyle(headerColor)

            if style == .paperMinimal {
                // Extending line
                Rectangle()
                    .fill(tokens.separatorColor(for: colorScheme))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var headerFont: Font {
        switch style {
        case .defaultStyle, .midnightAurora:
            return Typography.headline
        case .paperMinimal:
            return .system(size: 11, weight: .semibold, design: .default)
        case .warmFinance:
            return Typography.subheadline.weight(.semibold)
        }
    }

    private var headerColor: Color {
        switch style {
        case .defaultStyle, .midnightAurora:
            return .primary
        case .paperMinimal:
            return .secondary
        case .warmFinance:
            return .primary
        }
    }
}

// MARK: - Styled Hero Amount

/// Large hero amount display that adapts to the current UI style
struct StyledHeroAmount: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let amount: String

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        Text(amount)
            .font(.system(
                size: tokens.heroNumberSize,
                weight: tokens.titleWeight,
                design: tokens.heroNumberDesign
            ))
            .foregroundStyle(heroGradient(tokens: tokens))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    private func heroGradient(tokens: UIStyleTokens) -> some ShapeStyle {
        switch style {
        case .defaultStyle, .midnightAurora:
            // Vibrant multi-color gradient
            return AnyShapeStyle(LinearGradient(
                colors: [
                    tokens.primaryColor(for: colorScheme),
                    tokens.secondaryAccent(for: colorScheme),
                    tokens.primaryColor(for: colorScheme).opacity(0.8)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))

        case .paperMinimal:
            // Solid color
            return AnyShapeStyle(Color.primary)

        case .warmFinance:
            // Subtle warm gradient
            return AnyShapeStyle(LinearGradient(
                colors: [
                    .primary,
                    tokens.primaryColor(for: colorScheme)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
        }
    }
}

// MARK: - Styled Document Row

/// Document list row that adapts to the current UI style
struct StyledDocumentRow: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let vendorName: String
    let amount: String
    let dueInfo: String
    let statusType: StyledStatusBadge.StatusType
    let statusText: String

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        HStack(spacing: Spacing.md) {
            // Left content
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(vendorName)
                    .font(Typography.body)
                    .fontWeight(style == .paperMinimal ? .medium : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(dueInfo)
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Right content
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(amount)
                    .font(.system(size: 17, weight: .semibold, design: tokens.heroNumberDesign).monospacedDigit())
                    .foregroundStyle(.primary)

                StyledStatusBadge(statusText, status: statusType, size: .small)
            }
        }
        .padding(.horizontal, tokens.cardPadding)
        .padding(.vertical, tokens.rowVerticalPadding)
        .background {
            rowBackground(tokens: tokens)
        }
        .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
        .overlay {
            if tokens.usesCardBorders && tokens.rowBackgroundStyle != .flat {
                RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                    .strokeBorder(tokens.cardBorderColor(for: colorScheme), lineWidth: 0.5)
            }
        }
        .shadow(
            color: tokens.rowBackgroundStyle == .elevated
                ? tokens.cardShadow(for: colorScheme).color
                : .clear,
            radius: tokens.rowBackgroundStyle == .elevated ? 6 : 0,
            y: tokens.rowBackgroundStyle == .elevated ? 3 : 0
        )
    }

    @ViewBuilder
    private func rowBackground(tokens: UIStyleTokens) -> some View {
        switch tokens.rowBackgroundStyle {
        case .glassMorphism:
            if reduceTransparency {
                tokens.cardBackgroundColor(for: colorScheme)
            } else {
                ZStack {
                    tokens.cardBackgroundColor(for: colorScheme)
                    if let gradient = tokens.cardHighlightGradient(for: colorScheme) {
                        gradient
                    }
                }
            }

        case .flat:
            tokens.cardBackgroundColor(for: colorScheme)

        case .elevated:
            tokens.cardBackgroundColor(for: colorScheme)
        }
    }
}

// MARK: - Styled Divider

/// Divider that adapts to the current UI style
struct StyledDivider: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let inset: CGFloat

    init(inset: CGFloat = 0) {
        self.inset = inset
    }

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        Rectangle()
            .fill(tokens.separatorColor(for: colorScheme))
            .frame(height: style == .paperMinimal ? 1 : 0.5)
            .padding(.leading, inset)
    }
}

// MARK: - Styled Home Background

/// Home-specific background that adapts to the current UI style.
/// Midnight Aurora uses LuxuryHomeBackground, Paper Minimal uses flat solid,
/// Warm Finance uses subtle warm gradient.
struct StyledHomeBackground: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        switch style {
        case .defaultStyle:
            // Original luxury background (darker)
            LuxuryHomeBackground()

        case .midnightAurora:
            // BRIGHTER Midnight Aurora - enhanced version with better contrast
            EnhancedMidnightAuroraBackground()

        case .paperMinimal:
            // Pure flat background with no effects
            tokens.backgroundColor(for: colorScheme)
                .ignoresSafeArea()

        case .warmFinance:
            // Warm subtle gradient
            if reduceTransparency {
                tokens.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: tokens.backgroundGradientColors(for: colorScheme),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Enhanced Midnight Aurora Background

/// Brighter, higher-contrast version of Midnight Aurora for better sunlight readability.
/// Uses centralized AuroraPalette colors for consistency across the app.
struct EnhancedMidnightAuroraBackground: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Main gradient background using centralized palette
            LinearGradient(
                colors: [AuroraPalette.backgroundGradientStart, AuroraPalette.backgroundGradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft glow orbs (static, no animation for performance)
            if !reduceTransparency {
                Circle()
                    .fill(AuroraPalette.orbBlue)
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: -100, y: -200)

                Circle()
                    .fill(AuroraPalette.orbPurple)
                    .frame(width: 250, height: 250)
                    .blur(radius: 60)
                    .offset(x: 150, y: 100)

                Circle()
                    .fill(AuroraPalette.orbPink)
                    .frame(width: 200, height: 200)
                    .blur(radius: 50)
                    .offset(x: -50, y: 400)
            }
        }
    }
}

// MARK: - Enhanced Midnight Aurora Card

/// High-contrast card background for Midnight Aurora.
/// Uses centralized AuroraPalette for consistent 4-layer card system:
/// Layer 1: Solid dark backing (sunlight readability)
/// Layer 2: Subtle glass layer
/// Layer 3: Accent gradient overlay
/// Layer 4: Gradient border highlight
struct EnhancedMidnightAuroraCard: View {

    let accentColor: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AuroraPalette.cardCornerRadius, style: .continuous)

        ZStack {
            // Layer 1: Solid dark backing for sunlight readability
            shape.fill(AuroraPalette.cardBacking)

            // Layer 2: Subtle glass layer on top
            shape.fill(AuroraPalette.cardGlass)

            // Layer 3: Colored gradient overlay
            if let accent = accentColor {
                shape.fill(
                    LinearGradient(
                        colors: [accent.opacity(0.20), accent.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else {
                // Default blue-purple gradient from palette
                shape.fill(AuroraGradients.cardAccent)
            }

            // Layer 4: Strong gradient border
            shape.strokeBorder(
                AuroraGradients.cardBorder,
                lineWidth: AuroraPalette.cardBorderWidth
            )
        }
    }
}

// MARK: - Styled Home Card Background

/// Card background for Home view that adapts to the current UI style.
struct StyledHomeCardBackground: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let accentColor: Color?
    let cardType: CardType

    enum CardType {
        case hero
        case tile
        case standard
    }

    init(accentColor: Color? = nil, cardType: CardType = .standard) {
        self.accentColor = accentColor
        self.cardType = cardType
    }

    var body: some View {
        let tokens = UIStyleTokens(style: style)
        let cornerRadius = tokens.cardCornerRadius
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        switch style {
        case .defaultStyle:
            // Use the original LuxuryCardBackground for default
            let luxuryStyle: LuxuryCardBackground.CardStyle = {
                switch cardType {
                case .hero: return .hero
                case .tile: return .tile
                case .standard: return .standard
                }
            }()
            LuxuryCardBackground(accentColor: accentColor, style: luxuryStyle)

        case .midnightAurora:
            // ENHANCED card with multi-layer system (from demo)
            EnhancedMidnightAuroraCard(accentColor: accentColor)

        case .paperMinimal:
            // Flat card with subtle border (applied in container)
            shape.fill(tokens.cardBackgroundColor(for: colorScheme))

        case .warmFinance:
            // Warm card with subtle top highlight
            if reduceTransparency {
                shape.fill(tokens.cardBackgroundColor(for: colorScheme))
            } else {
                ZStack {
                    shape.fill(tokens.cardBackgroundColor(for: colorScheme))

                    if let gradient = tokens.cardHighlightGradient(for: colorScheme) {
                        shape.fill(gradient)
                    }

                    if let accent = accentColor {
                        shape.fill(accent.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    }
                }
            }
        }
    }
}

// MARK: - Styled Home Card Container

/// A complete styled card container for Home view cards.
/// Applies background, border, and shadow based on current style.
struct StyledHomeCard<Content: View>: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let accentColor: Color?
    let cardType: StyledHomeCardBackground.CardType
    let content: () -> Content

    init(
        accentColor: Color? = nil,
        cardType: StyledHomeCardBackground.CardType = .standard,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.accentColor = accentColor
        self.cardType = cardType
        self.content = content
    }

    var body: some View {
        let tokens = UIStyleTokens(style: style)
        let cornerRadius = tokens.cardCornerRadius

        content()
            .padding(tokens.cardPadding)
            .background {
                StyledHomeCardBackground(accentColor: accentColor, cardType: cardType)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .modifier(StyledCardBorderModifier(accentColor: accentColor, cornerRadius: cornerRadius))
            .modifier(StyledCardShadowModifier(accentColor: accentColor, cardType: cardType))
    }
}

/// Applies style-appropriate border to cards
/// NOTE: For midnightAurora, EnhancedMidnightAuroraCard already includes a border,
/// so we do NOT add another border here to avoid double borders.
private struct StyledCardBorderModifier: ViewModifier {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let accentColor: Color?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let tokens = UIStyleTokens(style: style)

        if reduceTransparency || !tokens.usesCardBorders {
            content
        } else {
            switch style {
            case .defaultStyle:
                // Use the existing luxuryCardBorder modifier
                content.luxuryCardBorder(accentColor: accentColor, cornerRadius: cornerRadius)

            case .midnightAurora:
                // EnhancedMidnightAuroraCard already has border built-in
                // Do NOT add another border to avoid double borders
                content

            case .paperMinimal:
                // Simple line border
                content.overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(tokens.cardBorderColor(for: colorScheme), lineWidth: 1)
                }

            case .warmFinance:
                // No border for Warm Finance (uses shadows instead)
                content
            }
        }
    }
}

/// Applies style-appropriate shadow to cards
private struct StyledCardShadowModifier: ViewModifier {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let accentColor: Color?
    let cardType: StyledHomeCardBackground.CardType

    func body(content: Content) -> some View {
        let tokens = UIStyleTokens(style: style)

        if !tokens.usesShadows {
            content
        } else {
            switch style {
            case .defaultStyle, .midnightAurora:
                let intensity: LuxuryCardShadowModifier.ShadowIntensity = {
                    switch cardType {
                    case .hero: return .high
                    case .tile: return .medium
                    case .standard: return .medium
                    }
                }()
                content.luxuryCardShadow(accentColor: accentColor, intensity: intensity)

            case .paperMinimal:
                // No shadows for Paper Minimal
                content

            case .warmFinance:
                let shadow = tokens.cardShadow(for: colorScheme)
                content.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
            }
        }
    }
}

// MARK: - Styled Hero Amount for Home

/// Styled hero amount display that adapts to current UI style
/// For Midnight Aurora: Uses demo-exact specs - size 48, weight .light, design .default
/// with white-to-accentBlue gradient
struct StyledHomeHeroAmount: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let amount: String

    // Aurora accent colors (from demo)
    private let accentBlue = Color(red: 0.3, green: 0.5, blue: 1.0)

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        Text(amount)
            .font(.system(
                size: tokens.heroNumberSize,
                weight: tokens.heroNumberWeight,
                design: tokens.heroNumberDesign
            ).monospacedDigit())
            .foregroundStyle(heroStyle(tokens: tokens))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    private func heroStyle(tokens: UIStyleTokens) -> some ShapeStyle {
        switch style {
        case .defaultStyle, .midnightAurora:
            // EXACT DEMO MATCH: White to accentBlue gradient
            // Demo line 142-148: .foregroundStyle(LinearGradient(colors: [textPrimary, accentBlue]...))
            // textPrimary = Color.white, accentBlue = Color(red: 0.3, green: 0.5, blue: 1.0)
            return AnyShapeStyle(LinearGradient(
                colors: [Color.white, accentBlue],
                startPoint: .leading,
                endPoint: .trailing
            ))

        case .paperMinimal:
            // Solid primary text color
            return AnyShapeStyle(tokens.textPrimaryColor(for: colorScheme))

        case .warmFinance:
            // Subtle warm gradient
            return AnyShapeStyle(LinearGradient(
                colors: [tokens.textPrimaryColor(for: colorScheme), tokens.primaryColor(for: colorScheme)],
                startPoint: .leading,
                endPoint: .trailing
            ))
        }
    }
}

// MARK: - Styled Status Capsule for Home

/// Status capsule that adapts styling to current UI style
struct StyledHomeStatusCapsule: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let color: Color

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        HStack(spacing: Spacing.xxs) {
            // Indicator dot (Midnight Aurora style)
            if style == .midnightAurora {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .shadow(color: color.opacity(0.6), radius: 2)
            }

            Text(text)
                .font(Typography.caption1.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background {
            capsuleBackground(tokens: tokens)
        }
        .modifier(CapsuleShadowModifier(style: style, color: color))
    }

    @ViewBuilder
    private func capsuleBackground(tokens: UIStyleTokens) -> some View {
        switch style {
        case .defaultStyle, .midnightAurora:
            // EXACT DEMO MATCH (lines 212-224):
            // Darker backing for better text contrast
            // .fill(Color.black.opacity(0.5))
            // .overlay(color.opacity(0.25))
            // .strokeBorder(color.opacity(0.6), lineWidth: 1.5)
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

        case .paperMinimal:
            RoundedRectangle(cornerRadius: tokens.badgeCornerRadius)
                .fill(color.opacity(0.12))

        case .warmFinance:
            Capsule()
                .fill(color.opacity(colorScheme == .dark ? 0.2 : 0.12))
        }
    }
}

private struct CapsuleShadowModifier: ViewModifier {
    let style: UIStyleProposal
    let color: Color

    func body(content: Content) -> some View {
        if style == .midnightAurora {
            // Demo uses shadow on the pill's indicator dot, not the whole pill
            content
        } else {
            content
        }
    }
}

// MARK: - Styled Settings Background

/// Background for the settings view that adapts to the current UI style.
/// For lists with scrollable content, designed to work with .scrollContentBackground(.hidden).
struct StyledSettingsBackground: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        switch style {
        case .defaultStyle:
            // Original gradient background
            ListGradientBackground()

        case .midnightAurora:
            // ENHANCED brighter Midnight Aurora background
            EnhancedMidnightAuroraBackground()

        case .paperMinimal:
            // Pure flat background with no effects
            tokens.backgroundColor(for: colorScheme)
                .ignoresSafeArea()

        case .warmFinance:
            // Warm subtle gradient
            if reduceTransparency {
                tokens.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: tokens.backgroundGradientColors(for: colorScheme),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Styled Add Document Background

/// Background for the add document view that adapts to the current UI style.
struct StyledAddDocumentBackground: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        switch style {
        case .defaultStyle:
            // Original gradient background
            GradientBackgroundFixed()

        case .midnightAurora:
            // ENHANCED brighter Midnight Aurora background
            EnhancedMidnightAuroraBackground()

        case .paperMinimal:
            // Pure flat background with no effects
            tokens.backgroundColor(for: colorScheme)
                .ignoresSafeArea()

        case .warmFinance:
            // Warm subtle gradient
            if reduceTransparency {
                tokens.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: tokens.backgroundGradientColors(for: colorScheme),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Aurora List Components

/// Aurora-styled section for List views.
/// Provides dark translucent backgrounds matching the Midnight Aurora aesthetic.
struct AuroraListSection<Content: View, Header: View, Footer: View>: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let content: () -> Content
    let header: (() -> Header)?
    let footer: (() -> Footer)?

    init(
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.content = content
        self.header = header
        self.footer = footer
    }

    var body: some View {
        if style == .midnightAurora {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Section header
                if let header = header {
                    header()
                        .auroraListSectionHeader()
                }

                // Section content with Aurora card styling
                VStack(spacing: 0) {
                    content()
                }
                .background(AuroraListSectionBackground())
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))

                // Section footer
                if let footer = footer {
                    footer()
                        .auroraListSectionFooter()
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
        } else {
            // Non-Aurora styles use standard Section
            Section {
                content()
            } header: {
                if let header = header {
                    header()
                }
            } footer: {
                if let footer = footer {
                    footer()
                }
            }
        }
    }
}

// Convenience initializers for AuroraListSection
extension AuroraListSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.header = nil
        self.footer = nil
    }
}

extension AuroraListSection where Footer == EmptyView {
    init(
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder header: @escaping () -> Header
    ) {
        self.content = content
        self.header = header
        self.footer = nil
    }
}

extension AuroraListSection where Header == EmptyView {
    init(
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.content = content
        self.header = nil
        self.footer = footer
    }
}

/// Aurora-styled section background with the 3-layer card system.
/// Uses centralized AuroraPalette for consistent section styling.
struct AuroraListSectionBackground: View {

    var body: some View {
        AuroraSectionBackground(cornerRadius: CornerRadius.md)
    }
}

/// Aurora-styled row for List views.
/// Wraps content with proper padding and separator styling.
/// Uses centralized AuroraPalette for consistent separator colors.
struct AuroraListRow<Content: View>: View {

    @Environment(\.uiStyle) private var style

    let content: () -> Content
    let showDivider: Bool

    init(showDivider: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.showDivider = showDivider
    }

    var body: some View {
        if style == .midnightAurora {
            VStack(spacing: 0) {
                content()
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)

                if showDivider {
                    Rectangle()
                        .fill(AuroraPalette.separator)
                        .frame(height: 0.5)
                        .padding(.leading, Spacing.md)
                }
            }
            .contentShape(Rectangle())
        } else {
            content()
        }
    }
}

/// Aurora-styled navigation link row.
/// Uses centralized AuroraPalette for consistent colors.
struct AuroraNavigationRow<Destination: View, Label: View>: View {

    @Environment(\.uiStyle) private var style

    let destination: () -> Destination
    let label: () -> Label
    let showDivider: Bool

    init(
        showDivider: Bool = true,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.destination = destination
        self.label = label
        self.showDivider = showDivider
    }

    var body: some View {
        if style == .midnightAurora {
            VStack(spacing: 0) {
                NavigationLink(destination: destination) {
                    HStack {
                        label()
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AuroraPalette.textTertiary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
                .buttonStyle(AuroraRowButtonStyle())

                if showDivider {
                    Rectangle()
                        .fill(AuroraPalette.separator)
                        .frame(height: 0.5)
                        .padding(.leading, Spacing.md)
                }
            }
        } else {
            NavigationLink(destination: destination) {
                label()
            }
        }
    }
}

/// Button style for Aurora rows with press feedback
struct AuroraRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.white.opacity(0.08)
                    : Color.clear
            )
            .contentShape(Rectangle())
    }
}

/// Aurora-styled toggle row
struct AuroraToggleRow: View {

    @Environment(\.uiStyle) private var style

    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    let showDivider: Bool

    init(
        _ title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>,
        showDivider: Bool = true
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
        self.showDivider = showDivider
    }

    var body: some View {
        if style == .midnightAurora {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(title)
                            .font(Typography.body)
                            .foregroundStyle(Color.white)

                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(Typography.caption1)
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                    }

                    Spacer()

                    Toggle("", isOn: $isOn)
                        .labelsHidden()
                        .tint(Color(red: 0.3, green: 0.5, blue: 1.0))
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

                if showDivider {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 0.5)
                        .padding(.leading, Spacing.md)
                }
            }
        } else {
            Toggle(title, isOn: $isOn)
        }
    }
}

/// Aurora-styled picker row
struct AuroraPickerRow<SelectionValue: Hashable>: View {

    @Environment(\.uiStyle) private var style

    let title: String
    @Binding var selection: SelectionValue
    let options: [(value: SelectionValue, label: String)]
    let showDivider: Bool

    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        options: [(value: SelectionValue, label: String)],
        showDivider: Bool = true
    ) {
        self.title = title
        self._selection = selection
        self.options = options
        self.showDivider = showDivider
    }

    var body: some View {
        if style == .midnightAurora {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(Color.white)

                    Spacer()

                    Menu {
                        ForEach(options, id: \.value) { option in
                            Button {
                                selection = option.value
                            } label: {
                                HStack {
                                    Text(option.label)
                                    if selection == option.value {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Text(options.first { $0.value == selection }?.label ?? "")
                                .font(Typography.body)
                                .foregroundStyle(Color.white.opacity(0.7))

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

                if showDivider {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 0.5)
                        .padding(.leading, Spacing.md)
                }
            }
        } else {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
        }
    }
}

/// Aurora-styled info row (label + value)
struct AuroraInfoRow: View {

    @Environment(\.uiStyle) private var style

    let label: String
    let value: String
    let showDivider: Bool

    init(_ label: String, value: String, showDivider: Bool = true) {
        self.label = label
        self.value = value
        self.showDivider = showDivider
    }

    var body: some View {
        if style == .midnightAurora {
            VStack(spacing: 0) {
                HStack {
                    Text(label)
                        .font(Typography.body)
                        .foregroundStyle(Color.white)

                    Spacer()

                    Text(value)
                        .font(Typography.body)
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

                if showDivider {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 0.5)
                        .padding(.leading, Spacing.md)
                }
            }
        } else {
            HStack {
                Text(label)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Aurora-styled settings row with icon
struct AuroraSettingsRow: View {

    @Environment(\.uiStyle) private var style

    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?

    var body: some View {
        if style == .midnightAurora {
            HStack(spacing: Spacing.sm) {
                // Icon with gradient background
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [iconColor, iconColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: icon)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                }
                .shadow(color: iconColor.opacity(0.4), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(Color.white)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Typography.caption1)
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
            }
        } else {
            SettingsRow(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle)
        }
    }
}

// MARK: - View Modifiers for Aurora List Styling

extension View {
    /// Applies Aurora section header styling
    func auroraListSectionHeader() -> some View {
        self
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.6))
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, Spacing.xxs)
            .padding(.bottom, Spacing.xxs)
    }

    /// Applies Aurora section footer styling
    func auroraListSectionFooter() -> some View {
        self
            .font(Typography.caption1)
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.horizontal, Spacing.xxs)
            .padding(.top, Spacing.xs)
    }

    /// Applies Aurora list row styling for text
    func auroraListText() -> some View {
        self.foregroundStyle(Color.white)
    }

    /// Applies Aurora list secondary text styling
    func auroraListSecondaryText() -> some View {
        self.foregroundStyle(Color.white.opacity(0.6))
    }
}

/// Modifier to style a List for Aurora theme
struct AuroraListModifier: ViewModifier {

    @Environment(\.uiStyle) private var style

    func body(content: Content) -> some View {
        if style == .midnightAurora {
            content
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            content
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
        }
    }
}

extension View {
    /// Applies Aurora list styling
    func auroraListStyle() -> some View {
        modifier(AuroraListModifier())
    }
}

// MARK: - Styled Settings List

/// A complete styled settings list that adapts to the current UI style.
/// For Midnight Aurora, it renders as a ScrollView with styled sections.
/// For other styles, it uses a standard List.
struct StyledSettingsList<Content: View>: View {

    @Environment(\.uiStyle) private var style

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        if style == .midnightAurora {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    content()
                }
                .padding(.vertical, Spacing.md)
            }
            .scrollIndicators(.hidden)
        } else {
            List {
                content()
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
    }
}

// MARK: - View Modifiers

extension View {
    /// Applies the styled background for the current UI style
    func styledBackground() -> some View {
        background { StyledBackground() }
    }

    /// Applies the styled home background for the current UI style
    func styledHomeBackground() -> some View {
        background { StyledHomeBackground() }
    }

    /// Applies the styled settings background for the current UI style
    func styledSettingsBackground() -> some View {
        background { StyledSettingsBackground() }
    }

    /// Applies the styled add document background for the current UI style
    func styledAddDocumentBackground() -> some View {
        background { StyledAddDocumentBackground() }
    }

    /// Applies Aurora-aware primary text color
    /// For Aurora: Color.white
    /// For others: uses system .primary
    func auroraPrimaryText() -> some View {
        modifier(AuroraPrimaryTextModifier())
    }

    /// Applies Aurora-aware secondary text color
    /// For Aurora: Color.white.opacity(0.75)
    /// For others: uses system .secondary
    func auroraSecondaryText() -> some View {
        modifier(AuroraSecondaryTextModifier())
    }
}

// MARK: - Aurora Text Color Modifiers

/// Modifier that applies Aurora-aware primary text color
private struct AuroraPrimaryTextModifier: ViewModifier {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let tokens = UIStyleTokens(style: style)
        content.foregroundStyle(tokens.textPrimaryColor(for: colorScheme))
    }
}

/// Modifier that applies Aurora-aware secondary text color
private struct AuroraSecondaryTextModifier: ViewModifier {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let tokens = UIStyleTokens(style: style)
        content.foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
    }
}

// MARK: - Styled Detail View Background

/// Background for detail views that adapts to the current UI style.
/// Used by DocumentDetailView, DocumentReviewView, ManualEntryView.
struct StyledDetailViewBackground: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        switch style {
        case .defaultStyle:
            GradientBackgroundFixed()

        case .midnightAurora:
            EnhancedMidnightAuroraBackground()

        case .paperMinimal:
            tokens.backgroundColor(for: colorScheme)
                .ignoresSafeArea()

        case .warmFinance:
            if reduceTransparency {
                tokens.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: tokens.backgroundGradientColors(for: colorScheme),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Styled Form Field

/// Style-aware form field that adapts to Aurora and other styles.
/// Replaces the basic FormField for style-aware form inputs.
struct StyledFormField<Content: View>: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let label: String
    let isRequired: Bool
    let content: () -> Content

    init(
        label: String,
        isRequired: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.isRequired = isRequired
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xxs) {
                Text(label)
                    .font(Typography.caption1)
                    .foregroundStyle(labelColor)

                if isRequired {
                    Text("*")
                        .font(Typography.caption1)
                        .foregroundStyle(AppColors.error)
                }
            }

            content()
                .modifier(StyledTextFieldModifier())
        }
    }

    private var labelColor: Color {
        style == .midnightAurora ? Color.white.opacity(0.7) : .secondary
    }
}

/// Modifier that styles text fields for Aurora and other styles
private struct StyledTextFieldModifier: ViewModifier {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if style == .midnightAurora {
            content
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(AuroraTextFieldBackground())
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
                .foregroundStyle(Color.white)
        } else {
            content
                .textFieldStyle(.roundedBorder)
        }
    }
}

/// Aurora-styled text field background
struct AuroraTextFieldBackground: View {
    private let bgColor = Color(red: 0.08, green: 0.08, blue: 0.14)
    private let borderColor = Color.white.opacity(0.2)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .fill(bgColor)

            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .fill(Color.white.opacity(0.05))

            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }
}

// MARK: - Styled Detail Card

/// Style-aware card for detail view sections.
/// Replaces Color(UIColor.secondarySystemGroupedBackground) in detail views.
struct StyledDetailCard<Content: View>: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            .overlay {
                if style == .midnightAurora {
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch style {
        case .midnightAurora:
            AuroraDetailCardBackground()

        case .defaultStyle, .paperMinimal, .warmFinance:
            Color(UIColor.secondarySystemGroupedBackground)
        }
    }
}

/// Aurora-styled card background for detail views
struct AuroraDetailCardBackground: View {
    private let cardBackingColor = Color(red: 0.08, green: 0.08, blue: 0.14)
    private let cardGlassLayer = Color.white.opacity(0.08)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(cardBackingColor)

            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(cardGlassLayer)
        }
    }
}

// MARK: - Styled Glass Card

/// Style-aware glass card that replaces Card.glass {} usage.
/// Works for both Aurora and standard styles.
struct StyledGlassCard<Content: View>: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        if style == .midnightAurora {
            content()
                .padding(Spacing.md)
                .background(AuroraDetailCardBackground())
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        } else {
            Card.glass {
                content()
            }
        }
    }
}

// MARK: - Styled Detail Row

/// Style-aware detail row for label/value pairs in detail views.
struct StyledDetailRow: View {

    @Environment(\.uiStyle) private var style

    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(Typography.caption1)
                .foregroundStyle(labelColor)

            Text(value)
                .font(Typography.body)
                .foregroundStyle(valueColor)
        }
    }

    private var labelColor: Color {
        style == .midnightAurora ? Color.white.opacity(0.6) : .secondary
    }

    private var valueColor: Color {
        style == .midnightAurora ? Color.white : .primary
    }
}

// MARK: - Styled Floating Button

/// Style-aware floating button for detail view headers.
struct StyledFloatingButton: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let action: () -> Void
    let isEnabled: Bool

    init(icon: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.icon = icon
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 44, height: 44)
                .background(backgroundView, in: Circle())
        }
        .disabled(!isEnabled)
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return Color.gray
        }
        return style == .midnightAurora
            ? Color(red: 0.3, green: 0.5, blue: 1.0)
            : AppColors.primary
    }

    // Aurora card backing color (matches EnhancedMidnightAuroraCard)
    private let auroraCardBacking = Color(red: 0.08, green: 0.08, blue: 0.14)

    private var backgroundView: Color {
        if style == .midnightAurora {
            // Use the card backing color for consistency with Aurora cards
            return auroraCardBacking.opacity(0.95)
        } else {
            return colorScheme == .light
                ? Color(white: 0.94)
                : Color(white: 0.22)
        }
    }
}

// MARK: - Styled Header Background

/// Style-aware floating header background for detail views.
/// For Aurora: Uses a subtle gradient that blends with the EnhancedMidnightAuroraBackground.
/// The key is matching the exact background color to avoid a visible black bar.
struct StyledFloatingHeaderBackground: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if style == .midnightAurora {
            // Use AuroraPalette for consistent colors across the app.
            // The gradient matches the background exactly at top and fades
            // to transparent at bottom for seamless blending with content.
            LinearGradient(
                stops: [
                    .init(color: AuroraPalette.backgroundGradientStart, location: 0),
                    .init(color: AuroraPalette.backgroundGradientStart.opacity(0.90), location: 0.4),
                    .init(color: AuroraPalette.backgroundGradientStart.opacity(0.60), location: 0.7),
                    .init(color: Color.clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color(UIColor.systemGroupedBackground)
                .opacity(0.95)
        }
    }
}

// MARK: - Styled Reminder Chip

/// Style-aware reminder chip for selecting reminder offsets.
struct StyledReminderChip: View {

    @Environment(\.uiStyle) private var style

    let offset: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typography.caption1)
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(backgroundColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        switch offset {
        case 0:
            return L10n.Review.reminderDueDate.localized
        case 1:
            return L10n.Review.reminderOneDay.localized
        default:
            return L10n.Review.reminderDays.localized(with: offset)
        }
    }

    private var foregroundColor: Color {
        if isSelected {
            return .white
        }
        return style == .midnightAurora ? AuroraPalette.textSecondary : .primary
    }

    private var backgroundColor: Color {
        if isSelected {
            return style == .midnightAurora
                ? AuroraPalette.accentBlue
                : AppColors.primary
        }
        return style == .midnightAurora
            ? AuroraPalette.cardGlass
            : AppColors.secondaryBackground
    }
}

// MARK: - View Extensions for Detail Views

extension View {
    /// Applies styled detail view background
    func styledDetailBackground() -> some View {
        background { StyledDetailViewBackground() }
    }
}
