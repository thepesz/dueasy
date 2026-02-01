import Foundation
import os

/// Source of the OCR line data - which pass detected this line
enum OCRPassSource: String, Codable, Sendable {
    case standard = "standard"    // Pass 1: Standard recognition (minTextHeight 0.012)
    case sensitive = "sensitive"  // Pass 2: Sensitive/fine text (minTextHeight 0.007)
    case merged = "merged"        // Result of merging both passes
}

/// Structured OCR data for a single recognized line of text.
///
/// PRIVACY: This struct is intentionally NOT Codable to prevent accidental
/// serialization of raw OCR text (which may contain PII like names, addresses,
/// amounts, etc.). The text content should only exist in memory during processing.
///
/// For persistence, use `OCRResultMetadata` which contains only metrics.
struct OCRLineData: Sendable, Equatable {
    /// The recognized text content for this line
    /// PRIVACY: Contains raw document text - do not serialize or log
    let text: String

    /// Page index for multi-page documents (0-based)
    let pageIndex: Int

    /// Bounding box in normalized coordinates (0.0-1.0)
    let bbox: BoundingBox

    /// OCR confidence score (0.0-1.0)
    let confidence: Double

    /// Tokenized words (lowercased, normalized for matching)
    /// PRIVACY: Contains raw document text - do not serialize or log
    let tokens: [String]

    /// Which OCR pass detected this line
    let source: OCRPassSource

    init(text: String, pageIndex: Int, bbox: BoundingBox, confidence: Double, source: OCRPassSource = .standard) {
        self.text = text
        self.pageIndex = pageIndex
        self.bbox = bbox
        self.confidence = confidence
        self.tokens = Self.tokenize(text)
        self.source = source
    }

    /// Tokenize text into normalized words for keyword matching
    private static func tokenize(_ text: String) -> [String] {
        return text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current) // Remove Polish diacritics
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    /// Check if this line has high confidence (>0.9)
    var hasHighConfidence: Bool {
        confidence > 0.9
    }

    /// Check if this line has medium confidence (0.7-0.9)
    var hasMediumConfidence: Bool {
        confidence >= 0.7 && confidence <= 0.9
    }

    /// Check if this line has low confidence (<0.7)
    var hasLowConfidence: Bool {
        confidence < 0.7
    }

    /// Check if this line overlaps with another line (for deduplication)
    /// Uses 80% overlap threshold by default
    func overlaps(with other: OCRLineData, threshold: Double = 0.8) -> Bool {
        // Must be on same page
        guard pageIndex == other.pageIndex else { return false }
        return bbox.overlaps(with: other.bbox, threshold: threshold)
    }

    /// Calculate text similarity with another line (normalized Levenshtein distance)
    /// Returns 1.0 for identical text, 0.0 for completely different
    func textSimilarity(with other: OCRLineData) -> Double {
        let s1 = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let s2 = other.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if s1 == s2 { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }

        // Use simple containment check for efficiency
        if s1.contains(s2) || s2.contains(s1) {
            let minLen = min(s1.count, s2.count)
            let maxLen = max(s1.count, s2.count)
            return Double(minLen) / Double(maxLen)
        }

        // Calculate Jaccard similarity on tokens for quick approximation
        let tokens1 = Set(tokens)
        let tokens2 = Set(other.tokens)
        let intersection = tokens1.intersection(tokens2)
        let union = tokens1.union(tokens2)

        guard !union.isEmpty else { return 0.0 }
        return Double(intersection.count) / Double(union.count)
    }

    /// Check if this line is a duplicate of another (overlapping bbox + similar text)
    func isDuplicate(of other: OCRLineData, bboxThreshold: Double = 0.8, textThreshold: Double = 0.6) -> Bool {
        guard overlaps(with: other, threshold: bboxThreshold) else { return false }
        return textSimilarity(with: other) >= textThreshold
    }

    // Equatable conformance
    static func == (lhs: OCRLineData, rhs: OCRLineData) -> Bool {
        return lhs.text == rhs.text &&
               lhs.pageIndex == rhs.pageIndex &&
               lhs.bbox == rhs.bbox &&
               lhs.confidence == rhs.confidence &&
               lhs.tokens == rhs.tokens &&
               lhs.source == rhs.source
    }
}

// MARK: - OCR Result Metadata (Codable, Safe for Storage)

/// Metadata-only summary of OCR results.
/// PRIVACY: Contains only metrics - safe to serialize and log.
/// Use this instead of full OCRResult/OCRLineData when persistence is needed.
struct OCRResultMetadata: Codable, Sendable, Equatable {
    /// Number of lines detected
    let lineCount: Int

    /// Average confidence across all lines (0.0-1.0)
    let averageConfidence: Double

