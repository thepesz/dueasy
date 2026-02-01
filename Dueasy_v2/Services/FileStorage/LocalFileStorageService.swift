import Foundation
import UIKit
import os

/// Local file storage service using the app sandbox.
/// Stores documents with iOS Data Protection enabled.
///
/// SECURITY FEATURES:
/// - All files have iOS Data Protection (NSFileProtectionComplete)
/// - All files and directories are excluded from iCloud backup
/// - Uses crypto service for optional AES encryption (Iteration 2)
///
/// Iteration 1: Uses crypto service for file protection only.
/// Iteration 2: Will use crypto service for AES encryption before writing.
final class LocalFileStorageService: FileStorageServiceProtocol, @unchecked Sendable {

    private let fileManager = FileManager.default
    private let cryptoService: CryptoServiceProtocol

    init(cryptoService: CryptoServiceProtocol) {
        self.cryptoService = cryptoService
    }

    /// Directory for storing documents
    private var documentsDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0].appendingPathComponent("ScannedDocuments", isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: documentsDirectory.path) {
            try? fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)

            // PRIVACY: Exclude directory from backup
            excludeFromBackup(documentsDirectory)
            PrivacyLogger.logStorageMetrics(operation: "create_directory", pageCount: 0, success: true)
        }

        return documentsDirectory
    }

    // MARK: - FileStorageServiceProtocol

    func saveDocumentFile(images: [UIImage]) async throws -> String {
        guard !images.isEmpty else {
            throw AppError.fileStorageSaveFailed("No images to save")
        }

        let documentId = UUID().uuidString
        let documentDirectory = documentsDirectory.appendingPathComponent(documentId, isDirectory: true)

        do {
            // Create document directory
            try fileManager.createDirectory(at: documentDirectory, withIntermediateDirectories: true)

            // PRIVACY: Exclude document directory from backup
            excludeFromBackup(documentDirectory)

            // Save each image
            for (index, image) in images.enumerated() {
                guard let imageData = image.jpegData(compressionQuality: 0.85) else {
                    throw AppError.fileStorageSaveFailed("Failed to convert image to JPEG")
                }

                let filename = String(format: "page_%03d.jpg", index)
                let fileURL = documentDirectory.appendingPathComponent(filename)

                // Encrypt data (pass-through in Iteration 1, AES in Iteration 2)
                let encryptedData = try await cryptoService.encrypt(imageData)
                try encryptedData.write(to: fileURL)

                // Apply iOS file protection and exclude from backup
                try cryptoService.applyFileProtection(to: fileURL)
                excludeFromBackup(fileURL)
            }

            // Create manifest file with metadata
            let manifest = DocumentManifest(
                id: documentId,
                pageCount: images.count,
                createdAt: Date()
            )
            let manifestData = try JSONEncoder().encode(manifest)
            let manifestURL = documentDirectory.appendingPathComponent("manifest.json")

            // Encrypt manifest (pass-through in Iteration 1, AES in Iteration 2)
            let encryptedManifest = try await cryptoService.encrypt(manifestData)
            try encryptedManifest.write(to: manifestURL)
            try cryptoService.applyFileProtection(to: manifestURL)
            excludeFromBackup(manifestURL)

            // PRIVACY: Log only metrics, not document ID or path
            PrivacyLogger.logStorageMetrics(operation: "save", pageCount: images.count, success: true)

            return documentDirectory.path
        } catch let error as AppError {
            PrivacyLogger.logStorageMetrics(operation: "save", pageCount: images.count, success: false)
            throw error
        } catch {
            PrivacyLogger.logStorageMetrics(operation: "save", pageCount: images.count, success: false)
            PrivacyLogger.storage.error("Failed to save document: \(error.localizedDescription)")
            throw AppError.fileStorageSaveFailed(error.localizedDescription)
        }
    }

    func saveDocumentFile(data: Data, fileExtension: String) async throws -> String {
        let documentId = UUID().uuidString
        let filename = "\(documentId).\(fileExtension)"
        let fileURL = documentsDirectory.appendingPathComponent(filename)

        do {
            // Encrypt data (pass-through in Iteration 1, AES in Iteration 2)
            let encryptedData = try await cryptoService.encrypt(data)
            try encryptedData.write(to: fileURL)

            // Apply iOS file protection and exclude from backup
            try cryptoService.applyFileProtection(to: fileURL)
            excludeFromBackup(fileURL)

            // PRIVACY: Log only success, not filename
            PrivacyLogger.logStorageMetrics(operation: "save_file", pageCount: 1, success: true)

            return fileURL.path
        } catch {
            PrivacyLogger.logStorageMetrics(operation: "save_file", pageCount: 1, success: false)
            PrivacyLogger.storage.error("Failed to save document file: \(error.localizedDescription)")
            throw AppError.fileStorageSaveFailed(error.localizedDescription)
        }
    }

    func loadDocumentFile(urlString: String) async throws -> Data {
        let fileURL = URL(fileURLWithPath: urlString)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw AppError.fileStorageNotFound(urlString)
        }

        do {
            let encryptedData = try Data(contentsOf: fileURL)
            // Decrypt data (pass-through in Iteration 1, AES decryption in Iteration 2)
            return try await cryptoService.decrypt(encryptedData)
        } catch {
            PrivacyLogger.storage.error("Failed to load document file: \(error.localizedDescription)")
            throw AppError.fileStorageLoadFailed(error.localizedDescription)
        }
    }

    func loadDocumentImage(urlString: String) async throws -> UIImage {
        let data = try await loadDocumentFile(urlString: urlString)

        guard let image = UIImage(data: data) else {
            throw AppError.fileStorageLoadFailed("Invalid image data")
        }

        return image
    }

    func loadDocumentImages(urlString: String) async throws -> [UIImage] {
        let documentURL = URL(fileURLWithPath: urlString)

        // Check if it's a directory (multi-page scan)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: documentURL.path, isDirectory: &isDirectory) else {
            throw AppError.fileStorageNotFound(urlString)
        }

        if isDirectory.boolValue {
            // Load all page images from directory
            return try await loadImagesFromDirectory(documentURL)
        } else {
            // Single file
            let image = try await loadDocumentImage(urlString: urlString)
            return [image]
        }
    }

    func deleteDocumentFile(urlString: String) async throws {
        let fileURL = URL(fileURLWithPath: urlString)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            // Already deleted or doesn't exist - not an error
            return
        }

        do {
            try fileManager.removeItem(at: fileURL)
            // PRIVACY: Log only operation success, not path
            PrivacyLogger.logStorageMetrics(operation: "delete", pageCount: 0, success: true)
        } catch {
            PrivacyLogger.logStorageMetrics(operation: "delete", pageCount: 0, success: false)
            PrivacyLogger.storage.error("Failed to delete document file: \(error.localizedDescription)")
            throw AppError.fileStorageDeleteFailed(error.localizedDescription)
        }
    }

    func fileExists(urlString: String) -> Bool {
        fileManager.fileExists(atPath: urlString)
    }

    // MARK: - Private Helpers

    private func loadImagesFromDirectory(_ directoryURL: URL) async throws -> [UIImage] {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )

            // Filter for image files and sort by name
            let imageURLs = contents
                .filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "jpeg" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            var images: [UIImage] = []
            for url in imageURLs {
                let encryptedData = try Data(contentsOf: url)
                // Decrypt data (pass-through in Iteration 1, AES decryption in Iteration 2)
                let data = try await cryptoService.decrypt(encryptedData)
                if let image = UIImage(data: data) {
                    images.append(image)
                }
            }

            return images
        } catch {
            throw AppError.fileStorageLoadFailed(error.localizedDescription)
        }
    }

    // MARK: - Privacy Helpers

    /// Excludes a file or directory from iCloud backup.
    /// PRIVACY: Ensures sensitive document scans are never backed up to iCloud.
    /// - Parameter url: URL of file or directory to exclude
    @discardableResult
    private func excludeFromBackup(_ url: URL) -> Bool {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true

        do {
            try mutableURL.setResourceValues(resourceValues)
            return true
        } catch {
            PrivacyLogger.storage.warning("Failed to exclude from backup: \(error.localizedDescription)")
            return false
        }
    }

    /// Creates a secure directory with backup exclusion and file protection.
    /// PRIVACY: Use this for any directory containing sensitive data.
    /// - Parameter name: Directory name
    /// - Returns: URL of created directory
    func createSecureDirectory(name: String) throws -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let secureDir = appSupport.appendingPathComponent(name, isDirectory: true)

        try fileManager.createDirectory(at: secureDir, withIntermediateDirectories: true)

        // Exclude from backup
        excludeFromBackup(secureDir)

        // Apply file protection to directory
        try cryptoService.applyFileProtection(to: secureDir)

        PrivacyLogger.storage.debug("Created secure directory: \(name)")
        return secureDir
    }
}

// MARK: - Document Manifest

/// Metadata for a stored document.
/// PRIVACY: Contains only non-sensitive metadata (ID, page count, date).
struct DocumentManifest: Codable {
    let id: String
    let pageCount: Int
    let createdAt: Date
}
