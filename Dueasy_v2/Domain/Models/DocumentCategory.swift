import Foundation

/// Category of a document for recurring payment detection.
/// Used to filter out categories that are not suitable for auto-detection.
///
/// Categories are divided into:
/// - Recurring-friendly: utility, telecom, rent, insurance, subscription, invoiceGeneric
/// - Non-recurring: fuel, grocery, retail, receipt (excluded from auto-detection)
enum DocumentCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Utility bills (electricity, gas, water)
    case utility

    /// Telecom services (phone, internet, TV)
    case telecom

    /// Rent payments
    case rent

    /// Insurance premiums
    case insurance

    /// Subscription services (software, streaming, etc.)
    case subscription

    /// Generic invoice (B2B, services)
    case invoiceGeneric

    /// Fuel purchases (excluded from auto-detection)
    case fuel

    /// Grocery purchases (excluded from auto-detection)
    case grocery

    /// Retail purchases (excluded from auto-detection)
    case retail

    /// Receipts (excluded from auto-detection)
    case receipt

    /// Unknown category
    case unknown

    var id: String { rawValue }

    /// Display name for UI (localized)
    var displayName: String {
        L10n.DocumentCategoryKeys.forCategory(self).localized
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .utility:
            return "bolt.fill"
        case .telecom:
            return "antenna.radiowaves.left.and.right"
        case .rent:
            return "house.fill"
        case .insurance:
            return "shield.fill"
        case .subscription:
            return "repeat.circle.fill"
        case .invoiceGeneric:
            return "doc.text.fill"
        case .fuel:
            return "fuelpump.fill"
        case .grocery:
            return "cart.fill"
        case .retail:
            return "bag.fill"
        case .receipt:
            return "receipt"
        case .unknown:
            return "questionmark.circle"
        }
    }

    /// Whether this category is suitable for auto-detection of recurring patterns.
    /// Fuel, grocery, retail, and receipt are excluded because:
    /// - They have irregular timing (fuel based on usage)
    /// - Amounts vary significantly (grocery)
    /// - They are one-time purchases (retail)
    /// - Receipts rarely have due dates
    var isRecurringFriendly: Bool {
        switch self {
        case .utility, .telecom, .rent, .insurance, .subscription, .invoiceGeneric:
            return true
        case .fuel, .grocery, .retail, .receipt, .unknown:
            return false
        }
    }

    /// Hard rejection for auto-detection suggestions.
    /// These categories should never be suggested as recurring.
    var isHardRejectedForAutoDetection: Bool {
        switch self {
        case .fuel, .retail, .receipt, .grocery:
            return true
        default:
            return false
        }
    }

    /// Weight for confidence scoring in recurring detection (0.0 to 1.0).
    /// This is a soft filter - unknown/generic categories get partial score, not blocked.
    ///
    /// Scoring approach:
    /// - 1.0: Strong recurring signal (utility, telecom, rent, insurance)
    /// - 0.8: Good recurring signal (subscription)
    /// - 0.5: Neutral - don't block but lower confidence (invoiceGeneric, unknown)
    /// - 0.0: Hard block - will fail threshold (fuel, grocery, retail, receipt)
    var recurringConfidenceWeight: Double {
        switch self {
        case .utility, .telecom, .rent, .insurance:
            // Strong recurring signal - these categories are almost always recurring
            return 1.0
        case .subscription:
            // Good signal but less certain than utilities
            return 0.8
        case .invoiceGeneric, .unknown:
            // Soft filter: don't block, just give lower score
            // Require strong signals from other factors (IBAN, amount, keywords)
            return 0.5
        case .fuel, .grocery, .retail, .receipt:
            // Hard block - these should never be detected as recurring
            return 0.0
        }
    }

    /// Whether this category requires additional strong signals for recurring detection.
    /// When true, the detection algorithm should require stable IBAN, amounts, or keywords.
    var requiresStrongSignalForRecurring: Bool {
        switch self {
        case .invoiceGeneric, .unknown:
            return true
        default:
            return false
        }
    }
}
