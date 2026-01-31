import Foundation
import UIKit

/// Protocol for file storage operations.
/// Iteration 1: Local sandbox storage with iOS file protection.
/// Iteration 2: Adds optional upload tokens and remote references.
protocol FileStorageServiceProtocol: Sendable {

    /// Saves document images to storage and returns the file URL path.
    /// - Parameter images: Array of images to save (typically from scanner)
    /// - Returns: Local file URL string for the saved document
    /// - Throws: `AppError.fileStorageSaveFailed` on failure
    func saveDocumentFile(images: [UIImage]) async throws -> String

    /// Saves raw data to storage and returns the file URL path.
    /// - Parameters:
    ///   - data: Raw file data (PDF, image, etc.)
    ///   - fileExtension: File extension (e.g., "pdf", "jpg")
    /// - Returns: Local file URL string for the saved document
    /// - Throws: `AppError.fileStorageSaveFailed` on failure
    func saveDocumentFile(data: Data, fileExtension: String) async throws -> String

    /// Loads document file as Data.
    /// - Parameter urlString: Local file URL string
    /// - Returns: File data
    /// - Throws: `AppError.fileStorageLoadFailed` or `AppError.fileStorageNotFound`
    func loadDocumentFile(urlString: String) async throws -> Data

    /// Loads document file as UIImage (for image files).
    /// - Parameter urlString: Local file URL string
    /// - Returns: UIImage if file is an image
    /// - Throws: `AppError.fileStorageLoadFailed` or `AppError.fileStorageNotFound`
    func loadDocumentImage(urlString: String) async throws -> UIImage

    /// Loads all images from a document (for multi-page scans).
    /// - Parameter urlString: Local file URL string
    /// - Returns: Array of UIImages
    /// - Throws: `AppError.fileStorageLoadFailed` or `AppError.fileStorageNotFound`
    func loadDocumentImages(urlString: String) async throws -> [UIImage]

    /// Deletes document file from storage.
    /// - Parameter urlString: Local file URL string
    /// - Throws: `AppError.fileStorageDeleteFailed`
    func deleteDocumentFile(urlString: String) async throws

    /// Checks if a file exists at the given path.
    /// - Parameter urlString: Local file URL string
    /// - Returns: True if file exists
    func fileExists(urlString: String) -> Bool

    // MARK: - Iteration 2 Extension Points (Optional)

    /// Gets an upload URL/token for remote storage.
    /// Iteration 1: Returns nil (no remote storage).
    /// Iteration 2: Returns pre-signed URL for direct upload.
    func getUploadURL(for documentId: String) async throws -> URL?

    /// Marks a file as uploaded to remote storage.
    /// Iteration 1: No-op.
    /// Iteration 2: Updates local record with remote file ID.
    func markAsUploaded(localURLString: String, remoteFileId: String) async throws
}

// MARK: - Default Implementations for Optional Methods

extension FileStorageServiceProtocol {

    func getUploadURL(for documentId: String) async throws -> URL? {
        // No remote storage in Iteration 1
        return nil
    }

    func markAsUploaded(localURLString: String, remoteFileId: String) async throws {
        // No-op in Iteration 1
    }
}
