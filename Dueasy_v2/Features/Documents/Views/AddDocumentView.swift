import SwiftUI

/// Add document entry point screen.
/// Allows selecting document type and initiating scan.
struct AddDocumentView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: AddDocumentViewModel
    @State private var selectedType: DocumentType = .invoice
    @State private var showingScanner = false
    @State private var showingReview = false
    @State private var scannedImages: [UIImage] = []

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: AddDocumentViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                // Document type selection
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(L10n.AddDocument.documentType.localized)
                        .font(Typography.headline)
                        .foregroundStyle(.secondary)

                    ForEach(DocumentType.allCases) { type in
                        DocumentTypeRow(
                            type: type,
                            isSelected: selectedType == type,
                            isEnabled: type.isEnabledInMVP
                        ) {
                            if type.isEnabledInMVP {
                                selectedType = type
                            }
                        }
                    }
                }

                Spacer()

                // Action buttons
                VStack(spacing: Spacing.sm) {
                    PrimaryButton(L10n.AddDocument.scanDocument.localized, icon: "camera.fill") {
                        showingScanner = true
                    }

                    // PDF import could be added here in the future
                    // PrimaryButton.secondary("Import PDF", icon: "doc.badge.plus") {}
                }
            }
            .padding(Spacing.md)
            .navigationTitle(L10n.AddDocument.title.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel.localized) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                DocumentScannerView(
                    documentType: selectedType,
                    onScanComplete: { images in
                        scannedImages = images
                        showingScanner = false
                        Task {
                            await handleScannedImages(images)
                        }
                    },
                    onCancel: {
                        showingScanner = false
                    }
                )
                .environment(environment)
            }
            .sheet(isPresented: $showingReview) {
                if let document = viewModel.currentDocument {
                    DocumentReviewView(
                        document: document,
                        images: scannedImages,
                        environment: environment,
                        onSave: {
                            showingReview = false
                            dismiss()
                        }
                    )
                    .environment(environment)
                }
            }
            .overlay(alignment: .top) {
                if let error = viewModel.error {
                    ErrorBanner(error: error, onDismiss: viewModel.clearError)
                        .padding()
                }
            }
            .loadingOverlay(isLoading: viewModel.isProcessing, message: L10n.AddDocument.processing.localized)
        }
    }

    private func handleScannedImages(_ images: [UIImage]) async {
        // Delegate to ViewModel (proper MVVM flow)
        if let document = await viewModel.handleScannedImages(images, documentType: selectedType) {
            showingReview = true
        }
    }
}

// MARK: - Document Type Row

struct DocumentTypeRow: View {

    let type: DocumentType
    let isSelected: Bool
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: type.iconName)
                    .font(.title2)
                    .foregroundStyle(isEnabled ? (isSelected ? AppColors.primary : Color.primary) : Color.secondary.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .background(isEnabled ? (isSelected ? AppColors.primary.opacity(0.12) : AppColors.secondaryBackground) : AppColors.tertiaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(type.displayName)
                        .font(Typography.headline)
                        .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.5))

                    if let comingSoon = type.comingSoonMessage {
                        Text(comingSoon)
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected && isEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.primary)
                }
            }
            .padding(Spacing.sm)
            .background(isSelected && isEnabled ? AppColors.primary.opacity(0.05) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            .overlay {
                if isSelected && isEnabled {
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .strokeBorder(AppColors.primary.opacity(0.3), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - ViewModel

/// ViewModel for AddDocumentView - handles document creation and file attachment flow
@MainActor
@Observable
final class AddDocumentViewModel {

    // MARK: - Published State

    private(set) var isProcessing = false
    private(set) var error: AppError?
    private(set) var currentDocument: FinanceDocument?

    // MARK: - Dependencies

    private let createDocumentUseCase: CreateDocumentUseCase
    private let scanAndAttachUseCase: ScanAndAttachFileUseCase

    // MARK: - Initialization

    init(environment: AppEnvironment) {
        self.createDocumentUseCase = environment.makeCreateDocumentUseCase()
        self.scanAndAttachUseCase = environment.makeScanAndAttachFileUseCase()
    }

    // MARK: - Public Actions

    /// Handle scanned images: create document and attach files
    @discardableResult
    func handleScannedImages(_ images: [UIImage], documentType: DocumentType) async -> FinanceDocument? {
        guard !images.isEmpty else { return nil }

        isProcessing = true
        error = nil

        do {
            // Step 1: Create draft document
            let document = try await createDocumentUseCase.execute(type: documentType)

            // Step 2: Attach scanned files
            _ = try await scanAndAttachUseCase.execute(images: images, document: document)

            // Success
            currentDocument = document
            isProcessing = false
            return document

        } catch let appError as AppError {
            error = appError
            isProcessing = false
            return nil
        } catch {
            self.error = .unknown(error.localizedDescription)
            isProcessing = false
            return nil
        }
    }

    /// Clear current error
    func clearError() {
        error = nil
    }

    /// Reset state
    func reset() {
        isProcessing = false
        error = nil
        currentDocument = nil
    }
}

// MARK: - Preview

#Preview {
    AddDocumentView(environment: .preview)
        .environment(AppEnvironment.preview)
}
