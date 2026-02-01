import SwiftUI

/// Add document entry point screen.
/// Allows selecting document type and initiating scan.
struct AddDocumentView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: AddDocumentViewModel
    @State private var selectedType: DocumentType = .invoice
    @State private var showingScanner = false
    @State private var showingReview = false
    @State private var scannedImages: [UIImage] = []
    @State private var appeared = false

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: AddDocumentViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Modern gradient background
                GradientBackground()

                VStack(spacing: Spacing.lg) {
                    // Document type selection
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(L10n.AddDocument.documentType.localized)
                            .font(Typography.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.xxs)

                        ForEach(Array(DocumentType.allCases.enumerated()), id: \.element) { index, type in
                            DocumentTypeRow(
                                type: type,
                                isSelected: selectedType == type,
                                isEnabled: type.isEnabledInMVP
                            ) {
                                if type.isEnabledInMVP {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedType = type
                                    }
                                }
                            }
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 15)
                            .animation(
                                reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.08),
                                value: appeared
                            )
                        }
                    }

                    Spacer()

                    // Action buttons
                    VStack(spacing: Spacing.sm) {
                        PrimaryButton(L10n.AddDocument.scanDocument.localized, icon: "camera.fill") {
                            showingScanner = true
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(
                            reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(0.3),
                            value: appeared
                        )
                    }
                }
                .padding(Spacing.md)
            }
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

    private func handleScannedImages(_ images: [UIImage]) async {
        // Delegate to ViewModel (proper MVVM flow)
        if let document = await viewModel.handleScannedImages(images, documentType: selectedType) {
            showingReview = true
        }
    }
}

// MARK: - Document Type Row

struct DocumentTypeRow: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let type: DocumentType
    let isSelected: Bool
    let isEnabled: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                // Icon with gradient ring
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isEnabled
                                    ? (isSelected
                                        ? [AppColors.primary.opacity(0.25), AppColors.primary.opacity(0.1)]
                                        : [Color.gray.opacity(0.15), Color.gray.opacity(0.05)])
                                    : [Color.gray.opacity(0.1), Color.gray.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: type.iconName)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(
                            isEnabled
                                ? (isSelected ? AppColors.primary : .primary)
                                : .secondary.opacity(0.5)
                        )
                        .symbolRenderingMode(.hierarchical)
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: isEnabled && isSelected
                                    ? [AppColors.primary.opacity(0.6), AppColors.primary.opacity(0.2)]
                                    : [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .shadow(
                    color: isSelected ? AppColors.primary.opacity(0.2) : .clear,
                    radius: 6,
                    y: 3
                )

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
                        .font(.title2)
                        .foregroundStyle(AppColors.primary)
                        .symbolEffect(.bounce, options: .speed(1.5), value: isSelected)
                }
            }
            .padding(Spacing.md)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(isSelected ? AppColors.primary.opacity(0.08) : AppColors.secondaryBackground)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                            .fill(.ultraThinMaterial)

                        if isSelected {
                            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                                .fill(AppColors.primary.opacity(0.1))
                        }

                        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .light ? 0.5 : 0.1),
                                        Color.white.opacity(colorScheme == .light ? 0.2 : 0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isSelected
                                ? [AppColors.primary.opacity(0.5), AppColors.primary.opacity(0.2)]
                                : [Color.white.opacity(colorScheme == .light ? 0.6 : 0.2), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .light ? 0.06 : 0.15),
                radius: 8,
                y: 4
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !reduceMotion && !isPressed && isEnabled {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    if !reduceMotion {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isPressed = false
                        }
                    }
                }
        )
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
