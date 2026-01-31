import Foundation

/// Protocol for document analysis (parsing extracted text).
/// Iteration 1: Local heuristic-based invoice parsing.
/// Iteration 2: Backend AI analysis (OpenAI Vision, Gemini Vision).
protocol DocumentAnalysisServiceProtocol: Sendable {

    /// Analyzes OCR text and extracts structured fields.
    /// - Parameters:
    ///   - text: OCR-recognized text
    ///   - documentType: Expected document type (helps focus parsing)
    /// - Returns: Structured analysis result with extracted fields
    /// - Throws: `AppError.parsingFailed`
    func analyzeDocument(
        text: String,
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult

    /// Analyzes document from images directly (for AI providers that support vision).
    /// Iteration 1: Falls back to OCR + text analysis.
    /// Iteration 2: Sends images directly to vision AI.
    /// - Parameters:
    ///   - images: Document images
    ///   - documentType: Expected document type
    /// - Returns: Structured analysis result
    /// - Throws: `AppError.parsingFailed`
    func analyzeDocument(
        images: [Data],
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult

    /// The provider identifier (e.g., "local", "openai", "gemini").
    var providerIdentifier: String { get }

    /// Current analysis version for schema tracking.
    var analysisVersion: Int { get }

    /// Whether this provider supports direct image analysis.
    var supportsVisionAnalysis: Bool { get }
}

// MARK: - Default Implementations

extension DocumentAnalysisServiceProtocol {

    var analysisVersion: Int { 1 }

    var supportsVisionAnalysis: Bool { false }

    func analyzeDocument(
        images: [Data],
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {
        // Default: Vision analysis not supported, return empty result
        // Subclasses should override if they support vision
        throw AppError.parsingFailed("Vision analysis not supported by this provider")
    }
}
