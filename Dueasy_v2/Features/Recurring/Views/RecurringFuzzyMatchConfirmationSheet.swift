import SwiftUI

/// Modal sheet for fuzzy match confirmation when creating a recurring template.
///
/// Presented when a new document has an amount that is 30-50% different from an existing
/// recurring template from the same vendor. The user must decide:
/// 1. "Same Service" - Link to existing template (variable amount, same payment)
/// 2. "Different Service" - Create a new template (different payment from same vendor)
///
/// Example scenario:
/// - User has Santander template with 173 PLN
/// - User scans new Santander invoice for 250 PLN (44% difference)
/// - Sheet asks: "Is this the same recurring payment?"
///
/// Uses iOS 26 Liquid Glass aesthetic.
/// Supports accessibility (Reduce Motion, VoiceOver).
struct RecurringFuzzyMatchConfirmationSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.uiStyle) private var uiStyle

    /// Design tokens for the current style
    private var tokens: UIStyleTokens {
        UIStyleTokens(style: uiStyle)
    }

    /// The fuzzy match candidates to choose from
    let candidates: [FuzzyMatchCandidate]

    /// The new amount from the document being saved
    let newAmount: Decimal

    /// Currency code for formatting
    let currency: String

    /// Callback when user confirms "Same Service" - link to this template
    let onSameService: (UUID) -> Void

    /// Callback when user confirms "Different Service" - create new template
    let onDifferentService: () -> Void

    /// Callback when user cancels (recurring toggle will be turned off)
    let onCancel: () -> Void

    /// Selected candidate for multiple-choice scenario
    @State private var selectedCandidateId: UUID?

    /// Whether Aurora style is active
    private var isAurora: Bool {
        uiStyle == .midnightAurora
    }

    /// The primary candidate (first/closest match)
    private var primaryCandidate: FuzzyMatchCandidate? {
        candidates.first
    }

    /// Whether there are multiple candidates to choose from
    private var hasMultipleCandidates: Bool {
        candidates.count > 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Header with icon and question
                    headerSection

                    // Amount comparison
                    amountComparisonSection

                    // Candidate selection (if multiple)
                    if hasMultipleCandidates {
                        candidateSelectionSection
                    }

                    // Action buttons
                    actionButtonsSection
                }
                .padding(Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .scrollContentBackground(.hidden)
            .background {
                tokens.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()
            }
            .navigationTitle(L10n.RecurringFuzzyMatch.title.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel.localized) {
                        onCancel()
                        dismiss()
                    }
                    .foregroundStyle(isAurora ? Color.white : .primary)
                }
            }
        }
        .onAppear {
            // Pre-select the first candidate
            if selectedCandidateId == nil {
                selectedCandidateId = primaryCandidate?.id
            }
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        StyledGlassCard {
            VStack(spacing: Spacing.sm) {
                // Icon
                ZStack {
                    Circle()
                        .fill(AppColors.warning.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(AppColors.warning)
                        .symbolRenderingMode(.hierarchical)
                }

                // Question text
                Text(L10n.RecurringFuzzyMatch.question.localized)
                    .font(Typography.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isAurora ? Color.white : .primary)

                // Subtitle
                Text(L10n.RecurringFuzzyMatch.subtitle.localized)
                    .font(Typography.body)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.7) : .secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Amount Comparison Section

    @ViewBuilder
    private var amountComparisonSection: some View {
        if let candidate = selectedCandidate {
            StyledGlassCard {
                VStack(spacing: Spacing.md) {
                    // Existing template info
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(L10n.RecurringFuzzyMatch.existingAmount.localized(with: formatAmount(candidate.existingTypicalAmount)))
                                .font(Typography.bodyBold)
                                .foregroundStyle(isAurora ? Color.white : .primary)

                            Text(candidate.vendorDisplayName)
                                .font(Typography.caption1)
                                .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)

                            if candidate.matchedCount > 0 {
                                Text(L10n.RecurringFuzzyMatch.matchedInvoices.localized(with: candidate.matchedCount))
                                    .font(Typography.caption2)
                                    .foregroundStyle(isAurora ? Color.white.opacity(0.5) : Color.secondary.opacity(0.6))
                            }
                        }

                        Spacer()

                        // Percent difference badge
                        Text(L10n.RecurringFuzzyMatch.percentDifference.localized(with: candidate.formattedPercentDifference))
                            .font(Typography.caption1.weight(.medium))
                            .foregroundStyle(AppColors.warning)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                Capsule()
                                    .fill(AppColors.warning.opacity(0.15))
                            )
                    }

                    Divider()
                        .opacity(isAurora ? 0.3 : 1.0)

                    // New amount
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(L10n.RecurringFuzzyMatch.newAmount.localized(with: formatAmount(newAmount)))
                                .font(Typography.bodyBold)
                                .foregroundStyle(isAurora ? Color.white : .primary)

                            Text(L10n.RecurringFuzzyMatch.dueDayInfo.localized(with: candidate.dueDayOfMonth))
                                .font(Typography.caption1)
                                .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
                        }

                        Spacer()

                        // Arrow indicating change direction
                        Image(systemName: newAmount > candidate.existingTypicalAmount ? "arrow.up.right" : "arrow.down.right")
                            .font(.title3)
                            .foregroundStyle(newAmount > candidate.existingTypicalAmount ? AppColors.error : AppColors.success)
                    }
                }
            }
        }
    }

    // MARK: - Candidate Selection Section (Multiple Candidates)

    @ViewBuilder
    private var candidateSelectionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(L10n.RecurringFuzzyMatch.selectTemplate.localized)
                .font(Typography.caption1)
                .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
                .padding(.horizontal, Spacing.xs)

            ForEach(candidates) { candidate in
                Button {
                    selectedCandidateId = candidate.id
                } label: {
                    HStack(spacing: Spacing.md) {
                        // Selection indicator
                        Image(systemName: selectedCandidateId == candidate.id ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedCandidateId == candidate.id ? AppColors.primary : (isAurora ? Color.white.opacity(0.4) : .secondary))

                        // Candidate info
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(formatAmount(candidate.existingTypicalAmount))
                                .font(Typography.bodyBold)
                                .foregroundStyle(isAurora ? Color.white : .primary)

                            Text(candidate.formattedPercentDifference + " " + L10n.RecurringFuzzyMatch.percentDifference.localized(with: ""))
                                .font(Typography.caption1)
                                .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
                        }

                        Spacer()
                    }
                    .padding(Spacing.md)
                    .background {
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .fill(isAurora ? Color.white.opacity(0.08) : Color(UIColor.secondarySystemGroupedBackground))
                    }
                    .overlay {
                        if selectedCandidateId == candidate.id {
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .strokeBorder(AppColors.primary, lineWidth: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Action Buttons Section

    @ViewBuilder
    private var actionButtonsSection: some View {
        VStack(spacing: Spacing.sm) {
            // Same Service button (Primary action)
            FuzzyMatchOptionButton(
                title: L10n.RecurringFuzzyMatch.sameService.localized,
                description: L10n.RecurringFuzzyMatch.sameServiceDescription.localized,
                icon: "link.circle.fill",
                isPrimary: true,
                isAurora: isAurora
            ) {
                if let candidateId = selectedCandidateId,
                   let candidate = candidates.first(where: { $0.id == candidateId }) {
                    onSameService(candidate.templateId)
                    dismiss()
                }
            }

            // Different Service button (Secondary action)
            FuzzyMatchOptionButton(
                title: L10n.RecurringFuzzyMatch.differentService.localized,
                description: L10n.RecurringFuzzyMatch.differentServiceDescription.localized,
                icon: "plus.circle.fill",
                isPrimary: false,
                isAurora: isAurora
            ) {
                onDifferentService()
                dismiss()
            }
        }
    }

    // MARK: - Helpers

    private var selectedCandidate: FuzzyMatchCandidate? {
        if let id = selectedCandidateId {
            return candidates.first { $0.id == id }
        }
        return primaryCandidate
    }

    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }
}

// MARK: - Fuzzy Match Option Button

/// A styled option button for fuzzy match confirmation.
struct FuzzyMatchOptionButton: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let description: String
    let icon: String
    let isPrimary: Bool
    let isAurora: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                // Icon
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isPrimary ? .white : (isAurora ? AppColors.primary : AppColors.primary))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isPrimary ? AppColors.primary : AppColors.primary.opacity(0.15))
                    )

                // Text content
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Typography.bodyBold)
                        .foregroundStyle(isPrimary ? .white : (isAurora ? Color.white : .primary))

                    Text(description)
                        .font(Typography.caption1)
                        .foregroundStyle(isPrimary ? Color.white.opacity(0.8) : (isAurora ? Color.white.opacity(0.6) : .secondary))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPrimary ? Color.white.opacity(0.6) : (isAurora ? Color.white.opacity(0.4) : Color.secondary.opacity(0.6)))
            }
            .padding(Spacing.md)
            .background {
                if isPrimary {
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(AppColors.primary)
                } else {
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(isAurora ? Color.white.opacity(0.08) : Color(UIColor.secondarySystemGroupedBackground))
                }
            }
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .strokeBorder(isAurora ? Color.white.opacity(0.15) : Color.clear, lineWidth: 1)
                }
            }
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isPressed = false
                        }
                    }
                }
        )
    }
}

