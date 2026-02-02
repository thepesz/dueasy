import Foundation
import Observation
import os.log

/// ViewModel for the recurring suggestions screen.
/// Displays auto-detection suggestions and handles accept/dismiss/snooze actions.
@MainActor
@Observable
final class RecurringSuggestionsViewModel {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "RecurringSuggestions")

    // MARK: - State

    var isLoading: Bool = false
    var isProcessing: Bool = false
    var error: AppError?
    var suggestions: [RecurringCandidate] = []

    // MARK: - Dependencies

    private let detectCandidatesUseCase: DetectRecurringCandidatesUseCase
    private let schedulerService: RecurringSchedulerServiceProtocol

    // MARK: - Computed Properties

    var hasSuggestions: Bool {
        !suggestions.isEmpty
    }

    // MARK: - Initialization

    init(
        detectCandidatesUseCase: DetectRecurringCandidatesUseCase,
        schedulerService: RecurringSchedulerServiceProtocol
    ) {
        self.detectCandidatesUseCase = detectCandidatesUseCase
        self.schedulerService = schedulerService
    }

    // MARK: - Actions

    func loadSuggestions() async {
        isLoading = true
        error = nil

        do {
            suggestions = try await detectCandidatesUseCase.execute()
            logger.info("Loaded \(self.suggestions.count) recurring suggestions")
        } catch {
            logger.error("Failed to load suggestions: \(error.localizedDescription)")
            self.error = .repositoryFetchFailed(error.localizedDescription)
        }

        isLoading = false
    }

    func acceptSuggestion(_ candidate: RecurringCandidate) async {
        isProcessing = true
        error = nil

        do {
            let template = try await detectCandidatesUseCase.acceptCandidate(candidate)
            logger.info("Accepted suggestion, created template: \(template.id)")

            // Generate instances for the new template (includeHistorical for linking existing docs)
            let instances = try await schedulerService.generateInstances(for: template, monthsAhead: 3, includeHistorical: true)
            logger.info("Generated \(instances.count) instances for new template")

            // Remove from suggestions
            suggestions.removeAll { $0.id == candidate.id }

        } catch {
            logger.error("Failed to accept suggestion: \(error.localizedDescription)")
            self.error = .repositorySaveFailed(error.localizedDescription)
        }

        isProcessing = false
    }

    func dismissSuggestion(_ candidate: RecurringCandidate) async {
        isProcessing = true
        error = nil

        do {
            try await detectCandidatesUseCase.dismissCandidate(candidate)
            // PRIVACY: Don't log vendor name
            logger.info("Dismissed suggestion: confidence=\(String(format: "%.2f", candidate.confidenceScore))")

            // Remove from suggestions
            suggestions.removeAll { $0.id == candidate.id }

        } catch {
            logger.error("Failed to dismiss suggestion: \(error.localizedDescription)")
            self.error = .repositorySaveFailed(error.localizedDescription)
        }

        isProcessing = false
    }

    func snoozeSuggestion(_ candidate: RecurringCandidate) async {
        isProcessing = true
        error = nil

        do {
            try await detectCandidatesUseCase.snoozeCandidate(candidate)
            // PRIVACY: Don't log vendor name
            logger.info("Snoozed suggestion: confidence=\(String(format: "%.2f", candidate.confidenceScore))")

            // Remove from suggestions (will reappear later)
            suggestions.removeAll { $0.id == candidate.id }

        } catch {
            logger.error("Failed to snooze suggestion: \(error.localizedDescription)")
            self.error = .repositorySaveFailed(error.localizedDescription)
        }

        isProcessing = false
    }

    func clearError() {
        error = nil
    }
}
