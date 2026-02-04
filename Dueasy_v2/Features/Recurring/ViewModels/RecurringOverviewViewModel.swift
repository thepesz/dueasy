import Foundation
import Observation
import os.log

/// ViewModel for the recurring payments overview screen.
/// Displays templates, upcoming instances, and manages template lifecycle.
@MainActor
@Observable
final class RecurringOverviewViewModel {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "RecurringOverview")

    // MARK: - State

    var isLoading: Bool = false
    var error: AppError?
    var templates: [RecurringTemplate] = []
    var upcomingInstances: [RecurringInstanceWithTemplate] = []

    // Filter state
    var showPausedTemplates: Bool = false

    // MARK: - Dependencies

    private let templateService: RecurringTemplateServiceProtocol
    private let schedulerService: RecurringSchedulerServiceProtocol

    // MARK: - Computed Properties

    var activeTemplates: [RecurringTemplate] {
        templates.filter { $0.isActive }
    }

    var pausedTemplates: [RecurringTemplate] {
        templates.filter { !$0.isActive }
    }

    var filteredTemplates: [RecurringTemplate] {
        showPausedTemplates ? pausedTemplates : activeTemplates
    }

    var hasTemplates: Bool {
        !templates.isEmpty
    }

    var hasUpcomingInstances: Bool {
        !upcomingInstances.isEmpty
    }

    // MARK: - Initialization

    init(
        templateService: RecurringTemplateServiceProtocol,
        schedulerService: RecurringSchedulerServiceProtocol
    ) {
        self.templateService = templateService
        self.schedulerService = schedulerService
    }

    // MARK: - Actions

    func loadData() async {
        isLoading = true
        error = nil

        do {
            // Load templates
            templates = try await templateService.fetchAllTemplates()

            // Enhanced logging for debugging "7 of 9" issue
            let activeCount = templates.filter { $0.isActive }.count
            let pausedCount = templates.filter { !$0.isActive }.count
            logger.info("[RecurringOverview] Total templates fetched: \(self.templates.count)")
            logger.info("[RecurringOverview] Active templates: \(activeCount), Paused templates: \(pausedCount)")

            // Log each template's basic info for debugging (without sensitive data)
            for (index, template) in templates.enumerated() {
                let fpPrefix = String(template.vendorFingerprint.prefix(8))
                logger.debug("[RecurringOverview] Template \(index + 1): id=\(template.id), fingerprint=\(fpPrefix)..., isActive=\(template.isActive)")
            }

            // Load upcoming instances
            let instances = try await schedulerService.fetchUpcomingInstances(limit: 10)

            // Enrich instances with template data
            var enrichedInstances: [RecurringInstanceWithTemplate] = []
            for instance in instances {
                if let template = templates.first(where: { $0.id == instance.templateId }) {
                    enrichedInstances.append(RecurringInstanceWithTemplate(
                        instance: instance,
                        template: template
                    ))
                }
            }
            upcomingInstances = enrichedInstances
            logger.info("Loaded \(self.upcomingInstances.count) upcoming instances")

            // Mark overdue instances as missed
            let missedCount = try await schedulerService.markOverdueInstancesAsMissed()
            if missedCount > 0 {
                logger.info("Marked \(missedCount) overdue instances as missed")
            }

        } catch {
            logger.error("Failed to load recurring data: \(error.localizedDescription)")
            self.error = .repositoryFetchFailed(error.localizedDescription)
        }

        isLoading = false
    }

    func pauseTemplate(_ template: RecurringTemplate) async {
        do {
            try await templateService.updateTemplate(template, reminderOffsets: nil, toleranceDays: nil, isActive: false)
            await loadData()
            // PRIVACY: Don't log vendor name
            logger.info("Paused template: id=\(template.id)")
        } catch {
            logger.error("Failed to pause template: \(error.localizedDescription)")
            self.error = .repositorySaveFailed(error.localizedDescription)
        }
    }

    func resumeTemplate(_ template: RecurringTemplate) async {
        do {
            try await templateService.updateTemplate(template, reminderOffsets: nil, toleranceDays: nil, isActive: true)

            // Regenerate instances for resumed template
            let _ = try await schedulerService.generateInstances(for: template, monthsAhead: 3, includeHistorical: false)

            await loadData()
            // PRIVACY: Don't log vendor name
            logger.info("Resumed template: id=\(template.id)")
        } catch {
            logger.error("Failed to resume template: \(error.localizedDescription)")
            self.error = .repositorySaveFailed(error.localizedDescription)
        }
    }

    func deleteTemplate(_ template: RecurringTemplate) async {
        do {
            try await templateService.deleteTemplate(template)
            await loadData()
            // PRIVACY: Don't log vendor name
            logger.info("Deleted template: id=\(template.id)")
        } catch {
            logger.error("Failed to delete template: \(error.localizedDescription)")
            self.error = .repositoryDeleteFailed(error.localizedDescription)
        }
    }

    func markInstanceAsPaid(_ instance: RecurringInstance) async {
        do {
            try await schedulerService.markInstanceAsPaid(instance)
            await loadData()
            logger.info("Marked instance as paid: \(instance.periodKey)")
        } catch {
            logger.error("Failed to mark instance as paid: \(error.localizedDescription)")
            self.error = .repositorySaveFailed(error.localizedDescription)
        }
    }

    func clearError() {
        error = nil
    }
}

/// Wrapper combining a RecurringInstance with its parent Template for display
struct RecurringInstanceWithTemplate: Identifiable {
    let instance: RecurringInstance
    let template: RecurringTemplate

    var id: UUID { instance.id }
}
