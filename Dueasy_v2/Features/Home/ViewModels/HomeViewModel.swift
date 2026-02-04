import Foundation
import Observation
import os.log

/// ViewModel for the Home screen (Glance Dashboard).
///
/// Exposes `HomeViewState` as single source of truth for UI binding.
/// All computation happens in `FetchHomeMetricsUseCase` - this ViewModel
/// only orchestrates loading and error handling.
///
/// Architecture: SwiftUI View -> HomeViewModel -> FetchHomeMetricsUseCase -> Repositories/Services
@MainActor
@Observable
final class HomeViewModel {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "HomeViewModel")

    // MARK: - State

    /// The computed state for the Home screen
    private(set) var state: HomeViewState = .empty

    /// Whether data is currently loading
    private(set) var isLoading: Bool = false

    /// Current error, if any
    private(set) var error: AppError?

    // MARK: - Dependencies

    private let fetchHomeMetricsUseCase: FetchHomeMetricsUseCase

    // MARK: - Initialization

    init(fetchHomeMetricsUseCase: FetchHomeMetricsUseCase) {
        self.fetchHomeMetricsUseCase = fetchHomeMetricsUseCase
    }

    // MARK: - Actions

    /// Loads all Home screen metrics.
    /// Call this on appear and after document changes.
    func loadMetrics() async {
        logger.info("HomeViewModel.loadMetrics() called")
        isLoading = true
        error = nil

        do {
            state = try await fetchHomeMetricsUseCase.execute()
            logger.info("Home metrics loaded successfully")
        } catch let appError as AppError {
            logger.error("Home metrics load failed: \(appError.localizedDescription)")
            error = appError
        } catch {
            logger.error("Home metrics load failed: \(error.localizedDescription)")
            self.error = .repositoryFetchFailed(error.localizedDescription)
        }

        isLoading = false
    }

    /// Clears the current error
    func clearError() {
        error = nil
    }

    // MARK: - Computed Properties for UI

    /// Status chip text (Offline or Pro)
    var statusChipText: String {
        state.appTier == .pro
            ? L10n.Home.statusPro.localized
            : L10n.Home.statusOffline.localized
    }

    /// Whether to show the status chip as Pro (blue) vs Offline (gray)
    var isProTier: Bool {
        state.appTier == .pro
    }

    /// Formatted hero amount for display
    var formattedHeroAmount: String {
        formatCurrency(state.dueIn7DaysTotal, currency: state.heroCurrency)
    }

    /// Hero subtitle text (e.g., "3 invoices - Next due: Feb 5")
    var heroSubtitle: String {
        var parts: [String] = []

        if state.dueIn7DaysCount > 0 {
            let invoicesText = String.localized(L10n.Home.invoicesCount, with: state.dueIn7DaysCount)
            parts.append(invoicesText)
        }

        if let nextDue = state.nextDueDate {
            let nextDueText = L10n.Home.nextDue.localized + ": " + formatShortDate(nextDue)
            parts.append(nextDueText)
        }

        return parts.joined(separator: " - ")
    }

    /// Formatted overdue amount for tile display
    var formattedOverdueAmount: String {
        formatCurrency(state.overdueTotal, currency: state.overdueCurrency)
    }

    /// Overdue tile subtitle (e.g., "Oldest: 5 days")
    var overdueSubtitle: String? {
        guard let days = state.oldestOverdueDays, days > 0 else { return nil }
        return String.localized(L10n.Home.oldestOverdue, with: days)
    }

    /// Recurring tile - formatted active count (e.g., "Aktywne: 2")
    var recurringActiveCountText: String {
        String.localized(L10n.Home.activeCount, with: state.activeRecurringCount)
    }

    /// Recurring tile - next vendor line (e.g., "Nastepna: Lantech")
    /// Returns nil if no upcoming recurring payment
    var recurringNextVendorText: String? {
        guard let vendor = state.nextRecurringVendor else { return nil }
        return String.localized(L10n.Home.nextRecurringVendor, with: vendor)
    }

    /// Recurring tile - days until next (e.g., "Za 12 dni")
    /// Returns nil if no upcoming recurring payment
    var recurringDaysUntilText: String? {
        guard let days = state.nextRecurringDaysUntil else { return nil }
        return String.localized(L10n.Home.inDays, with: days)
    }

    /// Formatted month unpaid total
    var formattedMonthUnpaidTotal: String {
        formatCurrency(state.monthUnpaidTotal, currency: state.monthCurrency)
    }

    /// Center text for donut chart
    var donutCenterPercent: String {
        "\(state.paidPercent)%"
    }

    var donutCenterSubtitle: String {
        String.localized(L10n.Home.invoicesCount, with: state.monthTotalCount)
    }

    // MARK: - Private Helpers

    private func formatCurrency(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(currency)"
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
