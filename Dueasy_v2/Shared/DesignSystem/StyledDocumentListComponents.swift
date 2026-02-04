import SwiftUI

// MARK: - Styled Document List Components
//
// UI components for DocumentListView that automatically adapt their appearance
// based on the current UIStyleProposal. These follow the same pattern as
// StyledHomeCard and related components in UIStyleComponents.swift.

// MARK: - Styled Document List Background

/// Background for the document list view that adapts to the current UI style.
/// Uses style-specific gradients and colors.
struct StyledDocumentListBackground: View {

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

// MARK: - Styled Document List Row

/// Document row component for DocumentListView that adapts styling to the current UI style.
/// Provides style-specific card backgrounds, borders, and shadows.
/// Note: This is different from StyledDocumentRow in UIStyleComponents which takes string params.
struct StyledDocumentListRow: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let document: FinanceDocument
    let onTap: () -> Void

    @State private var isPressed = false

    init(document: FinanceDocument, onTap: @escaping () -> Void = {}) {
        self.document = document
        self.onTap = onTap
    }

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        Button(action: {
            #if DEBUG
            print("StyledDocumentListRow tapped: \(document.id)")
            #endif
            onTap()
        }) {
            HStack(spacing: Spacing.sm) {
                // Document type icon with styled ring
                documentTypeIcon(tokens: tokens)

                // Main content
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    // Title and status
                    HStack {
                        Text(document.title.isEmpty ? "Untitled" : document.title)
                            .font(Typography.listRowPrimary)
                            .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))
                            .lineLimit(1)

                        Spacer()

                        StyledDocumentListStatusBadge(status: document.status)
                    }

