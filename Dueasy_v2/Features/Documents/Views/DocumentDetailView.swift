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
    @Environment(\.uiStyle) private var uiStyle

    let documentId: UUID

    @State private var viewModel: DocumentDetailViewModel?
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false  // Step 1: Initial confirmation
    @State private var showingRecurringDeletionSheet = false  // Step 2: Recurring options
    @State private var recurringDeletionViewModel: RecurringDeletionViewModel?

    var body: some View {
        // LAYOUT FIX (v3): Use .safeAreaInset instead of GeometryReader + ZStack
        // .safeAreaInset handles safe area calculations automatically and reliably
        ZStack {
            // Background FIRST to ensure it's rendered immediately during navigation
            StyledDetailViewBackground()
                .ignoresSafeArea()

            ScrollView {
                contentBody
            }
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                floatingButtonsHeader
            }
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
                    .environment(\.uiStyle, uiStyle)
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

    // MARK: - Aurora Style Check

    private var isAurora: Bool {
        uiStyle == .midnightAurora
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
                    .tint(isAurora ? Color.white : nil)
                Text(L10n.Common.loading.localized)
                    .font(Typography.body)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.7) : .secondary)
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
        VStack(spacing: 0) {
            // This spacer fills the safe area (status bar region) with background color
            // Without this, there would be a gap between the header and the top of the screen
            Spacer()
                .frame(height: 0)

            HStack {
                // Back button - ALWAYS visible
                StyledFloatingButton(icon: "chevron.left") {
                    dismiss()
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
                        .foregroundStyle(menuButtonColor)
                        .frame(width: 44, height: 44)
                        .background(buttonBackground, in: Circle())
                }
                .disabled(viewModel == nil)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .background(headerBackground)
    }

    /// Header background that matches the view's background color.
    /// For Aurora: Uses the exact same background color as EnhancedMidnightAuroraBackground
    /// to create a seamless appearance without a visible black bar.
    @ViewBuilder
    private var headerBackground: some View {
        if isAurora {
            // Use AuroraPalette.backgroundGradientStart for perfect match
            AuroraPalette.backgroundGradientStart
        } else {
            Color(UIColor.systemGroupedBackground)
        }
    }

    /// Menu button foreground color
    private var menuButtonColor: Color {
        if viewModel == nil {
            return Color.gray
        }
        return isAurora
            ? AuroraPalette.accentBlue
            : AppColors.primary
    }

    /// Solid background for floating buttons.
    /// Avoids material effects entirely to prevent visual style conflicts.
    private var buttonBackground: some ShapeStyle {
        if isAurora {
            return AuroraPalette.sectionBacking.opacity(0.95)
        }
        return colorScheme == .light
            ? Color(white: 0.94)
            : Color(white: 0.22)
    }

    // MARK: - Sections

    @ViewBuilder
    private func headerSection(document: FinanceDocument) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(document.type.displayName)
                    .font(Typography.sectionTitle)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)

                if let number = document.documentNumber, !number.isEmpty {
                    Text(L10n.Detail.documentNumber.localized(with: number))
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
                }
            }

            Spacer()

            StatusBadge(status: document.status, size: .large)
        }
    }

    @ViewBuilder
    private func amountSection(document: FinanceDocument) -> some View {
        StyledDetailCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(L10n.Detail.amount.localized)
                    .font(Typography.sectionTitle)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)

                Text(formattedAmount(for: document))
                    .font(Typography.heroNumber())
                    .foregroundStyle(isAurora ? Color.white : .primary)
            }
        }
    }

    @ViewBuilder
    private func detailsSection(document: FinanceDocument) -> some View {
        StyledDetailCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Vendor
                StyledDetailRow(label: L10n.Detail.vendor.localized, value: document.title.isEmpty ? L10n.Detail.notSpecified.localized : document.title)

                // Address
                if let address = document.vendorAddress, !address.isEmpty {
                    StyledDetailRow(label: L10n.Detail.address.localized, value: address)
                }

                // NIP
                if let nip = document.vendorNIP, !nip.isEmpty {
                    StyledDetailRow(label: L10n.Detail.nip.localized, value: nip)
                }

                // Bank Account
                if let bankAccount = document.bankAccountNumber, !bankAccount.isEmpty {
                    StyledDetailRow(label: L10n.Detail.bankAccount.localized, value: bankAccount)
                }

                // Due Date
                if let dueDate = document.dueDate {
                    StyledDetailRow(label: L10n.Detail.dueDate.localized, value: formattedDate(dueDate))
                }

                // Notes
                if let notes = document.notes, !notes.isEmpty {
                    StyledDetailRow(label: L10n.Detail.notes.localized, value: notes)
                }

                // Created
                StyledDetailRow(label: L10n.Detail.created.localized, value: formattedDate(document.createdAt))
            }
        }
    }

    @ViewBuilder
    private func calendarSection(document: FinanceDocument) -> some View {
        StyledDetailCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(isAurora ? AuroraPalette.accentBlue : AppColors.primary)

                    Text(L10n.Detail.calendar.localized)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(isAurora ? Color.white : .primary)

                    Spacer()

                    if document.calendarEventId != nil {
                        Text(L10n.Detail.calendarAdded.localized)
                            .font(Typography.stat)
                            .foregroundStyle(AppColors.success)
                    } else {
                        Text(L10n.Detail.calendarNotAdded.localized)
                            .font(Typography.stat)
                            .foregroundStyle(isAurora ? Color.white.opacity(0.5) : .secondary)
                    }
                }

                if document.notificationsEnabled {
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(isAurora ? AuroraPalette.accentBlue : AppColors.primary)

                        Text(L10n.DetailLabels.remindersEnabled.localized)
                            .font(Typography.bodyText)
                            .foregroundStyle(isAurora ? Color.white : .primary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionsSection(viewModel: DocumentDetailViewModel) -> some View {
        Button {
            Task { await viewModel.markAsPaid() }
        } label: {
            Label(L10n.Detail.markAsPaid.localized, systemImage: "checkmark.circle.fill")
                .font(Typography.buttonText)
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.success)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        }
        .shadow(
            color: isAurora ? AppColors.success.opacity(0.4) : .clear,
            radius: isAurora ? 8 : 0,
            y: isAurora ? 4 : 0
        )
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
    @Environment(\.uiStyle) private var uiStyle

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

    private var isAurora: Bool {
        uiStyle == .midnightAurora
    }

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
            formContent
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
                                    .background(savingOverlayBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .tint(isAurora ? Color.white : nil)
                            }
                    }
                }
        }
    }

    private var savingOverlayBackground: Color {
        isAurora
            ? Color(red: 0.08, green: 0.08, blue: 0.14).opacity(0.95)
            : Color(UIColor.systemBackground).opacity(0.95)
    }

    @ViewBuilder
    private var formContent: some View {
        if isAurora {
            auroraFormContent
        } else {
            standardFormContent
        }
    }

    // MARK: - Standard Form (non-Aurora)

    @ViewBuilder
    private var standardFormContent: some View {
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
    }

    // MARK: - Aurora Form

    @ViewBuilder
    private var auroraFormContent: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Vendor Section
                AuroraListSection(content: {
                    AuroraEditField(label: L10n.Edit.vendorNamePlaceholder.localized, text: $vendorName)
                    AuroraEditField(label: L10n.Detail.address.localized, text: $vendorAddress, axis: .vertical)
                    AuroraEditField(label: L10n.Detail.nip.localized, text: $vendorNIP, showDivider: false)
                }, header: {
                    Text(L10n.Detail.vendor.localized)
                })

                // Amount Section
                AuroraListSection(content: {
                    HStack(spacing: Spacing.sm) {
                        AuroraEditField(label: L10n.Edit.amountPlaceholder.localized, text: $amount, showDivider: false)
                            .keyboardType(.decimalPad)

                        Picker(L10n.Edit.currency.localized, selection: $currency) {
                            ForEach(SettingsManager.availableCurrencies, id: \.self) { curr in
                                Text(curr).tag(curr)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AuroraPalette.accentBlue)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }, header: {
                    Text(L10n.Detail.amount.localized)
                })

                // Document Details Section
                AuroraListSection(content: {
                    HStack {
                        Text(L10n.Detail.dueDate.localized)
                            .foregroundStyle(Color.white)
                        Spacer()
                        DatePicker("", selection: $dueDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(AuroraPalette.accentBlue)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)

                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 0.5)
                        .padding(.leading, Spacing.md)

                    AuroraEditField(label: L10n.Edit.documentNumberPlaceholder.localized, text: $documentNumber)
                    AuroraEditField(label: L10n.Detail.bankAccount.localized, text: $bankAccountNumber, showDivider: false)
                }, header: {
                    Text(L10n.Edit.documentNumber.localized)
                })

                // Notes Section
                AuroraListSection(content: {
                    AuroraEditField(label: L10n.Edit.notesPlaceholder.localized, text: $notes, axis: .vertical, showDivider: false)
                        .lineLimit(3...10)
                }, header: {
                    Text(L10n.Detail.notes.localized)
                })
            }
            .padding(.vertical, Spacing.md)
        }
        .scrollContentBackground(.hidden)
        .background { EnhancedMidnightAuroraBackground() }
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

// MARK: - Aurora Edit Field

/// Aurora-styled text field for edit forms
private struct AuroraEditField: View {
    let label: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            TextField(label, text: $text, axis: axis)
                .foregroundStyle(Color.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

            if showDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)
                    .padding(.leading, Spacing.md)
            }
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
