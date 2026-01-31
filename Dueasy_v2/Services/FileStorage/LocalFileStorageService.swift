import Foundation
import UIKit
import os.log

/// Local file storage service using the app sandbox.
/// Stores documents with iOS Data Protection enabled.
/// Iteration 1: Uses crypto service for file protection only.
/// Iteration 2: Will use crypto service for AES encryption before writing.
final class LocalFileStorageService: FileStorageServiceProtocol, @unchecked Sendable {

    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.dueasy.app", category: "FileStorage")
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

            // PRIVACY: Exclude from backup to prevent invoice scans in iCloud
            var url = documentsDirectory
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)
            logger.info("ScannedDocuments directory excluded from backup")
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

                // Apply iOS file protection
                try cryptoService.applyFileProtection(to: fileURL)
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

            logger.info("Saved document with \(images.count) pages: \(documentId)")

            return documentDirectory.path
        } catch let error as AppError {
            throw error
        } catch {
            logger.error("Failed to save document: \(error.localizedDescription)")
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
            try cryptoService.applyFileProtection(to: fileURL)

            logger.info("Saved document file: \(filename)")

            return fileURL.path
        } catch {
            logger.error("Failed to save document file: \(error.localizedDescription)")
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
            logger.error("Failed to load document file: \(error.localizedDescription)")
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
            logger.info("Deleted document file: \(urlString)")
        } catch {
            logger.error("Failed to delete document file: \(error.localizedDescription)")
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

}

// MARK: - Document Manifest

/// Metadata for a stored document
struct DocumentManifest: Codable {
    let id: String
    let pageCount: Int
    let createdAt: Date
}
