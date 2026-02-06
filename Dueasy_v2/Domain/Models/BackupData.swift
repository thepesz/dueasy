import Foundation

// MARK: - Backup Data Container

/// Root container for backup data.
/// Contains all documents, recurring templates, and recurring instances.
/// Version field enables schema evolution for future compatibility.
struct BackupData: Codable, Sendable {
    /// Schema version for backward/forward compatibility
    let version: String

    /// When this backup was created
    let exportedAt: Date

    /// Device identifier for tracking backup source
    let deviceId: String

    /// Count of documents included (for quick validation)
    let documentCount: Int

    /// All documents (metadata only, no file attachments)
    let documents: [DocumentBackupDTO]

    /// Recurring payment templates
    let recurringTemplates: [RecurringTemplateBackupDTO]

    /// Recurring payment instances
    let recurringInstances: [RecurringInstanceBackupDTO]

    /// Current schema version
    static let currentVersion = "1.0.0"

    init(
        documents: [DocumentBackupDTO],
        recurringTemplates: [RecurringTemplateBackupDTO],
        recurringInstances: [RecurringInstanceBackupDTO],
        deviceId: String
    ) {
        self.version = Self.currentVersion
        self.exportedAt = Date()
        self.deviceId = deviceId
        self.documentCount = documents.count
        self.documents = documents
        self.recurringTemplates = recurringTemplates
        self.recurringInstances = recurringInstances
    }
}

// MARK: - Document Backup DTO

/// Data transfer object for FinanceDocument backup.
/// Contains all fields except sourceFilePath (files are excluded from backup).
struct DocumentBackupDTO: Codable, Sendable, Identifiable {
    let id: UUID
    let typeRaw: String
    let title: String
    let amountValue: Double
    let currency: String
    let dueDate: Date?
    let createdAt: Date
    let updatedAt: Date
    let statusRaw: String
    let notes: String?
    let documentNumber: String?
    let vendorAddress: String?
    let vendorNIP: String?
    let bankAccountNumber: String?
    let calendarEventId: String?
    let reminderOffsetsDays: [Int]
    let notificationsEnabled: Bool
    let vendorProfileId: UUID?
    let remoteDocumentId: String?
    let remoteFileId: String?
    let analysisVersion: Int
    let analysisProvider: String?
    let documentCategoryRaw: String?
    let vendorFingerprint: String?
    let recurringTemplateId: UUID?
    let recurringInstanceId: UUID?

    /// Creates a DTO from a FinanceDocument
    init(from document: FinanceDocument) {
        self.id = document.id
        self.typeRaw = document.typeRaw
        self.title = document.title
        self.amountValue = document.amountValue
        self.currency = document.currency
        self.dueDate = document.dueDate
        self.createdAt = document.createdAt
        self.updatedAt = document.updatedAt
        self.statusRaw = document.statusRaw
        self.notes = document.notes
        self.documentNumber = document.documentNumber
        self.vendorAddress = document.vendorAddress
        self.vendorNIP = document.vendorNIP
        self.bankAccountNumber = document.bankAccountNumber
        self.calendarEventId = document.calendarEventId
        self.reminderOffsetsDays = document.reminderOffsetsDays
        self.notificationsEnabled = document.notificationsEnabled
        self.vendorProfileId = document.vendorProfileId
        self.remoteDocumentId = document.remoteDocumentId
        self.remoteFileId = document.remoteFileId
        self.analysisVersion = document.analysisVersion
        self.analysisProvider = document.analysisProvider
        self.documentCategoryRaw = document.documentCategoryRaw
        self.vendorFingerprint = document.vendorFingerprint
        self.recurringTemplateId = document.recurringTemplateId
        self.recurringInstanceId = document.recurringInstanceId
    }

