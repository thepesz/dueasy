import Foundation
import SwiftData

// MARK: - Anomaly Type

/// Types of anomalies that can be detected in documents.
/// Covers fraud detection, data quality issues, and behavioral anomalies.
enum AnomalyType: String, Codable, Sendable, CaseIterable {
    // MARK: - Bank Account Fraud Indicators

    /// Bank account changed from previously known account for this vendor
    case bankAccountChanged

    /// Bank account country doesn't match vendor's country
    case bankAccountCountryMismatch

    /// IBAN fails checksum validation
    case invalidIBAN

    /// Bank account has been flagged as suspicious across multiple vendors
    case suspiciousBankAccount

    // MARK: - Amount Anomalies

    /// Amount significantly higher than historical pattern
    case amountSpikeUp

    /// Amount significantly lower than historical pattern
    case amountSpikeDrop

    /// Amount is a round number (potential fabrication indicator)
    case suspiciousRoundAmount

    /// First invoice from vendor has unusually high amount
    case unusualFirstInvoiceAmount

    // MARK: - Timing Anomalies

    /// Invoice received outside normal billing cycle
    case unusualTimingPattern

    /// Duplicate invoice detected (same vendor, amount, date)
    case duplicateInvoice

    /// Invoice date is in the future
    case futureDatedInvoice

    /// Invoice date is suspiciously old
    case staleInvoice

    // MARK: - Vendor Anomalies

    /// New vendor with characteristics similar to known vendor (potential impersonation)
    case vendorImpersonation

    /// Vendor details changed unexpectedly (address, NIP, etc.)
    case vendorDetailsMismatch

    /// Vendor NIP fails validation
    case invalidVendorNIP

    // MARK: - Document Quality Issues

    /// Document appears to be modified or tampered with
    case documentTampering

    /// Required fields are missing or incomplete
    case missingRequiredFields

    /// Inconsistent data within the document
    case internalInconsistency

    /// Human-readable description of the anomaly type
    var displayName: String {
        switch self {
        case .bankAccountChanged:
            return "Bank Account Changed"
        case .bankAccountCountryMismatch:
            return "Bank Account Country Mismatch"
        case .invalidIBAN:
            return "Invalid IBAN"
        case .suspiciousBankAccount:
            return "Suspicious Bank Account"
        case .amountSpikeUp:
            return "Unusual Amount Increase"
        case .amountSpikeDrop:
            return "Unusual Amount Decrease"
        case .suspiciousRoundAmount:
            return "Suspicious Round Amount"
        case .unusualFirstInvoiceAmount:
            return "Unusual First Invoice Amount"
        case .unusualTimingPattern:
            return "Unusual Timing"
        case .duplicateInvoice:
            return "Duplicate Invoice"
        case .futureDatedInvoice:
            return "Future-Dated Invoice"
        case .staleInvoice:
            return "Stale Invoice"
        case .vendorImpersonation:
            return "Potential Vendor Impersonation"
        case .vendorDetailsMismatch:
            return "Vendor Details Mismatch"
        case .invalidVendorNIP:
            return "Invalid Vendor NIP"
        case .documentTampering:
            return "Potential Document Tampering"
        case .missingRequiredFields:
            return "Missing Required Fields"
        case .internalInconsistency:
            return "Internal Inconsistency"
        }
    }

