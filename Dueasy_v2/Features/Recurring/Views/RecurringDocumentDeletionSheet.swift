import SwiftUI

/// Modal sheet for Scenario 1: Deleting a document linked to a recurring payment.
///
/// Presents two destructive options:
/// 1. Delete this invoice only - unlinks document, keeps recurring active, calendar events remain
/// 2. Delete invoice and cancel recurring payments - deactivates template, deletes all future
///    instances and their calendar events
///
/// User dismisses via the X button in toolbar (no separate Cancel option).
///
/// Uses iOS 26 Liquid Glass aesthetic with Card.glass styling.
/// Supports accessibility (Reduce Motion, VoiceOver, Reduce Transparency).
struct RecurringDocumentDeletionSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @Bindable var viewModel: RecurringDeletionViewModel

    /// Callback when deletion completes (to trigger parent view dismiss if needed)
    let onComplete: (RecurringDeletionResult) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Header
                    headerSection

                    // Options (only 2 destructive options)
                    optionsSection

                    // Info about history preservation
                    warningSection
                }
                .padding(Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(L10n.RecurringDeletion.documentTitle.localized)
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
                Image(systemName: "repeat.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColors.primary)
                    .symbolRenderingMode(.hierarchical)

                Text(L10n.RecurringDeletion.recurringSeriesTitle.localized)
                    .font(Typography.headline)
                    .multilineTextAlignment(.center)

                Text(L10n.RecurringDeletion.recurringSeriesMessage.localized)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Options Section

    @ViewBuilder
    private var optionsSection: some View {
        VStack(spacing: Spacing.sm) {
            // Option 1: Delete only this invoice (like "Delete This Event Only" in iOS Calendar)
            DeletionOptionButton(
                title: L10n.RecurringDeletion.deleteThisOnly.localized,
                description: L10n.RecurringDeletion.deleteThisOnlyDescription.localized,
                icon: RecurringDocumentDeletionOption.deleteOnlyThisInvoice.iconName,
                isDestructive: true,
                isRecommended: false,
                isLoading: viewModel.isLoading
            ) {
                Task {
                    await viewModel.executeDocumentDeletion(option: .deleteOnlyThisInvoice)
                }
            }

            // Option 2: Delete all future (like "Delete All Future Events" in iOS Calendar)
            DeletionOptionButton(
                title: L10n.RecurringDeletion.deleteAllFuture.localized,
                description: L10n.RecurringDeletion.deleteAllFutureDescription.localized,
                icon: RecurringDocumentDeletionOption.cancelRecurringPayments.iconName,
                isDestructive: true,
                isRecommended: false,
                isLoading: viewModel.isLoading
            ) {
                Task {
                    await viewModel.executeDocumentDeletion(option: .cancelRecurringPayments)
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
}

// MARK: - Deletion Option Button

/// A styled option button for deletion modals.
/// Uses glass card aesthetic with icon and description.
struct DeletionOptionButton: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let description: String
    let icon: String
    let isDestructive: Bool
    let isRecommended: Bool
    let isLoading: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                // Icon
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isDestructive ? AppColors.error : AppColors.primary)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(iconBackgroundColor)
                    )

                // Text content
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(title)
                            .font(Typography.bodyBold)
                            .foregroundStyle(isDestructive ? AppColors.error : .primary)

                        if isRecommended {
                            Text(L10n.AddDocument.recommended.localized)
                                .font(Typography.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(AppColors.primary)
                                )
                        }
                    }

                    Text(description)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Spacing.md)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .disabled(isLoading)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !reduceMotion && !isPressed && !isLoading {
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

    private var iconBackgroundColor: Color {
        if isDestructive {
            return AppColors.error.opacity(0.1)
        } else {
            return AppColors.primary.opacity(0.1)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
            .fill(Color(UIColor.secondarySystemGroupedBackground))
    }

    private var borderColor: Color {
        if isRecommended {
            return AppColors.primary.opacity(0.3)
        } else if isDestructive {
            return AppColors.error.opacity(0.15)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Preview

#Preview("Document Deletion Sheet") {
    Text("Trigger Sheet")
        .sheet(isPresented: .constant(true)) {
            // Note: In preview we can't easily create the full ViewModel
            // This shows the basic structure
            VStack(spacing: Spacing.lg) {
                Card.glass {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "doc.badge.clock")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.primary)

                        Text("This invoice is linked to a recurring payment from PGE Energia")
                            .font(Typography.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                }

                DeletionOptionButton(
                    title: "Delete only this invoice",
                    description: "Remove this invoice but keep the recurring payment active.",
                    icon: "doc.badge.minus",
                    isDestructive: true,
                    isRecommended: true,
                    isLoading: false
                ) {}

                DeletionOptionButton(
                    title: "Cancel recurring payments",
                    description: "Stop tracking this recurring payment entirely.",
                    icon: "calendar.badge.minus",
                    isDestructive: true,
                    isRecommended: false,
                    isLoading: false
                ) {}
            }
            .padding()
            .background(Color(UIColor.systemGroupedBackground))
        }
}