    /// Applies this DTO to a FinanceDocument (for import/merge)
    func apply(to document: FinanceDocument) {
        document.typeRaw = typeRaw
        document.title = title
        document.amountValue = amountValue
        document.currency = currency
        document.dueDate = dueDate
        document.updatedAt = updatedAt
        document.statusRaw = statusRaw
        document.notes = notes
        document.documentNumber = documentNumber
        document.vendorAddress = vendorAddress
        document.vendorNIP = vendorNIP
        document.bankAccountNumber = bankAccountNumber
        document.calendarEventId = calendarEventId
        document.reminderOffsetsDays = reminderOffsetsDays
        document.notificationsEnabled = notificationsEnabled
        document.vendorProfileId = vendorProfileId
        document.remoteDocumentId = remoteDocumentId
        document.remoteFileId = remoteFileId
        document.analysisVersion = analysisVersion
        document.analysisProvider = analysisProvider
        document.documentCategoryRaw = documentCategoryRaw
        document.vendorFingerprint = vendorFingerprint
        document.recurringTemplateId = recurringTemplateId
        document.recurringInstanceId = recurringInstanceId
    }

    /// Creates a new FinanceDocument from this DTO
    func toFinanceDocument() -> FinanceDocument {
        let document = FinanceDocument(
            id: id,
            type: DocumentType(rawValue: typeRaw) ?? .invoice,
            title: title,
            amount: Decimal(amountValue),
            currency: currency,
            dueDate: dueDate,
            status: DocumentStatus(rawValue: statusRaw) ?? .draft,
            notes: notes,
            sourceFileURL: nil,  // Files are excluded from backup
            documentNumber: documentNumber,
            vendorAddress: vendorAddress,
            vendorNIP: vendorNIP,
            bankAccountNumber: bankAccountNumber,
            calendarEventId: calendarEventId,
            reminderOffsetsDays: reminderOffsetsDays,
            notificationsEnabled: notificationsEnabled,
            vendorProfileId: vendorProfileId,
            remoteDocumentId: remoteDocumentId,
            remoteFileId: remoteFileId,
            analysisVersion: analysisVersion,
            analysisProvider: analysisProvider,
            documentCategory: documentCategoryRaw.flatMap { DocumentCategory(rawValue: $0) } ?? .unknown,
            vendorFingerprint: vendorFingerprint,
            recurringTemplateId: recurringTemplateId,
            recurringInstanceId: recurringInstanceId
        )
        // Restore original timestamps
        document.createdAt = createdAt
        document.updatedAt = updatedAt
        return document
    }
}

// MARK: - Recurring Template Backup DTO

/// Data transfer object for RecurringTemplate backup.
struct RecurringTemplateBackupDTO: Codable, Sendable, Identifiable {
    let id: UUID
    let vendorFingerprint: String
    let vendorOnlyFingerprint: String?
    let amountBucket: String?
    let vendorDisplayName: String
    let vendorShortName: String?
    let documentCategoryRaw: String
    let dueDayOfMonth: Int
    let toleranceDays: Int
    let reminderOffsetsDays: [Int]
    let amountMinString: String?
    let amountMaxString: String?
    let currency: String
    let iban: String?
    let isActive: Bool
    let creationSourceRaw: String
    let createdAt: Date
    let updatedAt: Date
    let matchedDocumentCount: Int
    let paidInstanceCount: Int
    let missedInstanceCount: Int

    /// Creates a DTO from a RecurringTemplate
    init(from template: RecurringTemplate) {
        self.id = template.id
        self.vendorFingerprint = template.vendorFingerprint
        self.vendorOnlyFingerprint = template.vendorOnlyFingerprint
        self.amountBucket = template.amountBucket
        self.vendorDisplayName = template.vendorDisplayName
        self.vendorShortName = template.vendorShortName
        self.documentCategoryRaw = template.documentCategoryRaw
        self.dueDayOfMonth = template.dueDayOfMonth
        self.toleranceDays = template.toleranceDays
        self.reminderOffsetsDays = template.reminderOffsetsDays
        // Store amounts as strings to preserve decimal precision
        self.amountMinString = template.amountMin.map { "\($0)" }
        self.amountMaxString = template.amountMax.map { "\($0)" }
        self.currency = template.currency
        self.iban = template.iban
        self.isActive = template.isActive
        self.creationSourceRaw = template.creationSourceRaw
        self.createdAt = template.createdAt
        self.updatedAt = template.updatedAt
        self.matchedDocumentCount = template.matchedDocumentCount
        self.paidInstanceCount = template.paidInstanceCount
        self.missedInstanceCount = template.missedInstanceCount
    }

