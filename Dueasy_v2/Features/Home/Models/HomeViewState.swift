import Foundation

/// State container for the Home screen (Glance Dashboard).
/// Single source of truth for all computed metrics displayed on Home.
///
/// This struct is designed to be computed by `FetchHomeMetricsUseCase`
/// and consumed by `HomeViewModel`. All logic lives in the use case;
/// the ViewModel exposes this state for UI binding.
struct HomeViewState: Equatable, Sendable {

    // MARK: - Hero Card Metrics (Due in Next 7 Days)

    /// Total amount due in the next 7 days
    let dueIn7DaysTotal: Decimal

    /// Number of invoices due in the next 7 days
    let dueIn7DaysCount: Int

    /// Closest due date among upcoming invoices
    let nextDueDate: Date?

    /// Currency for the hero amount display (uses most common currency)
    let heroCurrency: String

    // MARK: - Status Capsules

    /// Number of overdue unpaid items
    let overdueCount: Int

    /// Number of items due within the next 3 days (due soon)
    let dueSoonCount: Int

    // MARK: - Overdue Tile Metrics

    /// Total amount overdue
    let overdueTotal: Decimal

    /// Days since the oldest overdue item was due
    let oldestOverdueDays: Int?

    /// Currency for overdue amount display
    let overdueCurrency: String

    // MARK: - Recurring Tile Metrics

    /// Number of active recurring templates
    let activeRecurringCount: Int

    /// Next recurring payment info (vendor name and days until due)
    let nextRecurringVendor: String?
    let nextRecurringDaysUntil: Int?

    /// Number of missing recurring instances this cycle
    let missingRecurringCount: Int

    /// Display name of the first active recurring template (for tile display)
    /// This is the short company name used for fingerprint matching
    let firstRecurringVendorName: String?

    // MARK: - Next 3 Payments List

    /// Up to 3 next payment items for the compact list
    let nextPayments: [HomePaymentItem]

    // MARK: - Month Summary (Donut Chart)

    /// Payment counts for the current month (by due date)
    let monthPaidCount: Int
    let monthDueCount: Int
    let monthOverdueCount: Int

    /// Paid percentage for center display (0-100)
    let paidPercent: Int

    /// Total unpaid amount this month
    let monthUnpaidTotal: Decimal

    /// Currency for month summary display
    let monthCurrency: String

    // MARK: - App State

    /// Whether the user has any documents at all
    let hasDocuments: Bool

    // MARK: - Computed Properties

    /// Whether there are any upcoming or overdue items
    var hasUpcomingPayments: Bool {
        dueIn7DaysCount > 0 || overdueCount > 0
    }

    /// Whether the overdue tile should show "All clear"
    var isOverdueClear: Bool {
        overdueCount == 0
    }

    /// Whether recurring section has no templates
    var hasNoRecurringTemplates: Bool {
        activeRecurringCount == 0
    }

    /// Total invoices this month for donut center
    var monthTotalCount: Int {
        monthPaidCount + monthDueCount + monthOverdueCount
    }

    // MARK: - Factory

    /// Empty state for initial load
    static let empty = HomeViewState(
        dueIn7DaysTotal: 0,
        dueIn7DaysCount: 0,
        nextDueDate: nil,
        heroCurrency: "PLN",
        overdueCount: 0,
        dueSoonCount: 0,
        overdueTotal: 0,
        oldestOverdueDays: nil,
        overdueCurrency: "PLN",
        activeRecurringCount: 0,
        nextRecurringVendor: nil,
        nextRecurringDaysUntil: nil,
        missingRecurringCount: 0,
        firstRecurringVendorName: nil,
        nextPayments: [],
        monthPaidCount: 0,
        monthDueCount: 0,
        monthOverdueCount: 0,
        paidPercent: 0,
        monthUnpaidTotal: 0,
        monthCurrency: "PLN",
        hasDocuments: false
    )
}

// MARK: - Payment Item

/// Represents a single payment row in the Next 3 Payments list.
struct HomePaymentItem: Identifiable, Equatable, Sendable {

    /// Unique identifier (document ID)
    let id: UUID

    /// Vendor or document title
    let vendorName: String

    /// Payment amount
    let amount: Decimal

    /// Currency code
    let currency: String

    /// Due date
    let dueDate: Date

    /// Whether this payment is overdue
    let isOverdue: Bool

    /// Days until due (negative if overdue)
    let daysUntilDue: Int

    /// Source document reference for navigation
    let documentId: UUID
}
