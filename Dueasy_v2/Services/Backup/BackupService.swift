import Foundation
import SwiftData
import os.log
import UIKit

// MARK: - Protocol

/// Protocol for backup operations.
/// Implementations handle export, import, and backup management.
/// Protocol-based design allows swapping implementations for testing
/// and future backend integration (Iteration 2).
protocol BackupServiceProtocol: Sendable {
    /// Exports all data to an encrypted backup file.
    /// - Parameter password: Encryption password (minimum 8 characters)
    /// - Returns: Export result including file URL for sharing
    func exportBackup(password: String) async throws -> BackupExportResult

    /// Imports data from an encrypted backup file.
    /// Uses last-write-wins merge strategy based on `updatedAt` timestamps.
    /// - Parameters:
    ///   - url: URL of the backup file to import
    ///   - password: Decryption password
    /// - Returns: Import result with counts of created/updated/skipped items
    func importBackup(from url: URL, password: String) async throws -> BackupImportResult

    /// Validates a backup file without importing.
    /// Useful for showing backup info before committing to import.
    /// - Parameters:
    ///   - url: URL of the backup file to validate
    ///   - password: Decryption password
    /// - Returns: Backup info if valid
    func validateBackup(from url: URL, password: String) async throws -> BackupData

    /// Lists available iCloud backups.
    /// - Returns: Array of backup info sorted by date (newest first)
    func listAvailableBackups() async throws -> [BackupInfo]

    /// Deletes a specific backup.
    /// - Parameter id: Backup identifier
    func deleteBackup(id: String) async throws
}

// MARK: - Implementation

/// Local backup service implementation.
/// Handles export/import of encrypted JSON backups.
/// Excludes scanned files (images/PDFs) - metadata only.
///
/// **Access Control**: Requires Sign in with Apple. All export/import operations
/// validate access before proceeding (defense in depth).
final class LocalBackupService: BackupServiceProtocol, @unchecked Sendable {

    private let modelContainer: ModelContainer
    private let authBootstrapper: AuthBootstrapper
    private let logger = Logger(subsystem: "com.dueasy.app", category: "BackupService")

