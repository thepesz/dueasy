import Foundation
import os.log

/// Use case for matching a document to a recurring template instance (runtime path).
/// Called after document scan/import to check if it matches an existing recurring pattern.
///
/// Flow:
/// 1. Generate vendor fingerprint if not present
/// 2. Classify document category if unknown
/// 3. Attempt to match to existing template/instance
/// 4. If matched, attach document to instance
final class MatchDocumentToRecurringUseCase: @unchecked Sendable {

    private let matcherService: RecurringMatcherServiceProtocol
    private let fingerprintService: VendorFingerprintServiceProtocol
    private let classifierService: DocumentClassifierServiceProtocol
    private let detectionService: RecurringDetectionServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "MatchDocumentToRecurring")

    init(
        matcherService: RecurringMatcherServiceProtocol,
        fingerprintService: VendorFingerprintServiceProtocol,
        classifierService: DocumentClassifierServiceProtocol,
        detectionService: RecurringDetectionServiceProtocol
    ) {
        self.matcherService = matcherService
        self.fingerprintService = fingerprintService
        self.classifierService = classifierService
        self.detectionService = detectionService
    }

    /// Attempts to match a document to a recurring template.
    /// Also updates auto-detection candidates.
    /// - Parameter document: The document to match
    /// - Returns: Match result if successful, nil otherwise
    @MainActor
    func execute(document: FinanceDocument) async throws -> MatchDocumentResult? {
        logger.info("Attempting to match document to recurring: \(document.id)")

        // Step 1: Generate vendor fingerprint with amount bucket
        // CRITICAL: Always regenerate with amount to ensure proper matching
        // This separates "Santander Credit Card (500 PLN)" from "Santander Loan (1200 PLN)"
        let fingerprintResult = fingerprintService.generateFingerprintWithMetadata(
            vendorName: document.title,
            nip: document.vendorNIP,
            amount: document.amount
        )
        document.vendorFingerprint = fingerprintResult.fingerprint
        logger.info("Generated vendor fingerprint with bucket: \(fingerprintResult.amountBucket ?? "none")")

        // Step 2: Classify document category if unknown
        if document.documentCategory == .unknown {
            let classification = classifierService.classify(
                vendorName: document.title,
                ocrText: nil,
                amount: document.amount
            )
            document.documentCategory = classification.category
            logger.info("Classified document as: \(classification.category.rawValue)")
        }

        // Step 3: Attempt to match to existing template
        if let matchResult = try await matcherService.match(document: document) {
            // Attach document to the matched instance
            try await matcherService.attachDocument(
                document,
                to: matchResult.instance,
                template: matchResult.template
            )

            logger.info("Matched document to recurring instance: \(matchResult.instance.periodKey)")

            return MatchDocumentResult(
                matched: true,
                template: matchResult.template,
                instance: matchResult.instance,
                matchScore: matchResult.matchScore,
                matchReason: matchResult.matchReason
            )
        }

        // Step 4: Update auto-detection candidate (for future suggestions)
        if let fingerprint = document.vendorFingerprint {
            _ = try? await detectionService.analyzeVendor(
                vendorFingerprint: fingerprint,
                vendorName: document.title
            )
            logger.debug("Updated auto-detection candidate for vendor")
        }

        logger.info("No recurring match found for document")
        return nil
    }

    /// Checks if a document could potentially match a recurring template.
    /// Used for UI hints (e.g., showing "Recurring detected" badge).
    /// - Parameter document: The document to check
    /// - Returns: True if the document has a matching template
    @MainActor
    func hasMatchingTemplate(for document: FinanceDocument) async throws -> Bool {
        guard let _ = document.vendorFingerprint ?? fingerprintService.generateFingerprint(
            vendorName: document.title,
            nip: document.vendorNIP
        ).nilIfEmpty else {
            return false
        }

        // Try to match (validation happens inside match() now)
        if let _ = try await matcherService.match(document: document) {
            return true
        }

        return false
    }
}

/// Result of matching a document to recurring
struct MatchDocumentResult {
    /// Whether a match was found
    let matched: Bool

    /// The matched template (if matched)
    let template: RecurringTemplate?

    /// The matched instance (if matched)
    let instance: RecurringInstance?

    /// Match confidence score (0.0 to 1.0)
    let matchScore: Double

    /// Human-readable match reason
    let matchReason: String
}

// MARK: - String Extension

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
