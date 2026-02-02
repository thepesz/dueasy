import Foundation

/// Review mode for a field based on confidence level.
/// Determines UI treatment and user interaction requirements.
enum ReviewMode: String, Codable, Sendable {
    /// High confidence - auto-filled with minimal UI
    case autoFilled = "autoFilled"

    /// Medium confidence - pre-filled but review suggested
    case suggested = "suggested"

    /// Low confidence - must review, cannot skip
    case required = "required"

    /// Human-readable description
    var description: String {
        switch self {
        case .autoFilled:
            return "Auto-filled (high confidence)"
        case .suggested:
            return "Review suggested"
        case .required:
            return "Review required"
        }
    }
}

/// Feedback for a single field extraction.
/// Privacy-first: stores only metadata, not actual values.
struct FieldFeedback: Sendable, Equatable {

    /// Original confidence score from extraction (0.0-1.0)
    let originalConfidence: Double

    /// Index of the alternative selected by user, or nil if kept original
    /// -1 means user manually entered a value not in alternatives
    let alternativeSelected: Int?

    /// Whether user made any correction to this field
    let correctionMade: Bool

    /// Review mode that was applied to this field
    let reviewMode: ReviewMode

    /// Extraction method used for original value
    let extractionMethod: ExtractionMethod?

    /// Whether field was ultimately accepted (used for accuracy metrics)
    let wasAccepted: Bool

    init(
        originalConfidence: Double,
        alternativeSelected: Int? = nil,
        correctionMade: Bool,
        reviewMode: ReviewMode,
        extractionMethod: ExtractionMethod? = nil,
        wasAccepted: Bool = true
    ) {
        self.originalConfidence = originalConfidence
        self.alternativeSelected = alternativeSelected
        self.correctionMade = correctionMade
        self.reviewMode = reviewMode
        self.extractionMethod = extractionMethod
        self.wasAccepted = wasAccepted
    }
}

// MARK: - Codable conformance with nonisolated init

extension FieldFeedback: Codable {
    // Explicit nonisolated Codable conformance to avoid Swift 6 strict concurrency warnings
    // when decoding from @Model class computed properties.

    private enum CodingKeys: String, CodingKey {
        case originalConfidence
        case alternativeSelected
        case correctionMade
        case reviewMode
        case extractionMethod
        case wasAccepted
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.originalConfidence = try container.decode(Double.self, forKey: .originalConfidence)
        self.alternativeSelected = try container.decodeIfPresent(Int.self, forKey: .alternativeSelected)
        self.correctionMade = try container.decode(Bool.self, forKey: .correctionMade)
        self.reviewMode = try container.decode(ReviewMode.self, forKey: .reviewMode)
        self.extractionMethod = try container.decodeIfPresent(ExtractionMethod.self, forKey: .extractionMethod)
        self.wasAccepted = try container.decode(Bool.self, forKey: .wasAccepted)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalConfidence, forKey: .originalConfidence)
        try container.encodeIfPresent(alternativeSelected, forKey: .alternativeSelected)
        try container.encode(correctionMade, forKey: .correctionMade)
        try container.encode(reviewMode, forKey: .reviewMode)
        try container.encodeIfPresent(extractionMethod, forKey: .extractionMethod)
        try container.encode(wasAccepted, forKey: .wasAccepted)
    }
}
