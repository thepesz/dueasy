import Foundation
import os.log

/// Use case for computing all Home screen metrics.
///
/// This use case is the single place where Home screen data is computed.
/// It fetches documents and recurring data, then computes all metrics
/// needed for `HomeViewState`.
///
/// Pure business logic - no UI dependencies.
@MainActor
final class FetchHomeMetricsUseCase: Sendable {

    private let documentRepository: DocumentRepositoryProtocol
    private let recurringTemplateService: RecurringTemplateServiceProtocol
    private let recurringSchedulerService: RecurringSchedulerServiceProtocol
    private let recurringDateService: RecurringDateServiceProtocol
    private let appTier: AppTier
    private let logger = Logger(subsystem: "com.dueasy.app", category: "FetchHomeMetrics")

    init(
        documentRepository: DocumentRepositoryProtocol,
        recurringTemplateService: RecurringTemplateServiceProtocol,
        recurringSchedulerService: RecurringSchedulerServiceProtocol,
        recurringDateService: RecurringDateServiceProtocol,
        appTier: AppTier
    ) {
        self.documentRepository = documentRepository
        self.recurringTemplateService = recurringTemplateService
        self.recurringSchedulerService = recurringSchedulerService
        self.recurringDateService = recurringDateService
        self.appTier = appTier
    }

    /// Executes the use case and returns computed HomeViewState.
    /// - Throws: AppError if data fetching fails
    /// - Returns: Fully computed HomeViewState
    func execute() async throws -> HomeViewState {
        logger.info("Computing Home metrics")

        // Fetch all documents
        let allDocuments = try await documentRepository.fetchAll()

        // Check if user has any documents at all
        guard !allDocuments.isEmpty else {
            logger.info("No documents found - returning empty state")
            return HomeViewState(
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
                nextPayments: [],
                monthPaidCount: 0,
                monthDueCount: 0,
                monthOverdueCount: 0,
                paidPercent: 0,
                monthUnpaidTotal: 0,
                monthCurrency: "PLN",
                hasDocuments: false,
                appTier: appTier
            )
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sevenDaysFromNow = calendar.date(byAdding: .day, value: 7, to: today)!
        let threeDaysFromNow = calendar.date(byAdding: .day, value: 3, to: today)!

        // Filter unpaid documents (not paid status)
        let unpaidDocuments = allDocuments.filter { $0.status != .paid }

        // --- Hero Card: Due in Next 7 Days + Overdue ---
        // The hero card now includes BOTH:
        // 1. Documents due in the next 7 days
        // 2. All overdue documents (due date in the past, not yet paid)
        // This gives users immediate visibility of ALL urgent items that need attention.
        let upcoming7Days = unpaidDocuments.filter { doc in
            guard let dueDate = doc.dueDate else { return false }
            let startOfDueDate = calendar.startOfDay(for: dueDate)
            return startOfDueDate >= today && startOfDueDate <= sevenDaysFromNow
        }

        // Overdue documents: due date in the past, not paid
        let overdueForHero = unpaidDocuments.filter { doc in
            guard let dueDate = doc.dueDate else { return false }
            return calendar.startOfDay(for: dueDate) < today
        }

        // Combine upcoming + overdue for total amount and count
        let heroDocuments = upcoming7Days + overdueForHero
        let dueIn7DaysTotal = heroDocuments.reduce(Decimal(0)) { $0 + $1.amount }
        let dueIn7DaysCount = heroDocuments.count

        // Next due date: show the closest upcoming date (not overdue dates which are in the past)
        let nextDueDate = upcoming7Days
            .compactMap { $0.dueDate }
            .min()
        let heroCurrency = mostCommonCurrency(in: heroDocuments) ?? "PLN"

        // --- Status Capsules ---
        let overdueDocuments = unpaidDocuments.filter { doc in
            guard let dueDate = doc.dueDate else { return false }
            return calendar.startOfDay(for: dueDate) < today
        }
        let overdueCount = overdueDocuments.count

        let dueSoonDocuments = unpaidDocuments.filter { doc in
            guard let dueDate = doc.dueDate else { return false }
            let startOfDueDate = calendar.startOfDay(for: dueDate)
            return startOfDueDate >= today && startOfDueDate <= threeDaysFromNow
        }
        let dueSoonCount = dueSoonDocuments.count

        // --- Overdue Tile ---
        let overdueTotal = overdueDocuments.reduce(Decimal(0)) { $0 + $1.amount }
        let oldestOverdueDate = overdueDocuments
            .compactMap { $0.dueDate }
            .min()
        let oldestOverdueDays: Int? = oldestOverdueDate.flatMap { oldestDate in
            let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: oldestDate), to: today)
            return components.day
        }
        let overdueCurrency = mostCommonCurrency(in: overdueDocuments) ?? "PLN"

        // --- Recurring Tile ---
        let activeTemplates = try await recurringTemplateService.fetchActiveTemplates()
        let activeRecurringCount = activeTemplates.count

        let upcomingInstances = try await recurringSchedulerService.fetchUpcomingInstances(limit: 10)
        let nextInstance = upcomingInstances.first { $0.status == .expected || $0.status == .matched }
        let nextRecurringVendor: String?
        let nextRecurringDaysUntil: Int?

        if let instance = nextInstance,
           let template = activeTemplates.first(where: { $0.id == instance.templateId }) {
            nextRecurringVendor = template.vendorDisplayName
            // Calculate days until due using dateService (MVVM compliance)
            let daysUntil = recurringDateService.daysBetween(from: today, to: instance.expectedDueDate)
            nextRecurringDaysUntil = daysUntil
        } else {
            nextRecurringVendor = nil
            nextRecurringDaysUntil = nil
        }

