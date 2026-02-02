import Foundation

/// Filter options for document lists.
/// Used by both UI layer and repository layer for database-level filtering.
enum DocumentFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case pending
    case scheduled
    case paid
    case overdue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:
            return L10n.Filters.all.localized
        case .pending:
            return L10n.Filters.pending.localized
        case .scheduled:
            return L10n.Filters.scheduled.localized
        case .paid:
            return L10n.Filters.paid.localized
        case .overdue:
            return L10n.Filters.overdue.localized
        }
    }

    var iconName: String {
        switch self {
        case .all:
            return "doc.on.doc"
        case .pending:
            return "doc.badge.ellipsis"
        case .scheduled:
            return "calendar.badge.clock"
        case .paid:
            return "checkmark.circle"
        case .overdue:
            return "exclamationmark.triangle"
        }
    }

    /// Maps filter to corresponding DocumentStatus for database queries.
    /// Returns nil for .all (no status filter) and .overdue (computed filter).
    var correspondingStatus: DocumentStatus? {
        switch self {
        case .all:
            return nil
        case .pending:
            return .draft
        case .scheduled:
            return .scheduled
        case .paid:
            return .paid
        case .overdue:
            return nil // Overdue is computed, not a status
        }
    }

    /// Whether this filter requires computing overdue status (dueDate < now AND status != paid)
    var isOverdueFilter: Bool {
        self == .overdue
    }
}
