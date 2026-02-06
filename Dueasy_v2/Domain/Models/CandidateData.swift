import Foundation

// MARK: - Extraction Method

/// Method used to extract a field value.
/// Tracks how a value was found for debugging and learning.
enum ExtractionMethod: String, Codable, Sendable {
    /// Extracted using anchor detection (label found nearby)
    case anchorBased = "anchor"

    /// Extracted using document region heuristics
    case regionHeuristic = "region"

    /// Extracted using pattern matching on full text
    case patternMatching = "pattern"

    /// Fallback extraction when other methods fail
    case fallback = "fallback"

    /// Extracted using cloud AI (OpenAI Vision, etc.)
    /// Iteration 2: Used for cloud-based extraction results
    case cloudAI = "cloud_ai"

    /// Extracted using vendor template from previous documents
    case vendorTemplate = "vendor_template"

    /// Human-readable description
    var description: String {
        switch self {
        case .anchorBased: return "Anchor-based (label detected)"
        case .regionHeuristic: return "Region heuristic"
        case .patternMatching: return "Pattern matching"
        case .fallback: return "Fallback"
        case .cloudAI: return "Cloud AI"
        case .vendorTemplate: return "Vendor template"
        }
    }

    /// Whether this method uses cloud resources
    var isCloudBased: Bool {
        self == .cloudAI
    }
}

// MARK: - Extraction Candidate

/// A generic extraction candidate with value, confidence, and provenance.
/// Used as the standardized output format for layout-first extraction.
struct ExtractionCandidate: Codable, Sendable, Identifiable {
    /// Stable identity for SwiftUI ForEach. Composite of value + source + confidence + bbox
    /// to guarantee uniqueness even when multiple strategies find the same value.
    var id: String {
        let bboxKey = String(format: "%.3f,%.3f", bbox.x, bbox.y)
        return "\(value)|\(source)|\(String(format: "%.4f", confidence))|\(bboxKey)"
    }

    /// The extracted value as a string
    let value: String

    /// Confidence score for this candidate (0.0-1.0)
    let confidence: Double

    /// Bounding box of the source text
    let bbox: BoundingBox

    /// How this value was extracted
    let method: ExtractionMethod

    /// Source description for debugging (e.g., "anchor: Sprzedawca", "region: topLeft")
    let source: String

    /// The anchor type that was used (if anchor-based)
    let anchorType: String?

    /// The document region (if region-based)
    let region: String?

    /// Additional extracted data (e.g., address from vendor block)
    let additionalData: [String: String]?

    init(
        value: String,
        confidence: Double,
        bbox: BoundingBox,
        method: ExtractionMethod,
        source: String,
        anchorType: String? = nil,
        region: String? = nil,
        additionalData: [String: String]? = nil
    ) {
        self.value = value
        self.confidence = confidence
        self.bbox = bbox
        self.method = method
        self.source = source
        self.anchorType = anchorType
        self.region = region
        self.additionalData = additionalData
    }
}

// MARK: - Field Extraction Result

/// Result of extracting a single field with the best value and alternatives.
struct FieldExtraction: Sendable {
    /// The best extracted value (highest confidence)
    let bestValue: String?

    /// Up to 3 alternative candidates for user selection
    let candidates: [ExtractionCandidate]

    /// Confidence of the best value (0.0-1.0)
    let confidence: Double

    /// Bounding box of the best value for UI highlighting
    let evidence: BoundingBox?

    /// Method used to extract the best value
    let method: ExtractionMethod

    /// Whether extraction was successful
    var hasValue: Bool {
        bestValue != nil && !bestValue!.isEmpty
    }

    /// Create an empty/failed extraction result
    static let empty = FieldExtraction(
        bestValue: nil,
        candidates: [],
        confidence: 0.0,
        evidence: nil,
        method: .fallback
    )

    init(
        bestValue: String?,
        candidates: [ExtractionCandidate],
        confidence: Double,
        evidence: BoundingBox?,
        method: ExtractionMethod
    ) {
        self.bestValue = bestValue
        self.candidates = candidates
        self.confidence = confidence
        self.evidence = evidence
        self.method = method
    }

    /// Create from a single candidate
    init(candidate: ExtractionCandidate) {
        self.bestValue = candidate.value
        self.candidates = [candidate]
        self.confidence = candidate.confidence
        self.evidence = candidate.bbox
        self.method = candidate.method
    }

    /// Create from multiple candidates (picks best)
    init(candidates: [ExtractionCandidate]) {
        let sorted = candidates.sorted { $0.confidence > $1.confidence }
        let best = sorted.first

        self.bestValue = best?.value
        self.candidates = Array(sorted.prefix(3)) // Keep top 3
        self.confidence = best?.confidence ?? 0.0
        self.evidence = best?.bbox
        self.method = best?.method ?? .fallback
    }
}

// MARK: - Amount Candidate

/// Amount candidate detected during parsing, with context for learning
struct AmountCandidate: Codable, Sendable {
    /// The detected amount value
    let value: Decimal

    /// Currency hint from nearby text
    let currencyHint: String?

    /// The line of text where this amount was found
    let lineText: String

    /// Bounding box of the line containing this amount
    let lineBBox: BoundingBox

    /// Keywords found in nearby lines (1-2 lines before/after)
    let nearbyKeywords: [String]

