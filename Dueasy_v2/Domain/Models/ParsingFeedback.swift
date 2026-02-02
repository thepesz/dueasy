import Foundation
import SwiftData

// Note: FieldFeedback and ReviewMode are defined in FieldFeedback.swift
// to avoid Swift 6 strict concurrency warnings with @Model classes.

/// Privacy-first parsing feedback record.
/// Stores only metadata about corrections, NOT actual field values.
/// Used for:
/// - Parser accuracy metrics
/// - Template learning signals
/// - UX optimization
@Model
final class ParsingFeedback {

    // MARK: - Identifiers

    /// Unique identifier for this feedback record
    var id: UUID = UUID()

    /// Associated document ID
    var documentId: UUID

    /// Vendor NIP (for vendor-specific learning)
    /// Optional because user might not have vendor identified
    var vendorNIP: String?

    /// Timestamp when feedback was recorded
    var timestamp: Date

    // MARK: - Field Feedback (stored as JSON)

    /// Feedback for vendor name field
    var vendorNameFeedbackData: Data?

    /// Feedback for amount field
    var amountFeedbackData: Data?

    /// Feedback for due date field
    var dueDateFeedbackData: Data?

    /// Feedback for NIP field
    var nipFeedbackData: Data?

    /// Feedback for document number field
    var documentNumberFeedbackData: Data?

    /// Feedback for bank account field
    var bankAccountFeedbackData: Data?

    // MARK: - Session Metadata

    /// Overall OCR confidence for the document
    var ocrConfidence: Double

    /// Time spent on review screen (seconds)
    var reviewDuration: TimeInterval?

    /// Number of alternative suggestions shown to user
    var alternativesShown: Int

    /// Number of alternatives selected by user
    var alternativesSelected: Int

    /// Whether document was saved successfully
    var saveSuccessful: Bool

    /// Provider identifier (e.g., "local-layout")
    var parserProvider: String

    /// Parser version for tracking improvements
    var parserVersion: Int

    // MARK: - Computed Properties

    /// Vendor name feedback (decoded)
    var vendorNameFeedback: FieldFeedback? {
        get {
            guard let data = vendorNameFeedbackData else { return nil }
            return Self.decodeFieldFeedback(from: data)
        }
        set {
            vendorNameFeedbackData = Self.encodeFieldFeedback(newValue)
        }
    }

    /// Amount feedback (decoded)
    var amountFeedback: FieldFeedback? {
        get {
            guard let data = amountFeedbackData else { return nil }
            return Self.decodeFieldFeedback(from: data)
        }
        set {
            amountFeedbackData = Self.encodeFieldFeedback(newValue)
        }
    }

    /// Due date feedback (decoded)
    var dueDateFeedback: FieldFeedback? {
        get {
            guard let data = dueDateFeedbackData else { return nil }
            return Self.decodeFieldFeedback(from: data)
        }
        set {
            dueDateFeedbackData = Self.encodeFieldFeedback(newValue)
        }
    }

    /// NIP feedback (decoded)
    var nipFeedback: FieldFeedback? {
        get {
            guard let data = nipFeedbackData else { return nil }
            return Self.decodeFieldFeedback(from: data)
        }
        set {
            nipFeedbackData = Self.encodeFieldFeedback(newValue)
        }
    }

    /// Document number feedback (decoded)
    var documentNumberFeedback: FieldFeedback? {
        get {
            guard let data = documentNumberFeedbackData else { return nil }
            return Self.decodeFieldFeedback(from: data)
        }
        set {
            documentNumberFeedbackData = Self.encodeFieldFeedback(newValue)
        }
    }

    /// Bank account feedback (decoded)
    var bankAccountFeedback: FieldFeedback? {
        get {
            guard let data = bankAccountFeedbackData else { return nil }
            return Self.decodeFieldFeedback(from: data)
        }
        set {
            bankAccountFeedbackData = Self.encodeFieldFeedback(newValue)
        }
    }

    // MARK: - Nonisolated Helpers for Codable Operations
    // These helpers allow Codable operations to work correctly with Swift 6 strict concurrency
    // since JSONDecoder/JSONEncoder operations don't need main actor isolation.

    /// Decodes FieldFeedback from JSON data in a nonisolated context
    private nonisolated static func decodeFieldFeedback(from data: Data) -> FieldFeedback? {
        try? JSONDecoder().decode(FieldFeedback.self, from: data)
    }

    /// Encodes FieldFeedback to JSON data in a nonisolated context
    private nonisolated static func encodeFieldFeedback(_ feedback: FieldFeedback?) -> Data? {
        try? JSONEncoder().encode(feedback)
    }

    /// Count of fields that were corrected
    var correctionCount: Int {
        var count = 0
        if vendorNameFeedback?.correctionMade == true { count += 1 }
        if amountFeedback?.correctionMade == true { count += 1 }
        if dueDateFeedback?.correctionMade == true { count += 1 }
        if nipFeedback?.correctionMade == true { count += 1 }
        if documentNumberFeedback?.correctionMade == true { count += 1 }
        if bankAccountFeedback?.correctionMade == true { count += 1 }
        return count
    }