        // Missing recurring count: instances expected in current month but not matched/paid
        let currentMonthInstances = upcomingInstances.filter { instance in
            guard let yearMonth = instance.yearMonth else { return false }
            let currentYear = calendar.component(.year, from: today)
            let currentMonth = calendar.component(.month, from: today)
            return yearMonth.year == currentYear && yearMonth.month == currentMonth
        }
        let missingRecurringCount = currentMonthInstances.filter {
            $0.status == .expected && $0.isOverdue
        }.count

        // --- Next 3 Payments ---
        let nextPayments = computeNextPayments(
            unpaidDocuments: unpaidDocuments,
            calendar: calendar,
            today: today,
            limit: 3
        )

        // --- Month Summary (Donut) ---
        // The donut chart shows the current state of payments:
        // - Paid: Documents paid this month (due date in current month, status = paid)
        // - Due: Documents due this month that are not yet overdue (due date >= today)
        // - Overdue: ALL unpaid overdue documents (due date < today) regardless of which month
        //
        // This gives users visibility into their complete payment status including
        // historical overdue items that still need attention.
        let currentYear = calendar.component(.year, from: today)
        let currentMonth = calendar.component(.month, from: today)

        let thisMonthDocuments = allDocuments.filter { doc in
            guard let dueDate = doc.dueDate else { return false }
            let dueDateYear = calendar.component(.year, from: dueDate)
            let dueDateMonth = calendar.component(.month, from: dueDate)
            return dueDateYear == currentYear && dueDateMonth == currentMonth
        }

        // Paid: documents with due date in current month that are paid
        let monthPaidCount = thisMonthDocuments.filter { $0.status == .paid }.count

        // Due: documents with due date in current month, not paid, not yet overdue
        let monthDueCount = thisMonthDocuments.filter { doc in
            guard doc.status != .paid, let dueDate = doc.dueDate else { return false }
            return calendar.startOfDay(for: dueDate) >= today
        }.count

        // Overdue: ALL unpaid overdue documents from ANY month (not just current month)
        // This ensures historical overdue items are always visible in the chart
        let monthOverdueCount = overdueDocuments.count

        let monthTotalCount = monthPaidCount + monthDueCount + monthOverdueCount
        let paidPercent = monthTotalCount > 0 ? (monthPaidCount * 100) / monthTotalCount : 0

        // Unpaid total includes: current month due items + all overdue items
        let currentMonthUnpaidDocuments = thisMonthDocuments.filter { $0.status != .paid }
        let monthUnpaidTotal = currentMonthUnpaidDocuments.reduce(Decimal(0)) { $0 + $1.amount } + overdueTotal
        let monthCurrency = mostCommonCurrency(in: thisMonthDocuments) ?? "PLN"

        logger.info("Home metrics computed: upcoming7=\(dueIn7DaysCount), overdue=\(overdueCount), recurring=\(activeRecurringCount)")

        return HomeViewState(
            dueIn7DaysTotal: dueIn7DaysTotal,
            dueIn7DaysCount: dueIn7DaysCount,
            nextDueDate: nextDueDate,
            heroCurrency: heroCurrency,
            overdueCount: overdueCount,
            dueSoonCount: dueSoonCount,
            overdueTotal: overdueTotal,
            oldestOverdueDays: oldestOverdueDays,
            overdueCurrency: overdueCurrency,
            activeRecurringCount: activeRecurringCount,
            nextRecurringVendor: nextRecurringVendor,
            nextRecurringDaysUntil: nextRecurringDaysUntil,
            missingRecurringCount: missingRecurringCount,
            nextPayments: nextPayments,
            monthPaidCount: monthPaidCount,
            monthDueCount: monthDueCount,
            monthOverdueCount: monthOverdueCount,
            paidPercent: paidPercent,
            monthUnpaidTotal: monthUnpaidTotal,
            monthCurrency: monthCurrency,
            hasDocuments: true,
            appTier: appTier
        )
    }

    // MARK: - Private Helpers

    /// Returns the most common currency among documents
    private func mostCommonCurrency(in documents: [FinanceDocument]) -> String? {
        let currencyCounts = documents.reduce(into: [String: Int]()) { counts, doc in
            counts[doc.currency, default: 0] += 1
        }
        return currencyCounts.max(by: { $0.value < $1.value })?.key
    }

    /// Computes the next N payment items for the compact list.
    /// Ordering: overdue first (by due date asc), then upcoming (by due date asc)
    private func computeNextPayments(
        unpaidDocuments: [FinanceDocument],
        calendar: Calendar,
        today: Date,
        limit: Int
    ) -> [HomePaymentItem] {
        // Partition into overdue and upcoming
        let overdueItems = unpaidDocuments.filter { doc in
            guard let dueDate = doc.dueDate else { return false }
            return calendar.startOfDay(for: dueDate) < today
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        let upcomingItems = unpaidDocuments.filter { doc in
            guard let dueDate = doc.dueDate else { return false }
            return calendar.startOfDay(for: dueDate) >= today
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        // Combine: overdue first, then upcoming
        let combinedItems = overdueItems + upcomingItems
        let limitedItems = Array(combinedItems.prefix(limit))

        return limitedItems.compactMap { doc -> HomePaymentItem? in
            guard let dueDate = doc.dueDate else { return nil }

            let startOfDueDate = calendar.startOfDay(for: dueDate)
            let isOverdue = startOfDueDate < today

            let components = calendar.dateComponents([.day], from: today, to: startOfDueDate)
            let daysUntilDue = components.day ?? 0

            return HomePaymentItem(
                id: doc.id,
                vendorName: doc.title,
                amount: doc.amount,
                currency: doc.currency,
                dueDate: dueDate,
                isOverdue: isOverdue,
                daysUntilDue: daysUntilDue,
                documentId: doc.id
            )
        }
    }
}
