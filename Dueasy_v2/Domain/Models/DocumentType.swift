import Foundation

/// Types of documents supported by DuEasy.
/// MVP: Only Invoice is fully functional. Contract/Receipt are "Coming soon".
enum DocumentType: String, Codable, CaseIterable, Identifiable {
    case invoice
    case contract
    case receipt

    var id: String { rawValue }

    /// Display name for UI (localized)
    var displayName: String {
        switch self {
        case .invoice:
            return L10n.DocumentTypes.invoice.localized
        case .contract:
            return L10n.DocumentTypes.contract.localized
        case .receipt:
            return L10n.DocumentTypes.receipt.localized
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .invoice:
            return "doc.text"
        case .contract:
            return "signature"
        case .receipt:
            return "receipt"
        }
    }

    /// Whether this document type is enabled in MVP
    var isEnabledInMVP: Bool {
        switch self {
        case .invoice:
            return true
        case .contract, .receipt:
            return false // Coming soon
        }
    }

    /// Description for disabled types (localized)
    var comingSoonMessage: String? {
        isEnabledInMVP ? nil : L10n.DocumentTypes.comingSoon.localized
    }
}
