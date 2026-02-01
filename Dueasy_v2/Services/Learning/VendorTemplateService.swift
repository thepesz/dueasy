import Foundation
import SwiftData
import os.log

/// Service for managing vendor templates and local learning.
/// Learns extraction patterns from user corrections and applies them to improve future accuracy.
@MainActor
final class VendorTemplateService {

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.dueasy.app", category: "VendorTemplate")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Template Lookup

    /// Fetch template for a vendor by NIP
    func fetchTemplate(for nip: String) -> VendorTemplate? {
        let descriptor = FetchDescriptor(predicate: VendorTemplate.byNIP(nip))
        do {
            let templates = try modelContext.fetch(descriptor)
            return templates.first
        } catch {
            logger.error("Failed to fetch template for NIP \(nip): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Template Learning

    /// Record user correction to learn extraction patterns.
    /// Call this when user saves a document after making corrections.
    ///
    /// - Parameters:
    ///   - vendorNIP: Polish Tax ID to identify vendor
    ///   - vendorName: Display name of vendor
    ///   - field: Which field was corrected
    ///   - correctedValue: The user-corrected value (for pattern matching, not stored)
    ///   - evidence: Bounding box of the correct value
    ///   - region: Document region where the value was found
    ///   - anchorUsed: Anchor phrase used to find the value
    func recordCorrection(
        vendorNIP: String,
        vendorName: String,
        field: FieldType,
        correctedValue: String,
        evidence: BoundingBox?,
        region: DocumentRegion?,
        anchorUsed: String?
    ) {
        logger.info("Recording correction for vendor \(vendorName), field: \(field.rawValue)")

        // Find or create template
        var template = fetchTemplate(for: vendorNIP)
        if template == nil {
            template = createTemplate(nip: vendorNIP, name: vendorName)
        }

        guard let template = template else {
            logger.error("Failed to get or create template")
            return
        }

        // Update the field-specific template
        template.updateTemplate(
            for: field,
            region: region,
            anchorPhrase: anchorUsed,
            regionHint: evidence
        )

        // Save changes
        do {
            try modelContext.save()
            logger.info("Template updated successfully. Corrections count: \(template.correctionsCount), Active: \(template.isActive)")
        } catch {
            logger.error("Failed to save template: \(error.localizedDescription)")
        }
    }

    /// Record corrections for all fields in a document.
    /// Convenience method for batch recording.
    func recordAllCorrections(
        vendorNIP: String,
        vendorName: String,
        corrections: [FieldCorrection]
    ) {
        for correction in corrections {
            recordCorrection(
                vendorNIP: vendorNIP,
                vendorName: vendorName,
                field: correction.field,
                correctedValue: correction.correctedValue,
                evidence: correction.evidence,
                region: correction.region,
                anchorUsed: correction.anchorUsed
            )
        }
    }

    // MARK: - Alternative Selection Learning

    /// Record when user selects a non-first alternative for learning.
    /// This helps improve future extractions by learning which patterns users prefer.
    ///
    /// - Parameters:
    ///   - vendorNIP: Polish Tax ID to identify vendor
    ///   - vendorName: Display name of vendor
    ///   - field: Which field the selection was made for
    ///   - selectedAlternative: The candidate the user selected
    ///   - wasFirstChoice: Whether this was the first (best confidence) candidate
    func recordAlternativeSelection(
        vendorNIP: String,
        vendorName: String,
        field: FieldType,
        selectedAlternative: ExtractionCandidate,
        wasFirstChoice: Bool
    ) {
        // Only learn from non-first-choice selections
        guard !wasFirstChoice else {
            logger.debug("User selected first choice for \(field.rawValue) - no learning needed")
            return
        }

        logger.info("Learning from alternative selection for \(field.rawValue)")

        // Find or create template
        var template = fetchTemplate(for: vendorNIP)
        if template == nil {
            template = createTemplate(nip: vendorNIP, name: vendorName)
        }

        guard let template = template else {
            logger.error("Failed to get or create template for alternative learning")
            return
        }

        // Extract region from bounding box
        let region = regionFromBBox(selectedAlternative.bbox)

        // Extract anchor phrase from source
        let anchorPhrase = extractAnchorPhrase(from: selectedAlternative)

        // Update template with the preferred pattern
        template.updateTemplate(
            for: field,
            region: region,
            anchorPhrase: anchorPhrase,
            regionHint: selectedAlternative.bbox
        )

        // Increment corrections count to mark this template as trained
        template.correctionsCount += 1

        // Save changes
        do {
            try modelContext.save()
            logger.info("Alternative selection learned for \(field.rawValue). Template active: \(template.isActive)")
        } catch {
            logger.error("Failed to save alternative learning: \(error.localizedDescription)")
        }
    }

    /// Extract anchor phrase from candidate source description
    private func extractAnchorPhrase(from candidate: ExtractionCandidate) -> String? {
        let source = candidate.source.lowercased()

        // Look for anchor patterns in source
        if source.contains("anchor") {
            // Extract anchor phrase: "anchor: Sprzedawca" -> "sprzedawca"
            if let colonIndex = source.lastIndex(of: ":") {
                let afterColon = source[source.index(after: colonIndex)...]
                let phrase = afterColon.trimmingCharacters(in: .whitespaces)
                if !phrase.isEmpty {
                    return String(phrase)
                }
            }
        }

        return candidate.anchorType
    }

    /// Convert bounding box to document region
    private func regionFromBBox(_ bbox: BoundingBox) -> DocumentRegion? {
        let verticalIndex: Int
        let horizontalIndex: Int

        if bbox.centerY < 0.33 {
            verticalIndex = 0  // top
        } else if bbox.centerY < 0.66 {
            verticalIndex = 1  // middle
        } else {
            verticalIndex = 2  // bottom
        }

        if bbox.centerX < 0.33 {
            horizontalIndex = 0  // left
        } else if bbox.centerX < 0.66 {
            horizontalIndex = 1  // center
        } else {
            horizontalIndex = 2  // right
        }

        let regionMap: [[DocumentRegion]] = [
            [.topLeft, .topCenter, .topRight],
            [.middleLeft, .middleCenter, .middleRight],
            [.bottomLeft, .bottomCenter, .bottomRight]
        ]

        return regionMap[verticalIndex][horizontalIndex]
    }

    /// Create a new template for a vendor (internal helper made accessible)
    func createTemplate(nip: String, name: String) -> VendorTemplate {
        let template = VendorTemplate(vendorNIP: nip, vendorName: name)
        modelContext.insert(template)
        logger.info("Created new vendor template for: \(name) (NIP: \(nip))")
        return template
    }

    // MARK: - Template Application

    /// Apply vendor template to boost extraction confidence.
    /// Returns modified extraction with confidence boost if template matches.
    ///
    /// - Parameters:
    ///   - vendorNIP: Vendor NIP to look up template
    ///   - extraction: The original extraction result
    ///   - field: Which field to apply template to
    /// - Returns: Modified extraction with confidence boost, or original if no template
    func applyTemplate(
        vendorNIP: String,
        to extraction: FieldExtraction,
        field: FieldType
    ) -> FieldExtraction {
        guard let template = fetchTemplate(for: vendorNIP),
              template.isActive else {
            return extraction
        }

        guard let fieldTemplate = template.template(for: field) else {
            return extraction
        }

        // Check if extraction matches the template
        var confidenceBoost: Double = 0.0

        // Boost if region matches
        if let evidence = extraction.evidence,
           let templateRegion = fieldTemplate.regionHint,
           regionsMatch(evidence, templateRegion) {
            confidenceBoost += fieldTemplate.confidenceBoost * 0.5
            logger.debug("Region match for \(field.rawValue), boost: \(confidenceBoost)")
        }

        // Boost if anchor matches
        if let anchor = extraction.candidates.first?.anchorType,
           let templateAnchor = fieldTemplate.anchorPhrase,
           anchor.lowercased().contains(templateAnchor.lowercased()) {
            confidenceBoost += fieldTemplate.confidenceBoost * 0.5
            logger.debug("Anchor match for \(field.rawValue), boost: \(confidenceBoost)")
        }

        // Apply boost and mark template as used
        if confidenceBoost > 0 {
            template.markAsUsed()

            // Create boosted candidates
            let boostedCandidates = extraction.candidates.map { candidate in
                ExtractionCandidate(
                    value: candidate.value,
                    confidence: min(1.0, candidate.confidence + confidenceBoost),
                    bbox: candidate.bbox,
                    method: candidate.method,
                    source: candidate.source + " [template-boosted]",
                    anchorType: candidate.anchorType,
                    region: candidate.region
                )
            }

            return FieldExtraction(
                bestValue: extraction.bestValue,
                candidates: boostedCandidates,
                confidence: min(1.0, extraction.confidence + confidenceBoost),
                evidence: extraction.evidence,
                method: extraction.method
            )
        }

        return extraction
    }

    /// Apply templates to all fields in an analysis result.
    /// Returns modified result with confidence boosts where templates match.
    func applyTemplates(
        vendorNIP: String,
        to result: DocumentAnalysisResult
    ) -> DocumentAnalysisResult {
        guard let template = fetchTemplate(for: vendorNIP),
              template.isActive else {
            return result
        }

        logger.info("Applying template for vendor NIP: \(vendorNIP)")
        template.markAsUsed()

        // Build field confidences with boosts
        var vendorConfidence = result.fieldConfidences?.vendorName ?? 0.5
        var amountConfidence = result.fieldConfidences?.amount ?? 0.5
        var dueDateConfidence = result.fieldConfidences?.dueDate ?? 0.5
        var docNumConfidence = result.fieldConfidences?.documentNumber ?? 0.5

        // Apply boosts for matching fields
        if let vendorTemplate = template.vendorNameTemplate,
           let evidence = result.vendorEvidence,
           regionsMatch(evidence, vendorTemplate.regionHint) {
            vendorConfidence = min(1.0, vendorConfidence + vendorTemplate.confidenceBoost)
        }

        if let amountTemplate = template.amountTemplate,
           let evidence = result.amountEvidence,
           regionsMatch(evidence, amountTemplate.regionHint) {
            amountConfidence = min(1.0, amountConfidence + amountTemplate.confidenceBoost)
        }

        if let dueDateTemplate = template.dueDateTemplate,
           let evidence = result.dueDateEvidence,
           regionsMatch(evidence, dueDateTemplate.regionHint) {
            dueDateConfidence = min(1.0, dueDateConfidence + dueDateTemplate.confidenceBoost)
        }

        if let docNumTemplate = template.documentNumberTemplate,
           let evidence = result.documentNumberEvidence,
           regionsMatch(evidence, docNumTemplate.regionHint) {
            docNumConfidence = min(1.0, docNumConfidence + docNumTemplate.confidenceBoost)
        }

        // Calculate new overall confidence
        let confidences = [vendorConfidence, amountConfidence, dueDateConfidence, docNumConfidence]
        let overallConfidence = confidences.reduce(0, +) / Double(confidences.count)

        // Build new result with boosted confidences
        return DocumentAnalysisResult(
            documentType: result.documentType,
            vendorName: result.vendorName,
            vendorAddress: result.vendorAddress,
            vendorNIP: result.vendorNIP,
            vendorREGON: result.vendorREGON,
            amount: result.amount,
            currency: result.currency,
            dueDate: result.dueDate,
            documentNumber: result.documentNumber,
            bankAccountNumber: result.bankAccountNumber,
            suggestedAmounts: result.suggestedAmounts,
            amountCandidates: result.amountCandidates,
            dateCandidates: result.dateCandidates,
            vendorCandidates: result.vendorCandidates,
            nipCandidates: result.nipCandidates,
            bankAccountCandidates: result.bankAccountCandidates,
            documentNumberCandidates: result.documentNumberCandidates,
            vendorEvidence: result.vendorEvidence,
            amountEvidence: result.amountEvidence,
            dueDateEvidence: result.dueDateEvidence,
            documentNumberEvidence: result.documentNumberEvidence,
            nipEvidence: result.nipEvidence,
            bankAccountEvidence: result.bankAccountEvidence,
            vendorExtractionMethod: result.vendorExtractionMethod,
            amountExtractionMethod: result.amountExtractionMethod,
            dueDateExtractionMethod: result.dueDateExtractionMethod,
            nipExtractionMethod: result.nipExtractionMethod,
            overallConfidence: overallConfidence,
            fieldConfidences: FieldConfidences(
                vendorName: vendorConfidence,
                amount: amountConfidence,
                dueDate: dueDateConfidence,
                documentNumber: docNumConfidence,
                nip: result.fieldConfidences?.nip,
                bankAccount: result.fieldConfidences?.bankAccount
            ),
            provider: result.provider + "-templated",
            version: result.version,
            rawHints: result.rawHints,
            rawOCRText: result.rawOCRText
        )
    }

    // MARK: - Helper Methods

    /// Check if two bounding boxes are in approximately the same region
    private func regionsMatch(_ box1: BoundingBox?, _ box2: BoundingBox?) -> Bool {
        guard let b1 = box1, let b2 = box2 else { return false }

        // Check if centers are close (within 10% of page)
        let xDistance = abs(b1.centerX - b2.centerX)
        let yDistance = abs(b1.centerY - b2.centerY)

        return xDistance < 0.1 && yDistance < 0.1
    }

    // MARK: - Feedback Recording

    /// Record parsing feedback for analytics and learning.
    /// Privacy-first: stores only metadata, not actual values.
    func recordFeedback(
        documentId: UUID,
        vendorNIP: String?,
        analysisResult: DocumentAnalysisResult,
        corrections: [FieldCorrection]
    ) {
        let feedback = ParsingFeedback(
            documentId: documentId,
            vendorNIP: vendorNIP,
            ocrConfidence: analysisResult.overallConfidence,
            parserProvider: analysisResult.provider,
            parserVersion: analysisResult.version
        )

        // Record field-specific feedback
        for correction in corrections {
            let originalConfidence = getOriginalConfidence(
                for: correction.field,
                from: analysisResult
            )

            feedback.recordFeedback(
                for: correction.field,
                originalConfidence: originalConfidence,
                alternativeSelected: correction.alternativeIndex,
                corrected: correction.wasCorrected,
                reviewMode: correction.reviewMode,
                extractionMethod: getExtractionMethod(for: correction.field, from: analysisResult)
            )
        }

        feedback.markSaveSuccessful()

        modelContext.insert(feedback)

        do {
            try modelContext.save()
            logger.info("Feedback recorded successfully for document \(documentId)")
        } catch {
            logger.error("Failed to save feedback: \(error.localizedDescription)")
        }
    }

    private func getOriginalConfidence(for field: FieldType, from result: DocumentAnalysisResult) -> Double {
        switch field {
        case .vendor:
            return result.fieldConfidences?.vendorName ?? 0.5
        case .amount:
            return result.fieldConfidences?.amount ?? 0.5
        case .dueDate:
            return result.fieldConfidences?.dueDate ?? 0.5
        case .documentNumber:
            return result.fieldConfidences?.documentNumber ?? 0.5
        case .nip:
            return result.fieldConfidences?.nip ?? 0.5
        case .bankAccount:
            return result.fieldConfidences?.bankAccount ?? 0.5
        }
    }

    private func getExtractionMethod(for field: FieldType, from result: DocumentAnalysisResult) -> ExtractionMethod? {
        switch field {
        case .vendor:
            return result.vendorExtractionMethod
        case .amount:
            return result.amountExtractionMethod
        case .dueDate:
            return result.dueDateExtractionMethod
        case .documentNumber:
            return nil // Not tracked in result
        case .nip:
            return result.nipExtractionMethod
        case .bankAccount:
            return nil // Not tracked in result
        }
    }

    // MARK: - Template Statistics

    /// Get statistics about template usage
    func getTemplateStats() -> TemplateStats {
        do {
            let allTemplates = try modelContext.fetch(FetchDescriptor<VendorTemplate>())
            let activeTemplates = allTemplates.filter { $0.isActive }

            let totalCorrections = allTemplates.reduce(0) { $0 + $1.correctionsCount }

            // Recent usage (last 30 days)
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            let recentlyUsed = allTemplates.filter { $0.lastUsed >= thirtyDaysAgo }

            return TemplateStats(
                totalTemplates: allTemplates.count,
                activeTemplates: activeTemplates.count,
                totalCorrections: totalCorrections,
                recentlyUsedCount: recentlyUsed.count
            )
        } catch {
            logger.error("Failed to get template stats: \(error.localizedDescription)")
            return TemplateStats(
                totalTemplates: 0,
                activeTemplates: 0,
                totalCorrections: 0,
                recentlyUsedCount: 0
            )
        }
    }

    /// Get feedback statistics for a vendor
    func getFeedbackStats(for vendorNIP: String?) -> FeedbackStats {
        do {
            let predicate: Predicate<ParsingFeedback>?
            if let nip = vendorNIP {
                predicate = ParsingFeedback.byVendor(nip)
            } else {
                predicate = nil
            }

            var descriptor = FetchDescriptor<ParsingFeedback>()
            if let pred = predicate {
                descriptor.predicate = pred
            }

            let feedbacks = try modelContext.fetch(descriptor)
            return FeedbackStats(feedbacks: feedbacks)
        } catch {
            logger.error("Failed to get feedback stats: \(error.localizedDescription)")
            return FeedbackStats(feedbacks: [])
        }
    }
}

// MARK: - Supporting Types

/// Represents a single field correction for template learning
struct FieldCorrection: Sendable {
    let field: FieldType
    let correctedValue: String
    let originalValue: String?
    let evidence: BoundingBox?
    let region: DocumentRegion?
    let anchorUsed: String?
    let alternativeIndex: Int?
    let wasCorrected: Bool
    let reviewMode: ReviewMode

    init(
        field: FieldType,
        correctedValue: String,
        originalValue: String? = nil,
        evidence: BoundingBox? = nil,
        region: DocumentRegion? = nil,
        anchorUsed: String? = nil,
        alternativeIndex: Int? = nil,
        wasCorrected: Bool = true,
        reviewMode: ReviewMode = .suggested
    ) {
        self.field = field
        self.correctedValue = correctedValue
        self.originalValue = originalValue
        self.evidence = evidence
        self.region = region
        self.anchorUsed = anchorUsed
        self.alternativeIndex = alternativeIndex
        self.wasCorrected = wasCorrected
        self.reviewMode = reviewMode
    }
}

/// Statistics about vendor template usage
struct TemplateStats: Sendable {
    let totalTemplates: Int
    let activeTemplates: Int
    let totalCorrections: Int
    let recentlyUsedCount: Int

    var activationRate: Double {
        guard totalTemplates > 0 else { return 0.0 }
        return Double(activeTemplates) / Double(totalTemplates)
    }
}
