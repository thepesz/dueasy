import Foundation
import SwiftData

/// Learning data captured from user corrections.
/// Stored WITHOUT full invoice text for privacy.
/// Used to improve parsing accuracy over time.
@Model
final class LearningData {
    /// Unique identifier
    @Attribute(.unique)
    var id: UUID

    /// When this learning data was captured
    var timestamp: Date

    /// Document type (invoice, contract, receipt)
    var documentType: String

    // PRIVACY: NO vendor names, amounts, or dates stored!
    // We only store metrics and boolean flags for learning

    /// Top 3 amount candidates - PRIVACY SAFE (NO lineText, NO values!)
    /// Format: [{currencyHint, confidence, keywordsMatched, candidateRank}]
    var topAmountCandidatesJSON: Data?

    /// Top 3 date candidates - PRIVACY SAFE (NO lineText!)
    /// Format: [{score, scoreReason, keywordsMatched, candidateRank}]
    var topDateCandidatesJSON: Data?

    /// Top 3 vendor candidates - PRIVACY SAFE (NO name, NO lineText!)
    /// Format: [{matchedPattern, confidence, candidateRank, nameLength}]
    var topVendorCandidatesJSON: Data?

    /// Keywords that successfully matched for amount (array of strings)
    var amountKeywordsHit: [String]

    /// Keywords that successfully matched for due date (array of strings)
    var dueDateKeywordsHit: [String]

    /// Whether user corrected the amount (indicates initial detection failed)
    var amountCorrected: Bool

    /// Whether user corrected the due date
    var dueDateCorrected: Bool

    /// Whether user corrected the vendor
    var vendorCorrected: Bool

    /// Overall OCR confidence (0.0-1.0)
    var ocrConfidence: Double

    /// Analysis version that produced this data
    var analysisVersion: Int

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        documentType: String,
        topAmountCandidatesJSON: Data? = nil,
        topDateCandidatesJSON: Data? = nil,
        topVendorCandidatesJSON: Data? = nil,
        amountKeywordsHit: [String] = [],
        dueDateKeywordsHit: [String] = [],
        amountCorrected: Bool = false,
        dueDateCorrected: Bool = false,
        vendorCorrected: Bool = false,
        ocrConfidence: Double = 0.0,
        analysisVersion: Int = 1
    ) {
        self.id = id
        self.timestamp = timestamp
        self.documentType = documentType
        self.topAmountCandidatesJSON = topAmountCandidatesJSON
        self.topDateCandidatesJSON = topDateCandidatesJSON
        self.topVendorCandidatesJSON = topVendorCandidatesJSON
        self.amountKeywordsHit = amountKeywordsHit
        self.dueDateKeywordsHit = dueDateKeywordsHit
        self.amountCorrected = amountCorrected
        self.dueDateCorrected = dueDateCorrected
        self.vendorCorrected = vendorCorrected
        self.ocrConfidence = ocrConfidence
        self.analysisVersion = analysisVersion
    }
}

// MARK: - Helper Models for JSON Encoding

/// PRIVACY-SAFE: Amount candidate for learning storage
/// NO lineText, NO nearbyKeywords - only metrics!
struct LearningAmountCandidate: Codable {
    let currencyHint: String?
    let confidence: Double
    let keywordsMatched: [String]  // Just keywords, no surrounding text
    let candidateRank: Int  // Position in candidate list (1st, 2nd, 3rd)
}

/// PRIVACY-SAFE: Date candidate for learning storage
/// NO lineText, NO nearbyKeywords - only metrics!
struct LearningDateCandidate: Codable {
    let score: Int
    let scoreReason: String  // Pattern type, not actual text
    let keywordsMatched: [String]  // Just keywords, no surrounding text
    let candidateRank: Int
}

/// PRIVACY-SAFE: Vendor candidate for learning storage
/// NO name, NO lineText - only pattern info!
struct LearningVendorCandidate: Codable {
    let matchedPattern: String  // Pattern type (e.g., "Sprzedawca label")
    let confidence: Double
    let candidateRank: Int
    let nameLength: Int  // For correlation, but not actual name
}