    /// Count of fields that were extracted (had original values)
    var fieldsExtracted: Int {
        var count = 0
        if vendorNameFeedback != nil { count += 1 }
        if amountFeedback != nil { count += 1 }
        if dueDateFeedback != nil { count += 1 }
        if nipFeedback != nil { count += 1 }
        if documentNumberFeedback != nil { count += 1 }
        if bankAccountFeedback != nil { count += 1 }
        return count
    }

    /// Accuracy rate for this feedback (fields correct / fields extracted)
    var accuracyRate: Double {
        guard fieldsExtracted > 0 else { return 0.0 }
        return Double(fieldsExtracted - correctionCount) / Double(fieldsExtracted)
    }

    // MARK: - Initialization

    init(
        documentId: UUID,
        vendorNIP: String? = nil,
        ocrConfidence: Double,
        parserProvider: String,
        parserVersion: Int
    ) {
        self.documentId = documentId
        self.vendorNIP = vendorNIP
        self.timestamp = Date()
        self.ocrConfidence = ocrConfidence
        self.alternativesShown = 0
        self.alternativesSelected = 0
        self.saveSuccessful = false
        self.parserProvider = parserProvider
        self.parserVersion = parserVersion
    }

    // MARK: - Recording Methods

    /// Record feedback for a field
    func recordFeedback(
        for field: FieldType,
        originalConfidence: Double,
        alternativeSelected: Int?,
        corrected: Bool,
        reviewMode: ReviewMode,
        extractionMethod: ExtractionMethod?
    ) {
        let feedback = FieldFeedback(
            originalConfidence: originalConfidence,
            alternativeSelected: alternativeSelected,
            correctionMade: corrected,
            reviewMode: reviewMode,
            extractionMethod: extractionMethod,
            wasAccepted: true
        )

        switch field {
        case .vendor:
            vendorNameFeedback = feedback
        case .amount:
            amountFeedback = feedback
        case .dueDate:
            dueDateFeedback = feedback
        case .documentNumber:
            documentNumberFeedback = feedback
        case .nip:
            nipFeedback = feedback
        case .bankAccount:
            bankAccountFeedback = feedback
        }

        if alternativeSelected != nil {
            alternativesSelected += 1
        }
    }

    /// Mark save as successful
    func markSaveSuccessful() {
        saveSuccessful = true
    }

    /// Record review duration
    func recordReviewDuration(_ duration: TimeInterval) {
        reviewDuration = duration
    }
}

// MARK: - Predicates

extension ParsingFeedback {

    /// Predicate to find feedback by document ID
    static func byDocument(_ documentId: UUID) -> Predicate<ParsingFeedback> {
        #Predicate<ParsingFeedback> { feedback in
            feedback.documentId == documentId
        }
    }

    /// Predicate to find feedback by vendor NIP
    static func byVendor(_ nip: String) -> Predicate<ParsingFeedback> {
        #Predicate<ParsingFeedback> { feedback in
            feedback.vendorNIP == nip
        }
    }

    /// Predicate to find feedback with corrections
    static var withCorrections: Predicate<ParsingFeedback> {
        #Predicate<ParsingFeedback> { feedback in
            feedback.vendorNameFeedbackData != nil ||
            feedback.amountFeedbackData != nil ||
            feedback.dueDateFeedbackData != nil
        }
    }

    /// Predicate to find successful saves
    static var successful: Predicate<ParsingFeedback> {
        #Predicate<ParsingFeedback> { feedback in
            feedback.saveSuccessful == true
        }
    }
}

// MARK: - Aggregation Helper

/// Aggregated feedback statistics for monitoring parser performance.
/// Privacy-safe: contains only aggregate metrics, no individual values.
struct FeedbackStats: Sendable {
    let totalDocuments: Int
    let averageAccuracy: Double
    let correctionsByField: [FieldType: Int]
    let averageReviewDuration: TimeInterval?
    let alternativeSelectionRate: Double

    init(feedbacks: [ParsingFeedback]) {
        self.totalDocuments = feedbacks.count

        // Calculate average accuracy
        let accuracies = feedbacks.map { $0.accuracyRate }
        self.averageAccuracy = accuracies.isEmpty ? 0.0 : accuracies.reduce(0, +) / Double(accuracies.count)

        // Count corrections by field
        var corrections: [FieldType: Int] = [:]
        for feedback in feedbacks {
            if feedback.vendorNameFeedback?.correctionMade == true {
                corrections[.vendor, default: 0] += 1
            }
            if feedback.amountFeedback?.correctionMade == true {
                corrections[.amount, default: 0] += 1
            }
            if feedback.dueDateFeedback?.correctionMade == true {
                corrections[.dueDate, default: 0] += 1
            }
            if feedback.documentNumberFeedback?.correctionMade == true {
                corrections[.documentNumber, default: 0] += 1
            }
        }
        self.correctionsByField = corrections

        // Calculate average review duration
        let durations = feedbacks.compactMap { $0.reviewDuration }
        self.averageReviewDuration = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)

        // Calculate alternative selection rate
        let totalAlternativesShown = feedbacks.reduce(0) { $0 + $1.alternativesShown }
        let totalAlternativesSelected = feedbacks.reduce(0) { $0 + $1.alternativesSelected }
        self.alternativeSelectionRate = totalAlternativesShown > 0
            ? Double(totalAlternativesSelected) / Double(totalAlternativesShown)
            : 0.0
    }
}
