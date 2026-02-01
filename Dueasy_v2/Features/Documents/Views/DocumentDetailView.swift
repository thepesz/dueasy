import SwiftUI

/// Document detail view showing all fields and actions.
struct DocumentDetailView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let document: FinanceDocument

    @State private var viewModel: DocumentDetailViewModel?
    @State private var showingEditSheet = false
    @State private var appeared = false

    var body: some View {
        Group {
            if let viewModel = viewModel {
                contentView(viewModel: viewModel)
            } else {
                LoadingView(L10n.Common.loading.localized)
                    .gradientBackground(style: .list)
            }
        }
        .navigationTitle(document.title.isEmpty ? L10n.Detail.title.localized : document.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            setupViewModel()
        }
        .onChange(of: viewModel?.shouldDismiss ?? false) { _, shouldDismiss in
            if shouldDismiss {
                dismiss()
            }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.4)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private func contentView(viewModel: DocumentDetailViewModel) -> some View {
        ZStack {
            // Modern gradient background
            GradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Header with status
                    headerSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8), value: appeared)

                    // Amount section
                    amountSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 15)
                        .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(0.05), value: appeared)

                    // Details section
                    detailsSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 15)
                        .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(0.1), value: appeared)

                    // Calendar section
                    calendarSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 15)
                        .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(0.15), value: appeared)

                    // Actions section
                    actionsSection(viewModel: viewModel)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 15)
                        .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(0.2), value: appeared)
                }
                .padding(Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label(L10n.Common.edit.localized, systemImage: "pencil")
                    }

                    if document.status == .scheduled {
                        Button {
                            Task {
                                await viewModel.markAsPaid()
                            }
                        } label: {
                            Label(L10n.Detail.markAsPaid.localized, systemImage: "checkmark.circle")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteDocument()
                        }
                    } label: {
                        Label(L10n.Common.delete.localized, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            DocumentEditView(document: document)
                .environment(environment)
        }
        .overlay(alignment: .top) {
            if let error = viewModel.error {
                ErrorBanner(error: error, onDismiss: { viewModel.clearError() })
                    .padding()
            }
        }
        .loadingOverlay(isLoading: viewModel.isLoading, message: L10n.Detail.deleting.localized)
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(document.type.displayName)
                    .font(Typography.caption1.weight(.medium))
                    .foregroundStyle(.secondary)

                if let number = document.documentNumber, !number.isEmpty {
                    Text("No. \(number)")
                        .font(Typography.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            StatusBadge(status: document.status, size: .large)
        }
    }

    @ViewBuilder
    private var amountSection: some View {
        PremiumGlassCard(accentColor: document.status.color) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(L10n.Detail.amount.localized)
                    .font(Typography.caption1.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(formattedAmount)
                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Card.glass {
            VStack(spacing: Spacing.md) {
                DetailRow(label: L10n.Detail.vendor.localized, value: document.title.isEmpty ? L10n.Detail.notSpecified.localized : document.title)

                // Vendor address
                if let address = document.vendorAddress, !address.isEmpty {
                    DetailRow(label: L10n.Detail.address.localized, value: address)
                }

                // Bank account number
                if let bankAccount = document.bankAccountNumber, !bankAccount.isEmpty {
                    DetailRow(label: L10n.Detail.bankAccount.localized, value: bankAccount)
                        .font(.system(.caption, design: .monospaced))
                }

                if let dueDate = document.dueDate {
                    DetailRow(
                        label: L10n.Detail.dueDate.localized,
                        value: formattedDate(dueDate),
                        valueColor: AppColors.dueDateColor(daysUntilDue: document.daysUntilDue)
                    )

                    if let days = document.daysUntilDue {
                        DueDateBadge(daysUntilDue: days)
                    }
                }

                if let notes = document.notes, !notes.isEmpty {
                    DetailRow(label: L10n.Detail.notes.localized, value: notes)
                }

                DetailRow(label: L10n.Detail.created.localized, value: formattedDate(document.createdAt))
            }
        }
    }

    @ViewBuilder
    private var calendarSection: some View {
        Card.glass {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(AppColors.primary)

                    Text(L10n.Detail.calendar.localized)
                        .font(Typography.headline)

                    Spacer()

                    if document.calendarEventId != nil {
                        Text(L10n.Detail.added.localized)
                            .font(Typography.caption1)
                            .foregroundStyle(AppColors.success)
                    } else {
                        Text(L10n.Detail.notAdded.localized)
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                    }
                }

                if document.notificationsEnabled {
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(AppColors.primary)

                        Text(L10n.Detail.reminders.localized)
                            .font(Typography.subheadline)

                        Spacer()

                        Text(reminderOffsetsText)
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionsSection(viewModel: DocumentDetailViewModel) -> some View {
        if document.status == .scheduled {
            PrimaryButton(L10n.Detail.markAsPaid.localized, icon: "checkmark.circle.fill") {
                Task {
                    await viewModel.markAsPaid()
                }
            }
        }
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
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var reminderOffsetsText: String {
        document.reminderOffsetsDays.map { days in
            if days == 0 {
                return L10n.Review.reminderDueDate.localized
            } else if days == 1 {
                return L10n.Review.reminderOneDay.localized
            } else {
                return String.localized(L10n.Review.reminderDays, with: days)
            }
        }.joined(separator: ", ")
    }

    // MARK: - Setup

    private func setupViewModel() {
        guard viewModel == nil else { return }
        viewModel = DocumentDetailViewModel(
            documentId: document.id,
            markAsPaidUseCase: environment.makeMarkAsPaidUseCase(),
            deleteUseCase: environment.makeDeleteDocumentUseCase()
        )
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(Typography.caption1)
                .foregroundStyle(.secondary)

            Text(value)
                .font(Typography.body)
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Document Edit View (Placeholder)

struct DocumentEditView: View {
    @Environment(\.dismiss) private var dismiss
    let document: FinanceDocument

    var body: some View {
        NavigationStack {
            Text("Edit view - to be implemented")
                .navigationTitle(L10n.Detail.editDocument.localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Common.cancel.localized) { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DocumentDetailView(
            document: FinanceDocument(
                type: .invoice,
                title: "Acme Corporation",
                amount: 1250.00,
                currency: "PLN",
                dueDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
                status: .scheduled,
                documentNumber: "INV-2024-001",
                calendarEventId: "mock-event-id",
                reminderOffsetsDays: [7, 1, 0],
                notificationsEnabled: true
            )
        )
        .environment(AppEnvironment.preview)
    }
}
