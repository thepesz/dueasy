import SwiftUI
import os.log

/// Document review screen for editing extracted fields and finalizing the document.
struct DocumentReviewView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: DocumentReviewViewModel
    @State private var showPermissionAlert = false

    private let logger = Logger(subsystem: "com.dueasy.app", category: "DocumentReview")

    let onSave: () -> Void

    init(
        document: FinanceDocument,
        images: [UIImage],
        environment: AppEnvironment,
        onSave: @escaping () -> Void
    ) {
        self.onSave = onSave
        _viewModel = State(initialValue: DocumentReviewViewModel(
            document: document,
            images: images,
            extractUseCase: environment.makeExtractAndSuggestFieldsUseCase(),
            finalizeUseCase: environment.makeFinalizeInvoiceUseCase(),
            checkPermissionsUseCase: environment.makeCheckPermissionsUseCase(),
            settingsManager: environment.settingsManager,
            keywordLearningService: environment.keywordLearningService,
            learningDataService: environment.learningDataService
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Permission prompt (if needed)
                    if viewModel.needsPermissions && !viewModel.isProcessingOCR {
                        permissionPrompt
                    }

                    // Document preview
                    documentPreview

                    // OCR status
                    if viewModel.isProcessingOCR {
                        ocrProcessingView
                    } else if viewModel.hasLowConfidence {
                        lowConfidenceWarning
                    }

                    // Form fields
                    formFields

                    // Calendar settings
                    calendarSettings

                    // Reminder settings
                    reminderSettings

                    // Validation errors
                    if !viewModel.validationErrors.isEmpty {
                        validationErrorsView
                    }

                    // Save button
                    saveButton
                }
                .padding(Spacing.md)
            }
            .navigationTitle(L10n.Review.title.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .top) {
                if let error = viewModel.error {
                    ErrorBanner(error: error, onDismiss: { viewModel.clearError() })
                        .padding()
                }
            }
            .loadingOverlay(isLoading: viewModel.isSaving, message: "Saving...")
        }
        .task {
            await viewModel.checkPermissions()
            await viewModel.processImages()
        }
        .interactiveDismissDisabled(viewModel.isSaving)
    }

    // MARK: - Permission Prompt

    @ViewBuilder
    private var permissionPrompt: some View {
        Card.glass {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(L10n.Review.permissionsNeeded.localized)
                        .font(Typography.headline)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if !viewModel.calendarPermissionGranted {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "calendar")
                                .font(.caption)
                            Text(L10n.Review.calendarPermissionNeeded.localized)
                                .font(Typography.caption1)
                        }
                        .foregroundStyle(.secondary)
                    }

                    if !viewModel.notificationPermissionGranted {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "bell")
                                .font(.caption)
                            Text(L10n.Review.notificationPermissionNeeded.localized)
                                .font(Typography.caption1)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Button {
                        Task {
                            await viewModel.requestPermissions()
                        }
                    } label: {
                        HStack {
                            if viewModel.isRequestingPermissions {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(L10n.Review.grantPermissions.localized)
                        }
                        .font(Typography.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(AppColors.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
                    }
                    .disabled(viewModel.isRequestingPermissions)
                }
            }
        }
    }

    // MARK: - Document Preview

    @ViewBuilder
    private var documentPreview: some View {
        if let firstImage = viewModel.images.first {
            VStack(spacing: Spacing.xs) {
                Image(uiImage: firstImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    }

                if viewModel.images.count > 1 {
                    Text("\(viewModel.images.count) pages scanned")
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - OCR Status

    @ViewBuilder
    private var ocrProcessingView: some View {
        Card.glass {
            HStack(spacing: Spacing.sm) {
                ProgressView()

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(L10n.Review.analyzing.localized)
                        .font(Typography.subheadline)

                    Text(L10n.Review.analyzingSubtitle.localized)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var lowConfidenceWarning: some View {
        WarningBanner(
            message: "Some fields may not be accurate",
            suggestion: "Please review and correct the extracted values"
        )
    }

    // MARK: - Form Fields

    @ViewBuilder
    private var formFields: some View {
        VStack(spacing: Spacing.md) {
            // Vendor name
            FormField(label: L10n.Review.vendorLabel.localized, isRequired: true) {
                TextField(L10n.Review.vendorPlaceholder.localized, text: $viewModel.vendorName, axis: .vertical)
                    .textContentType(.organizationName)
                    .lineLimit(2...4)
            }

            // Vendor address (optional - always show for manual entry)
            FormField(label: L10n.Review.vendorAddressLabel.localized, isRequired: false) {
                TextField(L10n.Review.vendorAddressPlaceholder.localized, text: $viewModel.vendorAddress, axis: .vertical)
                    .textContentType(.fullStreetAddress)
                    .lineLimit(2...5)
            }

            // Amount with dropdown for multiple detected amounts
            amountSection

            // Due date
            FormField(label: L10n.Review.dueDateLabel.localized, isRequired: true) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    DatePicker(
                        "Due Date",
                        selection: $viewModel.dueDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .onChange(of: viewModel.dueDate) { _, _ in
                        viewModel.checkDueDateWarning()
                    }

                    if viewModel.showDueDateWarning {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text("This date is in the past")
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

            // Bank account number (always show for manual entry)
            FormField(label: L10n.Review.bankAccountLabel.localized, isRequired: false) {
                TextField(L10n.Review.bankAccountPlaceholder.localized, text: $viewModel.bankAccountNumber, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
            }

            // Notes (optional)
            FormField(label: L10n.Review.notesLabel.localized, isRequired: false) {
                TextField(L10n.Review.notesPlaceholder.localized, text: $viewModel.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }

    // MARK: - Amount Section with Dropdown

    @ViewBuilder
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Amount and currency row
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

            // Amount suggestions dropdown (if multiple amounts detected)
            if viewModel.suggestedAmounts.count > 1 {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(L10n.Review.detectedAmounts.localized)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xs) {
                            ForEach(Array(viewModel.suggestedAmounts.enumerated()), id: \.offset) { index, suggestion in
                                AmountSuggestionChip(
                                    amount: suggestion.value,
                                    context: suggestion.context,
                                    currency: viewModel.currency,
                                    isSelected: index == viewModel.selectedAmountIndex
                                ) {
                                    viewModel.selectAmount(at: index)
                                }
                            }
                        }
                    }
                }
                .padding(.top, Spacing.xxs)
            }
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
                    .foregroundStyle(viewModel.addToCalendar ? AppColors.primary : .secondary)

                if !viewModel.addToCalendar {
                    Text(L10n.Review.remindersRequireCalendar.localized)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }

                FlowLayout(spacing: Spacing.xs) {
                    ForEach(SettingsManager.availableReminderOffsets, id: \.self) { offset in
                        ReminderChip(
                            offset: offset,
                            isSelected: viewModel.reminderOffsets.contains(offset)
                        ) {
                            viewModel.toggleReminderOffset(offset)
                        }
                        .disabled(!viewModel.addToCalendar)
                        .opacity(viewModel.addToCalendar ? 1.0 : 0.5)
                    }
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
                    dismiss()
                }
            }
        }
        .disabled(!viewModel.canSave)
    }
}

// MARK: - Form Field

struct FormField<Content: View>: View {
    let label: String
    let isRequired: Bool
    let content: () -> Content

    init(
        label: String,
        isRequired: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.isRequired = isRequired
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xxs) {
                Text(label)
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)

                if isRequired {
                    Text("*")
                        .font(Typography.caption1)
                        .foregroundStyle(AppColors.error)
                }
            }

            content()
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Reminder Chip

struct ReminderChip: View {
    let offset: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typography.caption1)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(isSelected ? AppColors.primary : AppColors.secondaryBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        switch offset {
        case 0:
            return "Due date"
        case 1:
            return "1 day"
        default:
            return "\(offset) days"
        }
    }
}

// MARK: - Amount Suggestion Chip

struct AmountSuggestionChip: View {
    let amount: Decimal
    let context: String
    let currency: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedAmount)
                    .font(Typography.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(truncatedContext)
                    .font(Typography.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(isSelected ? AppColors.primary : AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .strokeBorder(AppColors.primary, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }

    private var truncatedContext: String {
        let cleaned = context
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.count > 30 {
            return String(cleaned.prefix(30)) + "..."
        }
        return cleaned
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                     y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + maxHeight)
        }
    }
}

// MARK: - Preview

#Preview {
    DocumentReviewView(
        document: FinanceDocument(type: .invoice),
        images: [],
        environment: AppEnvironment.preview,
        onSave: {}
    )
    .environment(AppEnvironment.preview)
}
