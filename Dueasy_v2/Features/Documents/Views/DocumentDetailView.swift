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
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(L10n.Detail.amount.localized)
                        .font(Typography.caption1.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(formattedAmount)
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = formattedAmount
                    #endif
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Copy amount")
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

                // Vendor NIP
                if let nip = document.vendorNIP, !nip.isEmpty {
                    DetailRow(label: L10n.Detail.nip.localized, value: nip)
                        .font(.system(.caption, design: .monospaced))
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
    var showCopyButton: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(Typography.caption1)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: Spacing.xs) {
                Text(value)
                    .font(Typography.body)
                    .foregroundStyle(valueColor)

                if showCopyButton {
                    Spacer()

                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = value
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Copy \(label)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Document Edit View

struct DocumentEditView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let document: FinanceDocument

    @State private var vendorName: String
    @State private var vendorAddress: String
    @State private var amount: String
    @State private var currency: String
    @State private var dueDate: Date
    @State private var documentNumber: String
    @State private var vendorNIP: String
    @State private var bankAccountNumber: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var error: AppError?

    init(document: FinanceDocument) {
        self.document = document

        // Initialize state with current document values
        _vendorName = State(initialValue: document.title)
        _vendorAddress = State(initialValue: document.vendorAddress ?? "")
        _amount = State(initialValue: String(describing: document.amount))
        _currency = State(initialValue: document.currency)
        _dueDate = State(initialValue: document.dueDate ?? Date())
        _documentNumber = State(initialValue: document.documentNumber ?? "")
        _vendorNIP = State(initialValue: document.vendorNIP ?? "")
        _bankAccountNumber = State(initialValue: document.bankAccountNumber ?? "")
        _notes = State(initialValue: document.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Vendor section
                        Card.glass {
                            VStack(spacing: Spacing.md) {
                                FormField(label: L10n.Edit.vendorName.localized, isRequired: true) {
                                    TextField(L10n.Edit.vendorNamePlaceholder.localized, text: $vendorName)
                                }

                                FormField(label: L10n.Edit.vendorAddress.localized, isRequired: false) {
                                    TextField(L10n.Edit.vendorAddressPlaceholder.localized, text: $vendorAddress, axis: .vertical)
                                        .lineLimit(2...5)
                                }

                                FormField(label: L10n.Edit.nip.localized, isRequired: false) {
                                    TextField(L10n.Edit.nipPlaceholder.localized, text: $vendorNIP)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }

                        // Amount section
                        Card.glass {
                            HStack(spacing: Spacing.sm) {
                                FormField(label: L10n.Edit.amount.localized, isRequired: true) {
                                    TextField(L10n.Edit.amountPlaceholder.localized, text: $amount)
                                        .keyboardType(.decimalPad)
                                }

                                FormField(label: L10n.Edit.currency.localized) {
                                    Picker(L10n.Edit.currency.localized, selection: $currency) {
                                        ForEach(SettingsManager.availableCurrencies, id: \.self) { curr in
                                            Text(curr).tag(curr)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                                .frame(width: 100)
                            }
                        }

                        // Date and details section
                        Card.glass {
                            VStack(spacing: Spacing.md) {
                                FormField(label: L10n.Edit.dueDate.localized, isRequired: true) {
                                    DatePicker(L10n.Edit.dueDate.localized, selection: $dueDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                }

                                FormField(label: L10n.Edit.documentNumber.localized, isRequired: false) {
                                    TextField(L10n.Edit.documentNumberPlaceholder.localized, text: $documentNumber)
                                }

                                FormField(label: L10n.Edit.bankAccount.localized, isRequired: false) {
                                    TextField(L10n.Edit.bankAccountPlaceholder.localized, text: $bankAccountNumber, axis: .vertical)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1...3)
                                }
                            }
                        }

                        // Notes section
                        Card.glass {
                            FormField(label: L10n.Edit.notes.localized, isRequired: false) {
                                TextField(L10n.Edit.notesPlaceholder.localized, text: $notes, axis: .vertical)
                                    .lineLimit(3...10)
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationTitle(L10n.Edit.title.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel.localized) { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save.localized) {
                        Task { await saveChanges() }
                    }
                    .disabled(isSaving || !isValid)
                }
            }
            .loadingOverlay(isLoading: isSaving, message: L10n.Edit.saving.localized)
            .overlay(alignment: .top) {
                if let error = error {
                    ErrorBanner(error: error, onDismiss: { self.error = nil })
                        .padding()
                }
            }
        }
    }

    private var isValid: Bool {
        !vendorName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !amount.trimmingCharacters(in: .whitespaces).isEmpty &&
        amountDecimal != nil &&
        amountDecimal! > 0
    }

    private var amountDecimal: Decimal? {
        var normalized = amount
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")

        if normalized.contains(",") && !normalized.contains(".") {
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        } else if normalized.contains(",") && normalized.contains(".") {
            if let commaIndex = normalized.lastIndex(of: ","),
               let dotIndex = normalized.lastIndex(of: "."),
               commaIndex > dotIndex {
                normalized = normalized.replacingOccurrences(of: ".", with: "")
                normalized = normalized.replacingOccurrences(of: ",", with: ".")
            } else {
                normalized = normalized.replacingOccurrences(of: ",", with: "")
            }
        }

        return Decimal(string: normalized)
    }

    private func saveChanges() async {
        guard let finalAmount = amountDecimal else { return }

        isSaving = true
        error = nil

        do {
            // Update fields not handled by UpdateDocumentUseCase directly
            document.vendorAddress = vendorAddress.isEmpty ? nil : vendorAddress
            document.vendorNIP = vendorNIP.isEmpty ? nil : vendorNIP
            document.bankAccountNumber = bankAccountNumber.isEmpty ? nil : bankAccountNumber

            let updateUseCase = environment.makeUpdateDocumentUseCase()
            try await updateUseCase.execute(
                document: document,
                title: vendorName,
                amount: finalAmount,
                currency: currency,
                dueDate: dueDate,
                documentNumber: documentNumber.isEmpty ? nil : documentNumber,
                notes: notes.isEmpty ? nil : notes,
                reminderOffsets: document.reminderOffsetsDays
            )

            isSaving = false
            dismiss()
        } catch let appError as AppError {
            error = appError
            isSaving = false
        } catch {
            self.error = .unknown(error.localizedDescription)
            isSaving = false
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
