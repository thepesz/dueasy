import SwiftUI

// MARK: - Styled Calendar Components
//
// UI components for CalendarView that automatically adapt their appearance
// based on the current UIStyleProposal. These follow the same pattern as
// StyledHomeCard and related components in UIStyleComponents.swift.

// MARK: - Styled Calendar Background

/// Background for the calendar view that adapts to the current UI style.
/// Uses style-specific gradients and colors.
struct StyledCalendarBackground: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        switch style {
        case .defaultStyle:
            // Original gradient background
            GradientBackground()

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

// MARK: - Styled Calendar Day Cell

/// Calendar day cell that adapts to the current UI style
struct StyledCalendarDayCell: View {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let day: Int
    let isToday: Bool
    let isSelected: Bool
    let summary: CalendarDaySummary?
    let recurringSummary: CalendarRecurringSummary?
    let combinedPriority: CalendarCombinedPriority
    let showRecurringOnly: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        Button(action: action) {
            ZStack {
                // Background with style-specific styling
                cellBackground(tokens: tokens)

                // Day number and indicator
                VStack(spacing: 3) {
                    Text("\(day)")
                        .font(isToday || isSelected ? Typography.bodyBold : Typography.body)
                        .foregroundStyle(textColor(tokens: tokens))

                    // Indicator dots
                    HStack(spacing: 2) {
                        // Document indicator
                        if !showRecurringOnly, let summary = summary, summary.totalCount > 0 {
                            indicatorDot(color: indicatorColor(for: summary.priority, tokens: tokens))
                        }

                        // Recurring indicator
                        if let recurringSummary = recurringSummary, recurringSummary.totalCount > 0 {
                            indicatorDot(color: recurringIndicatorColor(for: recurringSummary.priority, tokens: tokens), isDotted: recurringSummary.expectedCount > 0)
                        }
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendar_day_\(day)")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !reduceMotion && !isPressed {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    if !reduceMotion {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                            isPressed = false
                        }
                    }
                }
        )
    }

    // MARK: - Cell Background

    @ViewBuilder
    private func cellBackground(tokens: UIStyleTokens) -> some View {
        if isSelected {
            selectedBackground(tokens: tokens)
        } else if isToday {
            todayBackground(tokens: tokens)
        } else if !reduceTransparency {
            defaultBackground(tokens: tokens)
        }
    }

    @ViewBuilder
    private func selectedBackground(tokens: UIStyleTokens) -> some View {
        switch style {
        case .midnightAurora:
            // ENHANCED: Vibrant gradient with glow using AuroraPalette
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(AuroraGradients.accentPrimary)
                .shadow(color: AuroraPalette.accentBlue.opacity(0.5), radius: 8, y: 4)

        default:
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(
                    LinearGradient(
                        colors: [AppColors.primary, AppColors.primary.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: AppColors.primary.opacity(0.4), radius: 6, y: 3)
        }
    }

    @ViewBuilder
    private func todayBackground(tokens: UIStyleTokens) -> some View {
        switch style {
        case .midnightAurora:
            // ENHANCED: Subtle glow ring using AuroraPalette
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(AuroraPalette.accentBlue.opacity(0.2))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .strokeBorder(
                            LinearGradient(
                                colors: [AuroraPalette.accentBlue.opacity(0.8), AuroraPalette.accentPurple.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }

        default:
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(AppColors.primary.opacity(0.15))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .strokeBorder(AppColors.primary.opacity(0.5), lineWidth: 1.5)
                }
        }
    }

    @ViewBuilder
    private func defaultBackground(tokens: UIStyleTokens) -> some View {
        switch style {
        case .midnightAurora:
            // ENHANCED: Multi-layer dark card using AuroraPalette
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(AuroraPalette.sectionBacking)
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(AuroraPalette.sectionGlass)
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .strokeBorder(AuroraPalette.sectionBorder, lineWidth: 0.5)
            }

        case .paperMinimal:
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(tokens.cardBackgroundColor(for: colorScheme))

        default:
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.white.opacity(colorScheme == .light ? 0.3 : 0.05))
        }
    }

    // MARK: - Indicator Dot

    @ViewBuilder
    private func indicatorDot(color: Color, isDotted: Bool = false) -> some View {
        switch style {
        case .midnightAurora:
            // ENHANCED: Glowing dots
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color.opacity(0.6), radius: 2)
                .overlay {
                    if isDotted {
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .foregroundStyle(color)
                            .frame(width: 7, height: 7)
                    }
                }

        default:
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .overlay {
                    if isDotted {
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .foregroundStyle(color)
                            .frame(width: 7, height: 7)
                    }
                }
        }
    }