    /// Pattern that matched this amount (for debugging/learning)
    let matchedPattern: String

    /// Confidence score for this candidate (0.0-1.0)
    let confidence: Double

    /// Context text (surrounding lines for learning)
    let context: String

    /// Extraction method used to find this amount
    let extractionMethod: ExtractionMethod?

    /// Source description for debugging
    let extractionSource: String?

    init(
        value: Decimal,
        currencyHint: String?,
        lineText: String,
        lineBBox: BoundingBox,
        nearbyKeywords: [String],
        matchedPattern: String,
        confidence: Double,
        context: String,
        extractionMethod: ExtractionMethod? = nil,
        extractionSource: String? = nil
    ) {
        self.value = value
        self.currencyHint = currencyHint
        self.lineText = lineText
        self.lineBBox = lineBBox
        self.nearbyKeywords = nearbyKeywords
        self.matchedPattern = matchedPattern
        self.confidence = confidence
        self.context = context
        self.extractionMethod = extractionMethod
        self.extractionSource = extractionSource
    }
}

// MARK: - Date Candidate

/// Date candidate detected during parsing, with context for learning
struct DateCandidate: Codable, Sendable, Identifiable {
    /// Stable identity for SwiftUI ForEach. Composite of date + score + source + bbox
    /// to guarantee uniqueness even when multiple strategies find the same date.
    var id: String {
        let timestamp = String(format: "%.0f", date.timeIntervalSinceReferenceDate)
        let bboxKey = String(format: "%.3f,%.3f", lineBBox.x, lineBBox.y)
        return "\(timestamp)|\(scoreReason)|\(score)|\(bboxKey)"
    }

    /// The detected date value
    let date: Date

    /// The line of text where this date was found
    let lineText: String

    /// Bounding box of the line containing this date
    let lineBBox: BoundingBox

    /// Keywords found in nearby lines (1-2 lines before/after)
    let nearbyKeywords: [String]

    /// Pattern that matched this date (for debugging/learning)
    let matchedPattern: String

    /// Score assigned to this date (higher = more likely to be due date)
    let score: Int

    /// Reason for the score (for debugging/learning)
    let scoreReason: String

    /// Context text (surrounding lines for learning)
    let context: String

    /// Extraction method used to find this date
    let extractionMethod: ExtractionMethod?

    /// Source description for debugging
    let extractionSource: String?

    init(
        date: Date,
        lineText: String,
        lineBBox: BoundingBox,
        nearbyKeywords: [String],
        matchedPattern: String,
        score: Int,
        scoreReason: String,
        context: String,
        extractionMethod: ExtractionMethod? = nil,
        extractionSource: String? = nil
    ) {
        self.date = date
        self.lineText = lineText
        self.lineBBox = lineBBox
        self.nearbyKeywords = nearbyKeywords
        self.matchedPattern = matchedPattern
        self.score = score
        self.scoreReason = scoreReason
        self.context = context
        self.extractionMethod = extractionMethod
        self.extractionSource = extractionSource
    }
}

// MARK: - Vendor Candidate

/// Vendor candidate detected during parsing
struct VendorCandidate: Codable, Sendable {
    /// The detected vendor name
    let name: String

    /// The line of text where this vendor was found
    let lineText: String

    /// Bounding box of the line containing this vendor
    let lineBBox: BoundingBox

    /// Pattern that matched this vendor (for debugging/learning)
    let matchedPattern: String

    /// Confidence score for this candidate (0.0-1.0)
    let confidence: Double

    /// Extraction method used to find this vendor
    let extractionMethod: ExtractionMethod?

    /// Source description for debugging
    let extractionSource: String?

    init(
        name: String,
        lineText: String,
        lineBBox: BoundingBox,
        matchedPattern: String,
        confidence: Double,
        extractionMethod: ExtractionMethod? = nil,
        extractionSource: String? = nil
    ) {
        self.name = name
        self.lineText = lineText
        self.lineBBox = lineBBox
        self.matchedPattern = matchedPattern
        self.confidence = confidence
        self.extractionMethod = extractionMethod
        self.extractionSource = extractionSource
    }
}

// MARK: - NIP Candidate

/// NIP (Polish Tax ID) candidate detected during parsing
struct NIPCandidate: Codable, Sendable {
    /// The detected NIP value (10 digits)
    let value: String

    /// The line of text where this NIP was found
    let lineText: String

    /// Bounding box of the line containing this NIP
    let lineBBox: BoundingBox

    /// Whether this is the vendor NIP (vs buyer NIP)
    let isVendorNIP: Bool

    /// Confidence score for this candidate (0.0-1.0)
    let confidence: Double

    /// Extraction method used
    let extractionMethod: ExtractionMethod

    /// Source description for debugging
    let extractionSource: String
}

// MARK: - Bank Account Candidate

/// Bank account candidate detected during parsing
struct BankAccountCandidate: Codable, Sendable {
    /// The detected account number (IBAN or Polish format)
    let value: String

    /// The line of text where this account was found
    let lineText: String

    /// Bounding box of the line containing this account
    let lineBBox: BoundingBox

    /// Whether this appears to be an IBAN
    let isIBAN: Bool

    /// Confidence score for this candidate (0.0-1.0)
    let confidence: Double

    /// Extraction method used
    let extractionMethod: ExtractionMethod

    /// Source description for debugging
    let extractionSource: String
}
