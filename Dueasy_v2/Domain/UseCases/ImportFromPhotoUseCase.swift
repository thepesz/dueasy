import Foundation
import UIKit

/// Use case for importing photos from the photo library.
/// Saves selected photos and prepares them for analysis.
struct ImportFromPhotoUseCase: Sendable {

    private let fileStorageService: FileStorageServiceProtocol
    private let repository: DocumentRepositoryProtocol

    init(
        fileStorageService: FileStorageServiceProtocol,
        repository: DocumentRepositoryProtocol
    ) {
        self.fileStorageService = fileStorageService
        self.repository = repository
    }

    /// Imports photos and saves them to storage.
    /// - Parameters:
    ///   - images: Array of UIImages from photo picker
    ///   - document: Document to attach the photos to
    /// - Returns: Updated document
    /// - Throws: `AppError` on failure
    @MainActor
    func execute(
        images: [UIImage],
        document: FinanceDocument
    ) async throws -> FinanceDocument {
        guard !images.isEmpty else {
            throw AppError.fileStorageSaveFailed("No images provided")
        }

        // Preprocess images for better OCR quality
        let processedImages = images.map { preprocessImageForOCR($0) }

        // Save images to file storage
        let fileURLString = try await fileStorageService.saveDocumentFile(images: processedImages)

        // Update document with file reference
        document.sourceFileURL = fileURLString
        document.markUpdated()

        try await repository.update(document)

        return document
    }

    // MARK: - Private Helpers

    /// Preprocesses an image for better OCR quality.
    /// - Parameter image: Original image
    /// - Returns: Processed image optimized for OCR
    private func preprocessImageForOCR(_ image: UIImage) -> UIImage {
        // For imported photos, we apply some basic preprocessing
        // to improve OCR quality (though it won't match VisionKit scanner quality)

        guard let cgImage = image.cgImage else { return image }

        // Ensure reasonable size (not too small, not too large)
        let maxDimension: CGFloat = 2048
        let scale = min(maxDimension / CGFloat(cgImage.width), maxDimension / CGFloat(cgImage.height), 1.0)

        if scale >= 1.0 {
            // Image is already within acceptable size
            return image
        }

        // Resize image if too large
        let newWidth = CGFloat(cgImage.width) * scale
        let newHeight = CGFloat(cgImage.height) * scale

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: newWidth, height: newHeight))
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        }
    }
}
