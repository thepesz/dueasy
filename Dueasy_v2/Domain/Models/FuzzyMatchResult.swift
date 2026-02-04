import Foundation

// MARK: - Fuzzy Match Configuration

/// Configuration for fuzzy matching thresholds.
/// These thresholds define when to auto-match, ask user, or create new template.
enum FuzzyMatchThreshold {
    /// Below this threshold (30%), amounts are similar enough to auto-match
    static let autoMatchThreshold: Double = 0.30

    /// Above this threshold (50%), amounts are different enough to auto-create new template
    static let createNewThreshold: Double = 0.50

    /// Between autoMatchThreshold and createNewThreshold is the "fuzzy zone"
    /// where we need to ask the user for confirmation
}

// MARK: - Fuzzy Match Candidate

/// Represents a potential match between a new document and an existing recurring template.
/// Used when the amount difference falls within the fuzzy zone (30-50%).
struct FuzzyMatchCandidate: Identifiable, Sendable {
    /// Unique identifier for SwiftUI List
    let id: UUID

    /// The existing template that might match
    let templateId: UUID

    /// Display name of the vendor for the existing template
    let vendorDisplayName: String

    /// Short name for compact displays
    let vendorShortName: String?

    /// The amount range from the existing template (min-max)
    let existingAmountMin: Decimal?
    let existingAmountMax: Decimal?

    /// The amount from the new document
    let newAmount: Decimal

    /// Currency code
    let currency: String

    /// Percent difference between new amount and template's typical amount
    /// Calculated as: abs(newAmount - templateMidpoint) / templateMidpoint
    let percentDifference: Double

    /// Due day of month from the existing template
    let dueDayOfMonth: Int

    /// When the template was created
    let createdAt: Date

    /// Number of documents matched to this template
    let matchedCount: Int

    /// Computed property for UI display: the typical amount for the existing template
    var existingTypicalAmount: Decimal {
        if let min = existingAmountMin, let max = existingAmountMax {
            return (min + max) / 2
        }
        return existingAmountMin ?? existingAmountMax ?? 0
    }

    /// Formatted percent difference for display (e.g., "44%")
    var formattedPercentDifference: String {
        let intPercent = Int(round(percentDifference * 100))
        return "\(intPercent)%"
    }

    /// Creates a candidate from a RecurringTemplate
    init(
        template: RecurringTemplate,
        newAmount: Decimal,
        percentDifference: Double
    ) {
        self.id = UUID()
        self.templateId = template.id
        self.vendorDisplayName = template.vendorDisplayName
        self.vendorShortName = template.vendorShortName
        self.existingAmountMin = template.amountMin
        self.existingAmountMax = template.amountMax
        self.newAmount = newAmount
        self.currency = template.currency
        self.percentDifference = percentDifference
        self.dueDayOfMonth = template.dueDayOfMonth
        self.createdAt = template.createdAt
        self.matchedCount = template.matchedDocumentCount
    }
}

// MARK: - Fuzzy Match Result

/// Result of checking for fuzzy matches when creating a recurring template.
/// Determines whether to auto-match, ask user, or create new template.
enum FuzzyMatchResult: Sendable {
    /// No existing templates from this vendor - safe to create new
    case noExistingTemplates

    /// Exact fingerprint match found - template already exists
    /// The document should be linked to this template, not create a new one
    case exactMatch(templateId: UUID)

    /// Amount is within 30% of an existing template - auto-match to existing
    /// No user confirmation needed
    case autoMatch(templateId: UUID, percentDifference: Double)

    /// Amount is 30-50% different from existing template(s) - needs user confirmation
    /// User must choose: "Same service" (link) or "Different service" (create new)
    case needsConfirmation(candidates: [FuzzyMatchCandidate])

    /// Amount is >50% different from all existing templates - auto-create new
    /// No user confirmation needed
    case autoCreateNew

    // MARK: - Computed Properties

    /// Whether user confirmation is required
    var requiresUserConfirmation: Bool {
        if case .needsConfirmation = self {
            return true
        }
        return false
    }

    /// Whether a new template should be created (either auto or after user confirmation)
    var shouldCreateNewTemplate: Bool {
        switch self {
        case .noExistingTemplates, .autoCreateNew:
            return true
        case .exactMatch, .autoMatch, .needsConfirmation:
            return false
        }
    }

    /// The template ID to link to, if any
    var templateIdToLink: UUID? {
        switch self {
        case .exactMatch(let id), .autoMatch(let id, _):
            return id
        case .noExistingTemplates, .needsConfirmation, .autoCreateNew:
            return nil
        }
    }
}

// MARK: - Fuzzy Match Helper

/// Helper for calculating fuzzy match percent differences
enum FuzzyMatchCalculator {
    /// Calculates the percent difference between two amounts.
    /// Returns a value from 0.0 (identical) to infinity (very different).
    /// - Parameters:
    ///   - newAmount: The amount from the new document
    ///   - existingMin: Minimum amount from existing template
    ///   - existingMax: Maximum amount from existing template (optional)
    /// - Returns: Percent difference as a decimal (0.44 = 44%)
    static func calculatePercentDifference(
        newAmount: Decimal,
        existingMin: Decimal?,
        existingMax: Decimal?
    ) -> Double {
        guard let min = existingMin else { return 1.0 }

        let max = existingMax ?? min
        let midpoint = (min + max) / 2

        guard midpoint > 0 else { return 1.0 }

        let difference = abs(newAmount - midpoint)
        let percentDiff = NSDecimalNumber(decimal: difference / midpoint).doubleValue

        return percentDiff
    }

    /// Determines the fuzzy match category based on percent difference
    static func categorize(percentDifference: Double) -> FuzzyMatchCategory {
        if percentDifference < FuzzyMatchThreshold.autoMatchThreshold {
            return .autoMatch
        } else if percentDifference >= FuzzyMatchThreshold.createNewThreshold {
            return .autoCreateNew
        } else {
            return .fuzzyZone
        }
    }
}

/// Category of fuzzy match based on percent difference
enum FuzzyMatchCategory {
    case autoMatch      // < 30%
    case fuzzyZone      // 30-50%
    case autoCreateNew  // > 50%
}
