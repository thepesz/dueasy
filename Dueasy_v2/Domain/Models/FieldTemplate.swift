import Foundation

// NOTE: DocumentRegion is defined in Domain/Models/KeywordModels.swift
// with 9 regions for the 3x3 grid layout analysis.

/// Field template capturing learned extraction patterns for a specific field.
/// Stored as JSON within VendorTemplate.
struct FieldTemplate: Sendable, Equatable {
    /// Preferred document region where this field typically appears
    let preferredRegion: DocumentRegion?

    /// Anchor phrase found near the field value (e.g., "Sprzedawca", "Do zaplaty")
    let anchorPhrase: String?

    /// Bounding box region (normalized coordinates) for UI highlighting
    let regionHint: BoundingBox?

    /// Confidence boost to apply when extraction matches this template (+0.1 to +0.2)
    let confidenceBoost: Double

    init(
        preferredRegion: DocumentRegion? = nil,
        anchorPhrase: String? = nil,
        regionHint: BoundingBox? = nil,
        confidenceBoost: Double = 0.1
    ) {
        self.preferredRegion = preferredRegion
        self.anchorPhrase = anchorPhrase
        self.regionHint = regionHint
        self.confidenceBoost = confidenceBoost
    }
}

// MARK: - Codable conformance with nonisolated init

extension FieldTemplate: Codable {
    // Explicit nonisolated Codable conformance to avoid Swift 6 strict concurrency warnings
    // when decoding from @Model class computed properties.

    private enum CodingKeys: String, CodingKey {
        case preferredRegion
        case anchorPhrase
        case regionHint
        case confidenceBoost
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.preferredRegion = try container.decodeIfPresent(DocumentRegion.self, forKey: .preferredRegion)
        self.anchorPhrase = try container.decodeIfPresent(String.self, forKey: .anchorPhrase)
        self.regionHint = try container.decodeIfPresent(BoundingBox.self, forKey: .regionHint)
        self.confidenceBoost = try container.decode(Double.self, forKey: .confidenceBoost)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(preferredRegion, forKey: .preferredRegion)
        try container.encodeIfPresent(anchorPhrase, forKey: .anchorPhrase)
        try container.encodeIfPresent(regionHint, forKey: .regionHint)
        try container.encode(confidenceBoost, forKey: .confidenceBoost)
    }
}