    /// Detailed description explaining what this anomaly means
    var detailedDescription: String {
        switch self {
        case .bankAccountChanged:
            return "The bank account on this invoice differs from the account previously used by this vendor. Verify the change is legitimate before paying."
        case .bankAccountCountryMismatch:
            return "The bank account country code doesn't match the vendor's registered country. This could indicate fraud."
        case .invalidIBAN:
            return "The IBAN on this invoice fails validation. The account number may be incorrect or fraudulent."
        case .suspiciousBankAccount:
            return "This bank account has been flagged as suspicious based on patterns across multiple documents."
        case .amountSpikeUp:
            return "The invoice amount is significantly higher than the typical range for this vendor."
        case .amountSpikeDrop:
            return "The invoice amount is significantly lower than usual, which may indicate an error or partial billing."
        case .suspiciousRoundAmount:
            return "The amount is an unusually round number, which can sometimes indicate fabricated invoices."
        case .unusualFirstInvoiceAmount:
            return "This is the first invoice from this vendor and the amount is unusually high. Verify the vendor's legitimacy."
        case .unusualTimingPattern:
            return "This invoice was received outside the normal billing cycle for this vendor."
        case .duplicateInvoice:
            return "This invoice appears to be a duplicate of an existing invoice from the same vendor."
        case .futureDatedInvoice:
            return "The invoice date is in the future, which is unusual and may indicate an error."
        case .staleInvoice:
            return "The invoice date is unusually old. Verify this is not a duplicate or already-paid invoice."
        case .vendorImpersonation:
            return "This vendor's details are suspiciously similar to a known vendor but with key differences. This may be an impersonation attempt."
        case .vendorDetailsMismatch:
            return "The vendor's details on this invoice differ from their previously recorded information."
        case .invalidVendorNIP:
            return "The vendor's tax ID (NIP) fails validation and may be incorrect or fraudulent."
        case .documentTampering:
            return "Analysis suggests this document may have been modified or tampered with."
        case .missingRequiredFields:
            return "This invoice is missing required fields that are normally present."
        case .internalInconsistency:
            return "There are inconsistencies within this document that require review."
        }
    }
}

// MARK: - Anomaly Severity

/// Severity level of detected anomalies.
/// Determines UI presentation and notification priority.
enum AnomalySeverity: String, Codable, Sendable, CaseIterable, Comparable {
    /// Critical issues that may indicate fraud - requires immediate attention
    case critical

    /// Warning-level issues that should be reviewed
    case warning

    /// Informational notices that may be worth noting
    case info

    /// Numeric priority for sorting (higher = more severe)
    var priority: Int {
        switch self {
        case .critical: return 3
        case .warning: return 2
        case .info: return 1
        }
    }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .critical: return "Critical"
        case .warning: return "Warning"
        case .info: return "Info"
        }
    }

    static func < (lhs: AnomalySeverity, rhs: AnomalySeverity) -> Bool {
        lhs.priority < rhs.priority
    }
}

// MARK: - Anomaly Resolution

/// How an anomaly was resolved by the user or system.
enum AnomalyResolution: String, Codable, Sendable, CaseIterable {
    /// User dismissed the anomaly as not concerning
    case dismissed

    /// User confirmed the anomaly is safe (e.g., verified bank account change)
    case confirmedSafe

    /// User confirmed this is actual fraud
    case confirmedFraud

    /// System automatically resolved (e.g., duplicate detection cleared)
    case autoResolved

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .dismissed: return "Dismissed"
        case .confirmedSafe: return "Confirmed Safe"
        case .confirmedFraud: return "Confirmed Fraud"
        case .autoResolved: return "Auto-Resolved"
        }
    }
}

// MARK: - Anomaly Context Data

/// Type-specific context data for anomalies.
/// Stores additional details relevant to the specific anomaly type.
struct AnomalyContextData: Codable, Sendable, Equatable {

    // MARK: - Bank Account Context

    /// Previous bank account (for bankAccountChanged)
    var previousBankAccount: String?

    /// New bank account (for bankAccountChanged)
    var newBankAccount: String?

    /// Expected country code (for bankAccountCountryMismatch)
    var expectedCountry: String?

    /// Actual country code found (for bankAccountCountryMismatch)
    var actualCountry: String?

    // MARK: - Amount Context

    /// Current invoice amount
    var currentAmount: Double?

    /// Expected/average amount
    var expectedAmount: Double?

    /// Minimum amount in historical range
    var historicalMin: Double?