    /// Device identifier for tracking backup source
    private var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }

    init(modelContainer: ModelContainer, authBootstrapper: AuthBootstrapper) {
        self.modelContainer = modelContainer
        self.authBootstrapper = authBootstrapper
    }

    // MARK: - Access Control

    /// Validates that the user has access to backup features.
    /// Requires Sign in with Apple (isAppleLinked).
    /// - Throws: BackupError.requiresAppleSignIn if not authorized
    @MainActor
    private func validateBackupAccess() throws {
        guard authBootstrapper.isAppleLinked else {
            logger.warning("Backup operation blocked: user not signed in with Apple")
            throw BackupError.requiresAppleSignIn
        }
    }

    // MARK: - Export

    @MainActor
    func exportBackup(password: String) async throws -> BackupExportResult {
        logger.info("Starting backup export")

        // Defense in depth: validate user has backup access
        try validateBackupAccess()

        // Validate password
        guard BackupEncryption.isPasswordValid(password) else {
            throw BackupError.passwordTooWeak
        }

        // Fetch all data from SwiftData
        let context = modelContainer.mainContext

        // Fetch documents
        let documentDescriptor = FetchDescriptor<FinanceDocument>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let documents = try context.fetch(documentDescriptor)
        logger.info("Fetched \(documents.count) documents for backup")

        // Fetch recurring templates
        let templateDescriptor = FetchDescriptor<RecurringTemplate>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let templates = try context.fetch(templateDescriptor)
        logger.info("Fetched \(templates.count) recurring templates for backup")

        // Fetch recurring instances
        let instanceDescriptor = FetchDescriptor<RecurringInstance>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let instances = try context.fetch(instanceDescriptor)
        logger.info("Fetched \(instances.count) recurring instances for backup")

        // Convert to DTOs
        let documentDTOs = documents.map { DocumentBackupDTO(from: $0) }
        let templateDTOs = templates.map { RecurringTemplateBackupDTO(from: $0) }
        let instanceDTOs = instances.map { RecurringInstanceBackupDTO(from: $0) }

        // Create backup data container
        let backupData = BackupData(
            documents: documentDTOs,
            recurringTemplates: templateDTOs,
            recurringInstances: instanceDTOs,
            deviceId: deviceId
        )

        // Serialize to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData: Data
        do {
            jsonData = try encoder.encode(backupData)
            logger.info("Serialized backup to \(jsonData.count) bytes of JSON")
        } catch {
            logger.error("Failed to serialize backup: \(error.localizedDescription)")
            throw BackupError.encryptionFailed("Failed to serialize backup data")
        }

        // Encrypt
        let encryptedData: Data
        do {
            encryptedData = try BackupEncryption.encrypt(data: jsonData, password: password)
            logger.info("Encrypted backup to \(encryptedData.count) bytes")
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.encryptionFailed(error.localizedDescription)
        }

        // Write to temporary file for sharing
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "DuEasy_Backup_\(timestamp).dueasy"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try encryptedData.write(to: tempURL, options: [.atomic, .completeFileProtection])
            logger.info("Wrote backup to \(tempURL.path)")
        } catch {
            logger.error("Failed to write backup file: \(error.localizedDescription)")
            throw BackupError.fileWriteFailed(error.localizedDescription)
        }

        // Get file size
        let fileSize: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            fileSize = (attributes[.size] as? Int64) ?? Int64(encryptedData.count)
        } catch {
            fileSize = Int64(encryptedData.count)
        }

        return BackupExportResult(
            fileURL: tempURL,
            documentCount: documents.count,
            templateCount: templates.count,
            instanceCount: instances.count,
            exportedAt: backupData.exportedAt,
            fileSize: fileSize
        )
    }

    // MARK: - Import

    @MainActor
    func importBackup(from url: URL, password: String) async throws -> BackupImportResult {
        logger.info("Starting backup import from \(url.lastPathComponent)")

        // Defense in depth: validate user has backup access
        try validateBackupAccess()

        // Read and decrypt
        let backupData = try await validateBackup(from: url, password: password)

        // Perform merge
        let context = modelContainer.mainContext

        // Track results
        var documentsCreated = 0
        var documentsUpdated = 0
        var documentsSkipped = 0
        var templatesCreated = 0
        var templatesUpdated = 0
        var templatesSkipped = 0
        var instancesCreated = 0
        var instancesUpdated = 0
        var instancesSkipped = 0

        // Merge documents
        for dto in backupData.documents {
            let result = try await mergeDocument(dto, in: context)
            switch result {
            case .created: documentsCreated += 1
            case .updated: documentsUpdated += 1
            case .skipped: documentsSkipped += 1
            }
        }
        logger.info("Documents: \(documentsCreated) created, \(documentsUpdated) updated, \(documentsSkipped) skipped")

        // Merge recurring templates
        for dto in backupData.recurringTemplates {
            let result = try await mergeTemplate(dto, in: context)
            switch result {
            case .created: templatesCreated += 1
            case .updated: templatesUpdated += 1
            case .skipped: templatesSkipped += 1
            }
        }
        logger.info("Templates: \(templatesCreated) created, \(templatesUpdated) updated, \(templatesSkipped) skipped")

        // Merge recurring instances
        for dto in backupData.recurringInstances {
            let result = try await mergeInstance(dto, in: context)
            switch result {
            case .created: instancesCreated += 1
            case .updated: instancesUpdated += 1
            case .skipped: instancesSkipped += 1
            }
        }
        logger.info("Instances: \(instancesCreated) created, \(instancesUpdated) updated, \(instancesSkipped) skipped")

        // Save all changes
        do {
            try context.save()
            logger.info("Saved imported data to database")
        } catch {
            logger.error("Failed to save imported data: \(error.localizedDescription)")
            throw BackupError.databaseError(error.localizedDescription)
        }

        return BackupImportResult(
            documentsCreated: documentsCreated,
            documentsUpdated: documentsUpdated,
            documentsSkipped: documentsSkipped,
            templatesCreated: templatesCreated,
            templatesUpdated: templatesUpdated,
            templatesSkipped: templatesSkipped,
            instancesCreated: instancesCreated,
            instancesUpdated: instancesUpdated,
            instancesSkipped: instancesSkipped,
            backupVersion: backupData.version,
            backupDate: backupData.exportedAt
        )
    }

    // MARK: - Validate

    func validateBackup(from url: URL, password: String) async throws -> BackupData {
        // Start accessing security-scoped resource if needed
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Read file
        let encryptedData: Data
        do {
            encryptedData = try Data(contentsOf: url)
            logger.info("Read \(encryptedData.count) bytes from backup file")
        } catch {
            logger.error("Failed to read backup file: \(error.localizedDescription)")
            throw BackupError.fileReadFailed(error.localizedDescription)
        }

        // Decrypt
        let jsonData: Data
        do {
            jsonData = try BackupEncryption.decrypt(data: encryptedData, password: password)
            logger.info("Decrypted to \(jsonData.count) bytes of JSON")
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.decryptionFailed(error.localizedDescription)
        }

        // Parse JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let backupData: BackupData
        do {
            backupData = try decoder.decode(BackupData.self, from: jsonData)
            logger.info("Parsed backup: version \(backupData.version), \(backupData.documentCount) documents")
        } catch {
            logger.error("Failed to parse backup JSON: \(error.localizedDescription)")
            throw BackupError.invalidBackupFormat
        }

        // Validate version compatibility
        // For now, we only support version 1.0.0
        // Future versions should handle migration here
        if backupData.version != BackupData.currentVersion {
            // Allow newer patch versions (1.0.x) but warn about minor/major
            let backupComponents = backupData.version.split(separator: ".").compactMap { Int($0) }
            let currentComponents = BackupData.currentVersion.split(separator: ".").compactMap { Int($0) }

            if backupComponents.count >= 2 && currentComponents.count >= 2 {
                if backupComponents[0] != currentComponents[0] {
                    // Major version mismatch
                    throw BackupError.versionMismatch(
                        expected: BackupData.currentVersion,
                        found: backupData.version
                    )
                }
                // Minor/patch differences are acceptable - proceed with warning
                logger.warning("Backup version \(backupData.version) differs from current \(BackupData.currentVersion)")
            }
        }

        // Validate data integrity (non-fatal warning)
        if backupData.documentCount != backupData.documents.count {
            logger.warning("Document count mismatch: header says \(backupData.documentCount), actual \(backupData.documents.count)")
        }

        return backupData
    }

    // MARK: - List/Delete (iCloud integration)

    func listAvailableBackups() async throws -> [BackupInfo] {
        // This will be implemented when iCloud backup is added
        // For now, return empty array
        return []
    }

    func deleteBackup(id: String) async throws {
        // This will be implemented when iCloud backup is added
        logger.warning("deleteBackup not implemented for local-only service")
    }

    // MARK: - Merge Helpers

    private enum MergeResult {
        case created
        case updated
        case skipped
    }

    @MainActor
    private func mergeDocument(_ dto: DocumentBackupDTO, in context: ModelContext) async throws -> MergeResult {
        // Check if document exists
        let predicate = #Predicate<FinanceDocument> { $0.id == dto.id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        let existing = try context.fetch(descriptor).first

        if let existing = existing {
            // Document exists - use last-write-wins
            if dto.updatedAt > existing.updatedAt {
                dto.apply(to: existing)
                return .updated
            } else {
                return .skipped
            }
        } else {
            // New document - create it
            let newDocument = dto.toFinanceDocument()
            context.insert(newDocument)
            return .created
        }
    }

    @MainActor
    private func mergeTemplate(_ dto: RecurringTemplateBackupDTO, in context: ModelContext) async throws -> MergeResult {
        let predicate = #Predicate<RecurringTemplate> { $0.id == dto.id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        let existing = try context.fetch(descriptor).first

        if let existing = existing {
            if dto.updatedAt > existing.updatedAt {
                dto.apply(to: existing)
                return .updated
            } else {
                return .skipped
            }
        } else {
            let newTemplate = dto.toRecurringTemplate()
            context.insert(newTemplate)
            return .created
        }
    }

    @MainActor
    private func mergeInstance(_ dto: RecurringInstanceBackupDTO, in context: ModelContext) async throws -> MergeResult {
        let predicate = #Predicate<RecurringInstance> { $0.id == dto.id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        let existing = try context.fetch(descriptor).first

        if let existing = existing {
            if dto.updatedAt > existing.updatedAt {
                dto.apply(to: existing)
                return .updated
            } else {
                return .skipped
            }
        } else {
            let newInstance = dto.toRecurringInstance()
            context.insert(newInstance)
            return .created
        }
    }
}

// MARK: - File Type Registration

/// Backup file extension
let backupFileExtension = "dueasy"

/// UTI for DuEasy backup files
let backupFileUTI = "com.dueasy.backup"
