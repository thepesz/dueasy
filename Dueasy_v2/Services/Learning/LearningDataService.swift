import Foundation
import SwiftData
import os.log

/// Service for persisting and querying learning data from user corrections.
/// Stores structured feedback WITHOUT full invoice text for privacy.
@MainActor
final class LearningDataService {

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.dueasy.app", category: "LearningData")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Save Learning Data

    /// Save learning data from user corrections
    /// PRIVACY-SAFE: NO vendor names, amounts, or dates are saved!
    /// Only metrics and boolean correction flags.
    func saveLearningData(
        documentType: DocumentType,
        wasAmountCorrected: Bool,
        wasDueDateCorrected: Bool,
        wasVendorCorrected: Bool,
        amountCandidates: [AmountCandidate],
        dateCandidates: [DateCandidate],
        vendorCandidates: [VendorCandidate],
        amountKeywords: [String],
        dateKeywords: [String],
        ocrConfidence: Double
    ) async throws {

        // PRIVACY: Only store boolean correction flags, not actual values!

        // PRIVACY-SAFE: Take top 3 candidates but strip all sensitive data
        // NO lineText, NO values, NO names - only metrics and pattern info!
        let topAmountCandidates = Array(amountCandidates.prefix(3)).enumerated().map { (index, candidate) in
            LearningAmountCandidate(
                currencyHint: candidate.currencyHint,
                confidence: candidate.confidence,
                keywordsMatched: candidate.nearbyKeywords,  // Just keywords, not surrounding text
                candidateRank: index + 1
            )
        }

        let topDateCandidates = Array(dateCandidates.prefix(3)).enumerated().map { (index, candidate) in
            LearningDateCandidate(
                score: candidate.score,
                scoreReason: candidate.scoreReason,  // Pattern type, not actual text
                keywordsMatched: candidate.nearbyKeywords,  // Just keywords, not surrounding text
                candidateRank: index + 1
            )
        }

        let topVendorCandidates = Array(vendorCandidates.prefix(3)).enumerated().map { (index, candidate) in
            LearningVendorCandidate(
                matchedPattern: candidate.matchedPattern,
                confidence: candidate.confidence,
                candidateRank: index + 1,
                nameLength: candidate.name.count  // Length for correlation, not actual name
            )
        }

        // Encode to JSON
        let encoder = JSONEncoder()
        let topAmountJSON = try? encoder.encode(topAmountCandidates)
        let topDateJSON = try? encoder.encode(topDateCandidates)
        let topVendorJSON = try? encoder.encode(topVendorCandidates)

        // PRIVACY-SAFE: Create learning data entry with NO sensitive data
        let learningData = LearningData(
            timestamp: Date(),
            documentType: documentType.rawValue,
            topAmountCandidatesJSON: topAmountJSON,
            topDateCandidatesJSON: topDateJSON,
            topVendorCandidatesJSON: topVendorJSON,
            amountKeywordsHit: amountKeywords,
            dueDateKeywordsHit: dateKeywords,
            amountCorrected: wasAmountCorrected,
            dueDateCorrected: wasDueDateCorrected,
            vendorCorrected: wasVendorCorrected,
            ocrConfidence: ocrConfidence,
            analysisVersion: 2  // v2 = privacy-safe, no PII
        )

        modelContext.insert(learningData)
        try modelContext.save()

        // PRIVACY: Only log boolean flags, no sensitive data
        logger.info("Saved learning data: amountCorrected=\(wasAmountCorrected), dueDateCorrected=\(wasDueDateCorrected), vendorCorrected=\(wasVendorCorrected)")
    }

    // MARK: - Query Learning Data

    /// Get recent learning data for analysis
    func getRecentLearningData(limit: Int = 100) async throws -> [LearningData] {
        let descriptor = FetchDescriptor<LearningData>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let allData = try modelContext.fetch(descriptor)
        return Array(allData.prefix(limit))
    }

    /// Get learning data where amount was corrected (indicates detection failure)
    func getAmountCorrectionData(limit: Int = 50) async throws -> [LearningData] {
        let descriptor = FetchDescriptor<LearningData>(
            predicate: #Predicate { $0.amountCorrected == true },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let allData = try modelContext.fetch(descriptor)
        return Array(allData.prefix(limit))
    }

    /// Get learning data where due date was corrected
    func getDueDateCorrectionData(limit: Int = 50) async throws -> [LearningData] {
        let descriptor = FetchDescriptor<LearningData>(
            predicate: #Predicate { $0.dueDateCorrected == true },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let allData = try modelContext.fetch(descriptor)
        return Array(allData.prefix(limit))
    }

    /// Get success rate metrics for monitoring
    func getSuccessMetrics() async throws -> LearningMetrics {
        let allData = try await getRecentLearningData(limit: 1000)

        let totalCount = allData.count
        guard totalCount > 0 else {
            return LearningMetrics(
                totalSamples: 0,
                amountSuccessRate: 0,
                dueDateSuccessRate: 0,
                vendorSuccessRate: 0,
                averageOCRConfidence: 0
            )
        }

        let amountSuccesses = allData.filter { !$0.amountCorrected }.count
        let dueDateSuccesses = allData.filter { !$0.dueDateCorrected }.count
        let vendorSuccesses = allData.filter { !$0.vendorCorrected }.count

        let avgOCRConfidence = allData.map { $0.ocrConfidence }.reduce(0, +) / Double(totalCount)

        return LearningMetrics(
            totalSamples: totalCount,
            amountSuccessRate: Double(amountSuccesses) / Double(totalCount),
            dueDateSuccessRate: Double(dueDateSuccesses) / Double(totalCount),
            vendorSuccessRate: Double(vendorSuccesses) / Double(totalCount),
            averageOCRConfidence: avgOCRConfidence
        )
    }

    // MARK: - Cleanup

    /// Delete old learning data (keep last N entries for privacy)
    func pruneOldData(keepLast: Int = 1000) async throws {
        let descriptor = FetchDescriptor<LearningData>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let allData = try modelContext.fetch(descriptor)

        // Delete everything beyond keepLast
        if allData.count > keepLast {
            let toDelete = allData.suffix(from: keepLast)
            for data in toDelete {
                modelContext.delete(data)
            }
            try modelContext.save()
            logger.info("Pruned \(toDelete.count) old learning data entries")
        }
    }
}

// MARK: - Metrics

struct LearningMetrics {
    let totalSamples: Int
    let amountSuccessRate: Double  // 0.0-1.0
    let dueDateSuccessRate: Double
    let vendorSuccessRate: Double
    let averageOCRConfidence: Double
}
