import Foundation
import UIKit

/// Use case for scanning a document and attaching the file.
/// Saves scanned images and updates the document with the file reference.
struct ScanAndAttachFileUseCase: Sendable {

    private let fileStorageService: FileStorageServiceProtocol
    private let repository: DocumentRepositoryProtocol

    init(
        fileStorageService: FileStorageServiceProtocol,
        repository: DocumentRepositoryProtocol
    ) {
        self.fileStorageService = fileStorageService
        self.repository = repository
    }

    /// Saves scanned images and attaches them to a document.
    /// - Parameters:
    ///   - images: Scanned images from VisionKit
    ///   - document: Document to attach the file to
    /// - Returns: Updated document with sourceFileURL set
    @MainActor
    func execute(
        images: [UIImage],
        document: FinanceDocument
    ) async throws -> FinanceDocument {
        // Save images to file storage
        let fileURLString = try await fileStorageService.saveDocumentFile(images: images)

        // Update document with file reference
        document.sourceFileURL = fileURLString
        document.markUpdated()

        try await repository.update(document)

        return document
    }
}