    // MARK: - Colors

    private func textColor(tokens: UIStyleTokens) -> Color {
        if isSelected {
            return .white
        } else if isToday {
            switch style {
            case .midnightAurora:
                return AuroraPalette.accentBlue
            default:
                return AppColors.primary
            }
        } else {
            // For Midnight Aurora, use high-contrast white text
            switch style {
            case .midnightAurora:
                return AuroraPalette.textPrimary
            default:
                return .primary
            }
        }
    }

    private func indicatorColor(for priority: CalendarDayPriority, tokens: UIStyleTokens) -> Color {
        switch priority {
        case .overdue:
            return tokens.errorColor(for: colorScheme)
        case .scheduled:
            return tokens.warningColor(for: colorScheme)
        case .draft:
            return .gray
        case .paid:
            return tokens.successColor(for: colorScheme)
        }
    }

    private func recurringIndicatorColor(for priority: CalendarRecurringPriority, tokens: UIStyleTokens) -> Color {
        switch priority {
        case .overdue:
            return tokens.errorColor(for: colorScheme)
        case .expected:
            return tokens.primaryColor(for: colorScheme)
        case .matched:
            return tokens.warningColor(for: colorScheme)
        case .paid:
            return tokens.successColor(for: colorScheme)
        case .missed:
            return .gray
        }
    }
}

// MARK: - Styled Calendar Selected Day Section

/// Selected day section background that adapts to current UI style
struct StyledCalendarSelectedDaySection<Content: View>: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        ZStack {
            // Background layer - separate from content for proper clipping
            sectionBackground(tokens: tokens)

            // Content layer with proper clipping applied directly
            content()
                .frame(maxHeight: .infinity)
                // Apply clipShape to content to prevent scroll overflow during scrolling
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
        }
        // Clip the entire ZStack to ensure nothing escapes
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
    }

    @ViewBuilder
    private func sectionBackground(tokens: UIStyleTokens) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)

        switch style {
        case .midnightAurora:
            // ENHANCED: Multi-layer card using AuroraPalette for consistency
            ZStack {
                // Layer 1: Solid dark backing
                cardShape
                    .fill(AuroraPalette.sectionBacking)
                // Layer 2: Glass overlay
                cardShape
                    .fill(AuroraPalette.sectionGlass)
                // Layer 3: Gradient border
                cardShape
                    .strokeBorder(
                        LinearGradient(
                            colors: [AuroraPalette.cardBorderHighlight, AuroraPalette.cardBorderBase],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: AuroraPalette.cardBorderWidth
                    )
            }
            .shadow(color: Color.black.opacity(0.3), radius: 8, y: -2)

        case .paperMinimal:
            cardShape
                .fill(tokens.cardBackgroundColor(for: colorScheme))
                .overlay {
                    cardShape
                        .strokeBorder(tokens.cardBorderColor(for: colorScheme), lineWidth: 1)
                }

        default:
            if reduceTransparency {
                cardShape
                    .fill(tokens.cardBackgroundColor(for: colorScheme))
            } else {
                CardMaterial(cornerRadius: CornerRadius.xl)
                    .overlay { GlassBorder(cornerRadius: CornerRadius.xl) }
                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: -4)
            }
        }
    }
}

// MARK: - Styled Recurring Instance Row

