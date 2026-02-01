import SwiftUI

/// Document detail view showing full document information.
///
/// ARCHITECTURE: This view is presented via NavigationStack from DocumentListView.
/// The parent NavigationStack is recreated after sheet dismissals to prevent
/// safe area corruption issues.
struct DocumentDetailView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let documentId: UUID

    @State private var viewModel: DocumentDetailViewModel?
    @State private var showingEditSheet = false

    var body: some View {
        ScrollView {
            if let viewModel = viewModel, let doc = viewModel.document {
                VStack(alignment: .leading, spacing: 16) {
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
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            } else {
                VStack {
                    ProgressView()
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .task {
            setupViewModel()
            await viewModel?.loadDocument()
        }
        .navigationTitle(viewModel?.document?.title ?? "Document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    if viewModel?.document?.status == .scheduled {
                        Button {
                            Task { await viewModel?.markAsPaid() }
                        } label: {
                            Label("Mark as Paid", systemImage: "checkmark.circle")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        Task { await viewModel?.deleteDocument() }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
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
    }

    // MARK: - Sections (Minimal Styling)

    @ViewBuilder
    private func headerSection(document: FinanceDocument) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let number = document.documentNumber, !number.isEmpty {
                    Text("No. \(number)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            StatusBadge(status: document.status, size: .large)
        }
    }

    @ViewBuilder
    private func amountSection(document: FinanceDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amount")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(formattedAmount(for: document))
                .font(.system(size: 32, weight: .bold, design: .rounded))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func detailsSection(document: FinanceDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Vendor
            detailRow(label: "Vendor", value: document.title.isEmpty ? "Not specified" : document.title)

            // Address
            if let address = document.vendorAddress, !address.isEmpty {
                detailRow(label: "Address", value: address)
            }

            // NIP
            if let nip = document.vendorNIP, !nip.isEmpty {
                detailRow(label: "NIP", value: nip)
            }

            // Bank Account
            if let bankAccount = document.bankAccountNumber, !bankAccount.isEmpty {
                detailRow(label: "Bank Account", value: bankAccount)
            }

            // Due Date
            if let dueDate = document.dueDate {
                detailRow(label: "Due Date", value: formattedDate(dueDate))
            }

            // Notes
            if let notes = document.notes, !notes.isEmpty {
                detailRow(label: "Notes", value: notes)
            }

            // Created
            detailRow(label: "Created", value: formattedDate(document.createdAt))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func calendarSection(document: FinanceDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)

                Text("Calendar")
                    .font(.headline)

                Spacer()

                if document.calendarEventId != nil {
                    Text("Added")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Not added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if document.notificationsEnabled {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.blue)

                    Text("Reminders enabled")
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func actionsSection(viewModel: DocumentDetailViewModel) -> some View {
        Button {
            Task { await viewModel.markAsPaid() }
        } label: {
            Label("Mark as Paid", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body)
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

// MARK: - Document Edit View (Minimal Version)

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
                Section("Vendor") {
                    TextField("Vendor Name", text: $vendorName)
                    TextField("Address", text: $vendorAddress, axis: .vertical)
                    TextField("NIP", text: $vendorNIP)
                }

                Section("Amount") {
                    HStack {
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)

                        Picker("Currency", selection: $currency) {
                            ForEach(SettingsManager.availableCurrencies, id: \.self) { curr in
                                Text(curr).tag(curr)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Details") {
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                    TextField("Document Number", text: $documentNumber)
                    TextField("Bank Account", text: $bankAccountNumber)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .navigationTitle("Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
                            ProgressView("Saving...")
                                .padding()
                                .background(.regularMaterial)
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
        DocumentDetailView(documentId: UUID())
            .environment(AppEnvironment.preview)
    }
}
