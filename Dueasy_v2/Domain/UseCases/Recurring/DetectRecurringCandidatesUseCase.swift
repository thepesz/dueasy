import Foundation
import os.log

/// Use case for detecting recurring payment candidates (auto-detection path).
/// Called periodically to analyze vendor patterns and generate suggestions.
///
/// Flow:
/// 1. Run detection analysis for all eligible vendors
/// 2. Return candidates that meet suggestion criteria
final class DetectRecurringCandidatesUseCase: @unchecked Sendable {

    private let detectionService: RecurringDetectionServiceProtocol
    private let templateService: RecurringTemplateServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "DetectRecurringCandidates")

    init(
        detectionService: RecurringDetectionServiceProtocol,
        templateService: RecurringTemplateServiceProtocol
    ) {
        self.detectionService = detectionService
        self.templateService = templateService
    }

    /// Runs detection analysis and returns candidates that should be shown as suggestions.
    /// - Returns: Array of recurring candidates to suggest to the user
    @MainActor
    func execute() async throws -> [RecurringCandidate] {
        logger.info("Running recurring detection analysis")

        // Run detection for all eligible vendors
        let updatedCount = try await detectionService.runDetectionAnalysis()
        logger.info("Detection updated \(updatedCount) candidates")

        // Fetch candidates that should be shown
        let suggestions = try await detectionService.fetchSuggestionCandidates()
        logger.info("Found \(suggestions.count) candidates to suggest")

        // Mark them as suggested
        for candidate in suggestions {
            candidate.markSuggested()
        }

        return suggestions
    }

    /// Accepts a recurring candidate and creates a template from it.
    /// - Parameters:
    ///   - candidate: The candidate to accept
    ///   - reminderOffsets: Reminder offsets in days before due date
    ///   - toleranceDays: Tolerance for matching due dates
    /// - Returns: The created template
    @MainActor
    func acceptCandidate(
        _ candidate: RecurringCandidate,
        reminderOffsets: [Int] = [7, 1, 0],
        toleranceDays: Int = 3
    ) async throws -> RecurringTemplate {
        logger.info("Accepting recurring candidate: \(candidate.vendorDisplayName)")

        let template = try await templateService.createTemplate(
            from: candidate,
            reminderOffsets: reminderOffsets,
            toleranceDays: toleranceDays
        )

        return template
    }

    /// Dismisses a recurring candidate (will not be shown again).
    /// - Parameter candidate: The candidate to dismiss
    @MainActor
    func dismissCandidate(_ candidate: RecurringCandidate) async throws {
        logger.info("Dismissing recurring candidate: \(candidate.vendorDisplayName)")
        try await detectionService.dismissCandidate(candidate)
    }

    /// Snoozes a recurring candidate (will be shown again later).
    /// - Parameter candidate: The candidate to snooze
    @MainActor
    func snoozeCandidate(_ candidate: RecurringCandidate) async throws {
        logger.info("Snoozing recurring candidate: \(candidate.vendorDisplayName)")
        try await detectionService.snoozeCandidate(candidate)
    }
}