/// Recurring instance row that adapts to the current UI style
struct StyledRecurringInstanceRow: View {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppEnvironment.self) private var environment

    let instance: RecurringInstance
    let onMarkAsPaid: () -> Void
    let onViewDocument: UUID?
    let onDelete: () -> Void

    @State private var showingActions = false

    var body: some View {
        let tokens = UIStyleTokens(style: style)
        let statusColor = statusColor(tokens: tokens)

        HStack(spacing: Spacing.md) {
            // Status icon
            statusIcon(tokens: tokens, statusColor: statusColor)

            // Content
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Text(L10n.CalendarView.expectedPayment.localized)
                        .font(Typography.listRowPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Status badge
                    statusBadge(tokens: tokens, statusColor: statusColor)
                }

                // Amount and due info
                HStack {
                    if let amount = instance.effectiveAmount {
                        Text(formatAmount(amount))
                            .font(Typography.listRowSecondary.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    dueLabel(tokens: tokens)
                }
            }
        }
        .padding(Spacing.md)
        .background {
            rowBackground(tokens: tokens, statusColor: statusColor)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingActions = true
        }
        .confirmationDialog(
            L10n.CalendarView.expectedPayment.localized,
            isPresented: $showingActions,
            titleVisibility: .visible
        ) {
            if instance.status == .expected || instance.status == .matched {
                Button(L10n.CalendarView.markAsPaid.localized) {
                    onMarkAsPaid()
                }
            }
            if let _ = onViewDocument {
                Button(L10n.CalendarView.viewDocument.localized) {
                    // Navigation handled by parent
                }
            }
            Button(L10n.Common.delete.localized, role: .destructive) {
                onDelete()
            }
            Button(L10n.Common.cancel.localized, role: .cancel) {}
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func statusIcon(tokens: UIStyleTokens, statusColor: Color) -> some View {
        Image(systemName: instance.status.iconName)
            .font(.title3)
            .foregroundStyle(statusColor)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(statusColor.opacity(0.15))
            )
            .overlay {
                if style == .midnightAurora {
                    Circle()
                        .strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
                }
            }
    }

    @ViewBuilder
    private func statusBadge(tokens: UIStyleTokens, statusColor: Color) -> some View {
        HStack(spacing: 3) {
            if style == .midnightAurora {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                    .shadow(color: statusColor.opacity(0.6), radius: 2)
            }

            Text(instance.status.displayName)
                .font(Typography.stat.weight(.medium))
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background {
            switch style {
            case .midnightAurora:
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

            default:
                Capsule()
                    .fill(statusColor.opacity(0.15))
            }
        }
    }

    @ViewBuilder
    private func dueLabel(tokens: UIStyleTokens) -> some View {
        let days = instance.daysUntilDue(using: environment.recurringDateService)
        Group {
            if days == 0 {
                Text(L10n.RecurringInstance.dueToday.localized)
                    .foregroundStyle(tokens.warningColor(for: colorScheme))
            } else if days < 0 {
                Text(String.localized(L10n.RecurringInstance.overdue, with: abs(days)))
                    .foregroundStyle(tokens.errorColor(for: colorScheme))
            } else {
                Text(String.localized(L10n.RecurringInstance.dueIn, with: days))
                    .foregroundStyle(.secondary)
            }
        }
        .font(Typography.listRowSecondary)
    }

    @ViewBuilder
    private func rowBackground(tokens: UIStyleTokens, statusColor: Color) -> some View {
        switch style {
        case .midnightAurora:
            // ENHANCED: Multi-layer card using AuroraPalette
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(AuroraPalette.sectionBacking)
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(AuroraPalette.sectionGlass)

                // Dotted border for expected instances
                if instance.status == .expected {
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(AuroraPalette.accentBlue.opacity(0.5))
                } else {
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [AuroraPalette.cardBorderHighlight, AuroraPalette.cardBorderBase],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: AuroraPalette.cardBorderWidth
                        )
                }
            }

        default:
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(colorScheme == .light ? Color.white.opacity(0.6) : Color.white.opacity(0.05))
                .overlay {
                    if instance.status == .expected {
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                            .foregroundStyle(AppColors.primary.opacity(0.5))
                    } else {
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
                    }
                }
        }
    }

    // MARK: - Helpers

    private func statusColor(tokens: UIStyleTokens) -> Color {
        switch instance.status {
        case .expected:
            return tokens.primaryColor(for: colorScheme)
        case .matched:
            return tokens.warningColor(for: colorScheme)
        case .paid:
            return tokens.successColor(for: colorScheme)
        case .missed:
            return tokens.errorColor(for: colorScheme)
        case .cancelled:
            return .secondary
        }
    }

    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "PLN"
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - Styled Month Header

/// Month navigation header that adapts to the current UI style
struct StyledMonthHeader: View {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let monthName: String
    let isCurrentMonth: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tokens.primaryColor(for: colorScheme))
                    .frame(width: 44, height: 44)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(monthName)
                    .font(Typography.title3)
                    .foregroundStyle(style == .midnightAurora ? AuroraPalette.textPrimary : .primary)

                if !isCurrentMonth {
                    Button(action: onToday) {
                        Text(L10n.CalendarView.today.localized)
                            .font(Typography.buttonText)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(todayButtonBackground(tokens: tokens))
                    }
                }
            }

            Spacer()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tokens.primaryColor(for: colorScheme))
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
    }

    @ViewBuilder
    private func todayButtonBackground(tokens: UIStyleTokens) -> some View {
        switch style {
        case .midnightAurora:
            Capsule()
                .fill(AuroraGradients.accentPrimary)
                .shadow(color: AuroraPalette.accentBlue.opacity(0.4), radius: 4, y: 2)

        default:
            Capsule()
                .fill(AppColors.primary)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies the styled calendar background for the current UI style
    func styledCalendarBackground() -> some View {
        background { StyledCalendarBackground() }
    }
}
