import Foundation
import SwiftData

/// Represents a potential recurring payment pattern detected by auto-detection.
/// Used to track vendor-level patterns before the user confirms them as recurring.
///
/// Auto-detection rules:
/// - Only analyzes vendors WITHOUT an existing RecurringTemplate
/// - Requires at least 2 documents spanning 60+ days, OR 3+ documents spanning 45+ days
/// - Must pass category gate (no fuel, grocery, retail, receipt)
/// - Must have stable due date pattern (stddev <= 3 days or dominant day bucket)
/// - Confidence score must be >= 0.75 to show suggestion
@Model
final class RecurringCandidate {

    // MARK: - Primary Fields

    /// Unique identifier
    @Attribute(.unique)
    var id: UUID

    /// Vendor fingerprint (same as RecurringTemplate)
    @Attribute(.spotlight)
    var vendorFingerprint: String

    /// Display name for UI
    var vendorDisplayName: String

    /// Document category detected for this vendor
    var documentCategoryRaw: String

    // MARK: - Detection Statistics

    /// Number of documents from this vendor
    var documentCount: Int

    /// Date of first document from this vendor
    var firstDocumentDate: Date

    /// Date of most recent document from this vendor
    var lastDocumentDate: Date

    /// Days between first and last document
    var daySpan: Int

    // MARK: - Due Date Analysis

    /// Most common day of month for due dates
    var dominantDueDayOfMonth: Int?

    /// Percentage of documents with the dominant due day
    var dominantDueDayPercentage: Double?

    /// Standard deviation of due dates (in days)
    var dueDateStdDev: Double?

    /// Ratio of documents within +/-3 days of dominant due day (0.0 to 1.0).
    /// Used for bucketed due date analysis to handle weekend/holiday shifts.
    var dueDateBucketStabilityRatio: Double?

    // MARK: - Amount Analysis

    /// Average amount across documents
    var averageAmountValue: Double?

    /// Standard deviation of amounts
    var amountStdDev: Double?

    /// Minimum amount seen
    var minAmountValue: Double?

    /// Maximum amount seen
    var maxAmountValue: Double?

    // MARK: - Confidence Scoring

    /// Overall confidence score (0.0 to 1.0)
    /// Must be >= 0.75 to show suggestion
    var confidenceScore: Double

    /// Whether IBAN is consistent across documents
    var hasStableIBAN: Bool

    /// Whether recurring keywords were found in documents
    var hasRecurringKeywords: Bool

    /// Currency used across documents
    var currency: String

    /// Common IBAN found (if stable)
    var stableIBAN: String?

    /// Whether the vendor fingerprint was generated without NIP (fallback mode).
    /// A fallback fingerprint has lower certainty and should apply a small confidence penalty.
    var hasFallbackFingerprint: Bool

    // MARK: - Suggestion State

    /// Current state of the suggestion
    var suggestionStateRaw: String

    /// When the suggestion was first shown to the user
    var firstSuggestedAt: Date?

    /// When the suggestion was last shown to the user
    var lastSuggestedAt: Date?

    /// Number of times the suggestion has been shown
    var suggestionCount: Int

    /// When the suggestion was dismissed (if dismissed)
    var dismissedAt: Date?

    /// When the suggestion was accepted (if accepted)
    var acceptedAt: Date?

    /// Date until which the candidate is snoozed.
    /// Only valid when suggestionState == .snoozed
    var snoozedUntil: Date?

    /// ID of the template created from this candidate (if accepted)
    var createdTemplateId: UUID?

    // MARK: - Timestamps

    /// When this candidate was first created
    var createdAt: Date

    /// When this candidate was last updated (stats recalculated)
    var updatedAt: Date

    // MARK: - Computed Properties

    /// Document category
    var documentCategory: DocumentCategory {
        get { DocumentCategory(rawValue: documentCategoryRaw) ?? .unknown }
        set { documentCategoryRaw = newValue.rawValue }
    }

    /// Suggestion state
    var suggestionState: SuggestionState {
        get { SuggestionState(rawValue: suggestionStateRaw) ?? .none }
        set { suggestionStateRaw = newValue.rawValue }
    }

