import Foundation
import SwiftUI

/// Status of a finance document in its lifecycle.
enum DocumentStatus: String, Codable, CaseIterable, Identifiable {
    case draft      // Document created but not finalized
    case scheduled  // Document finalized with calendar event
    case paid       // Payment completed
    case archived   // Document archived (for historical records)

    var id: String { rawValue }

    /// Display name for UI (localized)
    var displayName: String {
        switch self {
        case .draft:
            return L10n.Status.draft.localized
        case .scheduled:
            return L10n.Status.scheduled.localized
        case .paid:
            return L10n.Status.paid.localized
        case .archived:
            return L10n.Status.archived.localized
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .draft:
            return "doc.badge.ellipsis"
        case .scheduled:
            return "calendar.badge.clock"
        case .paid:
            return "checkmark.circle.fill"
        case .archived:
            return "archivebox"
        }
    }

    /// Color for status badge
    var color: Color {
        switch self {
        case .draft:
            return .secondary
        case .scheduled:
            return .orange
        case .paid:
            return .green
        case .archived:
            return .gray
        }
    }

    /// Whether document can be edited
    var isEditable: Bool {
        switch self {
        case .draft, .scheduled:
            return true
        case .paid, .archived:
            return false
        }
    }
}
