import Foundation
import SwiftData
import os.log

/// Use case for fetching RecurringInstance entities for a given month.
/// Groups instances by day for calendar display.
struct FetchRecurringInstancesForMonthUseCase: Sendable {

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.dueasy.app", category: "FetchRecurringInstances")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Fetches all recurring instances with expected due dates in the specified month.
    /// - Parameters:
    ///   - month: The month to fetch instances for (1-12)
    ///   - year: The year to fetch instances for
    /// - Returns: Dictionary mapping day-of-month to instances due on that day
    @MainActor
    func execute(month: Int, year: Int) async throws -> [Int: [RecurringInstance]] {
        // Generate the period key for this month (YYYY-MM format)
        let periodKey = String(format: "%04d-%02d", year, month)

        logger.info("📅 Fetching recurring instances for period: \(periodKey)")

        // DEBUG: First fetch ALL instances to see what's in the database
        let allDescriptor = FetchDescriptor<RecurringInstance>()
        let allInstances = try modelContext.fetch(allDescriptor)
        logger.info("📅 DEBUG: Total recurring instances in database: \(allInstances.count)")
        for inst in allInstances {
            logger.info("📅 DEBUG: Instance periodKey=\(inst.periodKey), id=\(inst.id.uuidString), templateId=\(inst.templateId.uuidString)")
        }

        // DEBUG: Also check templates
        let templateDescriptor = FetchDescriptor<RecurringTemplate>()
        let allTemplates = try modelContext.fetch(templateDescriptor)
        logger.info("📅 DEBUG: Total recurring templates in database: \(allTemplates.count)")
        for template in allTemplates {
            logger.info("📅 DEBUG: Template id=\(template.id.uuidString), vendor=\(template.vendorDisplayName)")
        }

        // Fetch instances for this period
        let descriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> { $0.periodKey == periodKey },
            sortBy: [SortDescriptor(\.expectedDueDate)]
        )

        let instances = try modelContext.fetch(descriptor)

        logger.info("📅 Found \(instances.count) recurring instances for period: \(periodKey)")

        // Log individual instances for debugging
        for instance in instances {
            logger.debug("📅 Instance: \(instance.id.uuidString), periodKey: \(instance.periodKey), status: \(instance.statusRaw), dueDate: \(instance.expectedDueDate)")
        }

        // Group by day of month
        var grouped: [Int: [RecurringInstance]] = [:]
        let calendar = Calendar.current

        for instance in instances {
            let day = calendar.component(.day, from: instance.effectiveDueDate)

            if grouped[day] == nil {
                grouped[day] = []
            }
            grouped[day]?.append(instance)
        }

        logger.info("📅 Grouped recurring instances into \(grouped.count) days")

        return grouped
    }

    /// Fetches recurring instances for a date range.
    /// Useful for cross-month views or upcoming instances.
    /// - Parameters:
    ///   - startDate: Start of the date range
    ///   - endDate: End of the date range
    /// - Returns: Array of instances within the range
    @MainActor
    func execute(from startDate: Date, to endDate: Date) async throws -> [RecurringInstance] {
        let descriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> {
                $0.expectedDueDate >= startDate && $0.expectedDueDate <= endDate
            },
            sortBy: [SortDescriptor(\.expectedDueDate)]
        )

        return try modelContext.fetch(descriptor)
    }

    /// Gets summary information for recurring instances in a month.
    /// - Parameters:
    ///   - month: The month (1-12)
    ///   - year: The year
    /// - Returns: Dictionary mapping day-of-month to CalendarRecurringSummary
    @MainActor
    func summaryByDay(month: Int, year: Int) async throws -> [Int: CalendarRecurringSummary] {
        let grouped = try await execute(month: month, year: year)

        return grouped.mapValues { instances in
            let expectedCount = instances.filter { $0.status == .expected }.count
            let matchedCount = instances.filter { $0.status == .matched }.count
            let paidCount = instances.filter { $0.status == .paid }.count
            let missedCount = instances.filter { $0.status == .missed }.count
            let overdueCount = instances.filter { $0.isOverdue }.count

            // Determine priority: overdue > expected > matched > paid > missed
            let priority: CalendarRecurringPriority
            if overdueCount > 0 {
                priority = .overdue
            } else if expectedCount > 0 {
                priority = .expected
            } else if matchedCount > 0 {
                priority = .matched
            } else if paidCount > 0 {
                priority = .paid
            } else {
                priority = .missed
            }

            return CalendarRecurringSummary(
                totalCount: instances.count,
                expectedCount: expectedCount,
                matchedCount: matchedCount,
                paidCount: paidCount,
                missedCount: missedCount,
                overdueCount: overdueCount,
                priority: priority
            )
        }
    }

    /// Fetches a single instance by ID.
    /// - Parameter instanceId: The instance ID
    /// - Returns: The instance if found
    @MainActor
    func fetchInstance(byId instanceId: UUID) async throws -> RecurringInstance? {
        let descriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> { $0.id == instanceId }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Fetches the template for an instance.
    /// - Parameter templateId: The template ID
    /// - Returns: The template if found
    @MainActor
    func fetchTemplate(byId templateId: UUID) async throws -> RecurringTemplate? {
        let descriptor = FetchDescriptor<RecurringTemplate>(
            predicate: #Predicate<RecurringTemplate> { $0.id == templateId }
        )
        return try modelContext.fetch(descriptor).first
    }
}

// MARK: - Supporting Types

/// Summary of recurring instances for a single calendar day.
struct CalendarRecurringSummary: Sendable {
    let totalCount: Int
    let expectedCount: Int
    let matchedCount: Int
    let paidCount: Int
    let missedCount: Int
    let overdueCount: Int
    let priority: CalendarRecurringPriority
}

/// Priority level for calendar day display of recurring instances.
enum CalendarRecurringPriority: Sendable {
    case overdue    // Red - requires attention
    case expected   // Blue - upcoming payment
    case matched    // Orange - matched, awaiting payment
    case paid       // Green - completed
    case missed     // Gray - past and missed
}