    /// Creates a new RecurringTemplate from this DTO
    func toRecurringTemplate() -> RecurringTemplate {
        let amountMin = amountMinString.flatMap { Decimal(string: $0) }
        let amountMax = amountMaxString.flatMap { Decimal(string: $0) }

        let template = RecurringTemplate(
            id: id,
            vendorFingerprint: vendorFingerprint,
            vendorOnlyFingerprint: vendorOnlyFingerprint,
            amountBucket: amountBucket,
            vendorDisplayName: vendorDisplayName,
            vendorShortName: vendorShortName,
            documentCategory: DocumentCategory(rawValue: documentCategoryRaw) ?? .unknown,
            dueDayOfMonth: dueDayOfMonth,
            toleranceDays: toleranceDays,
            reminderOffsetsDays: reminderOffsetsDays,
            amountMin: amountMin,
            amountMax: amountMax,
            currency: currency,
            iban: iban,
            isActive: isActive,
            creationSource: TemplateCreationSource(rawValue: creationSourceRaw) ?? .manual
        )
        // Restore original timestamps and stats
        template.createdAt = createdAt
        template.updatedAt = updatedAt
        template.matchedDocumentCount = matchedDocumentCount
        template.paidInstanceCount = paidInstanceCount
        template.missedInstanceCount = missedInstanceCount
        return template
    }

    /// Applies this DTO to a RecurringTemplate (for import/merge)
    func apply(to template: RecurringTemplate) {
        template.vendorFingerprint = vendorFingerprint
        template.vendorOnlyFingerprint = vendorOnlyFingerprint
        template.amountBucket = amountBucket
        template.vendorDisplayName = vendorDisplayName
        template.vendorShortName = vendorShortName
        template.documentCategoryRaw = documentCategoryRaw
        template.dueDayOfMonth = dueDayOfMonth
        template.toleranceDays = toleranceDays
        template.reminderOffsetsDays = reminderOffsetsDays
        if let minStr = amountMinString, let min = Decimal(string: minStr) {
            template.amountMin = min
        }
        if let maxStr = amountMaxString, let max = Decimal(string: maxStr) {
            template.amountMax = max
        }
        template.currency = currency
        template.iban = iban
        template.isActive = isActive
        template.creationSourceRaw = creationSourceRaw
        template.updatedAt = updatedAt
        template.matchedDocumentCount = matchedDocumentCount
        template.paidInstanceCount = paidInstanceCount
        template.missedInstanceCount = missedInstanceCount
    }
}

// MARK: - Recurring Instance Backup DTO

/// Data transfer object for RecurringInstance backup.
struct RecurringInstanceBackupDTO: Codable, Sendable, Identifiable {
    let id: UUID
    let templateId: UUID
    let periodKey: String
    let expectedDueDate: Date
    let expectedAmountValue: Double?
    let statusRaw: String
    let matchedDocumentId: UUID?
    let finalDueDate: Date?
    let finalAmountValue: Double?
    let invoiceNumber: String?
    let matchedAt: Date?
    let scheduledNotificationIds: [String]
    let notificationsScheduled: Bool
    let calendarEventId: String?
    let createdAt: Date
    let updatedAt: Date

    /// Creates a DTO from a RecurringInstance
    init(from instance: RecurringInstance) {
        self.id = instance.id
        self.templateId = instance.templateId
        self.periodKey = instance.periodKey
        self.expectedDueDate = instance.expectedDueDate
        self.expectedAmountValue = instance.expectedAmountValue
        self.statusRaw = instance.statusRaw
        self.matchedDocumentId = instance.matchedDocumentId
        self.finalDueDate = instance.finalDueDate
        self.finalAmountValue = instance.finalAmountValue
        self.invoiceNumber = instance.invoiceNumber
        self.matchedAt = instance.matchedAt
        self.scheduledNotificationIds = instance.scheduledNotificationIds
        self.notificationsScheduled = instance.notificationsScheduled
        self.calendarEventId = instance.calendarEventId
        self.createdAt = instance.createdAt
        self.updatedAt = instance.updatedAt
    }