                    // Amount and due date
                    HStack {
                        Text(formattedAmount)
                            .font(Typography.listRowAmount(design: tokens.heroNumberDesign))
                            .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))

                        Spacer()

                        if let dueDate = document.dueDate {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: "calendar")
                                    .font(Typography.sectionIcon)
                                Text(formattedDate(dueDate))
                                    .font(Typography.listRowSecondary)
                            }
                            .foregroundStyle(dueDateColor(tokens: tokens))
                        }
                    }

                    // Document number if available
                    if let number = document.documentNumber, !number.isEmpty {
                        Text("No. \(number)")
                            .font(Typography.listRowSecondary)
                            .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                    }
                }

                // Chevron with subtle animation
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tokens.textTertiaryColor(for: colorScheme))
                    .offset(x: isPressed ? 2 : 0)
            }
            .padding(tokens.cardPadding)
            .background {
                rowBackground(tokens: tokens)
            }
            .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
            .modifier(DocumentListRowBorderModifier(tokens: tokens))
            .modifier(DocumentListRowShadowModifier(tokens: tokens, accentColor: statusColorForStyle(tokens: tokens)))
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity) {
            // Never triggers - just for press state
        } onPressingChanged: { pressing in
            if !reduceMotion {
                withAnimation(pressing ? .easeInOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = pressing
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view details")
    }

    // MARK: - Subviews

    @ViewBuilder
    private func documentTypeIcon(tokens: UIStyleTokens) -> some View {
        let statusColor = statusColorForStyle(tokens: tokens)

        ZStack {
            // Background ring
            Circle()
                .fill(iconBackgroundGradient(statusColor: statusColor, tokens: tokens))
                .frame(width: 44, height: 44)

            // Icon
            Image(systemName: document.type.iconName)
                .font(.title3.weight(.medium))
                .foregroundStyle(statusColor)
                .symbolRenderingMode(.hierarchical)
        }
        .overlay {
            iconBorderOverlay(statusColor: statusColor)
        }
    }

    private func iconBackgroundGradient(statusColor: Color, tokens: UIStyleTokens) -> some ShapeStyle {
        switch style {
        case .defaultStyle, .midnightAurora:
            return AnyShapeStyle(LinearGradient(
                colors: [
                    statusColor.opacity(0.25),
                    statusColor.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))

        case .paperMinimal:
            return AnyShapeStyle(statusColor.opacity(0.08))

        case .warmFinance:
            return AnyShapeStyle(LinearGradient(
                colors: [
                    statusColor.opacity(0.15),
                    statusColor.opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }

    @ViewBuilder
    private func iconBorderOverlay(statusColor: Color) -> some View {
        switch style {
        case .defaultStyle, .midnightAurora:
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            statusColor.opacity(0.5),
                            statusColor.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )

        case .paperMinimal:
            Circle()
                .strokeBorder(statusColor.opacity(0.2), lineWidth: 1)

        case .warmFinance:
            Circle()
                .strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func rowBackground(tokens: UIStyleTokens) -> some View {
        let shape = RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)

        switch style {
        case .midnightAurora:
            // ENHANCED: Multi-layer card system matching HomeView demo
            if reduceTransparency {
                shape.fill(tokens.cardBackgroundColor(for: colorScheme))
            } else {
                let statusColor = statusColorForStyle(tokens: tokens)
                EnhancedMidnightAuroraCard(accentColor: statusColor)
            }

        case .defaultStyle:
            // Original glassmorphism
            if reduceTransparency {
                shape.fill(tokens.cardBackgroundColor(for: colorScheme))
            } else {
                ZStack {
                    shape.fill(tokens.cardBackgroundColor(for: colorScheme))
                    if let gradient = tokens.cardHighlightGradient(for: colorScheme) {
                        shape.fill(gradient)
                    }
                }
            }

        case .paperMinimal:
            shape.fill(tokens.cardBackgroundColor(for: colorScheme))

        case .warmFinance:
            shape.fill(tokens.cardBackgroundColor(for: colorScheme))
        }
    }

    private func statusColorForStyle(tokens: UIStyleTokens) -> Color {
        switch document.status {
        case .draft:
            return tokens.warningColor(for: colorScheme)
        case .scheduled:
            return tokens.primaryColor(for: colorScheme)
        case .paid:
            return tokens.successColor(for: colorScheme)
        case .archived:
            return tokens.separatorColor(for: colorScheme)
        }
    }

    private func dueDateColor(tokens: UIStyleTokens) -> Color {
        if let days = document.daysUntilDue {
            if days < 0 {
                return tokens.errorColor(for: colorScheme)
            } else if days <= 3 {
                return tokens.warningColor(for: colorScheme)
            }
        }
        return tokens.textSecondaryColor(for: colorScheme)
    }

    // MARK: - Formatting

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = document.currency

        let number = NSDecimalNumber(decimal: document.amount)
        return formatter.string(from: number) ?? "\(document.amount) \(document.currency)"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var accessibilityLabel: String {
        var label = "\(document.type.displayName): \(document.title.isEmpty ? "Untitled" : document.title)"
        label += ", \(formattedAmount)"
        label += ", Status: \(document.status.displayName)"

        if document.dueDate != nil {
            if let days = document.daysUntilDue {
                if days < 0 {
                    label += ", \(abs(days)) days overdue"
                } else if days == 0 {
                    label += ", due today"
                } else {
                    label += ", due in \(days) days"
                }
            }
        }

        return label
    }
}

// MARK: - Document List Row Border Modifier

private struct DocumentListRowBorderModifier: ViewModifier {
    let tokens: UIStyleTokens

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency || !tokens.usesCardBorders {
            content
        } else {
            switch style {
            case .midnightAurora:
                // ENHANCED: Strong 1.5pt gradient border (already applied by EnhancedMidnightAuroraCard)
                // No additional border needed - the card component handles it
                content

            case .defaultStyle:
                content.overlay {
                    RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.15 : 0.5),
                                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }

            case .paperMinimal:
                content.overlay {
                    RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                        .strokeBorder(tokens.cardBorderColor(for: colorScheme), lineWidth: 1)
                }

            case .warmFinance:
                content
            }
        }
    }
}

// MARK: - Document List Row Shadow Modifier

private struct DocumentListRowShadowModifier: ViewModifier {
    let tokens: UIStyleTokens
    var accentColor: Color?

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    init(tokens: UIStyleTokens, accentColor: Color? = nil) {
        self.tokens = tokens
        self.accentColor = accentColor
    }

    func body(content: Content) -> some View {
        if !tokens.usesShadows {
            content
        } else {
            switch style {
            case .midnightAurora:
                // ENHANCED: Dual shadow system (black depth + colored glow)
                content
                    .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
                    .shadow(color: (accentColor ?? Color.blue).opacity(0.2), radius: 15, y: 8)

            case .defaultStyle:
                content
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                        radius: 8,
                        y: 4
                    )

            case .paperMinimal:
                content

            case .warmFinance:
                let shadow = tokens.cardShadow(for: colorScheme)
                content.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
            }
        }
    }
}

// MARK: - Styled Document List Status Badge

/// Document status badge that adapts to the current UI style
struct StyledDocumentListStatusBadge: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let status: DocumentStatus

    var body: some View {
        let tokens = UIStyleTokens(style: style)
        let statusColor = colorForStatus(tokens: tokens)

        HStack(spacing: 4) {
            // Status indicator dot (Midnight Aurora only)
            if style == .midnightAurora {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                    .shadow(color: statusColor.opacity(0.6), radius: 2)
            }

            Text(status.displayName)
                .font(Typography.stat)
                .fontWeight(style == .paperMinimal ? .medium : .semibold)
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, Spacing.xs + 2)
        .padding(.vertical, Spacing.xxs + 1)
        .background {
            badgeBackground(tokens: tokens, statusColor: statusColor)
        }
    }

    @ViewBuilder
    private func badgeBackground(tokens: UIStyleTokens, statusColor: Color) -> some View {
        switch style {
        case .midnightAurora:
            // ENHANCED: Darker backing with stronger border
            Capsule()
                .fill(Color.black.opacity(0.5))
                .overlay {
                    Capsule()
                        .fill(statusColor.opacity(0.25))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(statusColor.opacity(0.6), lineWidth: 1)
                }

        case .defaultStyle:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            statusColor.opacity(colorScheme == .dark ? 0.25 : 0.15),
                            statusColor.opacity(colorScheme == .dark ? 0.12 : 0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    Capsule()
                        .strokeBorder(statusColor.opacity(0.25), lineWidth: 0.5)
                }

        case .paperMinimal:
            RoundedRectangle(cornerRadius: tokens.badgeCornerRadius)
                .fill(statusColor.opacity(0.1))

        case .warmFinance:
            Capsule()
                .fill(statusColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
        }
    }

    private func colorForStatus(tokens: UIStyleTokens) -> Color {
        switch status {
        case .draft:
            return tokens.warningColor(for: colorScheme)
        case .scheduled:
            return tokens.primaryColor(for: colorScheme)
        case .paid:
            return tokens.successColor(for: colorScheme)
        case .archived:
            return tokens.separatorColor(for: colorScheme)
        }
    }
}

// MARK: - Styled Search Bar

/// Search bar that adapts to the current UI style
struct StyledSearchBar: View {

    @Binding var text: String
    let placeholder: String

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        HStack(spacing: Spacing.xs) {
            // Search icon - animate color change only, not layout
            Image(systemName: "magnifyingglass")
                .font(Typography.listRowSecondary.weight(.medium))
                .foregroundStyle(isFocused ? tokens.primaryColor(for: colorScheme) : .secondary)

            // Text field
            TextField(placeholder, text: $text)
                .font(Typography.bodyText)
                .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))
                .focused($isFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            // Clear button (shown when text is not empty)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs + 2)
        .background {
            searchBarBackground(tokens: tokens)
        }
        .clipShape(RoundedRectangle(cornerRadius: tokens.inputCornerRadius, style: .continuous))
        .overlay {
            searchBarBorder(tokens: tokens)
        }
        // PERFORMANCE FIX: Only animate the clear button appearance, not the entire view
        // Removing animations on isFocused prevents lag during keyboard transitions
        // The keyboard notifications issue occurs when animations trigger view updates during keyboard state changes
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: text.isEmpty)
    }

    @ViewBuilder
    private func searchBarBackground(tokens: UIStyleTokens) -> some View {
        let shape = RoundedRectangle(cornerRadius: tokens.inputCornerRadius, style: .continuous)

        switch style {
        case .midnightAurora:
            // ENHANCED: Dark solid backing for better contrast
            if reduceTransparency {
                shape.fill(tokens.cardBackgroundColor(for: colorScheme))
            } else {
                ZStack {
                    shape.fill(AuroraPalette.sectionBacking)
                    shape.fill(AuroraPalette.sectionGlass)
                }
            }

        case .defaultStyle:
            if reduceTransparency {
                shape.fill(tokens.cardBackgroundColor(for: colorScheme))
            } else {
                CardMaterial(cornerRadius: tokens.inputCornerRadius, addHighlight: false)
            }

        case .paperMinimal:
            shape.fill(tokens.cardBackgroundColor(for: colorScheme))

        case .warmFinance:
            shape.fill(tokens.cardBackgroundColor(for: colorScheme))
        }
    }

    @ViewBuilder
    private func searchBarBorder(tokens: UIStyleTokens) -> some View {
        let shape = RoundedRectangle(cornerRadius: tokens.inputCornerRadius, style: .continuous)

        switch style {
        case .midnightAurora:
            // ENHANCED: Stronger gradient border
            if isFocused {
                shape.strokeBorder(tokens.primaryColor(for: colorScheme), lineWidth: 1.5)
            } else {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }

        case .defaultStyle:
            if isFocused {
                shape.strokeBorder(tokens.primaryColor(for: colorScheme), lineWidth: 1.5)
            } else {
                GlassBorder(
                    cornerRadius: tokens.inputCornerRadius,
                    lineWidth: 0.5,
                    accentColor: nil
                )
            }

        case .paperMinimal:
            shape.strokeBorder(
                isFocused ? tokens.primaryColor(for: colorScheme) : tokens.cardBorderColor(for: colorScheme),
                lineWidth: 1
            )

        case .warmFinance:
            if isFocused {
                shape.strokeBorder(tokens.primaryColor(for: colorScheme).opacity(0.5), lineWidth: 1)
            } else {
                EmptyView()
            }
        }
    }
}

// MARK: - Styled Filter Chip

/// Filter chip that adapts to the current UI style
/// For Midnight Aurora: Matches demo styling with blue-purple gradient and proper backgrounds
struct StyledFilterChip: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let icon: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    // Midnight Aurora colors - using centralized AuroraPalette
    private var auroraAccentBlue: Color { AuroraPalette.accentBlue }
    private var auroraAccentPurple: Color { AuroraPalette.accentPurple }
    private var auroraCardBg: Color { AuroraPalette.cardGlass }
    private var auroraCardBorder: Color { AuroraPalette.cardBorderBase }
    private var auroraTextSecondary: Color { AuroraPalette.textSecondary }

    // MARK: - Filter Chip Sizing (20% larger than default)
    // Base values scaled by 1.2x for better touch targets and readability
    private let chipIconFont: Font = .system(size: 14)           // was 12pt (sectionIcon)
    private let chipTextFont: Font = .system(size: 16, weight: .medium) // was 13pt (buttonText)
    private let chipCountFont: Font = .system(size: 14, weight: .semibold) // was 12pt
    private let chipHStackSpacing: CGFloat = 7                    // was 6pt
    private let chipHorizontalPadding: CGFloat = 17               // was 14pt
    private let chipVerticalPadding: CGFloat = 10                 // was 8pt
    private let chipCountHPadding: CGFloat = 7                    // was 6pt
    private let chipCountVPadding: CGFloat = 3                    // was 2pt

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        Button(action: action) {
            HStack(spacing: chipHStackSpacing) {
                Image(systemName: icon)
                    .font(chipIconFont)

                Text(title)
                    .font(chipTextFont)
                    .fontWeight(isSelected ? .semibold : .medium)

                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(chipCountFont)
                        .padding(.horizontal, chipCountHPadding)
                        .padding(.vertical, chipCountVPadding)
                        .background {
                            countBackground(tokens: tokens)
                        }
                }
            }
            .foregroundStyle(chipForegroundColor(tokens: tokens))
            .padding(.horizontal, chipHorizontalPadding)
            .padding(.vertical, chipVerticalPadding)
            .background {
                chipBackground(tokens: tokens)
            }
            .overlay {
                chipBorder(tokens: tokens)
            }
            .shadow(color: chipShadowColor(tokens: tokens), radius: isSelected ? 6 : 0, y: isSelected ? 3 : 0)
        }
        .buttonStyle(.plain)
    }

    private func chipForegroundColor(tokens: UIStyleTokens) -> Color {
        switch style {
        case .midnightAurora:
            return isSelected ? .white : auroraTextSecondary
        default:
            return isSelected ? .white : tokens.textPrimaryColor(for: colorScheme)
        }
    }

    @ViewBuilder
    private func countBackground(tokens: UIStyleTokens) -> some View {
        switch style {
        case .midnightAurora:
            Capsule()
                .fill(isSelected ? Color.white.opacity(0.25) : auroraAccentBlue.opacity(0.2))
        default:
            if isSelected {
                Capsule()
                    .fill(Color.white.opacity(0.25))
            } else {
                Capsule()
                    .fill(tokens.primaryColor(for: colorScheme).opacity(0.15))
            }
        }
    }

    @ViewBuilder
    private func chipBackground(tokens: UIStyleTokens) -> some View {
        if isSelected {
            selectedBackground(tokens: tokens)
        } else {
            unselectedBackground(tokens: tokens)
        }
    }

    @ViewBuilder
    private func selectedBackground(tokens: UIStyleTokens) -> some View {
        switch style {
        case .midnightAurora:
            // Matches demo: blue-to-purple gradient
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [auroraAccentBlue, auroraAccentPurple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

        case .defaultStyle:
            let primary = tokens.primaryColor(for: colorScheme)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [primary, primary.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

        case .paperMinimal:
            RoundedRectangle(cornerRadius: tokens.badgeCornerRadius)
                .fill(tokens.primaryColor(for: colorScheme))

        case .warmFinance:
            let primary = tokens.primaryColor(for: colorScheme)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [primary, primary.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    @ViewBuilder
    private func unselectedBackground(tokens: UIStyleTokens) -> some View {
        switch style {
        case .midnightAurora:
            // Matches demo: subtle dark background (cardBg = white.opacity(0.08))
            Capsule()
                .fill(auroraCardBg)

        case .defaultStyle:
            CapsuleMaterial()

        case .paperMinimal:
            RoundedRectangle(cornerRadius: tokens.badgeCornerRadius)
                .fill(tokens.cardBackgroundColor(for: colorScheme))

        case .warmFinance:
            Capsule()
                .fill(tokens.cardBackgroundColor(for: colorScheme))
        }
    }

    @ViewBuilder
    private func chipBorder(tokens: UIStyleTokens) -> some View {
        switch style {
        case .midnightAurora:
            // Matches demo: border only on unselected chips
            if !isSelected {
                Capsule()
                    .strokeBorder(auroraCardBorder, lineWidth: 1)
            }

        case .defaultStyle:
            if !isSelected {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .light ? 0.6 : 0.2),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }

        case .paperMinimal:
            if !isSelected {
                RoundedRectangle(cornerRadius: tokens.badgeCornerRadius)
                    .strokeBorder(tokens.cardBorderColor(for: colorScheme), lineWidth: 1)
            }

        case .warmFinance:
            EmptyView()
        }
    }

    private func chipShadowColor(tokens: UIStyleTokens) -> Color {
        guard isSelected else { return .clear }

        switch style {
        case .midnightAurora:
            return auroraAccentBlue.opacity(0.3)
        case .defaultStyle:
            return tokens.primaryColor(for: colorScheme).opacity(0.3)
        case .warmFinance:
            return tokens.primaryColor(for: colorScheme).opacity(0.2)
        case .paperMinimal:
            return .clear
        }
    }
}

// MARK: - Styled Filter Bar Container

/// Container for the filter bar that adapts to the current UI style
/// For Midnight Aurora: NO container background - chips float directly (matches demo)
/// For other styles: Glass/solid container background
struct StyledFilterBarContainer<Content: View>: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    // Fixed height for the filter bar - prevents vertical expansion
    private let filterBarHeight: CGFloat = 52

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        switch style {
        case .midnightAurora:
            // Midnight Aurora: NO container - just floating chips (matches demo)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    content()
                }
                .padding(.horizontal, 4)
                .frame(height: filterBarHeight) // Lock content height
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal) // Prevent vertical bounce
            .frame(height: filterBarHeight) // Lock ScrollView height
            .padding(.horizontal, Spacing.md)

        default:
            // Other styles: Use container background
            ZStack {
                containerBackground(tokens: tokens)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        content()
                    }
                    .padding(.horizontal, Spacing.sm)
                    .frame(height: filterBarHeight) // Lock content height
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal) // Prevent vertical bounce
            }
            .frame(height: filterBarHeight) // Lock container height
            .padding(.horizontal, Spacing.md)
        }
    }

    @ViewBuilder
    private func containerBackground(tokens: UIStyleTokens) -> some View {
        let shape = RoundedRectangle(cornerRadius: tokens.inputCornerRadius, style: .continuous)

        switch style {
        case .midnightAurora:
            // Not used - Midnight Aurora has no container
            EmptyView()

        case .defaultStyle:
            CardMaterial(cornerRadius: 12, addHighlight: false)
                .overlay { GlassBorder(cornerRadius: 12, lineWidth: 0.5) }

        case .paperMinimal:
            shape
                .fill(tokens.cardBackgroundColor(for: colorScheme))
                .overlay {
                    shape.strokeBorder(tokens.cardBorderColor(for: colorScheme), lineWidth: 1)
                }

        case .warmFinance:
            shape
                .fill(tokens.cardBackgroundColor(for: colorScheme))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.05), radius: 4, y: 2)
        }
    }
}