    /// Average amount as Decimal
    var averageAmount: Decimal? {
        get {
            guard let value = averageAmountValue else { return nil }
            return Decimal(value)
        }
        set {
            if let newValue = newValue {
                averageAmountValue = NSDecimalNumber(decimal: newValue).doubleValue
            } else {
                averageAmountValue = nil
            }
        }
    }

    /// Minimum amount as Decimal
    var minAmount: Decimal? {
        get {
            guard let value = minAmountValue else { return nil }
            return Decimal(value)
        }
        set {
            if let newValue = newValue {
                minAmountValue = NSDecimalNumber(decimal: newValue).doubleValue
            } else {
                minAmountValue = nil
            }
        }
    }

    /// Maximum amount as Decimal
    var maxAmount: Decimal? {
        get {
            guard let value = maxAmountValue else { return nil }
            return Decimal(value)
        }
        set {
            if let newValue = newValue {
                maxAmountValue = NSDecimalNumber(decimal: newValue).doubleValue
            } else {
                maxAmountValue = nil
            }
        }
    }

    /// Whether this candidate should be shown as a suggestion
    var shouldShowSuggestion: Bool {
        // Not if already accepted or dismissed
        guard suggestionState == .none || suggestionState == .suggested || suggestionState == .snoozed else {
            return false
        }

        // If snoozed, check if snooze period has expired
        if suggestionState == .snoozed {
            if let snoozedUntil = snoozedUntil, Date() < snoozedUntil {
                return false  // Still snoozed
            }
            // Snooze expired - will be shown (state updated in fetchSuggestionCandidates)
        }

        // ARCHITECTURAL DECISION: Category filtering removed.
        // User will manually choose category in future. Trust pattern detection.

        // Must meet confidence threshold
        guard confidenceScore >= 0.75 else {
            return false
        }

        return true
    }