    /// Creates a new RecurringInstance from this DTO
    func toRecurringInstance() -> RecurringInstance {
        let instance = RecurringInstance(
            id: id,
            templateId: templateId,
            periodKey: periodKey,
            expectedDueDate: expectedDueDate,
            expectedAmount: expectedAmountValue.map { Decimal($0) },
            status: RecurringInstanceStatus(rawValue: statusRaw) ?? .expected
        )
        // Restore matched document data
        instance.matchedDocumentId = matchedDocumentId
        instance.finalDueDate = finalDueDate
        instance.finalAmountValue = finalAmountValue
        instance.invoiceNumber = invoiceNumber
        instance.matchedAt = matchedAt
        instance.scheduledNotificationIds = scheduledNotificationIds
        instance.notificationsScheduled = notificationsScheduled
        instance.calendarEventId = calendarEventId
        // Restore timestamps
        instance.createdAt = createdAt
        instance.updatedAt = updatedAt
        return instance
    }

    /// Applies this DTO to a RecurringInstance (for import/merge)
    func apply(to instance: RecurringInstance) {
        instance.templateId = templateId
        instance.periodKey = periodKey
        instance.expectedDueDate = expectedDueDate
        instance.expectedAmountValue = expectedAmountValue
        instance.statusRaw = statusRaw
        instance.matchedDocumentId = matchedDocumentId
        instance.finalDueDate = finalDueDate
        instance.finalAmountValue = finalAmountValue
        instance.invoiceNumber = invoiceNumber
        instance.matchedAt = matchedAt
        instance.scheduledNotificationIds = scheduledNotificationIds
        instance.notificationsScheduled = notificationsScheduled
        instance.calendarEventId = calendarEventId
        instance.updatedAt = updatedAt
    }
}

// MARK: - Backup Result Types

/// Result of a successful backup export
struct BackupExportResult: Sendable {
    /// URL of the exported backup file (temporary location for sharing)
    let fileURL: URL

    /// Number of documents exported
    let documentCount: Int

    /// Number of recurring templates exported
    let templateCount: Int

    /// Number of recurring instances exported
    let instanceCount: Int

    /// When the export was created
    let exportedAt: Date

    /// Size of the exported file in bytes
    let fileSize: Int64
}

/// Result of a successful backup import
struct BackupImportResult: Sendable {
    /// Number of documents created (new)
    let documentsCreated: Int

    /// Number of documents updated (existing, newer in backup)
    let documentsUpdated: Int

    /// Number of documents skipped (existing, older in backup)
    let documentsSkipped: Int

    /// Number of recurring templates created
    let templatesCreated: Int

    /// Number of recurring templates updated
    let templatesUpdated: Int

    /// Number of recurring templates skipped
    let templatesSkipped: Int

    /// Number of recurring instances created
    let instancesCreated: Int

    /// Number of recurring instances updated
    let instancesUpdated: Int

    /// Number of recurring instances skipped
    let instancesSkipped: Int

    /// Backup version that was imported
    let backupVersion: String

    /// When the backup was originally created
    let backupDate: Date

    /// Total items imported (created + updated)
    var totalImported: Int {
        documentsCreated + documentsUpdated +
        templatesCreated + templatesUpdated +
        instancesCreated + instancesUpdated
    }

    /// Total items skipped
    var totalSkipped: Int {
        documentsSkipped + templatesSkipped + instancesSkipped
    }
}

/// Information about an available backup (for listing)
struct BackupInfo: Sendable, Identifiable {
    /// Unique identifier (filename or iCloud record ID)
    let id: String

    /// When the backup was created
    let date: Date

    /// Number of documents in the backup
    let documentCount: Int

    /// File size in bytes
    let fileSize: Int64

    /// Source of the backup (local export, iCloud auto-backup)
    let source: BackupSource

    /// Whether this is the latest auto-backup
    let isLatest: Bool
}

/// Source of a backup
enum BackupSource: String, Codable, Sendable {
    case localExport = "local"
    case iCloudAutoBackup = "icloud"
}

// MARK: - Backup Errors

/// Errors that can occur during backup operations
enum BackupError: LocalizedError, Equatable {
    // Password errors
    case passwordTooWeak
    case passwordMismatch

    // Encryption errors
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidSalt
    case invalidNonce

