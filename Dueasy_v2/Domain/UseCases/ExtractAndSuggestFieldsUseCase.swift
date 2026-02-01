import Foundation
import UIKit
import os.log

/// Use case for extracting text from images and suggesting field values.
/// Runs 2-pass OCR and confidence-weighted parsing to provide auto-fill suggestions.
struct ExtractAndSuggestFieldsUseCase: Sendable {

    private let ocrService: OCRServiceProtocol
    private let analysisService: DocumentAnalysisServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "ExtractUseCase")

    init(
        ocrService: OCRServiceProtocol,
        analysisService: DocumentAnalysisServiceProtocol
    ) {
        self.ocrService = ocrService
        self.analysisService = analysisService
    }

    /// Extracts text and analyzes document content using 2-pass OCR with confidence weighting.
    /// - Parameters:
    ///   - images: Document images to process
    ///   - documentType: Expected document type for focused parsing
    /// - Returns: Analysis result with extracted field suggestions
    func execute(
        images: [UIImage],
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {
        // Step 1: Run 2-pass OCR to extract text with line data and confidence
        let ocrResult = try await ocrService.recognizeText(from: images)

        // Log OCR statistics
        let lineCount = ocrResult.lineData?.count ?? 0
        logger.info("OCR completed: \(ocrResult.text.count) chars, \(lineCount) lines, confidence: \(String(format: "%.3f", ocrResult.confidence))")

        if let lineData = ocrResult.lineData, !lineData.isEmpty {
            // Log pass source distribution
            let standardLines = lineData.filter { $0.source == .standard }.count
            let sensitiveLines = lineData.filter { $0.source == .sensitive }.count
            let mergedLines = lineData.filter { $0.source == .merged }.count
            logger.info("OCR line sources: standard=\(standardLines), sensitive=\(sensitiveLines), merged=\(mergedLines)")

            // Log confidence distribution
            let highConfLines = lineData.filter { $0.hasHighConfidence }.count
            let medConfLines = lineData.filter { $0.hasMediumConfidence }.count
            let lowConfLines = lineData.filter { $0.hasLowConfidence }.count
            logger.info("OCR confidence: high=\(highConfLines), medium=\(medConfLines), low=\(lowConfLines)")
        }

        // Check if OCR found any text
        guard ocrResult.hasText else {
            logger.warning("OCR found no text in images")
            return DocumentAnalysisResult(
                overallConfidence: 0.0,
                provider: analysisService.providerIdentifier,
                version: analysisService.analysisVersion
            )
        }

        // Step 2: Analyze using full OCR result (with lineData for confidence-weighted scoring)
        let analysisResult = try await analysisService.analyzeDocument(
            ocrResult: ocrResult,
            documentType: documentType
        )

        logger.info("Analysis completed: vendor=\(analysisResult.vendorName != nil), amount=\(analysisResult.amount != nil), date=\(analysisResult.dueDate != nil), invoice#=\(analysisResult.documentNumber != nil)")

        // Return result with OCR confidence factored in and raw OCR text for learning
        // CRITICAL: Copy ALL fields including candidates (needed for learning system and alternatives UI)
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
            // All candidate arrays for alternatives UI
            amountCandidates: analysisResult.amountCandidates,
            dateCandidates: analysisResult.dateCandidates,
            vendorCandidates: analysisResult.vendorCandidates,
            nipCandidates: analysisResult.nipCandidates,
            bankAccountCandidates: analysisResult.bankAccountCandidates,
            documentNumberCandidates: analysisResult.documentNumberCandidates,
            // Evidence bounding boxes for UI highlighting
            vendorEvidence: analysisResult.vendorEvidence,
            amountEvidence: analysisResult.amountEvidence,
            dueDateEvidence: analysisResult.dueDateEvidence,
            documentNumberEvidence: analysisResult.documentNumberEvidence,
            nipEvidence: analysisResult.nipEvidence,
            bankAccountEvidence: analysisResult.bankAccountEvidence,
            // Extraction methods for debugging and learning
            vendorExtractionMethod: analysisResult.vendorExtractionMethod,
            amountExtractionMethod: analysisResult.amountExtractionMethod,
            dueDateExtractionMethod: analysisResult.dueDateExtractionMethod,
            nipExtractionMethod: analysisResult.nipExtractionMethod,
            overallConfidence: min(ocrResult.confidence, analysisResult.overallConfidence),
            fieldConfidences: analysisResult.fieldConfidences,
            provider: analysisResult.provider,
            version: analysisResult.version,
            rawHints: nil, // Don't store raw text for privacy
            rawOCRText: ocrResult.text // Provide OCR text for keyword learning (not persisted)
        )
    }
}
