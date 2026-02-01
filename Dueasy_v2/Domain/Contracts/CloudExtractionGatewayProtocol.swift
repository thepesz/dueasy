import Foundation

/// Gateway for cloud-based document analysis (OpenAI via Firebase).
/// This protocol defines the contract for cloud analysis providers.
///
/// Iteration 1: Mock implementation for testing.
/// Iteration 2: Firebase Functions integration with OpenAI Vision API.
///
/// Privacy-first design:
/// - Primary: Text-only analysis (OCR text sent, images stay on device)
/// - Fallback: Cropped image snippets when text is insufficient
protocol CloudExtractionGatewayProtocol: Sendable {

    /// Analyzes document using OCR text only (privacy-first approach).
    /// This is the preferred method - keeps images on device.
    /// - Parameters:
    ///   - ocrText: Pre-extracted OCR text from on-device Vision
    ///   - documentType: Expected document type for parsing hints
    ///   - languageHints: Language codes to assist parsing (e.g., ["pl", "en"])
    ///   - currencyHints: Currency codes expected in document (e.g., ["PLN", "EUR"])
    /// - Returns: Structured analysis result with extracted fields
    /// - Throws: `CloudExtractionError` on failure
    func analyzeText(
        ocrText: String,
        documentType: DocumentType,
        languageHints: [String],
        currencyHints: [String]
    ) async throws -> DocumentAnalysisResult

    /// Analyzes with cropped image snippets (fallback when text is insufficient).
    /// Used when text-only analysis returns low confidence and user opts in.
    /// - Parameters:
    ///   - ocrText: Pre-extracted OCR text (may be nil if OCR failed)
    ///   - croppedImages: JPEG data of cropped regions containing fields
    ///   - documentType: Expected document type for parsing hints
    ///   - languageHints: Language codes to assist parsing
    /// - Returns: Structured analysis result with extracted fields
    /// - Throws: `CloudExtractionError` on failure
    func analyzeWithImages(
        ocrText: String?,
        croppedImages: [Data],
        documentType: DocumentType,
        languageHints: [String]
    ) async throws -> DocumentAnalysisResult

    /// Check if cloud analysis is available (auth + subscription + network).
    /// Returns false if user is not signed in, not subscribed, or offline.
    var isAvailable: Bool { get async }

    /// Provider identifier for this gateway (e.g., "openai-firebase", "mock-cloud").
    var providerIdentifier: String { get }
}

// MARK: - Cloud Extraction Errors

/// Errors specific to cloud-based document extraction.
enum CloudExtractionError: LocalizedError {
    case notAvailable
    case authenticationRequired
    case subscriptionRequired
    case networkError(Error)
    case rateLimitExceeded
    case serverError(statusCode: Int, message: String)
    case invalidResponse
    case timeout
    case imageUploadFailed
    case analysisIncomplete(partialResult: DocumentAnalysisResult?)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Cloud analysis is not available"
        case .authenticationRequired:
            return "Sign in required for cloud analysis"
        case .subscriptionRequired:
            return "Pro subscription required for cloud analysis"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimitExceeded:
            return "Too many requests. Please try again later."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .timeout:
            return "Request timed out"
        case .imageUploadFailed:
            return "Failed to upload images"
        case .analysisIncomplete(let partialResult):
            if partialResult != nil {
                return "Analysis partially completed"
            }
            return "Analysis incomplete"
        }
    }

    /// Whether the error is recoverable with retry
    var isRetryable: Bool {
        switch self {
        case .networkError, .timeout, .rateLimitExceeded:
            return true
        case .serverError(let statusCode, _):
            return statusCode >= 500 // Server errors may be transient
        default:
            return false
        }
    }
}
