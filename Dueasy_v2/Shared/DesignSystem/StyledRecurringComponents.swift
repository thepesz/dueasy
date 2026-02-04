import SwiftUI

// MARK: - Styled Recurring Components
//
// UI components for RecurringOverviewView that automatically adapt their appearance
// based on the current UIStyleProposal. These follow the same pattern as
// StyledHomeCard and related components in UIStyleComponents.swift.

// MARK: - Styled Recurring Background

/// Background for the recurring overview that adapts to the current UI style.
struct StyledRecurringBackground: View {

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
            // Pure flat background
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

// MARK: - Styled Upcoming Instance Card

/// Card for upcoming recurring payment instance that adapts to current UI style
struct StyledUpcomingInstanceCard: View {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppEnvironment.self) private var environment

    let instance: RecurringInstance
    let template: RecurringTemplate
    let onMarkAsPaid: () -> Void

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(template.vendorDisplayName)
                        .font(Typography.listRowPrimary)

                    Text(dueDateText(tokens: tokens))
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(dueDateColor(tokens: tokens))
                }

                Spacer()

                if let amount = instance.effectiveAmount {
                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        Text(formatAmount(amount, currency: template.currency))
                            .font(Typography.listRowAmount())

                        StyledRecurringInstanceBadge(status: instance.status)
                    }
                }
            }

            if instance.status == .expected || instance.status == .matched {
                Button(action: onMarkAsPaid) {
                    Label(L10n.Detail.markAsPaid.localized, systemImage: "checkmark.circle")
                        .font(Typography.buttonText)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tokens.successColor(for: colorScheme))
            }
        }
        .padding(tokens.cardPadding)
        .background {
            cardBackground(tokens: tokens)
        }
        .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
        .modifier(StyledRecurringCardShadowModifier(tokens: tokens))
    }

    @ViewBuilder
    private func cardBackground(tokens: UIStyleTokens) -> some View {
        switch style {
        case .midnightAurora:
            // ENHANCED: Multi-layer card
            EnhancedMidnightAuroraCard(accentColor: tokens.primaryColor(for: colorScheme))

        case .defaultStyle:
            CardMaterial(cornerRadius: tokens.cardCornerRadius, addHighlight: true)
                .overlay { GlassBorder(cornerRadius: tokens.cardCornerRadius) }

        case .paperMinimal:
            RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                .fill(tokens.cardBackgroundColor(for: colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                        .strokeBorder(tokens.cardBorderColor(for: colorScheme), lineWidth: 1)
                }

        case .warmFinance:
            RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                .fill(tokens.cardBackgroundColor(for: colorScheme))
        }
    }

    // MARK: - Helpers

    private func dueDateText(tokens: UIStyleTokens) -> String {
        let days = instance.daysUntilDue(using: environment.recurringDateService)
        if days == 0 {
            return L10n.RecurringInstance.dueToday.localized
        } else if days > 0 {
            return L10n.RecurringInstance.dueIn.localized(with: days)
        } else {
            return L10n.RecurringInstance.overdue.localized(with: abs(days))
        }
    }

    private func dueDateColor(tokens: UIStyleTokens) -> Color {
        let days = instance.daysUntilDue(using: environment.recurringDateService)
        if days < 0 {
            return tokens.errorColor(for: colorScheme)
        } else if days <= 3 {
            return tokens.warningColor(for: colorScheme)
        } else {
            return .secondary
        }
    }

    private func formatAmount(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }
}

// MARK: - Styled Recurring Template Card

/// Card for recurring template that adapts to current UI style
struct StyledRecurringTemplateCard: View {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let template: RecurringTemplate
    let onPause: () -> Void
    let onResume: () -> Void
    let onDelete: () -> Void

    @State private var showActions: Bool = false

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                // Category icon
                categoryIcon(tokens: tokens)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(template.vendorDisplayName)
                        .font(Typography.listRowPrimary)

                    Text(L10n.Recurring.dueDayValue.localized(with: template.dueDayOfMonth))
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status indicator
                if !template.isActive {
                    Text(L10n.Recurring.pausedTemplates.localized)
                        .font(Typography.stat)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(pausedBadgeBackground(tokens: tokens))
                }

