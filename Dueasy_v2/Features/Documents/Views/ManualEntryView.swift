import SwiftUI

/// Manual entry form for creating documents without scanning.
/// Provides all fields for the user to fill in manually.
struct ManualEntryView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.uiStyle) private var uiStyle

    @State private var viewModel: ManualEntryViewModel
    @State private var appeared = false

    let documentType: DocumentType
    let onSave: () -> Void
    let onCancel: () -> Void

    /// Whether Aurora style is active
    private var isAurora: Bool {
        uiStyle == .midnightAurora
    }

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

                    // Recurring payment toggle
                    recurringPaymentSettings
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.3), value: appeared)

                    // Recurring settings (if enabled)
                    if viewModel.isRecurringPayment {
                        recurringDetailSettings
                            .opacity(appeared ? 1 : 0)
                            .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.35), value: appeared)
                    }

                    // Validation errors
                    if !viewModel.validationErrors.isEmpty {
                        validationErrorsView
                    }

                    // Save button
                    saveButton
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.4), value: appeared)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background {
                StyledDetailViewBackground()
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
        .sheet(isPresented: $viewModel.showFuzzyMatchSheet) {
            RecurringFuzzyMatchConfirmationSheet(
                candidates: viewModel.fuzzyMatchCandidates,
                newAmount: viewModel.parseAmount() ?? 0,
                currency: viewModel.currency,
                onSameService: { templateId in
                    viewModel.handleFuzzyMatchSameService(templateId: templateId)
                },
                onDifferentService: {
                    viewModel.handleFuzzyMatchDifferentService()
                },
                onCancel: {
                    viewModel.handleFuzzyMatchCancel()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Info Card

    @ViewBuilder
    private var infoCard: some View {
        StyledGlassCard {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppColors.info)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(L10n.AddDocument.ManualEntry.infoTitle.localized)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(isAurora ? Color.white : .primary)

                    Text(L10n.AddDocument.ManualEntry.infoDescription.localized)
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
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
                    .accessibilityIdentifier("ManualEntry_VendorName")
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
                    .environment(\.locale, LocalizationManager.shared.currentLocale)

                    if viewModel.showDueDateWarning {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(Typography.sectionIcon)
                            Text(L10n.Review.dueDatePast.localized)
                                .font(Typography.stat)
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
                    .accessibilityIdentifier("ManualEntry_Amount")
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
        StyledGlassCard {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2)
                    .foregroundStyle(isAurora ? Color(red: 0.3, green: 0.5, blue: 1.0) : AppColors.primary)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(L10n.Review.addToCalendarTitle.localized)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(isAurora ? Color.white : .primary)
                    Text(L10n.Review.addToCalendarDescription.localized)
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
                }

                Spacer()

                Toggle("", isOn: $viewModel.addToCalendar)
                    .labelsHidden()
                    .tint(isAurora ? Color(red: 0.3, green: 0.5, blue: 1.0) : nil)
            }
        }
    }

    // MARK: - Reminder Settings

    @ViewBuilder
    private var reminderSettings: some View {
        StyledGlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label(L10n.Review.remindersTitle.localized, systemImage: "bell.fill")
                    .font(Typography.sectionTitle)
                    .foregroundStyle(isAurora ? Color(red: 0.3, green: 0.5, blue: 1.0) : AppColors.primary)

                FlowLayout(spacing: Spacing.xs) {
                    ForEach(SettingsManager.availableReminderOffsets, id: \.self) { offset in
                        StyledReminderChip(
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
        StyledGlassCard {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppColors.success)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(L10n.Review.markAsPaidTitle.localized)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(isAurora ? Color.white : .primary)
                    Text(L10n.Review.markAsPaidDescription.localized)
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
                }

                Spacer()

                Toggle("", isOn: $viewModel.markAsPaid)
                    .labelsHidden()
                    .tint(isAurora ? Color(red: 0.3, green: 0.5, blue: 1.0) : nil)
            }
        }
    }

    // MARK: - Recurring Payment Settings

    @ViewBuilder
    private var recurringPaymentSettings: some View {
        StyledGlassCard {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "repeat.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isAurora ? Color(red: 0.3, green: 0.5, blue: 1.0) : AppColors.primary)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(L10n.Recurring.toggleTitle.localized)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(isAurora ? Color.white : .primary)
                    Text(L10n.Recurring.toggleDescription.localized)
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { viewModel.isRecurringPayment },
                    set: { viewModel.toggleRecurringPayment($0) }
                ))
                .labelsHidden()
                .tint(isAurora ? Color(red: 0.3, green: 0.5, blue: 1.0) : nil)
                .accessibilityIdentifier("ManualEntry_RecurringToggle")
            }
        }
    }

    @ViewBuilder
    private var recurringDetailSettings: some View {
        StyledGlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label(L10n.Recurring.settingsTitle.localized, systemImage: "gearshape.fill")
                    .font(Typography.sectionTitle)
                    .foregroundStyle(isAurora ? Color(red: 0.3, green: 0.5, blue: 1.0) : AppColors.primary)

                // Tolerance days picker
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(L10n.Recurring.toleranceDays.localized)
                            .font(Typography.bodyText)
                            .foregroundStyle(isAurora ? Color.white : .primary)
                        Text(L10n.Recurring.toleranceDaysDescription.localized)
                            .font(Typography.stat)
                            .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
                    }

                    Spacer()

                    Picker("", selection: $viewModel.recurringToleranceDays) {
                        Text("1").tag(1)
                        Text("3").tag(3)
                        Text("5").tag(5)
                        Text("7").tag(7)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                // Months ahead picker
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(L10n.Recurring.monthsAheadSetting.localized)
                            .font(Typography.bodyText)
                            .foregroundStyle(isAurora ? Color.white : .primary)
                        Text(L10n.Recurring.monthsAheadSettingDescription.localized)
                            .font(Typography.stat)
                            .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
                    }

                    Spacer()

                    Picker("", selection: $viewModel.recurringMonthsAhead) {
                        Text("3").tag(3)
                        Text("6").tag(6)
                        Text("9").tag(9)
                        Text("12").tag(12)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
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
                        .font(Typography.sectionIcon)
                    Text(error)
                        .font(Typography.stat)
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
        .accessibilityIdentifier("ManualEntry_SaveButton")
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
