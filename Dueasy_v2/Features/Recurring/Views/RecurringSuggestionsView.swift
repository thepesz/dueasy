import SwiftUI

/// View for displaying auto-detection recurring payment suggestions.
/// Shows suggestion cards with accept/dismiss/snooze actions.
struct RecurringSuggestionsView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RecurringSuggestionsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(L10n.RecurringSuggestions.title.localized)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.done.localized) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = RecurringSuggestionsViewModel(
                    detectCandidatesUseCase: environment.makeDetectRecurringCandidatesUseCase(),
                    schedulerService: environment.recurringSchedulerService
                )
            }
            await viewModel?.loadSuggestions()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: RecurringSuggestionsViewModel) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if viewModel.hasSuggestions {
                    ForEach(viewModel.suggestions, id: \.id) { candidate in
                        SuggestionCard(
                            candidate: candidate,
                            isProcessing: viewModel.isProcessing,
                            onAccept: {
                                Task {
                                    await viewModel.acceptSuggestion(candidate)
                                }
                            },
                            onDismiss: {
                                Task {
                                    await viewModel.dismissSuggestion(candidate)
                                }
                            },
                            onSnooze: {
                                Task {
                                    await viewModel.snoozeSuggestion(candidate)
                                }
                            }
                        )
                    }
                } else {
                    emptyStateView
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
        .scrollContentBackground(.hidden)
        .background {
            GradientBackgroundFixed()
        }
        .refreshable {
            await viewModel.loadSuggestions()
        }
        .overlay {
            if viewModel.isLoading && !viewModel.hasSuggestions {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(L10n.RecurringSuggestions.noSuggestions.localized)
                .font(Typography.title2)
                .foregroundStyle(.primary)

            Text(L10n.RecurringSuggestions.noSuggestionsMessage.localized)
                .font(Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }
}

// MARK: - Suggestion Card

struct SuggestionCard: View {
    let candidate: RecurringCandidate
    let isProcessing: Bool
    let onAccept: () -> Void
    let onDismiss: () -> Void
    let onSnooze: () -> Void

    var body: some View {
        Card.glass {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header
                HStack {
                    Image(systemName: candidate.documentCategory.iconName)
                        .font(.title2)
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 44, height: 44)
                        .background(AppColors.primary.opacity(0.1))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(candidate.vendorDisplayName)
                            .font(Typography.headline)

                        Text(candidate.documentCategory.displayName)
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Confidence badge
                    ConfidenceBadgeSmall(confidence: candidate.confidenceScore)
                }

                // Description
                Text(L10n.RecurringSuggestions.cardDescription.localized(with: candidate.documentCount, candidate.vendorDisplayName))
                    .font(Typography.subheadline)
                    .foregroundStyle(.secondary)

                // Stats
                HStack(spacing: Spacing.lg) {
                    if let dueDay = candidate.dominantDueDayOfMonth {
                        StatPill(
                            icon: "calendar",
                            text: L10n.Recurring.dueDayValue.localized(with: dueDay)
                        )
                    }

                    if let avgAmount = candidate.averageAmount {
                        StatPill(
                            icon: "banknote",
                            text: formatAmount(avgAmount, currency: candidate.currency)
                        )
                    }

                    if candidate.hasStableIBAN {
                        StatPill(icon: "checkmark.seal", text: "IBAN")
                    }
                }

                // Action buttons
                HStack(spacing: Spacing.sm) {
                    // Dismiss button
                    Button(action: onDismiss) {
                        Text(L10n.RecurringSuggestions.dismiss.localized)
                            .font(Typography.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)

                    // Snooze button
                    Button(action: onSnooze) {
                        Text(L10n.RecurringSuggestions.snooze.localized)
                            .font(Typography.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)

                    // Accept button
                    Button(action: onAccept) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(L10n.RecurringSuggestions.accept.localized)
                                .font(Typography.subheadline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.primary)
                    .disabled(isProcessing)
                }
            }
        }
    }

    private func formatAmount(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }
}

// MARK: - Confidence Badge Small

struct ConfidenceBadgeSmall: View {
    let confidence: Double

    var body: some View {
        Text(L10n.RecurringSuggestions.cardConfidence.localized(with: Int(confidence * 100)))
            .font(Typography.caption1)
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private var color: Color {
        if confidence >= 0.9 {
            return AppColors.success
        } else if confidence >= 0.8 {
            return AppColors.primary
        } else {
            return AppColors.warning
        }
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(Typography.caption1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    RecurringSuggestionsView()
        .environment(AppEnvironment.preview)
}