    /// Whether the candidate meets the time-based eligibility criteria
    var isTimeEligible: Bool {
        let now = Date()
        let daysSinceFirst = Calendar.current.dateComponents([.day], from: firstDocumentDate, to: now).day ?? 0

        // Option 1: First document >= 60 days ago
        if daysSinceFirst >= 60 {
            return true
        }

        // Option 2: 3+ documents spanning 45+ days
        if documentCount >= 3 && daySpan >= 45 {
            return true
        }

        return false
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        vendorFingerprint: String,
        vendorDisplayName: String,
        documentCategory: DocumentCategory = .unknown,
        documentCount: Int = 0,
        firstDocumentDate: Date = Date(),
        lastDocumentDate: Date = Date(),
        confidenceScore: Double = 0.0,
        currency: String = "PLN"
    ) {
        self.id = id
        self.vendorFingerprint = vendorFingerprint
        self.vendorDisplayName = vendorDisplayName
        self.documentCategoryRaw = documentCategory.rawValue
        self.documentCount = documentCount
        self.firstDocumentDate = firstDocumentDate
        self.lastDocumentDate = lastDocumentDate
        self.daySpan = Calendar.current.dateComponents([.day], from: firstDocumentDate, to: lastDocumentDate).day ?? 0
        self.dominantDueDayOfMonth = nil
        self.dominantDueDayPercentage = nil
        self.dueDateStdDev = nil
        self.dueDateBucketStabilityRatio = nil
        self.averageAmountValue = nil
        self.amountStdDev = nil
        self.minAmountValue = nil
        self.maxAmountValue = nil
        self.confidenceScore = confidenceScore
        self.hasStableIBAN = false
        self.hasRecurringKeywords = false
        self.currency = currency
        self.stableIBAN = nil
        self.hasFallbackFingerprint = false
        self.suggestionStateRaw = SuggestionState.none.rawValue
        self.firstSuggestedAt = nil
        self.lastSuggestedAt = nil
        self.suggestionCount = 0
        self.dismissedAt = nil
        self.acceptedAt = nil
        self.snoozedUntil = nil
        self.createdTemplateId = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Update Methods

    /// Marks the candidate as updated
    func markUpdated() {
        updatedAt = Date()
    }

    /// Updates statistics after a new document is added
    func updateStatistics(
        documentCount: Int,
        firstDocumentDate: Date,
        lastDocumentDate: Date,
        dominantDueDayOfMonth: Int?,
        dominantDueDayPercentage: Double?,
        dueDateStdDev: Double?,
        dueDateBucketStabilityRatio: Double?,
        averageAmount: Decimal?,
        amountStdDev: Double?,
        minAmount: Decimal?,
        maxAmount: Decimal?,
        hasStableIBAN: Bool,
        stableIBAN: String?,
        hasRecurringKeywords: Bool,
        hasFallbackFingerprint: Bool,
        confidenceScore: Double
    ) {
        self.documentCount = documentCount
        // Update first document date if earlier than current
        if firstDocumentDate < self.firstDocumentDate {
            self.firstDocumentDate = firstDocumentDate
        }
        self.lastDocumentDate = lastDocumentDate
        // CRITICAL: Calculate daySpan from first to last (positive value)
        // Using the stored firstDocumentDate which may have been updated above
        self.daySpan = Calendar.current.dateComponents([.day], from: self.firstDocumentDate, to: lastDocumentDate).day ?? 0
        self.dominantDueDayOfMonth = dominantDueDayOfMonth
        self.dominantDueDayPercentage = dominantDueDayPercentage
        self.dueDateStdDev = dueDateStdDev
        self.dueDateBucketStabilityRatio = dueDateBucketStabilityRatio
        self.averageAmount = averageAmount
        self.amountStdDev = amountStdDev
        self.minAmount = minAmount
        self.maxAmount = maxAmount
        self.hasStableIBAN = hasStableIBAN
        self.stableIBAN = stableIBAN
        self.hasRecurringKeywords = hasRecurringKeywords
        self.hasFallbackFingerprint = hasFallbackFingerprint
        self.confidenceScore = confidenceScore
        markUpdated()
    }

    /// Marks the candidate as suggested to the user
    func markSuggested() {
        if firstSuggestedAt == nil {
            firstSuggestedAt = Date()
        }
        lastSuggestedAt = Date()
        suggestionCount += 1
        suggestionState = .suggested
        markUpdated()
    }

    /// Marks the candidate as dismissed by the user
    func dismiss() {
        suggestionState = .dismissed
        dismissedAt = Date()
        markUpdated()
    }

    /// Marks the candidate as accepted and links to the created template
    func accept(templateId: UUID) {
        suggestionState = .accepted
        acceptedAt = Date()
        createdTemplateId = templateId
        markUpdated()
    }

    /// Snoozes the suggestion for the specified number of days.
    /// - Parameter days: Number of days to snooze (default: 7)
    func snooze(days: Int = 7) {
        let snoozeInterval = TimeInterval(days * 24 * 60 * 60)
        snoozedUntil = Date().addingTimeInterval(snoozeInterval)
        suggestionState = .snoozed
        lastSuggestedAt = nil  // Clear so it doesn't appear in current suggestions
        markUpdated()
    }

    /// Resets the suggestion state (e.g., after snooze period expires)
    func resetSuggestionState() {
        suggestionState = .suggested
        snoozedUntil = nil
        markUpdated()
    }

    /// Checks if snooze has expired and resets state if needed.
    /// Returns true if the candidate is now available for suggestion.
    func checkAndResetExpiredSnooze() -> Bool {
        if suggestionState == .snoozed {
            if let snoozedUntil = snoozedUntil, Date() >= snoozedUntil {
                // Snooze expired, reset to suggested
                resetSuggestionState()
                return true
            }
            return false  // Still snoozed
        }
        return suggestionState == .none || suggestionState == .suggested
    }
}

// MARK: - Suggestion State

/// State of a recurring candidate suggestion
enum SuggestionState: String, Codable, Sendable {
    /// Not yet shown to user (still gathering data or below threshold)
    case none

    /// Currently being shown as a suggestion
    case suggested

    /// User snoozed the suggestion (will re-suggest after snooze period)
    case snoozed

    /// User dismissed the suggestion (permanent)
    case dismissed

    /// User accepted the suggestion (template was created)
    case accepted
}
