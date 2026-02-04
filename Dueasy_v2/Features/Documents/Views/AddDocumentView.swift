import SwiftUI

/// Add document entry point screen.
/// Allows selecting document type and input method (scan, PDF, photo, manual).
///
/// UI STYLE: Adapts to the current UI style (Midnight Aurora, Paper Minimal, Warm Finance)
/// based on user preference from SettingsManager.uiStyleOtherViews.
struct AddDocumentView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel: AddDocumentViewModel

    /// Current UI style from settings
    private var currentStyle: UIStyleProposal {
        environment.settingsManager.uiStyle(for: .otherViews)
    }

    /// Design tokens for the current style
    private var tokens: UIStyleTokens {
        UIStyleTokens(style: currentStyle)
    }
    @State private var selectedType: DocumentType = .invoice
    @State private var showingScanner = false
    @State private var showingPhotoPicker = false
    @State private var showingPDFPicker = false
    @State private var showingManualEntry = false
    @State private var showingReview = false
    @State private var scannedImages: [UIImage] = []
    @State private var appeared = false

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: AddDocumentViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    // Document type selection
                    documentTypeSection
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3), value: appeared)

                    // Input method selection
                    inputMethodSection
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.1), value: appeared)
                }
                .padding(Spacing.sm)
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background {
                // Style-aware background
                StyledAddDocumentBackground()
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
            // Scanner sheet
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
            // Photo picker sheet
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPickerView(
                    maxSelectionCount: 10,
                    onPhotosSelected: { images in
                        scannedImages = images
                        showingPhotoPicker = false
                        Task {
                            await handleImportedPhotos(images)
                        }
                    },
                    onCancel: {
                        showingPhotoPicker = false
                    }
                )
            }
            // PDF picker sheet
            .sheet(isPresented: $showingPDFPicker) {
                PDFPickerView(
                    onPDFSelected: { url in
                        showingPDFPicker = false
                        Task {
                            await handleImportedPDF(url)
                        }
                    },
                    onCancel: {
                        showingPDFPicker = false
                    }
                )
            }
            // Manual entry sheet
            .sheet(isPresented: $showingManualEntry) {
                ManualEntryView(
                    documentType: selectedType,
                    environment: environment,
                    onSave: {
                        showingManualEntry = false
                        dismiss()
                    },
                    onCancel: {
                        showingManualEntry = false
                    }
                )
                .environment(environment)
            }
            // Document review sheet (for scan/PDF/photo)
            .sheet(isPresented: $showingReview) {
                if let document = viewModel.currentDocument {
                    DocumentReviewView(
                        document: document,
                        images: scannedImages,
                        environment: environment,
                        onSave: {
                            showingReview = false
                            dismiss()
                        },
                        onDismiss: { saved in
                            if !saved {
                                // Delete unsaved draft to prevent "Untitled" entries
                                Task {
                                    await viewModel.deleteUnsavedDraft()
                                }
                            }
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
            .loadingOverlay(isLoading: viewModel.isProcessing, message: viewModel.processingMessage)
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
        // Apply UI style to the environment
        .environment(\.uiStyle, currentStyle)
    }

    // MARK: - Document Type Section

    @ViewBuilder
    private var documentTypeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(L10n.AddDocument.documentType.localized)
                .font(Typography.sectionTitle)
                .foregroundStyle(currentStyle == .midnightAurora ? Color.white.opacity(0.7) : .secondary)
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
                .animation(
                    reduceMotion ? .none : .easeOut(duration: 0.3).delay(Double(index) * 0.08),
                    value: appeared
                )
            }
        }
    }

    // MARK: - Input Method Section

    @ViewBuilder
    private var inputMethodSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(L10n.AddDocument.selectInputMethod.localized)
                .font(Typography.sectionTitle)
                .foregroundStyle(currentStyle == .midnightAurora ? Color.white.opacity(0.7) : .secondary)
                .padding(.horizontal, Spacing.xxs)

            // Grid of input method cards
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Spacing.xs),
                GridItem(.flexible(), spacing: Spacing.xs)
            ], spacing: Spacing.xs) {
                ForEach(Array(DocumentInputMethod.allCases.enumerated()), id: \.element) { index, method in
                    InputMethodCard(
                        method: method,
                        action: { selectInputMethod(method) }
                    )
                    .opacity(appeared ? 1 : 0)
                    .animation(
                        reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.15 + Double(index) * 0.06),
                        value: appeared
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func selectInputMethod(_ method: DocumentInputMethod) {
        switch method {
        case .scan:
            showingScanner = true
        case .importPDF:
            showingPDFPicker = true
        case .importPhoto:
            showingPhotoPicker = true
        case .manualEntry:
            showingManualEntry = true
        }
    }

    private func handleScannedImages(_ images: [UIImage]) async {
        // Delegate to ViewModel (proper MVVM flow)
        if let _ = await viewModel.handleScannedImages(images, documentType: selectedType) {
            showingReview = true
        }
    }

    private func handleImportedPhotos(_ images: [UIImage]) async {
        // Delegate to ViewModel
        if let _ = await viewModel.handleImportedPhotos(images, documentType: selectedType) {
            showingReview = true
        }
    }

    private func handleImportedPDF(_ url: URL) async {
        // Delegate to ViewModel
        if let resultImages = await viewModel.handleImportedPDF(url, documentType: selectedType) {
            scannedImages = resultImages
            showingReview = true
        }
    }
}

// MARK: - Input Method Card

struct InputMethodCard: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let method: DocumentInputMethod
    let action: () -> Void

    @State private var isPressed = false

    private var tokens: UIStyleTokens {
        UIStyleTokens(style: style)
    }

    private var accentBlue: Color {
        Color(red: 0.3, green: 0.5, blue: 1.0)
    }

    private var accentPurple: Color {
        Color(red: 0.6, green: 0.3, blue: 0.9)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                // Icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: method.isRecommended
                                    ? (style == .midnightAurora
                                        ? [accentBlue.opacity(0.3), accentPurple.opacity(0.2)]
                                        : [AppColors.primary.opacity(0.25), AppColors.primary.opacity(0.1)])
                                    : [Color.gray.opacity(0.15), Color.gray.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: method.iconName)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(method.isRecommended ? tokens.primaryColor(for: colorScheme) : (style == .midnightAurora ? .white : .primary))
                        .symbolRenderingMode(.hierarchical)
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: method.isRecommended
                                    ? [tokens.primaryColor(for: colorScheme).opacity(0.6), tokens.primaryColor(for: colorScheme).opacity(0.2)]
                                    : [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: method.isRecommended ? 2 : 1
                        )
                }
                .shadow(
                    color: method.isRecommended ? tokens.primaryColor(for: colorScheme).opacity(0.2) : .clear,
                    radius: 4,
                    y: 2
                )

                VStack(spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xxs) {
                        Text(method.displayName)
                            .font(Typography.buttonText)
                            .foregroundStyle(style == .midnightAurora ? .white : .primary)
                            .lineLimit(1)

                        if method.isRecommended {
                            recommendedBadge
                        }
                    }

                    Text(method.description)
                        .font(Typography.stat)
                        .foregroundStyle(style == .midnightAurora ? Color.white.opacity(0.7) : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.xs)
            .background {
                cardBackground
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: method.isRecommended
                                ? [tokens.primaryColor(for: colorScheme).opacity(0.5), tokens.primaryColor(for: colorScheme).opacity(0.2)]
                                : [Color.white.opacity(style == .midnightAurora ? 0.2 : (colorScheme == .light ? 0.6 : 0.2)), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: method.isRecommended ? 1.5 : 0.5
                    )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .light ? 0.06 : 0.15),
                radius: 8,
                y: 4
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("InputMethod_\(method.rawValue)")
        .accessibilityLabel(method.displayName)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !reduceMotion && !isPressed {
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

    @ViewBuilder
    private var cardBackground: some View {
        switch style {
        case .midnightAurora:
            // Multi-layer dark card for Midnight Aurora
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.14))
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                if method.isRecommended {
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accentBlue.opacity(0.15), accentPurple.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
        default:
            // PERFORMANCE: Uses CardMaterial for optimized single-layer blur
            CardMaterial(
                cornerRadius: CornerRadius.lg,
                addHighlight: true,
                accentColor: method.isRecommended ? AppColors.primary : nil
            )
        }
    }

    @ViewBuilder
    private var recommendedBadge: some View {
        Text(L10n.AddDocument.recommended.localized)
            .font(Typography.stat.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.xxs)
            .padding(.vertical, 2)
            .background(
                style == .midnightAurora
                    ? LinearGradient(colors: [accentBlue, accentPurple], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [AppColors.primary, AppColors.primary], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(Capsule())
    }
}

// MARK: - Document Type Row

struct DocumentTypeRow: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let type: DocumentType
    let isSelected: Bool
    let isEnabled: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    private var tokens: UIStyleTokens {
        UIStyleTokens(style: style)
    }

    private var accentBlue: Color {
        Color(red: 0.3, green: 0.5, blue: 1.0)
    }

    private var accentPurple: Color {
        Color(red: 0.6, green: 0.3, blue: 0.9)
    }

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
                                        ? (style == .midnightAurora
                                            ? [accentBlue.opacity(0.3), accentPurple.opacity(0.2)]
                                            : [AppColors.primary.opacity(0.25), AppColors.primary.opacity(0.1)])
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
                                ? (isSelected ? tokens.primaryColor(for: colorScheme) : (style == .midnightAurora ? .white : .primary))
                                : .secondary.opacity(0.5)
                        )
                        .symbolRenderingMode(.hierarchical)
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: isEnabled && isSelected
                                    ? [tokens.primaryColor(for: colorScheme).opacity(0.6), tokens.primaryColor(for: colorScheme).opacity(0.2)]
                                    : [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .shadow(
                    color: isSelected ? tokens.primaryColor(for: colorScheme).opacity(0.2) : .clear,
                    radius: 6,
                    y: 3
                )

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(type.displayName)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(isEnabled ? (style == .midnightAurora ? Color.white : Color.primary) : Color.secondary.opacity(0.5))

                    if let comingSoon = type.comingSoonMessage {
                        Text(comingSoon)
                            .font(Typography.listRowSecondary)
                            .foregroundStyle(style == .midnightAurora ? Color.white.opacity(0.6) : .secondary)
                    }
                }

                Spacer()

                if isSelected && isEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(tokens.primaryColor(for: colorScheme))
                        .symbolEffect(.bounce, options: .speed(1.5), value: isSelected)
                }
            }
            .padding(Spacing.md)
            .background {
                rowBackground
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay {
                rowBorder
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

    @ViewBuilder
    private var rowBackground: some View {
        switch style {
        case .midnightAurora:
            // Multi-layer dark card for Midnight Aurora
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.14))
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                if isSelected {
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accentBlue.opacity(0.15), accentPurple.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
        default:
            // PERFORMANCE: Uses CardMaterial for optimized single-layer blur
            CardMaterial(
                cornerRadius: CornerRadius.lg,
                addHighlight: true,
                accentColor: isSelected ? AppColors.primary : nil
            )
        }
    }

    @ViewBuilder
    private var rowBorder: some View {
        switch style {
        case .midnightAurora:
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: isSelected
                            ? [tokens.primaryColor(for: colorScheme).opacity(0.5), tokens.primaryColor(for: colorScheme).opacity(0.2)]
                            : [Color.white.opacity(0.2), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        default:
            GlassBorder(
                cornerRadius: CornerRadius.lg,
                lineWidth: isSelected ? 1.5 : 0.5,
                accentColor: isSelected ? AppColors.primary : nil
            )
        }
    }
}

// MARK: - ViewModel

/// ViewModel for AddDocumentView - handles document creation and all input method flows
@MainActor
@Observable
final class AddDocumentViewModel {

    // MARK: - Published State

    private(set) var isProcessing = false
    private(set) var processingMessage: String = ""
    private(set) var error: AppError?
    private(set) var currentDocument: FinanceDocument?

    // MARK: - Dependencies

    private let environment: AppEnvironment
    private let createDocumentUseCase: CreateDocumentUseCase
    private let scanAndAttachUseCase: ScanAndAttachFileUseCase
    private let importFromPDFUseCase: ImportFromPDFUseCase
    private let importFromPhotoUseCase: ImportFromPhotoUseCase

    // MARK: - Initialization

    init(environment: AppEnvironment) {
        self.environment = environment
        self.createDocumentUseCase = environment.makeCreateDocumentUseCase()
        self.scanAndAttachUseCase = environment.makeScanAndAttachFileUseCase()
        self.importFromPDFUseCase = environment.makeImportFromPDFUseCase()
        self.importFromPhotoUseCase = environment.makeImportFromPhotoUseCase()
    }

    // MARK: - Public Actions

    /// Handle scanned images from VisionKit scanner
    @discardableResult
    func handleScannedImages(_ images: [UIImage], documentType: DocumentType) async -> FinanceDocument? {
        guard !images.isEmpty else { return nil }

        isProcessing = true
        processingMessage = L10n.AddDocument.processing.localized
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

    /// Handle imported photos from photo library
    @discardableResult
    func handleImportedPhotos(_ images: [UIImage], documentType: DocumentType) async -> FinanceDocument? {
        guard !images.isEmpty else { return nil }

        isProcessing = true
        processingMessage = L10n.AddDocument.Processing.analyzingPhoto.localized
        error = nil

        do {
            // Step 1: Create draft document
            let document = try await createDocumentUseCase.execute(type: documentType)

            // Step 2: Import and attach photos
            _ = try await importFromPhotoUseCase.execute(images: images, document: document)

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

    /// Handle imported PDF file
    @discardableResult
    func handleImportedPDF(_ url: URL, documentType: DocumentType) async -> [UIImage]? {
        isProcessing = true
        processingMessage = L10n.AddDocument.Processing.extractingPDF.localized
        error = nil

        do {
            // Step 1: Create draft document
            let document = try await createDocumentUseCase.execute(type: documentType)

            // Step 2: Import PDF and extract images
            let result = try await importFromPDFUseCase.execute(pdfURL: url, document: document)

            // Success
            currentDocument = result.document
            isProcessing = false
            return result.images

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

    /// Delete unsaved draft document
    func deleteUnsavedDraft() async {
        guard let document = currentDocument else { return }

        do {
            let deleteUseCase = environment.makeDeleteDocumentUseCase()
            try await deleteUseCase.execute(documentId: document.id)
            currentDocument = nil
        } catch {
            // Silently fail - draft cleanup is non-critical
        }
    }

    /// Reset state
    func reset() {
        isProcessing = false
        processingMessage = ""
        error = nil
        currentDocument = nil
    }
}

// MARK: - Preview

#Preview {
    AddDocumentView(environment: .preview)
        .environment(AppEnvironment.preview)
}
