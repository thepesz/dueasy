import Foundation
import UIKit
import os

/// Protocol for file storage operations.
/// Iteration 1: Local sandbox storage with iOS file protection.
/// Iteration 2: Adds optional upload tokens and remote references.
///
/// ## Path Strategy
/// Save methods return **relative paths** (e.g., `ScannedDocuments/ABC123`) instead of
/// absolute paths. This prevents file access issues after iOS app updates, which change
/// the container UUID in the path.
///
/// Load/delete methods accept **both relative and absolute paths** for backward
/// compatibility during migration. Absolute paths are resolved directly; relative
/// paths are resolved relative to the Documents directory.
///
/// **Example:**
/// - Save returns: `ScannedDocuments/ABC123.pdf`
/// - Load accepts: `ScannedDocuments/ABC123.pdf` (relative) or
///   `/var/mobile/.../Documents/ScannedDocuments/ABC123.pdf` (absolute)
protocol FileStorageServiceProtocol: Sendable {

    /// Saves document images to storage and returns the relative file path.
    /// - Parameter images: Array of images to save (typically from scanner)
    /// - Returns: **Relative path** to the saved document (e.g., `ScannedDocuments/ABC123`)
    /// - Throws: `AppError.fileStorageSaveFailed` on failure
    func saveDocumentFile(images: [UIImage]) async throws -> String

    /// Saves raw data to storage and returns the relative file path.
    /// - Parameters:
    ///   - data: Raw file data (PDF, image, etc.)
    ///   - fileExtension: File extension (e.g., "pdf", "jpg")
    /// - Returns: **Relative path** to the saved document (e.g., `ScannedDocuments/ABC123.pdf`)
    /// - Throws: `AppError.fileStorageSaveFailed` on failure
    func saveDocumentFile(data: Data, fileExtension: String) async throws -> String

    /// Loads document file as Data.
    /// - Parameter urlString: File path (relative or absolute)
    /// - Returns: File data
    /// - Throws: `AppError.fileStorageLoadFailed` or `AppError.fileStorageNotFound`
    func loadDocumentFile(urlString: String) async throws -> Data

    /// Loads document file as UIImage (for image files).
    /// - Parameter urlString: File path (relative or absolute)
    /// - Returns: UIImage if file is an image
    /// - Throws: `AppError.fileStorageLoadFailed` or `AppError.fileStorageNotFound`
    func loadDocumentImage(urlString: String) async throws -> UIImage

    /// Loads all images from a document (for multi-page scans).
    /// - Parameter urlString: File path (relative or absolute)
    /// - Returns: Array of UIImages
    /// - Throws: `AppError.fileStorageLoadFailed` or `AppError.fileStorageNotFound`
    func loadDocumentImages(urlString: String) async throws -> [UIImage]

    /// Deletes document file from storage.
    /// - Parameter urlString: File path (relative or absolute)
    /// - Throws: `AppError.fileStorageDeleteFailed`
    func deleteDocumentFile(urlString: String) async throws

    /// Checks if a file exists at the given path.
    /// - Parameter urlString: File path (relative or absolute)
    /// - Returns: True if file exists
    func fileExists(urlString: String) -> Bool

    // MARK: - Temporary File Management

    /// Creates a temporary file for processing (e.g., cloud upload).
    /// Files created here should be explicitly cleaned up after processing.
    ///
    /// SECURITY: Temporary files are:
    /// - Created in app's tmp directory (auto-cleared by iOS)
    /// - Protected with NSFileProtectionComplete
    /// - Should be manually deleted after processing for sensitive data
    ///
    /// - Parameters:
    ///   - data: File data to write
    ///   - fileExtension: File extension (e.g., "jpg", "pdf")
    /// - Returns: URL of the temporary file
    /// - Throws: `AppError.fileStorageSaveFailed` on failure
    func createTemporaryFile(data: Data, fileExtension: String) async throws -> URL

    /// Deletes a temporary file after processing.
    /// Should be called in both success and error paths.
    ///
    /// SECURITY: Explicit cleanup ensures sensitive document data
    /// is removed immediately rather than waiting for iOS cleanup.
    ///
    /// - Parameter url: URL of the temporary file to delete
    func deleteTemporaryFile(at url: URL) async

    /// Cleans up all temporary files created by this service.
    /// Call periodically or during app lifecycle events.
    ///
    /// SECURITY: Ensures no stale sensitive data remains in tmp.
    func cleanupAllTemporaryFiles() async

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

    func createTemporaryFile(data: Data, fileExtension: String) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "dueasy_\(UUID().uuidString).\(fileExtension)"
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            PrivacyLogger.storage.debug("Temporary file created: size=\(data.count)bytes")
            return fileURL
        } catch {
            PrivacyLogger.storage.error("Failed to create temporary file: \(error.localizedDescription)")
            throw AppError.fileStorageSaveFailed("Failed to create temporary file")
        }
    }

    func deleteTemporaryFile(at url: URL) async {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                PrivacyLogger.storage.debug("Temporary file deleted successfully")
            }
        } catch {
            // Log but don't throw - iOS will clean up eventually
            PrivacyLogger.storage.warning("Failed to delete temporary file: \(error.localizedDescription)")
        }
    }

    func cleanupAllTemporaryFiles() async {
        let tempDir = FileManager.default.temporaryDirectory
        let fileManager = FileManager.default

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )

            // Only delete files with our prefix
            let dueasyFiles = contents.filter { $0.lastPathComponent.hasPrefix("dueasy_") }

            var deletedCount = 0
            for fileURL in dueasyFiles {
                do {
                    try fileManager.removeItem(at: fileURL)
                    deletedCount += 1
                } catch {
                    // Continue with other files
                    PrivacyLogger.storage.warning("Failed to delete temp file during cleanup")
                }
            }

            if deletedCount > 0 {
                PrivacyLogger.storage.info("Cleaned up \(deletedCount) temporary files")
            }
        } catch {
            PrivacyLogger.storage.warning("Failed to enumerate temp directory: \(error.localizedDescription)")
        }
    }

    func getUploadURL(for documentId: String) async throws -> URL? {
        // No remote storage in Iteration 1
        return nil
    }

    func markAsUploaded(localURLString: String, remoteFileId: String) async throws {
        // No-op in Iteration 1
    }
}
