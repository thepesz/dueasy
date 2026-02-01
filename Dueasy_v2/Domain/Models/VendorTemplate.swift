import Foundation
import SwiftData

// NOTE: DocumentRegion is defined in Domain/Models/KeywordModels.swift
// with 9 regions for the 3x3 grid layout analysis.

/// Field template capturing learned extraction patterns for a specific field.
/// Stored as JSON within VendorTemplate.
struct FieldTemplate: Codable, Sendable, Equatable {
    /// Preferred document region where this field typically appears
    let preferredRegion: DocumentRegion?

    /// Anchor phrase found near the field value (e.g., "Sprzedawca", "Do zaplaty")
    let anchorPhrase: String?

    /// Bounding box region (normalized coordinates) for UI highlighting
    let regionHint: BoundingBox?

    /// Confidence boost to apply when extraction matches this template (+0.1 to +0.2)
    let confidenceBoost: Double

    init(
        preferredRegion: DocumentRegion? = nil,
        anchorPhrase: String? = nil,
        regionHint: BoundingBox? = nil,
        confidenceBoost: Double = 0.1
    ) {
        self.preferredRegion = preferredRegion
        self.anchorPhrase = anchorPhrase
        self.regionHint = regionHint
        self.confidenceBoost = confidenceBoost
    }
}

/// Vendor template for local learning.
/// Stores field-specific extraction patterns learned from user corrections.
/// Activates after 2+ corrections to ensure pattern reliability.
@Model
final class VendorTemplate {

    // MARK: - Identifiers

    /// Unique identifier for this template
    var id: UUID = UUID()

    /// Polish Tax ID (NIP) - primary identifier for vendor matching
    @Attribute(.unique) var vendorNIP: String

    /// Display name of the vendor
    var vendorName: String

    // MARK: - Field Templates (stored as JSON)

    /// Template for vendor name extraction
    var vendorNameTemplateData: Data?

    /// Template for NIP extraction
    var nipTemplateData: Data?

    /// Template for amount extraction
    var amountTemplateData: Data?

    /// Template for due date extraction
    var dueDateTemplateData: Data?

    /// Template for document number extraction
    var documentNumberTemplateData: Data?

    /// Template for bank account extraction
    var bankAccountTemplateData: Data?

    // MARK: - Metadata

    /// Number of corrections recorded for this vendor
    /// Template activates after 2+ corrections
    var correctionsCount: Int = 0

    /// Last time this template was used for extraction
    var lastUsed: Date

    /// When this template was created
    var createdAt: Date

    /// When this template was last updated
    var updatedAt: Date

    // MARK: - Computed Properties

    /// Template is active and should be applied to extractions
    /// Requires at least 2 corrections to avoid learning from single mistakes
    var isActive: Bool {
        correctionsCount >= 2
    }

    /// Vendor name template (decoded)
    var vendorNameTemplate: FieldTemplate? {
        get {
            guard let data = vendorNameTemplateData else { return nil }
            return try? JSONDecoder().decode(FieldTemplate.self, from: data)
        }
        set {
            vendorNameTemplateData = try? JSONEncoder().encode(newValue)
        }
    }

    /// NIP template (decoded)
    var nipTemplate: FieldTemplate? {
        get {
            guard let data = nipTemplateData else { return nil }
            return try? JSONDecoder().decode(FieldTemplate.self, from: data)
        }
        set {
            nipTemplateData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Amount template (decoded)
    var amountTemplate: FieldTemplate? {
        get {
            guard let data = amountTemplateData else { return nil }
            return try? JSONDecoder().decode(FieldTemplate.self, from: data)
        }
        set {
            amountTemplateData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Due date template (decoded)
    var dueDateTemplate: FieldTemplate? {
        get {
            guard let data = dueDateTemplateData else { return nil }
            return try? JSONDecoder().decode(FieldTemplate.self, from: data)
        }
        set {
            dueDateTemplateData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Document number template (decoded)
    var documentNumberTemplate: FieldTemplate? {
        get {
            guard let data = documentNumberTemplateData else { return nil }
            return try? JSONDecoder().decode(FieldTemplate.self, from: data)
        }
        set {
            documentNumberTemplateData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Bank account template (decoded)
    var bankAccountTemplate: FieldTemplate? {
        get {
            guard let data = bankAccountTemplateData else { return nil }
            return try? JSONDecoder().decode(FieldTemplate.self, from: data)
        }
        set {
            bankAccountTemplateData = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Initialization

    init(
        vendorNIP: String,
        vendorName: String
    ) {
        self.vendorNIP = vendorNIP
        self.vendorName = vendorName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastUsed = Date()
    }

    // MARK: - Template Updates

    /// Update field template from user correction
    func updateTemplate(
        for field: FieldType,
        region: DocumentRegion?,
        anchorPhrase: String?,
        regionHint: BoundingBox?
    ) {
        let template = FieldTemplate(
            preferredRegion: region,
            anchorPhrase: anchorPhrase,
            regionHint: regionHint,
            confidenceBoost: calculateConfidenceBoost()
        )

        switch field {
        case .vendor:
            vendorNameTemplate = template
        case .amount:
            amountTemplate = template
        case .dueDate:
            dueDateTemplate = template
        case .documentNumber:
            documentNumberTemplate = template
        case .nip:
            nipTemplate = template
        case .bankAccount:
            bankAccountTemplate = template
        }

        correctionsCount += 1
        updatedAt = Date()
    }

    /// Calculate confidence boost based on correction count
    /// More corrections = higher confidence in the template
    private func calculateConfidenceBoost() -> Double {
        switch correctionsCount {
        case 0...1:
            return 0.05 // Low boost until template is validated
        case 2...4:
            return 0.10 // Standard boost after activation
        case 5...9:
            return 0.15 // Higher boost with more corrections
        default:
            return 0.20 // Maximum boost for well-established patterns
        }
    }

    /// Get template for a specific field type
    func template(for field: FieldType) -> FieldTemplate? {
        switch field {
        case .vendor:
            return vendorNameTemplate
        case .amount:
            return amountTemplate
        case .dueDate:
            return dueDateTemplate
        case .documentNumber:
            return documentNumberTemplate
        case .nip:
            return nipTemplate
        case .bankAccount:
            return bankAccountTemplate
        }
    }

    /// Mark template as used (updates lastUsed timestamp)
    func markAsUsed() {
        lastUsed = Date()
    }
}

// MARK: - Predicates

extension VendorTemplate {

    /// Predicate to find template by NIP
    static func byNIP(_ nip: String) -> Predicate<VendorTemplate> {
        #Predicate<VendorTemplate> { template in
            template.vendorNIP == nip
        }
    }

    /// Predicate to find active templates
    static var active: Predicate<VendorTemplate> {
        #Predicate<VendorTemplate> { template in
            template.correctionsCount >= 2
        }
    }

    /// Predicate to find recently used templates (within last 30 days)
    static var recentlyUsed: Predicate<VendorTemplate> {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        return #Predicate<VendorTemplate> { template in
            template.lastUsed >= thirtyDaysAgo
        }
    }
}