    /// Maximum amount in historical range
    var historicalMax: Double?

    /// Standard deviation of historical amounts
    var historicalStdDev: Double?

    /// Percentage deviation from expected
    var deviationPercentage: Double?

    // MARK: - Timing Context

    /// Expected day of month
    var expectedDayOfMonth: Int?

    /// Actual day of month
    var actualDayOfMonth: Int?

    /// Days difference from expected
    var daysDifference: Int?

    // MARK: - Duplicate Detection Context

    /// ID of the potential duplicate document
    var duplicateDocumentId: UUID?

    /// Similarity score (0.0 to 1.0)
    var similarityScore: Double?

    // MARK: - Vendor Context

    /// Similar vendor fingerprint (for impersonation detection)
    var similarVendorFingerprint: String?

    /// Similar vendor name
    var similarVendorName: String?

    /// Fields that differ from expected
    var mismatchedFields: [String]?

    // MARK: - Validation Context

    /// Validation error message
    var validationError: String?

    /// List of missing fields
    var missingFields: [String]?

    // MARK: - General Context

    /// Additional notes or context
    var additionalNotes: String?

    /// Detection algorithm version that found this
    var algorithmVersion: String?

    /// Confidence score of the detection (0.0 to 1.0)
    var confidenceScore: Double?

    init(
        previousBankAccount: String? = nil,
        newBankAccount: String? = nil,
        expectedCountry: String? = nil,
        actualCountry: String? = nil,
        currentAmount: Double? = nil,
        expectedAmount: Double? = nil,
        historicalMin: Double? = nil,
        historicalMax: Double? = nil,
        historicalStdDev: Double? = nil,
        deviationPercentage: Double? = nil,
        expectedDayOfMonth: Int? = nil,
        actualDayOfMonth: Int? = nil,
        daysDifference: Int? = nil,
        duplicateDocumentId: UUID? = nil,
        similarityScore: Double? = nil,
        similarVendorFingerprint: String? = nil,
        similarVendorName: String? = nil,
        mismatchedFields: [String]? = nil,
        validationError: String? = nil,
        missingFields: [String]? = nil,
        additionalNotes: String? = nil,
        algorithmVersion: String? = nil,
        confidenceScore: Double? = nil
    ) {
        self.previousBankAccount = previousBankAccount
        self.newBankAccount = newBankAccount
        self.expectedCountry = expectedCountry
        self.actualCountry = actualCountry
        self.currentAmount = currentAmount
        self.expectedAmount = expectedAmount
        self.historicalMin = historicalMin
        self.historicalMax = historicalMax
        self.historicalStdDev = historicalStdDev
        self.deviationPercentage = deviationPercentage
        self.expectedDayOfMonth = expectedDayOfMonth
        self.actualDayOfMonth = actualDayOfMonth
        self.daysDifference = daysDifference
        self.duplicateDocumentId = duplicateDocumentId
        self.similarityScore = similarityScore
        self.similarVendorFingerprint = similarVendorFingerprint
        self.similarVendorName = similarVendorName
        self.mismatchedFields = mismatchedFields
        self.validationError = validationError
        self.missingFields = missingFields
        self.additionalNotes = additionalNotes
        self.algorithmVersion = algorithmVersion
        self.confidenceScore = confidenceScore
    }
}

// MARK: - Document Anomaly Model

/// Represents a detected anomaly or fraud indicator in a document.
/// Part of the Anomaly & Fraud Guard system.
///
/// Anomalies are linked to documents and optionally to vendors.
/// They track detection context, user acknowledgment, and resolution.
@Model
final class DocumentAnomaly {

    // MARK: - Primary Fields

    /// Unique identifier
    @Attribute(.unique)
    var id: UUID

    /// ID of the document this anomaly is associated with
    var documentId: UUID

    /// Vendor fingerprint for vendor-level anomaly tracking
    /// Allows finding all anomalies for a specific vendor
    @Attribute(.spotlight)
    var vendorFingerprint: String?

