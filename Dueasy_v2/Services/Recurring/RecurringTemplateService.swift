import Foundation
import SwiftData
import os.log

/// Service for managing recurring payment templates.
/// Handles creation, updates, and queries for RecurringTemplate entities.
protocol RecurringTemplateServiceProtocol: Sendable {
    /// Creates a new recurring template from a document.
    /// - Parameters:
    ///   - document: The source document
    ///   - reminderOffsets: Reminder offsets in days before due date
    ///   - toleranceDays: Tolerance for matching due dates
    ///   - creationSource: How the template was created (manual or auto-detection)
    /// - Returns: The created template
    func createTemplate(
        from document: FinanceDocument,
        reminderOffsets: [Int],
        toleranceDays: Int,
        creationSource: TemplateCreationSource
    ) async throws -> RecurringTemplate

    /// Creates a template from an auto-detection candidate.
    /// - Parameters:
    ///   - candidate: The recurring candidate
    ///   - reminderOffsets: Reminder offsets in days before due date
    ///   - toleranceDays: Tolerance for matching due dates
    /// - Returns: The created template
    func createTemplate(
        from candidate: RecurringCandidate,
        reminderOffsets: [Int],
        toleranceDays: Int
    ) async throws -> RecurringTemplate

    /// Fetches a template by vendor fingerprint.
    /// - Parameter vendorFingerprint: The vendor fingerprint
    /// - Returns: The template if found, nil otherwise
    func fetchTemplate(byVendorFingerprint vendorFingerprint: String) async throws -> RecurringTemplate?

    /// Fetches a template by ID.
    /// - Parameter id: The template ID
    /// - Returns: The template if found, nil otherwise
    func fetchTemplate(byId id: UUID) async throws -> RecurringTemplate?

    /// Fetches all active templates.
    /// - Returns: Array of active templates
    func fetchActiveTemplates() async throws -> [RecurringTemplate]

    /// Fetches all templates (active and paused).
    /// - Returns: Array of all templates
    func fetchAllTemplates() async throws -> [RecurringTemplate]

    /// Updates a template with new settings.
    /// - Parameters:
    ///   - template: The template to update
    ///   - reminderOffsets: New reminder offsets (optional)
    ///   - toleranceDays: New tolerance days (optional)
    ///   - isActive: New active status (optional)
    func updateTemplate(
        _ template: RecurringTemplate,
        reminderOffsets: [Int]?,
        toleranceDays: Int?,
        isActive: Bool?
    ) async throws

    /// Updates template amount range based on a matched document.
    /// - Parameters:
    ///   - template: The template to update
    ///   - amount: The amount from the matched document
    func updateAmountRange(_ template: RecurringTemplate, with amount: Decimal) async throws

    /// Deletes a template and its instances.
    /// - Parameter template: The template to delete
    func deleteTemplate(_ template: RecurringTemplate) async throws

    /// Checks if a template exists for a vendor fingerprint.
    /// - Parameter vendorFingerprint: The vendor fingerprint
    /// - Returns: True if a template exists
    func templateExists(forVendorFingerprint vendorFingerprint: String) async throws -> Bool
}

/// Default implementation of RecurringTemplateService
@MainActor
final class RecurringTemplateService: RecurringTemplateServiceProtocol {

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.dueasy.app", category: "RecurringTemplate")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Template Creation

    func createTemplate(
        from document: FinanceDocument,
        reminderOffsets: [Int],
        toleranceDays: Int,
        creationSource: TemplateCreationSource
    ) async throws -> RecurringTemplate {
        guard let vendorFingerprint = document.vendorFingerprint, !vendorFingerprint.isEmpty else {
            throw RecurringError.missingVendorFingerprint
        }

        guard let dueDate = document.dueDate else {
            throw RecurringError.missingDueDate
        }

        // Check if template already exists
        if try await templateExists(forVendorFingerprint: vendorFingerprint) {
            throw RecurringError.templateAlreadyExists
        }

        let calendar = Calendar.current
        let dueDayOfMonth = calendar.component(.day, from: dueDate)

        let template = RecurringTemplate(
            vendorFingerprint: vendorFingerprint,
            vendorDisplayName: document.title,
            documentCategory: document.documentCategory,
            dueDayOfMonth: dueDayOfMonth,
            toleranceDays: toleranceDays,
            reminderOffsetsDays: reminderOffsets,
            amountMin: document.amount,
            amountMax: document.amount,
            currency: document.currency,
            iban: document.bankAccountNumber,
            isActive: true,
            creationSource: creationSource
        )

        modelContext.insert(template)
        try modelContext.save()

        // PRIVACY: Don't log vendor name (document.title)
        logger.info("Created recurring template: id=\(template.id), source=\(creationSource.rawValue)")

        return template
    }

    func createTemplate(
        from candidate: RecurringCandidate,
        reminderOffsets: [Int],
        toleranceDays: Int
    ) async throws -> RecurringTemplate {
        // Check if template already exists
        if try await templateExists(forVendorFingerprint: candidate.vendorFingerprint) {
            throw RecurringError.templateAlreadyExists
        }

        let template = RecurringTemplate(
            vendorFingerprint: candidate.vendorFingerprint,
            vendorDisplayName: candidate.vendorDisplayName,
            documentCategory: candidate.documentCategory,
            dueDayOfMonth: candidate.dominantDueDayOfMonth ?? 15,
            toleranceDays: toleranceDays,
            reminderOffsetsDays: reminderOffsets,
            amountMin: candidate.minAmount,
            amountMax: candidate.maxAmount,
            currency: candidate.currency,
            iban: candidate.stableIBAN,
            isActive: true,
            creationSource: .autoDetection
        )

        modelContext.insert(template)

        // Mark candidate as accepted
        candidate.accept(templateId: template.id)

        try modelContext.save()

        // PRIVACY: Don't log vendor name
        logger.info("Created recurring template from candidate: id=\(template.id)")

        return template
    }