// MARK: - Preview

#Preview("Single Candidate") {
    let candidate = FuzzyMatchCandidate(
        template: RecurringTemplate(
            vendorFingerprint: "test123",
            vendorOnlyFingerprint: "vendor123",
            vendorDisplayName: "Santander Bank",
            vendorShortName: "Santander",
            dueDayOfMonth: 15,
            amountMin: 173,
            amountMax: 180,
            currency: "PLN"
        ),
        newAmount: 250,
        percentDifference: 0.44
    )

    RecurringFuzzyMatchConfirmationSheet(
        candidates: [candidate],
        newAmount: 250,
        currency: "PLN",
        onSameService: { _ in },
        onDifferentService: { },
        onCancel: { }
    )
}

#Preview("Multiple Candidates") {
    let candidate1 = FuzzyMatchCandidate(
        template: RecurringTemplate(
            vendorFingerprint: "test123",
            vendorOnlyFingerprint: "vendor123",
            vendorDisplayName: "Santander Bank",
            vendorShortName: "Santander",
            dueDayOfMonth: 15,
            amountMin: 173,
            amountMax: 180,
            currency: "PLN"
        ),
        newAmount: 250,
        percentDifference: 0.44
    )

    let candidate2 = FuzzyMatchCandidate(
        template: RecurringTemplate(
            vendorFingerprint: "test456",
            vendorOnlyFingerprint: "vendor123",
            vendorDisplayName: "Santander Bank",
            vendorShortName: "Santander",
            dueDayOfMonth: 5,
            amountMin: 200,
            amountMax: 210,
            currency: "PLN"
        ),
        newAmount: 250,
        percentDifference: 0.22
    )

    RecurringFuzzyMatchConfirmationSheet(
        candidates: [candidate1, candidate2],
        newAmount: 250,
        currency: "PLN",
        onSameService: { _ in },
        onDifferentService: { },
        onCancel: { }
    )
}