    // Format errors
    case invalidBackupFormat
    case versionMismatch(expected: String, found: String)
    case corruptedData
    case emptyBackup

    // File errors
    case fileNotFound
    case fileReadFailed(String)
    case fileWriteFailed(String)
    case insufficientSpace

    // iCloud errors
    case iCloudUnavailable
    case iCloudAccountChanged
    case iCloudQuotaExceeded
    case iCloudSyncInProgress

    // Database errors
    case databaseError(String)
    case mergeConflict(String)

    // Access control errors
    case requiresAppleSignIn

    var errorDescription: String? {
        switch self {
        case .passwordTooWeak:
            return L10n.Backup.Errors.passwordTooWeak.localized
        case .passwordMismatch:
            return L10n.Backup.Errors.passwordMismatch.localized
        case .encryptionFailed(let reason):
            return L10n.Backup.Errors.encryptionFailed.localized(with: reason)
        case .decryptionFailed(let reason):
            return L10n.Backup.Errors.decryptionFailed.localized(with: reason)
        case .invalidSalt, .invalidNonce:
            return L10n.Backup.Errors.invalidEncryptionParams.localized
        case .invalidBackupFormat:
            return L10n.Backup.Errors.invalidFormat.localized
        case .versionMismatch(let expected, let found):
            return L10n.Backup.Errors.versionMismatch.localized(with: expected, found)
        case .corruptedData:
            return L10n.Backup.Errors.corruptedData.localized
        case .emptyBackup:
            return L10n.Backup.Errors.emptyBackup.localized
        case .fileNotFound:
            return L10n.Backup.Errors.fileNotFound.localized
        case .fileReadFailed(let reason):
            return L10n.Backup.Errors.fileReadFailed.localized(with: reason)
        case .fileWriteFailed(let reason):
            return L10n.Backup.Errors.fileWriteFailed.localized(with: reason)
        case .insufficientSpace:
            return L10n.Backup.Errors.insufficientSpace.localized
        case .iCloudUnavailable:
            return L10n.Backup.Errors.iCloudUnavailable.localized
        case .iCloudAccountChanged:
            return L10n.Backup.Errors.iCloudAccountChanged.localized
        case .iCloudQuotaExceeded:
            return L10n.Backup.Errors.iCloudQuotaExceeded.localized
        case .iCloudSyncInProgress:
            return L10n.Backup.Errors.iCloudSyncInProgress.localized
        case .databaseError(let reason):
            return L10n.Backup.Errors.databaseError.localized(with: reason)
        case .mergeConflict(let reason):
            return L10n.Backup.Errors.mergeConflict.localized(with: reason)
        case .requiresAppleSignIn:
            return L10n.Backup.Errors.requiresAppleSignIn.localized
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .passwordTooWeak:
            return L10n.Backup.Recovery.passwordTooWeak.localized
        case .passwordMismatch, .decryptionFailed:
            return L10n.Backup.Recovery.wrongPassword.localized
        case .iCloudUnavailable:
            return L10n.Backup.Recovery.enableiCloud.localized
        case .insufficientSpace:
            return L10n.Backup.Recovery.freeSpace.localized
        case .versionMismatch:
            return L10n.Backup.Recovery.updateApp.localized
        default:
            return nil
        }
    }
}

// MARK: - Encrypted Backup Container

/// Container format for encrypted backup files.
/// Stores salt, nonce, and ciphertext together for self-contained decryption.
struct EncryptedBackupContainer: Codable {
    /// Magic bytes to identify DuEasy backup files
    static let magicBytes: [UInt8] = [0x44, 0x55, 0x45, 0x41, 0x53, 0x59] // "DUEASY"

    /// Container format version
    let containerVersion: Int

    /// Salt used for PBKDF2 key derivation (32 bytes)
    let salt: Data

    /// Nonce used for AES-GCM encryption (12 bytes)
    let nonce: Data

    /// Encrypted backup data (includes authentication tag)
    let ciphertext: Data

    /// Current container version
    static let currentContainerVersion = 1

    init(salt: Data, nonce: Data, ciphertext: Data) {
        self.containerVersion = Self.currentContainerVersion
        self.salt = salt
        self.nonce = nonce
        self.ciphertext = ciphertext
    }
}
