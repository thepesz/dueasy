import Foundation
import UIKit

/// Use case for extracting text from images and suggesting field values.
/// Runs OCR and parsing to provide auto-fill suggestions.
struct ExtractAndSuggestFieldsUseCase: Sendable {

    private let ocrService: OCRServiceProtocol
    private let analysisService: DocumentAnalysisServiceProtocol

    init(
        ocrService: OCRServiceProtocol,
        analysisService: DocumentAnalysisServiceProtocol
    ) {
        self.ocrService = ocrService
        self.analysisService = analysisService
    }

    /// Extracts text and analyzes document content.
    /// - Parameters:
    ///   - images: Document images to process
    ///   - documentType: Expected document type for focused parsing
    /// - Returns: Analysis result with extracted field suggestions
    func execute(
        images: [UIImage],
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {
        // Step 1: Run OCR to extract text
        let ocrResult = try await ocrService.recognizeText(from: images)

        // Check if OCR found any text
        guard ocrResult.hasText else {
            return DocumentAnalysisResult(
                overallConfidence: 0.0,
                provider: analysisService.providerIdentifier,
                version: analysisService.analysisVersion
            )
        }

        // Step 2: Analyze the extracted text
        let analysisResult = try await analysisService.analyzeDocument(
            text: ocrResult.text,
            documentType: documentType
        )

        // Return result with OCR confidence factored in and raw OCR text for learning
        // CRITICAL: Copy ALL fields including candidates (needed for learning system)
        return DocumentAnalysisResult(
            documentType: analysisResult.documentType,
            vendorName: analysisResult.vendorName,
            vendorAddress: analysisResult.vendorAddress,
            vendorNIP: analysisResult.vendorNIP,
            vendorREGON: analysisResult.vendorREGON,
            amount: analysisResult.amount,
            currency: analysisResult.currency,
            dueDate: analysisResult.dueDate,
            documentNumber: analysisResult.documentNumber,
            bankAccountNumber: analysisResult.bankAccountNumber,
            suggestedAmounts: analysisResult.suggestedAmounts,
            amountCandidates: analysisResult.amountCandidates,
            dateCandidates: analysisResult.dateCandidates,
            vendorCandidates: analysisResult.vendorCandidates,
            overallConfidence: min(ocrResult.confidence, analysisResult.overallConfidence),
            fieldConfidences: analysisResult.fieldConfidences,
            provider: analysisResult.provider,
            version: analysisResult.version,
            rawHints: nil, // Don't store raw text for privacy
            rawOCRText: ocrResult.text // Provide OCR text for keyword learning (not persisted)
        )
    }
}