// MARK: - Styled Suggestion Card

/// Inline suggestion card that adapts to the current UI style
struct StyledSuggestionCard: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let candidate: RecurringCandidate
    let totalCount: Int
    let onAccept: () -> Void
    let onDismiss: () -> Void
    let onSnooze: () -> Void

    @State private var isProcessing = false

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Main content
            HStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: candidate.documentCategory.iconName)
                    .font(.title3)
                    .foregroundStyle(tokens.primaryColor(for: colorScheme))
                    .frame(width: 36, height: 36)
                    .background(tokens.primaryColor(for: colorScheme).opacity(0.1))
                    .clipShape(Circle())

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.vendorDisplayName)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))
                        .lineLimit(1)

                    Text(suggestionMessage)
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                // Confidence badge
                Text("\(Int(candidate.confidenceScore * 100))%")
                    .font(Typography.stat.weight(.semibold))
                    .foregroundStyle(confidenceColor(tokens: tokens))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(confidenceColor(tokens: tokens).opacity(0.15))
                    .clipShape(Capsule())
            }

            // Action buttons
            HStack(spacing: Spacing.xs) {
                // Dismiss button
                Button(action: {
                    isProcessing = true
                    onDismiss()
                }) {
                    Text(L10n.RecurringSuggestions.dismiss.localized)
                        .font(Typography.buttonText)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isProcessing)

                // Snooze button
                Button(action: {
                    isProcessing = true
                    onSnooze()
                }) {
                    Text(L10n.RecurringSuggestions.snooze.localized)
                        .font(Typography.buttonText)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isProcessing)

                Spacer()

                // Accept button
                Button(action: {
                    isProcessing = true
                    onAccept()
                }) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text(L10n.RecurringSuggestions.accept.localized)
                            .font(Typography.buttonText)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(tokens.primaryColor(for: colorScheme))
                .disabled(isProcessing)
            }

            // Show count if more suggestions
            if totalCount > 1 {
                Text(L10n.RecurringSuggestions.moreSuggestions.localized(with: totalCount - 1))
                    .font(Typography.stat)
                    .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
            }
        }
        .padding(Spacing.sm)
        .background {
            cardBackground(tokens: tokens)
        }
        .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
        .overlay {
            cardBorder(tokens: tokens)
        }
        .modifier(SuggestionCardShadowModifier(tokens: tokens))
    }

    @ViewBuilder
    private func cardBackground(tokens: UIStyleTokens) -> some View {
        let shape = RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)

        switch style {
        case .midnightAurora:
            // ENHANCED: Multi-layer card background
            EnhancedMidnightAuroraCard(accentColor: tokens.primaryColor(for: colorScheme))

        case .defaultStyle:
            CardMaterial(cornerRadius: tokens.cardCornerRadius, addHighlight: false)

        case .paperMinimal:
            shape.fill(tokens.cardBackgroundColor(for: colorScheme))

        case .warmFinance:
            shape.fill(tokens.cardBackgroundColor(for: colorScheme))
        }
    }

    @ViewBuilder
    private func cardBorder(tokens: UIStyleTokens) -> some View {
        let shape = RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
        let accentColor = tokens.primaryColor(for: colorScheme)

        switch style {
        case .midnightAurora:
            // Border is already applied by EnhancedMidnightAuroraCard
            EmptyView()

        case .defaultStyle:
            GlassBorder(cornerRadius: tokens.cardCornerRadius, lineWidth: 1, accentColor: accentColor.opacity(0.5))

        case .paperMinimal:
            shape.strokeBorder(accentColor.opacity(0.3), lineWidth: 1)

        case .warmFinance:
            EmptyView()
        }
    }

    private var suggestionMessage: String {
        let count = candidate.documentCount
        if let dueDay = candidate.dominantDueDayOfMonth {
            return L10n.RecurringSuggestions.inlineDescription.localized(with: count, dueDay)
        } else {
            return L10n.RecurringSuggestions.inlineDescriptionNoDueDay.localized(with: count)
        }
    }

    private func confidenceColor(tokens: UIStyleTokens) -> Color {
        if candidate.confidenceScore >= 0.9 {
            return tokens.successColor(for: colorScheme)
        } else if candidate.confidenceScore >= 0.8 {
            return tokens.primaryColor(for: colorScheme)
        } else {
            return tokens.warningColor(for: colorScheme)
        }
    }
}

private struct SuggestionCardShadowModifier: ViewModifier {
    let tokens: UIStyleTokens

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if !tokens.usesShadows {
            content
        } else {
            switch style {
            case .midnightAurora:
                // ENHANCED: Dual shadow system
                content
                    .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
                    .shadow(color: tokens.primaryColor(for: colorScheme).opacity(0.2), radius: 15, y: 8)

            default:
                let shadow = tokens.cardShadow(for: colorScheme)
                content.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
            }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies the styled document list background for the current UI style
    func styledDocumentListBackground() -> some View {
        background { StyledDocumentListBackground() }
    }
}
