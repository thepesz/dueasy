import Foundation
import SwiftData

/// Represents a recurring payment pattern for a vendor.
/// Created either manually by the user or when accepting an auto-detection suggestion.
///
/// The template stores:
/// - Vendor identification (fingerprint for matching, display name for UI)
/// - Due date rules (day of month, tolerance for matching)
/// - Reminder configuration
/// - Amount expectations (learned over time)
/// - Payment details (IBAN)
@Model
final class RecurringTemplate {

    // MARK: - Primary Fields

    /// Unique identifier
    @Attribute(.unique)
    var id: UUID

    /// Vendor fingerprint for matching (SHA256 of normalized vendor name + NIP + amount bucket)
    /// This is the primary matching key - documents with this fingerprint match this template.
    @Attribute(.spotlight)
    var vendorFingerprint: String

    /// Vendor-only fingerprint (SHA256 of normalized vendor name + NIP, WITHOUT amount bucket).
    /// Used to find all templates from the same vendor (e.g., Santander Credit Card + Santander Loan).
    /// Enables UI features like "Other payments from this vendor" and migration detection.
    var vendorOnlyFingerprint: String?

    /// Amount bucket identifier used in fingerprint generation (e.g., "bucket_500").
    /// Nil for legacy templates created before amount bucketing was introduced.
    /// Used to understand which amount range this template covers.
    var amountBucket: String?

    /// Display name for UI (e.g., "PGE Energia")
    var vendorDisplayName: String

    /// Short name for compact UI displays (e.g., "Lantech" instead of "Lantech Sp. z o.o.")
    /// This is the normalized vendor name without business suffixes like "Sp. z o.o.", "S.A.", etc.
    /// Used for tile displays where space is limited.
    var vendorShortName: String?

    /// Document category for this vendor
    var documentCategoryRaw: String

    // MARK: - Due Date Rules

    /// Day of month when payment is typically due (1-31)
    /// Extracted from the first document or learned over time
    var dueDayOfMonth: Int

    /// Tolerance in days for matching documents to instances
    /// A document with dueDate within expectedDueDate +/- toleranceDays will match
    var toleranceDays: Int

    // MARK: - Reminder Settings

    /// Reminder offsets in days before due date (e.g., [7, 1, 0])
    var reminderOffsetsDays: [Int]

    // MARK: - Amount Rules (Optional, learned over time)

    /// Minimum expected amount stored as string to preserve decimal precision.
    /// CRITICAL FIX: Using String instead of Double to prevent precision loss
    /// for values like 123.45 which cannot be exactly represented in binary floating point.
    private var amountMinString: String?

    /// Maximum expected amount stored as string to preserve decimal precision.
    private var amountMaxString: String?

    /// Legacy Double storage (kept for migration from older schema versions)
    /// Will be migrated to String on first access through the computed properties
    /// Note: Not marked deprecated to avoid warnings in migration code paths
    var amountMinValue: Double?

    /// Legacy Double storage (kept for migration from older schema versions)
    var amountMaxValue: Double?

    /// Currency code for amount validation
    var currency: String

    // MARK: - Payment Details

    /// Bank account number (IBAN) for payment
    var iban: String?

    // MARK: - Status

    /// Whether this template is active (paused templates don't generate new instances)
    var isActive: Bool

    /// Source of template creation
    var creationSourceRaw: String

    // MARK: - Timestamps

    /// When the template was created
    var createdAt: Date

    /// When the template was last updated
    var updatedAt: Date

    // MARK: - Statistics

    /// Number of documents matched to this template
    var matchedDocumentCount: Int

    /// Number of instances marked as paid
    var paidInstanceCount: Int

    /// Number of instances marked as missed
    var missedInstanceCount: Int

    // MARK: - Computed Properties

    /// Document category for this vendor
    var documentCategory: DocumentCategory {
        get { DocumentCategory(rawValue: documentCategoryRaw) ?? .unknown }
        set { documentCategoryRaw = newValue.rawValue }
    }

    /// Amount range as Decimal values with precision preservation.
    /// CRITICAL FIX: Stores as String internally to prevent floating point precision loss.
    var amountMin: Decimal? {
        get {
            // First try String storage (new format)
            if let str = amountMinString, let decimal = Decimal(string: str) {
                return decimal
            }
            // Fallback to legacy Double storage (migrate on write)
            if let value = amountMinValue {
                return Decimal(value)
            }
            return nil
        }
        set {
            if let newValue = newValue {
                amountMinString = "\(newValue)"
            } else {
                amountMinString = nil
            }
            // Clear legacy storage
            amountMinValue = nil
        }
    }

