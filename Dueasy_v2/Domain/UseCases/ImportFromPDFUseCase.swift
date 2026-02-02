import Foundation
import UIKit
import PDFKit

/// Use case for importing a PDF file and preparing it for analysis.
/// Extracts pages as images and saves the original PDF to storage.
struct ImportFromPDFUseCase: Sendable {

    private let fileStorageService: FileStorageServiceProtocol
    private let repository: DocumentRepositoryProtocol

    init(
        fileStorageService: FileStorageServiceProtocol,
        repository: DocumentRepositoryProtocol
    ) {
        self.fileStorageService = fileStorageService
        self.repository = repository
    }

    /// Imports a PDF file and extracts page images for analysis.
    /// - Parameters:
    ///   - pdfURL: URL of the selected PDF file
    ///   - document: Document to attach the file to
    /// - Returns: Tuple of (updated document, extracted page images)
    /// - Throws: `AppError` on failure
    @MainActor
    func execute(
        pdfURL: URL,
        document: FinanceDocument
    ) async throws -> (document: FinanceDocument, images: [UIImage]) {
        // Step 1: Read PDF data
        guard pdfURL.startAccessingSecurityScopedResource() else {
            throw AppError.fileStorageLoadFailed("Cannot access PDF file")
        }
        defer { pdfURL.stopAccessingSecurityScopedResource() }

        guard let pdfData = try? Data(contentsOf: pdfURL) else {
            throw AppError.fileStorageLoadFailed("Cannot read PDF file")
        }

        // Step 2: Save PDF to app storage
        let savedPath = try await fileStorageService.saveDocumentFile(
            data: pdfData,
            fileExtension: "pdf"
        )
        document.sourceFileURL = savedPath
        document.markUpdated()

        // Step 3: Extract page images from PDF
        let images = try extractImagesFromPDF(data: pdfData)

        guard !images.isEmpty else {
            throw AppError.ocrNoTextFound
        }

        // Step 4: Update document in repository
        try await repository.update(document)

        return (document, images)
    }

    // MARK: - Private Helpers

    /// Extracts page images from PDF data.
    ///
    /// **Memory Optimization:**
    /// Uses autoreleasepool to release temporary objects (PDFPage, UIImage rendering buffers)
    /// after each page extraction. This prevents memory spikes when processing multi-page PDFs.
    ///
    /// - Parameter data: PDF file data
    /// - Returns: Array of UIImages for each page
    private func extractImagesFromPDF(data: Data) throws -> [UIImage] {
        guard let pdfDocument = PDFDocument(data: data) else {
            throw AppError.fileStorageLoadFailed("Invalid PDF format")
        }

        var images: [UIImage] = []
        let pageCount = min(pdfDocument.pageCount, 10) // Limit to 10 pages for performance

        for pageIndex in 0..<pageCount {
            // Use autoreleasepool to release temporary objects after each page.
            // PDF rendering creates large temporary buffers that can spike memory.
            autoreleasepool {
                guard let page = pdfDocument.page(at: pageIndex) else { return }

                // Render page at high resolution for good OCR quality
                let pageRect = page.bounds(for: .mediaBox)
                let scale: CGFloat = 2.0 // 2x scale for crisp rendering
                let width = pageRect.width * scale
                let height = pageRect.height * scale

                let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
                let image = renderer.image { context in
                    // White background
                    UIColor.white.set()
                    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

                    // Flip coordinate system for PDF rendering
                    context.cgContext.translateBy(x: 0, y: height)
                    context.cgContext.scaleBy(x: scale, y: -scale)

                    // Draw PDF page
                    page.draw(with: .mediaBox, to: context.cgContext)
                }

                images.append(image)
            }
        }

        return images
    }
}
