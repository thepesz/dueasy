import SwiftUI

/// Modal sheet for Scenario 2: Deleting a recurring instance from calendar view.
///
/// Presents two destructive options:
/// 1. Delete this month only - cancels specific instance and its calendar event, keeps template active
/// 2. Delete all future occurrences - deactivates template, cancels all future instances
///    and deletes their calendar events
///
/// User dismisses via the X button in toolbar (no separate Cancel option).
///
/// Uses iOS 26 Liquid Glass aesthetic with Card.glass styling.
/// Supports accessibility (Reduce Motion, VoiceOver, Reduce Transparency).
struct RecurringInstanceDeletionSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppEnvironment.self) private var appEnvironment

    @Bindable var viewModel: RecurringDeletionViewModel

    /// Callback when deletion completes (to trigger parent view refresh if needed)
    let onComplete: (RecurringDeletionResult) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Header
                    headerSection

                    // Instance info (if available)
                    if let instance = viewModel.instance {
                        instanceInfoSection(instance: instance)
                    }

                    // Options (only 2 destructive options)
                    optionsSection

                    // Info about history preservation
                    warningSection
                }
                .padding(Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(L10n.RecurringDeletion.instanceTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel.localized) {
                        dismiss()
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    loadingOverlay
                }
            }
            .onChange(of: viewModel.lastResult) { _, result in
                if let result = result, result.success {
                    onComplete(result)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        Card.glass {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColors.primary)
                    .symbolRenderingMode(.hierarchical)

                Text(L10n.RecurringDeletion.instanceSubtitle.localized(with: viewModel.vendorName))
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Instance Info Section

    @ViewBuilder
    private func instanceInfoSection(instance: RecurringInstance) -> some View {
        Card.solid {
            VStack(spacing: Spacing.sm) {
                // Period
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text(formattedPeriod(instance.periodKey))
                        .font(Typography.body)
                    Spacer()
                }

                // Due date
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text(formattedDate(instance.effectiveDueDate))
                        .font(Typography.body)
                    Spacer()

                    // Days indicator
                    daysIndicator(for: instance)
                }

                // Amount (if available)
                if let amount = instance.effectiveAmount {
                    HStack {
                        Image(systemName: "creditcard")
                            .foregroundStyle(.secondary)
                        Text(formattedAmount(amount, currency: viewModel.template?.currency ?? "PLN"))
                            .font(Typography.bodyBold)
                        Spacer()
                    }
                }

                // Status
                HStack {
                    Image(systemName: instance.status.iconName)
                        .foregroundStyle(statusColor(for: instance.status))
                    Text(instance.status.displayName)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Options Section

    @ViewBuilder
    private var optionsSection: some View {
        VStack(spacing: Spacing.sm) {
            // Option 1: Delete this month only
            DeletionOptionButton(
                title: L10n.RecurringDeletion.deleteThisMonthOnly.localized,
                description: L10n.RecurringDeletion.deleteThisMonthOnlyDescription.localized,
                icon: RecurringInstanceDeletionOption.deleteThisMonthOnly.iconName,
                isDestructive: true,
                isRecommended: true,
                isLoading: viewModel.isLoading
            ) {
                Task {
                    await viewModel.executeInstanceDeletion(option: .deleteThisMonthOnly)
                }
            }

            // Option 2: Delete all future occurrences
            DeletionOptionButton(
                title: L10n.RecurringDeletion.deleteAllFutureOccurrences.localized,
                description: L10n.RecurringDeletion.deleteAllFutureOccurrencesDescription.localized,
                icon: RecurringInstanceDeletionOption.deleteAllFutureOccurrences.iconName,
                isDestructive: true,
                isRecommended: false,
                isLoading: viewModel.isLoading
            ) {
                Task {
                    await viewModel.executeInstanceDeletion(option: .deleteAllFutureOccurrences)
                }
            }
        }
    }

    // MARK: - Warning Section

    @ViewBuilder
    private var warningSection: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)

            Text(L10n.RecurringDeletion.keepHistory.localized)
                .font(Typography.caption1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
    }

    // MARK: - Loading Overlay

    @ViewBuilder
    private var loadingOverlay: some View {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: Spacing.sm) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(L10n.Common.loading.localized)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }
                .padding(Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(Color(UIColor.systemBackground).opacity(0.95))
                )
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Helpers

    private func formattedPeriod(_ periodKey: String) -> String {
        let parts = periodKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return periodKey
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard let date = Calendar.current.date(from: components) else {
            return periodKey
        }

        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLocale
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLocale
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formattedAmount(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount) \(currency)"
    }

    @ViewBuilder
    private func daysIndicator(for instance: RecurringInstance) -> some View {
        let days = instance.daysUntilDue(using: appEnvironment.recurringDateService)

        if days == 0 {
            Text(L10n.RecurringInstance.dueToday.localized)
                .font(Typography.caption1)
                .foregroundStyle(AppColors.warning)
        } else if days > 0 {
            Text(L10n.RecurringInstance.dueIn.localized(with: days))
                .font(Typography.caption1)
                .foregroundStyle(.secondary)
        } else {
            Text(L10n.RecurringInstance.overdue.localized(with: abs(days)))
                .font(Typography.caption1)
                .foregroundStyle(AppColors.error)
        }
    }

    private func statusColor(for status: RecurringInstanceStatus) -> Color {
        switch status {
        case .expected:
            return AppColors.primary
        case .matched:
            return AppColors.warning
        case .paid:
            return AppColors.success
        case .missed:
            return AppColors.error
        case .cancelled:
            return .secondary
        }
    }
}

// MARK: - Preview

#Preview("Instance Deletion Sheet") {
    Text("Trigger Sheet")
        .sheet(isPresented: .constant(true)) {
            // Preview with mock data showing the structure
            VStack(spacing: Spacing.lg) {
                Card.glass {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.primary)

                        Text("This is an expected payment for PGE Energia")
                            .font(Typography.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                }

                Card.solid {
                    VStack(spacing: Spacing.sm) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(.secondary)
                            Text("February 2026")
                            Spacer()
                        }

                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                            Text("15 February 2026")
                            Spacer()
                            Text("Due in 13 days")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Image(systemName: "creditcard")
                                .foregroundStyle(.secondary)
                            Text("125.50 PLN")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }

                DeletionOptionButton(
                    title: "Delete this month only",
                    description: "Skip this specific payment. The recurring pattern continues.",
                    icon: "calendar.badge.minus",
                    isDestructive: true,
                    isRecommended: true,
                    isLoading: false
                ) {}

                DeletionOptionButton(
                    title: "Delete all future occurrences",
                    description: "Stop tracking this recurring payment entirely.",
                    icon: "calendar.badge.exclamationmark",
                    isDestructive: true,
                    isRecommended: false,
                    isLoading: false
                ) {}
            }
            .padding()
            .background(Color(UIColor.systemGroupedBackground))
        }
}