    var amountMax: Decimal? {
        get {
            // First try String storage (new format)
            if let str = amountMaxString, let decimal = Decimal(string: str) {
                return decimal
            }
            // Fallback to legacy Double storage (migrate on write)
            if let value = amountMaxValue {
                return Decimal(value)
            }
            return nil
        }
        set {
            if let newValue = newValue {
                amountMaxString = "\(newValue)"
            } else {
                amountMaxString = nil
            }
            // Clear legacy storage
            amountMaxValue = nil
        }
    }

    /// How the template was created
    var creationSource: TemplateCreationSource {
        get { TemplateCreationSource(rawValue: creationSourceRaw) ?? .manual }
        set { creationSourceRaw = newValue.rawValue }
    }

    /// Returns the short name for compact displays, with fallback to display name.
    /// The short name is properly capitalized (first letter uppercase).
    var compactDisplayName: String {
        if let shortName = vendorShortName, !shortName.isEmpty {
            // Capitalize first letter of the short name
            return shortName.prefix(1).uppercased() + shortName.dropFirst()
        }
        // Fallback to full display name if no short name available
        return vendorDisplayName
    }

    /// Whether amount is within expected range
    func isAmountWithinRange(_ amount: Decimal) -> Bool {
        // If no range learned yet, accept any amount
        guard let min = amountMin, let max = amountMax else { return true }

        // Allow 20% tolerance on the range
        let tolerance = (max - min) * Decimal(0.2)
        return amount >= (min - tolerance) && amount <= (max + tolerance)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        vendorFingerprint: String,
        vendorOnlyFingerprint: String? = nil,
        amountBucket: String? = nil,
        vendorDisplayName: String,
        vendorShortName: String? = nil,
        documentCategory: DocumentCategory = .unknown,
        dueDayOfMonth: Int,
        toleranceDays: Int = 3,
        reminderOffsetsDays: [Int] = [7, 1, 0],
        amountMin: Decimal? = nil,
        amountMax: Decimal? = nil,
        currency: String = "PLN",
        iban: String? = nil,
        isActive: Bool = true,
        creationSource: TemplateCreationSource = .manual
    ) {
        self.id = id
        self.vendorFingerprint = vendorFingerprint
        self.vendorOnlyFingerprint = vendorOnlyFingerprint
        self.amountBucket = amountBucket
        self.vendorDisplayName = vendorDisplayName
        self.vendorShortName = vendorShortName
        self.documentCategoryRaw = documentCategory.rawValue
        self.dueDayOfMonth = dueDayOfMonth
        self.toleranceDays = toleranceDays
        self.reminderOffsetsDays = reminderOffsetsDays
        // CRITICAL FIX: Store amounts as String to preserve decimal precision
        self.amountMinString = amountMin.map { "\($0)" }
        self.amountMaxString = amountMax.map { "\($0)" }
        self.amountMinValue = nil  // Don't use legacy storage for new templates
        self.amountMaxValue = nil
        self.currency = currency
        self.iban = iban
        self.isActive = isActive
        self.creationSourceRaw = creationSource.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.matchedDocumentCount = 0
        self.paidInstanceCount = 0
        self.missedInstanceCount = 0
    }

    // MARK: - Update Methods

    /// Marks the template as updated
    func markUpdated() {
        updatedAt = Date()
    }

    /// Updates the amount range based on a matched document
    /// Uses exponential moving average to adapt the range over time
    func updateAmountRange(with newAmount: Decimal) {
        if amountMin == nil || amountMax == nil {
            // First amount - initialize range
            amountMin = newAmount
            amountMax = newAmount
        } else {
            // Expand range if needed, with some tolerance
            if newAmount < amountMin! {
                amountMin = newAmount
            }
            if newAmount > amountMax! {
                amountMax = newAmount
            }
        }
        markUpdated()
    }

    /// Increments the matched document count
    func incrementMatchedCount() {
        matchedDocumentCount += 1
        markUpdated()
    }

    /// Increments the paid instance count
    func incrementPaidCount() {
        paidInstanceCount += 1
        markUpdated()
    }

    /// Increments the missed instance count
    func incrementMissedCount() {
        missedInstanceCount += 1
        markUpdated()
    }
}

// MARK: - Template Creation Source

/// How a recurring template was created
enum TemplateCreationSource: String, Codable, Sendable {
    /// User manually marked a document as recurring
    case manual

    /// User accepted an auto-detection suggestion
    case autoDetection
}
