import SwiftUI

/// Overview screen for recurring payments.
/// Shows templates (active/paused) and upcoming payment instances.
///
/// UI STYLE: Adapts to the current UI style (Midnight Aurora, Paper Minimal, Warm Finance)
/// based on user preference from SettingsManager.uiStyleOtherViews.
struct RecurringOverviewView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.uiStyle) private var uiStyle

    /// Design tokens for the current style
    private var tokens: UIStyleTokens {
        UIStyleTokens(style: uiStyle)
    }

    @State private var viewModel: RecurringOverviewViewModel?
    @State private var showDeleteConfirmation: Bool = false
    @State private var templateToDelete: RecurringTemplate?

    #if DEBUG
    @State private var isManuallyLinking: Bool = false
    @State private var linkingResult: String?
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(L10n.Recurring.overviewTitle.localized)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.done.localized) {
                        dismiss()
                    }
                }

                #if DEBUG
                // DEBUG-only: Manual linking button for testing/fixing document linkage
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await manuallyLinkDocuments()
                        }
                    } label: {
                        Image(systemName: "link.circle")
                            .foregroundStyle(.blue)
                    }
                    .disabled(isManuallyLinking)
                }
                #endif
            }
            .confirmationDialog(
                L10n.Recurring.deleteTemplate.localized,
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(L10n.Common.delete.localized, role: .destructive) {
                    if let template = templateToDelete, let vm = viewModel {
                        Task {
                            await vm.deleteTemplate(template)
                        }
                    }
                }
                Button(L10n.Common.cancel.localized, role: .cancel) {}
            } message: {
                Text(L10n.Recurring.deleteTemplateConfirm.localized)
            }
            #if DEBUG
            .alert("Link Documents", isPresented: Binding(
                get: { linkingResult != nil },
                set: { if !$0 { linkingResult = nil } }
            )) {
                Button("OK") { linkingResult = nil }
            } message: {
                if let result = linkingResult {
                    Text(result)
                }
            }
            #endif
        }
        .task {
            if viewModel == nil {
                viewModel = RecurringOverviewViewModel(
                    templateService: environment.recurringTemplateService,
                    schedulerService: environment.recurringSchedulerService
                )
            }
            await viewModel?.loadData()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: RecurringOverviewViewModel) -> some View {
        ScrollView {
            // PERFORMANCE: Use LazyVStack for potentially long lists of templates and instances
            LazyVStack(spacing: Spacing.lg) {
                // Upcoming instances section
                if viewModel.hasUpcomingInstances {
                    upcomingSection(viewModel)
                }

                // Templates section
                templatesSection(viewModel)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
        .scrollContentBackground(.hidden)
        .background {
            // Style-aware background
            StyledRecurringBackground()
        }
        .refreshable {
            await viewModel.loadData()
        }
        .overlay {
            if viewModel.isLoading && !viewModel.hasTemplates {
                ProgressView()
            }
        }
    }

    // MARK: - Upcoming Instances Section

    @ViewBuilder
    private func upcomingSection(_ viewModel: RecurringOverviewViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(L10n.Recurring.instancesSection.localized)
                .font(Typography.headline)
                .foregroundStyle(.primary)

            ForEach(viewModel.upcomingInstances) { enrichedInstance in
                StyledUpcomingInstanceCard(
                    instance: enrichedInstance.instance,
                    template: enrichedInstance.template,
                    onMarkAsPaid: {
                        Task {
                            await viewModel.markInstanceAsPaid(enrichedInstance.instance)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Templates Section

    @ViewBuilder
    private func templatesSection(_ viewModel: RecurringOverviewViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header with filter
            HStack {
                Text(L10n.Recurring.templatesSection.localized)
                    .font(Typography.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Picker("", selection: Binding(
                    get: { viewModel.showPausedTemplates },
                    set: { viewModel.showPausedTemplates = $0 }
                )) {
                    Text(L10n.Recurring.activeTemplates.localized).tag(false)
                    Text(L10n.Recurring.pausedTemplates.localized).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            if viewModel.filteredTemplates.isEmpty {
                StyledEmptyTemplatesView(showPaused: viewModel.showPausedTemplates)
            } else {
                ForEach(viewModel.filteredTemplates, id: \.id) { template in
                    StyledRecurringTemplateCard(
                        template: template,
                        onPause: {
                            Task {
                                await viewModel.pauseTemplate(template)
                            }
                        },
                        onResume: {
                            Task {
                                await viewModel.resumeTemplate(template)
                            }
                        },
                        onDelete: {
                            templateToDelete = template
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
        }
    }

    #if DEBUG
    // MARK: - Manual Linking (DEBUG only)

    private func manuallyLinkDocuments() async {
        isManuallyLinking = true
        linkingResult = nil

        do {
            let useCase = environment.makeManuallyLinkDocumentsUseCase()
            let linkedCount = try await useCase.execute()
            linkingResult = "Successfully linked \(linkedCount) documents to recurring templates"

            // Reload data to show updated state
            await viewModel?.loadData()
        } catch {
            linkingResult = "Linking failed: \(error.localizedDescription)"
        }

        isManuallyLinking = false
    }
    #endif
}

// MARK: - Upcoming Instance Card

struct UpcomingInstanceCard: View {
    @Environment(AppEnvironment.self) private var environment

    let instance: RecurringInstance
    let template: RecurringTemplate
    let onMarkAsPaid: () -> Void

    var body: some View {
        Card.glass {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(template.vendorDisplayName)
                            .font(Typography.headline)

                        Text(dueDateText)
                            .font(Typography.subheadline)
                            .foregroundStyle(dueDateColor)
                    }

                    Spacer()

                    if let amount = instance.effectiveAmount {
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text(formatAmount(amount, currency: template.currency))
                                .font(Typography.headline)

                            RecurringInstanceStatusBadge(status: instance.status)
                        }
                    }
                }

                if instance.status == .expected || instance.status == .matched {
                    Button(action: onMarkAsPaid) {
                        Label(L10n.Detail.markAsPaid.localized, systemImage: "checkmark.circle")
                            .font(Typography.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.success)
                }
            }
        }
    }

    private var dueDateText: String {
        let days = instance.daysUntilDue(using: environment.recurringDateService)
        if days == 0 {
            return L10n.RecurringInstance.dueToday.localized
        } else if days > 0 {
            return L10n.RecurringInstance.dueIn.localized(with: days)
        } else {
            return L10n.RecurringInstance.overdue.localized(with: abs(days))
        }
    }

    private var dueDateColor: Color {
        let days = instance.daysUntilDue(using: environment.recurringDateService)
        if days < 0 {
            return AppColors.error
        } else if days <= 3 {
            return AppColors.warning
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

// MARK: - Recurring Template Card

struct RecurringTemplateCard: View {
    let template: RecurringTemplate
    let onPause: () -> Void
    let onResume: () -> Void
    let onDelete: () -> Void

    @State private var showActions: Bool = false

    var body: some View {
        Card.glass {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    // Category icon
                    Image(systemName: template.documentCategory.iconName)
                        .font(.title2)
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 40, height: 40)
                        .background(AppColors.primary.opacity(0.1))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(template.vendorDisplayName)
                            .font(Typography.headline)

                        Text(L10n.Recurring.dueDayValue.localized(with: template.dueDayOfMonth))
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Status indicator
                    if !template.isActive {
                        Text(L10n.Recurring.pausedTemplates.localized)
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
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
                    StatItem(
                        value: template.matchedDocumentCount,
                        label: L10n.Recurring.matchedCount.localized(with: template.matchedDocumentCount)
                    )
                    StatItem(
                        value: template.paidInstanceCount,
                        label: L10n.Recurring.paidCount.localized(with: template.paidInstanceCount)
                    )
                    if template.missedInstanceCount > 0 {
                        StatItem(
                            value: template.missedInstanceCount,
                            label: L10n.Recurring.missedCount.localized(with: template.missedInstanceCount),
                            color: AppColors.error
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Status Badge for Instance

struct RecurringInstanceStatusBadge: View {
    let status: RecurringInstanceStatus

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: status.iconName)
                .font(.caption)
            Text(status.displayName)
                .font(Typography.caption1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .expected:
            return .secondary
        case .matched:
            return AppColors.primary
        case .paid:
            return AppColors.success
        case .missed:
            return AppColors.error
        case .cancelled:
            return .gray
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let value: Int
    let label: String
    var color: Color = .secondary

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Text("\(value)")
                .font(Typography.headline)
                .foregroundStyle(color)
            Text(label)
                .font(Typography.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    RecurringOverviewView()
        .environment(AppEnvironment.preview)
}
