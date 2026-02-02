import SwiftUI

/// Manual entry form for creating documents without scanning.
/// Provides all fields for the user to fill in manually.
struct ManualEntryView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: ManualEntryViewModel
    @State private var appeared = false

    let documentType: DocumentType
    let onSave: () -> Void
    let onCancel: () -> Void

    init(
        documentType: DocumentType,
        environment: AppEnvironment,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.documentType = documentType
        self.onSave = onSave
        self.onCancel = onCancel
        _viewModel = State(initialValue: ManualEntryViewModel(
            documentType: documentType,
            environment: environment
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Header info
                    infoCard
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3), value: appeared)

                    // Form fields
                    formFields
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.1), value: appeared)

                    // Calendar settings
                    calendarSettings
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.15), value: appeared)

                    // Reminder settings - only show when calendar is enabled
                    if viewModel.addToCalendar {
                        reminderSettings
                            .opacity(appeared ? 1 : 0)
                            .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.2), value: appeared)
                    }

                    // Invoice paid toggle
                    invoicePaidSettings
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.25), value: appeared)

                    // Validation errors
                    if !viewModel.validationErrors.isEmpty {
                        validationErrorsView
                    }

                    // Save button
                    saveButton
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.3), value: appeared)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background {
                GradientBackgroundFixed()
            }
            .navigationTitle(L10n.AddDocument.InputMethod.manualEntry.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel.localized) {
                        onCancel()
                    }
                }
            }
            .overlay(alignment: .top) {
                if let error = viewModel.error {
                    ErrorBanner(error: error, onDismiss: { viewModel.clearError() })
                        .padding()
                }
            }
            .loadingOverlay(isLoading: viewModel.isSaving, message: L10n.Review.saving.localized)
        }
        .interactiveDismissDisabled(viewModel.isSaving)
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

    // MARK: - Info Card

    @ViewBuilder
    private var infoCard: some View {
        Card.glass {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppColors.info)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(L10n.AddDocument.ManualEntry.infoTitle.localized)
                        .font(Typography.subheadline.weight(.semibold))

                    Text(L10n.AddDocument.ManualEntry.infoDescription.localized)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    // MARK: - Form Fields

    @ViewBuilder
    private var formFields: some View {
        VStack(spacing: Spacing.md) {
            // Vendor name (required)
            FormField(label: L10n.Review.vendorLabel.localized, isRequired: true) {
                TextField(L10n.Review.vendorPlaceholder.localized, text: $viewModel.vendorName, axis: .vertical)
                    .textContentType(.organizationName)
                    .lineLimit(2...4)
            }

            // Vendor address (optional)
            FormField(label: L10n.Review.vendorAddressLabel.localized, isRequired: false) {
                TextField(L10n.Review.vendorAddressPlaceholder.localized, text: $viewModel.vendorAddress, axis: .vertical)
                    .textContentType(.fullStreetAddress)
                    .lineLimit(2...5)
            }

            // Amount and currency
            amountSection

            // Due date (required)
            FormField(label: L10n.Review.dueDateLabel.localized, isRequired: true) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    DatePicker(
                        "Due Date",
                        selection: $viewModel.dueDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()

                    if viewModel.showDueDateWarning {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text(L10n.Review.dueDatePast.localized)
                                .font(Typography.caption1)
                        }
                        .foregroundStyle(AppColors.warning)
                    }
                }
            }

            // Document number (optional)
            FormField(label: L10n.Review.invoiceNumberLabel.localized, isRequired: false) {
                TextField(L10n.Review.invoiceNumberPlaceholder.localized, text: $viewModel.documentNumber, axis: .vertical)
                    .lineLimit(1...3)
            }

            // NIP (optional)
            FormField(label: L10n.Review.nipLabel.localized, isRequired: false) {
                TextField(L10n.Review.nipPlaceholder.localized, text: $viewModel.nip, axis: .vertical)
                    .font(Typography.monospacedBody)
                    .lineLimit(1)
            }

            // Bank account (optional)
            FormField(label: L10n.Review.bankAccountLabel.localized, isRequired: false) {
                TextField(L10n.Review.bankAccountPlaceholder.localized, text: $viewModel.bankAccountNumber, axis: .vertical)
                    .font(Typography.monospacedBody)
                    .lineLimit(1...3)
            }

            // Notes (optional)
            FormField(label: L10n.Review.notesLabel.localized, isRequired: false) {
                TextField(L10n.Review.notesPlaceholder.localized, text: $viewModel.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }

    // MARK: - Amount Section

    @ViewBuilder
    private var amountSection: some View {
        HStack(spacing: Spacing.sm) {
            FormField(label: L10n.Review.amountLabel.localized, isRequired: true) {
                TextField("0.00", text: $viewModel.amount)
                    .keyboardType(.decimalPad)
            }

            FormField(label: L10n.Review.currencyLabel.localized) {
                Picker("Currency", selection: $viewModel.currency) {
                    ForEach(SettingsManager.availableCurrencies, id: \.self) { currency in
                        Text(currency).tag(currency)
                    }
                }
                .pickerStyle(.menu)
            }
            .frame(width: 100)
        }
    }

    // MARK: - Calendar Settings

    @ViewBuilder
    private var calendarSettings: some View {
        Card.glass {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2)
                    .foregroundStyle(AppColors.primary)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(L10n.Review.addToCalendarTitle.localized)
                        .font(Typography.subheadline.weight(.semibold))
                    Text(L10n.Review.addToCalendarDescription.localized)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $viewModel.addToCalendar)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Reminder Settings

    @ViewBuilder
    private var reminderSettings: some View {
        Card.glass {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label(L10n.Review.remindersTitle.localized, systemImage: "bell.fill")
                    .font(Typography.headline)
                    .foregroundStyle(AppColors.primary)

                FlowLayout(spacing: Spacing.xs) {
                    ForEach(SettingsManager.availableReminderOffsets, id: \.self) { offset in
                        ReminderChip(
                            offset: offset,
                            isSelected: viewModel.reminderOffsets.contains(offset)
                        ) {
                            viewModel.toggleReminderOffset(offset)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Invoice Paid Settings

    @ViewBuilder
    private var invoicePaidSettings: some View {
        Card.glass {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppColors.success)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(L10n.Review.markAsPaidTitle.localized)
                        .font(Typography.subheadline.weight(.semibold))
                    Text(L10n.Review.markAsPaidDescription.localized)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $viewModel.markAsPaid)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Validation Errors

    @ViewBuilder
    private var validationErrorsView: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(viewModel.validationErrors, id: \.self) { error in
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(error)
                        .font(Typography.caption1)
                }
                .foregroundStyle(AppColors.error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Save Button

    @ViewBuilder
    private var saveButton: some View {
        PrimaryButton(
            viewModel.addToCalendar
                ? L10n.Review.saveAndAddToCalendar.localized
                : L10n.Review.saveButton.localized,
            icon: viewModel.addToCalendar ? "calendar.badge.plus" : "checkmark",
            isLoading: viewModel.isSaving
        ) {
            Task {
                let success = await viewModel.save()
                if success {
                    onSave()
                }
            }
        }
        .disabled(!viewModel.canSave)
    }
}

// MARK: - Manual Entry ViewModel

/// ViewModel for manual document entry form.
@MainActor
@Observable
final class ManualEntryViewModel {

    // MARK: - Form State

    var vendorName = ""
    var vendorAddress = ""
    var amount = ""
    var currency = "PLN"
    var dueDate = Date()
    var documentNumber = ""
    var nip = ""
    var bankAccountNumber = ""
    var notes = ""
    var addToCalendar = false // Will be initialized from SettingsManager
    var reminderOffsets: Set<Int> = [] // Will be initialized from SettingsManager
    var markAsPaid = false

    // MARK: - UI State

    private(set) var isSaving = false
    private(set) var error: AppError?
    private(set) var validationErrors: [String] = []

    // MARK: - Dependencies

    private let documentType: DocumentType
    private let environment: AppEnvironment
    private let createDocumentUseCase: CreateDocumentUseCase
    private let finalizeUseCase: FinalizeInvoiceUseCase
    private let settingsManager: SettingsManager

    // MARK: - Initialization

    init(documentType: DocumentType, environment: AppEnvironment) {
        self.documentType = documentType
        self.environment = environment
        self.createDocumentUseCase = environment.makeCreateDocumentUseCase()
        self.finalizeUseCase = environment.makeFinalizeInvoiceUseCase()
        self.settingsManager = environment.settingsManager

        // Load defaults from settings (single source of truth)
        self.currency = settingsManager.defaultCurrency
        self.reminderOffsets = Set(settingsManager.defaultReminderOffsets)
        self.addToCalendar = settingsManager.addToCalendarByDefault
    }

    // MARK: - Computed Properties

    var canSave: Bool {
        !vendorName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !amount.trimmingCharacters(in: .whitespaces).isEmpty &&
        parseAmount() != nil
    }

    var showDueDateWarning: Bool {
        dueDate < Calendar.current.startOfDay(for: Date())
    }

    // MARK: - Actions

    func save() async -> Bool {
        guard validate() else { return false }

        isSaving = true
        error = nil

        do {
            // Step 1: Create document
            let document = try await createDocumentUseCase.execute(
                type: documentType,
                title: vendorName.trimmingCharacters(in: .whitespaces)
            )

            // Step 2: Apply form values
            document.title = vendorName.trimmingCharacters(in: .whitespaces)
            document.vendorAddress = vendorAddress.isEmpty ? nil : vendorAddress
            document.amount = parseAmount() ?? 0
            document.currency = currency
            document.dueDate = dueDate
            document.documentNumber = documentNumber.isEmpty ? nil : documentNumber
            document.vendorNIP = nip.isEmpty ? nil : nip
            document.bankAccountNumber = bankAccountNumber.isEmpty ? nil : bankAccountNumber
            document.notes = notes.isEmpty ? nil : notes
            document.reminderOffsetsDays = Array(reminderOffsets).sorted(by: >)
            document.notificationsEnabled = addToCalendar
            document.analysisProvider = "manual"

            // Step 3: Finalize (schedule calendar/notifications)
            try await finalizeUseCase.execute(
                document: document,
                title: document.title,
                vendorAddress: document.vendorAddress,
                vendorNIP: document.vendorNIP,
                amount: document.amount,
                currency: document.currency,
                dueDate: document.dueDate ?? Date(),
                documentNumber: document.documentNumber,
                bankAccountNumber: document.bankAccountNumber,
                notes: document.notes,
                reminderOffsets: document.reminderOffsetsDays,
                skipCalendar: !addToCalendar
            )

            // Mark as paid if requested
            if markAsPaid {
                document.status = .paid
            }

            isSaving = false
            return true

        } catch let appError as AppError {
            error = appError
            isSaving = false
            return false
        } catch {
            self.error = .unknown(error.localizedDescription)
            isSaving = false
            return false
        }
    }

    func clearError() {
        error = nil
    }

    func toggleReminderOffset(_ offset: Int) {
        if reminderOffsets.contains(offset) {
            reminderOffsets.remove(offset)
        } else {
            reminderOffsets.insert(offset)
        }
    }

    // MARK: - Private Helpers

    private func validate() -> Bool {
        validationErrors = []

        if vendorName.trimmingCharacters(in: .whitespaces).isEmpty {
            validationErrors.append(L10n.Review.validationVendorRequired.localized)
        }

        if amount.trimmingCharacters(in: .whitespaces).isEmpty {
            validationErrors.append(L10n.Review.validationAmountRequired.localized)
        } else if parseAmount() == nil {
            validationErrors.append(L10n.Errors.validationAmountInvalid.localized)
        }

        return validationErrors.isEmpty
    }

    private func parseAmount() -> Decimal? {
        let cleaned = amount
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)

        return Decimal(string: cleaned)
    }
}

// MARK: - Preview

#Preview {
    ManualEntryView(
        documentType: .invoice,
        environment: AppEnvironment.preview,
        onSave: {},
        onCancel: {}
    )
    .environment(AppEnvironment.preview)
}