                // Menu button
                Menu {
                    if template.isActive {
                        Button(action: onPause) {
                            Label(L10n.Recurring.pauseTemplate.localized, systemImage: "pause.circle")
                        }
                    } else {
                        Button(action: onResume) {
                            Label(L10n.Recurring.resumeTemplate.localized, systemImage: "play.circle")
                        }
                    }

                    Divider()

                    Button(role: .destructive, action: onDelete) {
                        Label(L10n.Recurring.deleteTemplate.localized, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            // Stats row
            HStack(spacing: Spacing.md) {
                StyledStatItem(
                    value: template.matchedDocumentCount,
                    label: L10n.Recurring.matchedCount.localized(with: template.matchedDocumentCount)
                )
                StyledStatItem(
                    value: template.paidInstanceCount,
                    label: L10n.Recurring.paidCount.localized(with: template.paidInstanceCount)
                )
                if template.missedInstanceCount > 0 {
                    StyledStatItem(
                        value: template.missedInstanceCount,
                        label: L10n.Recurring.missedCount.localized(with: template.missedInstanceCount),
                        color: tokens.errorColor(for: colorScheme)
                    )
                }
            }
        }
        .padding(tokens.cardPadding)
        .background {
            cardBackground(tokens: tokens)
        }
        .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
        .modifier(StyledRecurringCardShadowModifier(tokens: tokens))
    }

    @ViewBuilder
    private func categoryIcon(tokens: UIStyleTokens) -> some View {
        let primary = tokens.primaryColor(for: colorScheme)

        Image(systemName: template.documentCategory.iconName)
            .font(.title2)
            .foregroundStyle(primary)
            .frame(width: 40, height: 40)
            .background(iconBackground(tokens: tokens, color: primary))
            .clipShape(Circle())
            .overlay {
                if style == .midnightAurora {
                    Circle()
                        .strokeBorder(primary.opacity(0.3), lineWidth: 1)
                }
            }
    }

    @ViewBuilder
    private func iconBackground(tokens: UIStyleTokens, color: Color) -> some View {
        switch style {
        case .midnightAurora:
            LinearGradient(
                colors: [color.opacity(0.25), color.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        default:
            color.opacity(0.1)
        }
    }

    @ViewBuilder
    private func pausedBadgeBackground(tokens: UIStyleTokens) -> some View {
        switch style {
        case .midnightAurora:
            Capsule()
                .fill(Color.black.opacity(0.5))
                .overlay {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                }

        default:
            Color.secondary.opacity(0.2)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func cardBackground(tokens: UIStyleTokens) -> some View {
        switch style {
        case .midnightAurora:
            EnhancedMidnightAuroraCard(accentColor: nil)

        case .defaultStyle:
            CardMaterial(cornerRadius: tokens.cardCornerRadius, addHighlight: true)
                .overlay { GlassBorder(cornerRadius: tokens.cardCornerRadius) }

        case .paperMinimal:
            RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                .fill(tokens.cardBackgroundColor(for: colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                        .strokeBorder(tokens.cardBorderColor(for: colorScheme), lineWidth: 1)
                }

        case .warmFinance:
            RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                .fill(tokens.cardBackgroundColor(for: colorScheme))
        }
    }
}

// MARK: - Styled Recurring Instance Badge

/// Status badge for recurring instances that adapts to current UI style
struct StyledRecurringInstanceBadge: View {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let status: RecurringInstanceStatus

    var body: some View {
        let tokens = UIStyleTokens(style: style)
        let statusColor = color(tokens: tokens)

        HStack(spacing: Spacing.xxs) {
            if style == .midnightAurora {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                    .shadow(color: statusColor.opacity(0.6), radius: 2)
            } else {
                Image(systemName: status.iconName)
                    .font(.caption)
            }
            Text(status.displayName)
                .font(Typography.stat)
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(badgeBackground(tokens: tokens, color: statusColor))
    }

    @ViewBuilder
    private func badgeBackground(tokens: UIStyleTokens, color: Color) -> some View {
        switch style {
        case .midnightAurora:
            Capsule()
                .fill(Color.black.opacity(0.5))
                .overlay {
                    Capsule()
                        .fill(color.opacity(0.25))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(color.opacity(0.6), lineWidth: 1)
                }

        default:
            Capsule()
                .fill(color.opacity(0.15))
        }
    }

    private func color(tokens: UIStyleTokens) -> Color {
        switch status {
        case .expected:
            return .secondary
        case .matched:
            return tokens.primaryColor(for: colorScheme)
        case .paid:
            return tokens.successColor(for: colorScheme)
        case .missed:
            return tokens.errorColor(for: colorScheme)
        case .cancelled:
            return .gray
        }
    }
}

// MARK: - Styled Stat Item

/// Stat item that adapts to current UI style
struct StyledStatItem: View {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let value: Int
    let label: String
    var color: Color = .secondary

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Text("\(value)")
                .font(Typography.statBold)
                .foregroundStyle(color)

            Text(label)
                .font(Typography.stat)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Styled Empty Templates View

/// Empty state for templates section that adapts to current UI style
struct StyledEmptyTemplatesView: View {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let showPaused: Bool

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        VStack(spacing: Spacing.md) {
            Image(systemName: showPaused ? "pause.circle" : "repeat.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(showPaused ? L10n.Recurring.pausedTemplates.localized : L10n.Recurring.noTemplates.localized)
                .font(Typography.listRowPrimary)

            Text(showPaused ? "" : L10n.Recurring.noTemplatesMessage.localized)
                .font(Typography.bodyText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, tokens.cardPadding)
        .background {
            cardBackground(tokens: tokens)
        }
        .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
        .modifier(StyledRecurringCardShadowModifier(tokens: tokens))
    }

    @ViewBuilder
    private func cardBackground(tokens: UIStyleTokens) -> some View {
        switch style {
        case .midnightAurora:
            EnhancedMidnightAuroraCard(accentColor: nil)

        case .defaultStyle:
            CardMaterial(cornerRadius: tokens.cardCornerRadius, addHighlight: true)
                .overlay { GlassBorder(cornerRadius: tokens.cardCornerRadius) }

        case .paperMinimal:
            RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                .fill(tokens.cardBackgroundColor(for: colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                        .strokeBorder(tokens.cardBorderColor(for: colorScheme), lineWidth: 1)
                }

        case .warmFinance:
            RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                .fill(tokens.cardBackgroundColor(for: colorScheme))
        }
    }
}

// MARK: - Shadow Modifier

private struct StyledRecurringCardShadowModifier: ViewModifier {
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
                    .shadow(color: Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.15), radius: 15, y: 8)

            default:
                let shadow = tokens.cardShadow(for: colorScheme)
                content.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
            }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies the styled recurring background for the current UI style
    func styledRecurringBackground() -> some View {
        background { StyledRecurringBackground() }
    }
}
