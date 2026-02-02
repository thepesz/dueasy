import SwiftUI

/// Document detail view showing full document information.
///
/// ARCHITECTURE: This view is presented via NavigationStack from DocumentListView.
/// Uses standard toolbar for navigation controls to avoid safe area corruption issues.
///
/// LAYOUT FIX (v3): Uses .safeAreaInset(edge: .top) for the floating header buttons.
/// This is SwiftUI's native way to add persistent header content - it automatically
/// handles safe area calculations and avoids GeometryReader timing issues where
/// incorrect values could be returned during navigation transitions.
struct DocumentDetailView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let documentId: UUID

    @State private var viewModel: DocumentDetailViewModel?
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false  // Step 1: Initial confirmation
    @State private var showingRecurringDeletionSheet = false  // Step 2: Recurring options
    @State private var recurringDeletionViewModel: RecurringDeletionViewModel?

    var body: some View {
        // LAYOUT FIX (v3): Use .safeAreaInset instead of GeometryReader + ZStack
        // .safeAreaInset handles safe area calculations automatically and reliably
        ScrollView {
            contentBody
        }
        .background(Color(UIColor.systemGroupedBackground))
        .safeAreaInset(edge: .top, spacing: 0) {
            floatingButtonsHeader
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            setupViewModel()
            await viewModel?.loadDocument()
        }
        .onChange(of: viewModel?.shouldDismiss ?? false) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let doc = viewModel?.document {
                DocumentEditView(document: doc)
                    .environment(environment)
            }
        }
        // Step 1: Initial delete confirmation alert (like iOS Calendar)
        .alert(
            L10n.Documents.deleteInvoiceTitle.localized,
            isPresented: $showingDeleteConfirmation,
            presenting: viewModel?.document
        ) { document in
            Button(L10n.Common.delete.localized, role: .destructive) {
                handleConfirmedDeletion()
            }
            Button(L10n.Common.cancel.localized, role: .cancel) {}
        } message: { document in
            Text(document.title)
        }
        // Step 2: Recurring deletion options sheet (only shown if document is linked to recurring)
        .sheet(isPresented: $showingRecurringDeletionSheet) {
            if let deletionVM = recurringDeletionViewModel {
                RecurringDocumentDeletionSheet(viewModel: deletionVM) { result in
                    // Handle completion - dismiss the detail view on any successful deletion
                    // This includes:
                    // 1. Document deleted (documentDeleted = true)
                    // 2. Future instances deleted but document kept (templateDeactivated = true)
                    if result.success && (result.documentDeleted || result.templateDeactivated) {
                        dismiss()
                    }
                }
            }
        }
        .id(documentId) // Force view recreation when document changes
    }

    // MARK: - Content Body

    @ViewBuilder
    private var contentBody: some View {
        if let viewModel = viewModel, let doc = viewModel.document {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header
                headerSection(document: doc)

                // Amount
                amountSection(document: doc)

                // Details
                detailsSection(document: doc)

                // Calendar
                calendarSection(document: doc)

                // Actions
                if doc.status == .scheduled {
                    actionsSection(viewModel: viewModel)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xs) // Small gap between header and content
            .padding(.bottom, Spacing.xl)
        } else {
            VStack {
                ProgressView()
                Text(L10n.Common.loading.localized)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    // MARK: - Floating Buttons Header

    /// Floating buttons header using .safeAreaInset for proper safe area handling.
    /// SwiftUI automatically positions this below the device safe area (notch/dynamic island)
    /// and adjusts the ScrollView content inset accordingly.
    @ViewBuilder
    private var floatingButtonsHeader: some View {
        HStack {
            // Back button - ALWAYS visible
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 44, height: 44)
                    .background(buttonBackground, in: Circle())
            }

            Spacer()

            // Menu button - ALWAYS visible (disabled during loading)
            Menu {
                Button {
                    showingEditSheet = true
                } label: {
                    Label(L10n.Common.edit.localized, systemImage: "pencil")
                }

                if let vm = viewModel, vm.document?.status == .scheduled {
                    Button {
                        Task { await vm.markAsPaid() }
                    } label: {
                        Label(L10n.Detail.markAsPaid.localized, systemImage: "checkmark.circle")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    handleDeleteAction()
                } label: {
                    Label(L10n.Common.delete.localized, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(viewModel != nil ? AppColors.primary : Color.gray)
                    .frame(width: 44, height: 44)
                    .background(buttonBackground, in: Circle())
            }
            .disabled(viewModel == nil)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(
            Color(UIColor.systemGroupedBackground)
                .opacity(0.95)
        )
    }

    /// Solid background for floating buttons.
    /// Avoids material effects entirely to prevent visual style conflicts.
    private var buttonBackground: some ShapeStyle {
        colorScheme == .light
            ? Color(white: 0.94)
            : Color(white: 0.22)
    }

    // MARK: - Sections

    @ViewBuilder
    private func headerSection(document: FinanceDocument) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(document.type.displayName)
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)

                if let number = document.documentNumber, !number.isEmpty {
                    Text(L10n.Detail.documentNumber.localized(with: number))
                        .font(Typography.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            StatusBadge(status: document.status, size: .large)
        }
    }

    @ViewBuilder
    private func amountSection(document: FinanceDocument) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L10n.Detail.amount.localized)
                .font(Typography.caption1)
                .foregroundStyle(.secondary)

            Text(formattedAmount(for: document))
                .font(Typography.monospacedTitle)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }

    @ViewBuilder
    private func detailsSection(document: FinanceDocument) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Vendor
            detailRow(label: L10n.Detail.vendor.localized, value: document.title.isEmpty ? L10n.Detail.notSpecified.localized : document.title)

            // Address
            if let address = document.vendorAddress, !address.isEmpty {
                detailRow(label: L10n.Detail.address.localized, value: address)
            }

            // NIP
            if let nip = document.vendorNIP, !nip.isEmpty {
                detailRow(label: L10n.Detail.nip.localized, value: nip)
            }

            // Bank Account
            if let bankAccount = document.bankAccountNumber, !bankAccount.isEmpty {
                detailRow(label: L10n.Detail.bankAccount.localized, value: bankAccount)
            }

            // Due Date
            if let dueDate = document.dueDate {
                detailRow(label: L10n.Detail.dueDate.localized, value: formattedDate(dueDate))
            }

            // Notes
            if let notes = document.notes, !notes.isEmpty {
                detailRow(label: L10n.Detail.notes.localized, value: notes)
            }

            // Created
            detailRow(label: L10n.Detail.created.localized, value: formattedDate(document.createdAt))
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }

    @ViewBuilder
    private func calendarSection(document: FinanceDocument) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(AppColors.primary)

                Text(L10n.Detail.calendar.localized)
                    .font(Typography.headline)

                Spacer()

                if document.calendarEventId != nil {
                    Text(L10n.Detail.calendarAdded.localized)
                        .font(Typography.caption1)
                        .foregroundStyle(AppColors.success)
                } else {
                    Text(L10n.Detail.calendarNotAdded.localized)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }
            }

            if document.notificationsEnabled {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(AppColors.primary)

                    Text(L10n.DetailLabels.remindersEnabled.localized)
                        .font(Typography.subheadline)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }

    @ViewBuilder
    private func actionsSection(viewModel: DocumentDetailViewModel) -> some View {
        Button {
            Task { await viewModel.markAsPaid() }
        } label: {
            Label(L10n.Detail.markAsPaid.localized, systemImage: "checkmark.circle.fill")
                .font(Typography.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.success)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(Typography.caption1)
                .foregroundStyle(.secondary)

            Text(value)
                .font(Typography.body)
        }
    }

    private func formattedAmount(for document: FinanceDocument) -> String {
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

    // MARK: - Delete Action

    /// Step 1: Handles delete action - always shows initial confirmation first (like iOS Calendar)
    private func handleDeleteAction() {
        guard viewModel != nil, viewModel?.document != nil else {
            return
        }
        showingDeleteConfirmation = true
    }

    /// Step 2: Called after user confirms initial deletion.
    /// If document is linked to recurring, shows additional options sheet.
    /// If not recurring, executes standard deletion immediately.
    private func handleConfirmedDeletion() {
        guard let vm = viewModel, let doc = vm.document else {
            return
        }

        if vm.isLinkedToRecurring {
            // Document is linked to recurring payment - show step 2 options
            let deletionVM = environment.makeRecurringDeletionViewModel()
            recurringDeletionViewModel = deletionVM

            // Setup the deletion view model with the document
            Task {
                await deletionVM.setupForDocumentDeletion(document: doc, template: nil)
                showingRecurringDeletionSheet = true
            }
        } else {
            // Not recurring - execute standard deletion immediately
            Task { await vm.deleteDocument() }
        }
    }

    // MARK: - Setup

    private func setupViewModel() {
        guard viewModel == nil else { return }

        viewModel = DocumentDetailViewModel(
            documentId: documentId,
            repository: environment.documentRepository,
            markAsPaidUseCase: environment.makeMarkAsPaidUseCase(),
            deleteUseCase: environment.makeDeleteDocumentUseCase()
        )
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
            Form {
                Section(L10n.Detail.vendor.localized) {
                    TextField(L10n.Edit.vendorNamePlaceholder.localized, text: $vendorName)
                    TextField(L10n.Detail.address.localized, text: $vendorAddress, axis: .vertical)
                    TextField(L10n.Detail.nip.localized, text: $vendorNIP)
                }

                Section(L10n.Detail.amount.localized) {
                    HStack {
                        TextField(L10n.Edit.amountPlaceholder.localized, text: $amount)
                            .keyboardType(.decimalPad)

                        Picker(L10n.Edit.currency.localized, selection: $currency) {
                            ForEach(SettingsManager.availableCurrencies, id: \.self) { curr in
                                Text(curr).tag(curr)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section(L10n.Edit.documentNumber.localized) {
                    DatePicker(L10n.Detail.dueDate.localized, selection: $dueDate, displayedComponents: .date)
                    TextField(L10n.Edit.documentNumberPlaceholder.localized, text: $documentNumber)
                    TextField(L10n.Detail.bankAccount.localized, text: $bankAccountNumber)
                }

                Section(L10n.Detail.notes.localized) {
                    TextField(L10n.Edit.notesPlaceholder.localized, text: $notes, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .navigationTitle(L10n.Detail.editDocument.localized)
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
            .overlay {
                if isSaving {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView(L10n.Edit.saving.localized)
                                .padding()
                                .background(Color(UIColor.systemBackground).opacity(0.95))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
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
            document.vendorAddress = vendorAddress.isEmpty ? nil : vendorAddress
            document.bankAccountNumber = bankAccountNumber.isEmpty ? nil : bankAccountNumber

            let updateUseCase = environment.makeUpdateDocumentUseCase()
            try await updateUseCase.execute(
                document: document,
                title: vendorName,
                vendorNIP: vendorNIP.isEmpty ? nil : vendorNIP,
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
        DocumentDetailView(documentId: UUID())
            .environment(AppEnvironment.preview)
    }
}