    /// Number of pages processed
    let pageCount: Int

    /// Distribution of lines by OCR pass source
    let sourceDistribution: SourceDistribution

    /// Confidence distribution metrics
    let confidenceDistribution: ConfidenceDistribution

    /// Timestamp when OCR was performed
    let timestamp: Date

    /// Duration of OCR processing in seconds
    let processingDuration: TimeInterval?

    /// Creates metadata from an array of OCRLineData
    /// - Parameters:
    ///   - lineData: Array of OCR line data
    ///   - processingDuration: Optional processing duration
    init(from lineData: [OCRLineData], processingDuration: TimeInterval? = nil) {
        self.lineCount = lineData.count
        self.pageCount = Set(lineData.map(\.pageIndex)).count

        let confidences = lineData.map(\.confidence)
        self.averageConfidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Double(confidences.count)

        self.sourceDistribution = SourceDistribution(
            standard: lineData.filter { $0.source == .standard }.count,
            sensitive: lineData.filter { $0.source == .sensitive }.count,
            merged: lineData.filter { $0.source == .merged }.count
        )

        self.confidenceDistribution = ConfidenceDistribution(
            high: lineData.filter { $0.hasHighConfidence }.count,
            medium: lineData.filter { $0.hasMediumConfidence }.count,
            low: lineData.filter { $0.hasLowConfidence }.count
        )

        self.timestamp = Date()
        self.processingDuration = processingDuration
    }

    /// Distribution of lines by OCR pass source
    struct SourceDistribution: Codable, Sendable, Equatable {
        let standard: Int
        let sensitive: Int
        let merged: Int
    }

    /// Distribution of lines by confidence level
    struct ConfidenceDistribution: Codable, Sendable, Equatable {
        let high: Int   // > 0.9
        let medium: Int // 0.7 - 0.9
        let low: Int    // < 0.7
    }
}

// MARK: - OCR Cache

/// In-memory cache for temporary OCR results.
/// PRIVACY: OCR results are stored only in memory and automatically expire.
/// This prevents raw text from being persisted to disk.
actor OCRCache {
    /// Cache entry with expiration
    private struct CacheEntry {
        let result: OCRResult
        let expiresAt: Date
    }

    /// Singleton instance
    static let shared = OCRCache()

    /// Cache storage
    private var cache: [UUID: CacheEntry] = [:]

    /// Default expiration time (1 hour)
    private let defaultExpiration: TimeInterval = 3600

    private init() {}

    /// Stores an OCR result in the cache
    /// - Parameters:
    ///   - result: OCR result to cache
    ///   - documentId: Document identifier
    ///   - expiration: Optional custom expiration time
    func store(_ result: OCRResult, for documentId: UUID, expiration: TimeInterval? = nil) {
        let actualExpiration = expiration ?? self.defaultExpiration
        let expiresAt = Date().addingTimeInterval(actualExpiration)
        cache[documentId] = CacheEntry(result: result, expiresAt: expiresAt)
        PrivacyLogger.storage.debug("OCR result cached for document (expires in \(String(format: "%.0f", actualExpiration))s)")

        // Schedule cleanup
        Task { [weak self] in
            await self?.cleanupExpired()
        }
    }

    /// Retrieves an OCR result from the cache
    /// - Parameter documentId: Document identifier
    /// - Returns: Cached OCR result if available and not expired
    func retrieve(for documentId: UUID) -> OCRResult? {
        guard let entry = cache[documentId] else { return nil }

        // Check expiration
        if Date() > entry.expiresAt {
            cache.removeValue(forKey: documentId)
            return nil
        }

        return entry.result
    }

    /// Removes a specific entry from the cache
    /// - Parameter documentId: Document identifier
    func remove(for documentId: UUID) {
        cache.removeValue(forKey: documentId)
    }

    /// Clears all cached OCR results
    func clear() {
        cache.removeAll()
        PrivacyLogger.storage.debug("OCR cache cleared")
    }

    /// Removes expired entries from the cache
    private func cleanupExpired() {
        let now = Date()
        let expiredKeys = cache.filter { $0.value.expiresAt < now }.map(\.key)

        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            PrivacyLogger.storage.debug("Cleaned up \(expiredKeys.count) expired OCR cache entries")
        }
    }
}

// MARK: - OCRResult Extension

/// OCR result structure (used by AppleVisionOCRService)
/// Note: This is defined in OCRServiceProtocol.swift but we add metadata helper here
extension OCRResult {
    /// Creates metadata summary from this OCR result
    /// PRIVACY: Use this when you need to persist or log OCR information
    func metadata(processingDuration: TimeInterval? = nil) -> OCRResultMetadata {
        OCRResultMetadata(from: lineData ?? [], processingDuration: processingDuration)
    }
}