    // MARK: - Template Queries

    func fetchTemplate(byVendorFingerprint vendorFingerprint: String) async throws -> RecurringTemplate? {
        let descriptor = FetchDescriptor<RecurringTemplate>(
            predicate: #Predicate<RecurringTemplate> { $0.vendorFingerprint == vendorFingerprint }
        )
        let templates = try modelContext.fetch(descriptor)
        return templates.first
    }

    func fetchTemplate(byId id: UUID) async throws -> RecurringTemplate? {
        let descriptor = FetchDescriptor<RecurringTemplate>(
            predicate: #Predicate<RecurringTemplate> { $0.id == id }
        )
        let templates = try modelContext.fetch(descriptor)
        return templates.first
    }

    func fetchActiveTemplates() async throws -> [RecurringTemplate] {
        let descriptor = FetchDescriptor<RecurringTemplate>(
            predicate: #Predicate<RecurringTemplate> { $0.isActive == true },
            sortBy: [SortDescriptor(\.vendorDisplayName)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchAllTemplates() async throws -> [RecurringTemplate] {
        let descriptor = FetchDescriptor<RecurringTemplate>(
            sortBy: [SortDescriptor(\.vendorDisplayName)]
        )
        return try modelContext.fetch(descriptor)
    }

    func templateExists(forVendorFingerprint vendorFingerprint: String) async throws -> Bool {
        let template = try await fetchTemplate(byVendorFingerprint: vendorFingerprint)
        return template != nil
    }

    // MARK: - Template Updates

    func updateTemplate(
        _ template: RecurringTemplate,
        reminderOffsets: [Int]?,
        toleranceDays: Int?,
        isActive: Bool?
    ) async throws {
        if let offsets = reminderOffsets {
            template.reminderOffsetsDays = offsets
        }
        if let tolerance = toleranceDays {
            template.toleranceDays = tolerance
        }
        if let active = isActive {
            template.isActive = active
        }
        template.markUpdated()

        try modelContext.save()
        // PRIVACY: Don't log vendor name
        logger.info("Updated recurring template: id=\(template.id)")
    }

    func updateAmountRange(_ template: RecurringTemplate, with amount: Decimal) async throws {
        template.updateAmountRange(with: amount)
        try modelContext.save()
    }

    // MARK: - Template Deletion

    func deleteTemplate(_ template: RecurringTemplate) async throws {
        let templateId = template.id

        // Fetch all instances for this template
        let instanceDescriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> { $0.templateId == templateId }
        )
        let instances = try modelContext.fetch(instanceDescriptor)

        logger.info("Deleting template \(templateId): \(instances.count) instances will be removed")

        // CRITICAL FIX: Clear linkage from all documents linked to these instances
        for instance in instances {
            if let documentId = instance.matchedDocumentId {
                let docDescriptor = FetchDescriptor<FinanceDocument>(
                    predicate: #Predicate<FinanceDocument> { $0.id == documentId }
                )
                if let document = try modelContext.fetch(docDescriptor).first {
                    logger.debug("Clearing recurring linkage from document \(documentId)")
                    document.recurringInstanceId = nil
                    document.recurringTemplateId = nil
                    document.markUpdated()
                }
            }
            modelContext.delete(instance)
        }

        // Also clear linkage from documents linked to the template but not to a specific instance
        // This can happen if instance creation failed after template linkage
        let docsWithTemplateDescriptor = FetchDescriptor<FinanceDocument>(
            predicate: #Predicate<FinanceDocument> { $0.recurringTemplateId == templateId }
        )
        let documentsWithTemplate = try modelContext.fetch(docsWithTemplateDescriptor)
        for document in documentsWithTemplate {
            logger.debug("Clearing orphaned template linkage from document \(document.id)")
            document.recurringInstanceId = nil
            document.recurringTemplateId = nil
            document.markUpdated()
        }

        // Delete the template
        modelContext.delete(template)
        try modelContext.save()

        // PRIVACY: Don't log vendor name
        logger.info("Deleted recurring template (id=\(templateId)), \(instances.count) instances, and cleared \(documentsWithTemplate.count) document linkages")
    }
}

// MARK: - Recurring Errors

/// Errors specific to recurring payment operations
enum RecurringError: Error, LocalizedError {
    case missingVendorFingerprint
    case missingDueDate
    case templateAlreadyExists
    case templateNotFound
    case instanceNotFound
    case matchingFailed(reason: String)
    case schedulingFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .missingVendorFingerprint:
            return "Vendor fingerprint is required to create a recurring template"
        case .missingDueDate:
            return "Due date is required to create a recurring template"
        case .templateAlreadyExists:
            return "A recurring template already exists for this vendor"
        case .templateNotFound:
            return "Recurring template not found"
        case .instanceNotFound:
            return "Recurring instance not found"
        case .matchingFailed(let reason):
            return "Failed to match document to recurring instance: \(reason)"
        case .schedulingFailed(let reason):
            return "Failed to schedule recurring instances: \(reason)"
        }
    }
}