    /// Anomaly type (stored as raw string for persistence)
    var typeRaw: String

    /// Severity level (stored as raw string for persistence)
    var severityRaw: String

    // MARK: - Detection Context

    /// When the anomaly was detected
    var detectedAt: Date

    /// Version of the detection algorithm that found this anomaly
    var detectionVersion: String

    /// Whether the user has acknowledged/reviewed this anomaly
    var isAcknowledged: Bool

    /// When the user acknowledged this anomaly
    var acknowledgedAt: Date?

    /// Resolution status (stored as raw string for persistence)
    var resolutionRaw: String?

    /// User notes about the resolution
    var resolutionNotes: String?

    // MARK: - Context Data

    /// Type-specific context data stored as JSON
    /// Using external storage for potentially large data
    @Attribute(.externalStorage)
    var contextDataJSON: Data?

    /// Human-readable summary of the anomaly for display
    var summary: String

    // MARK: - Computed Properties

    /// Anomaly type enum
    var type: AnomalyType {
        get { AnomalyType(rawValue: typeRaw) ?? .internalInconsistency }
        set { typeRaw = newValue.rawValue }
    }

    /// Severity level enum
    var severity: AnomalySeverity {
        get { AnomalySeverity(rawValue: severityRaw) ?? .info }
        set { severityRaw = newValue.rawValue }
    }

    /// Resolution status enum
    var resolution: AnomalyResolution? {
        get {
            guard let raw = resolutionRaw else { return nil }
            return AnomalyResolution(rawValue: raw)
        }
        set { resolutionRaw = newValue?.rawValue }
    }

    /// Whether this anomaly has been resolved
    var isResolved: Bool {
        resolution != nil
    }

    /// Context data decoded from JSON
    var contextData: AnomalyContextData? {
        get {
            guard let data = contextDataJSON else { return nil }
            return try? JSONDecoder().decode(AnomalyContextData.self, from: data)
        }
        set {
            if let newValue = newValue {
                contextDataJSON = try? JSONEncoder().encode(newValue)
            } else {
                contextDataJSON = nil
            }
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        documentId: UUID,
        vendorFingerprint: String? = nil,
        type: AnomalyType,
        severity: AnomalySeverity,
        detectionVersion: String = "1.0",
        summary: String,
        contextData: AnomalyContextData? = nil
    ) {
        self.id = id
        self.documentId = documentId
        self.vendorFingerprint = vendorFingerprint
        self.typeRaw = type.rawValue
        self.severityRaw = severity.rawValue
        self.detectedAt = Date()
        self.detectionVersion = detectionVersion
        self.isAcknowledged = false
        self.acknowledgedAt = nil
        self.resolutionRaw = nil
        self.resolutionNotes = nil
        self.summary = summary

        if let contextData = contextData {
            self.contextDataJSON = try? JSONEncoder().encode(contextData)
        } else {
            self.contextDataJSON = nil
        }
    }

    // MARK: - Methods

    /// Acknowledges the anomaly with a resolution and optional notes.
    /// - Parameters:
    ///   - resolution: How the anomaly was resolved
    ///   - notes: Optional user notes about the resolution
    func acknowledge(resolution: AnomalyResolution, notes: String? = nil) {
        self.isAcknowledged = true
        self.acknowledgedAt = Date()
        self.resolution = resolution
        self.resolutionNotes = notes
    }

    /// Marks the anomaly as reviewed without resolving it.
    func markAsReviewed() {
        self.isAcknowledged = true
        self.acknowledgedAt = Date()
    }

    /// Clears the resolution and marks as unacknowledged.
    /// Useful when circumstances change and re-review is needed.
    func clearResolution() {
        self.isAcknowledged = false
        self.acknowledgedAt = nil
        self.resolution = nil
        self.resolutionNotes = nil
    }
}
