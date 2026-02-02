import Foundation
import SwiftData
import os.log

#if canImport(UIKit)
import UIKit
#endif

/// Routes document analysis between local and cloud based on confidence and settings
final class HybridAnalysisRouter: DocumentAnalysisRouterProtocol {

    // MARK: - Properties

    private let localService: DocumentAnalysisServiceProtocol
    private let cloudGateway: CloudExtractionGatewayProtocol
    private let settingsManager: SettingsManager
    private let logger = Logger(subsystem: "com.dueasy.app", category: "HybridRouter")

    // Routing configuration
    private let config: RoutingConfiguration

    // Statistics tracking
    private var stats = RoutingStats()

    // MARK: - Initialization

    init(
        localService: DocumentAnalysisServiceProtocol,
        cloudGateway: CloudExtractionGatewayProtocol,
        settingsManager: SettingsManager,
        config: RoutingConfiguration = .default
    ) {
        self.localService = localService
        self.cloudGateway = cloudGateway
        self.settingsManager = settingsManager
        self.config = config
    }

    // MARK: - DocumentAnalysisRouterProtocol

    var analysisMode: AnalysisMode {
        if !settingsManager.cloudAnalysisEnabled {
            return .localOnly
        }

        if settingsManager.highAccuracyMode {
            return .alwaysCloud
        }

        return .localWithCloudAssist
    }

    var isCloudAvailable: Bool {
        get async {
            return await cloudGateway.isAvailable
        }
    }

    var routingStats: RoutingStats {
        return stats
    }

    func analyzeDocument(
        ocrResult: OCRResult,
        images: [UIImage],
        documentType: DocumentType,
        forceCloud: Bool
    ) async throws -> DocumentAnalysisResult {

        stats.totalRouted += 1

        // Force cloud if requested (and available)
        let cloudAvailable = await isCloudAvailable
        if forceCloud && cloudAvailable {
            return try await performCloudAnalysis(ocrResult: ocrResult, images: images, documentType: documentType)
        }

        // Route based on mode
        switch analysisMode {
        case .localOnly:
            logger.info("Using local-only analysis (cloud disabled)")
            stats.localOnly += 1
            return try await performLocalAnalysis(ocrResult: ocrResult, documentType: documentType)

        case .alwaysCloud:
            logger.info("Using cloud analysis (high accuracy mode)")
            return try await performCloudPrimaryAnalysis(ocrResult: ocrResult, images: images, documentType: documentType)

        case .localWithCloudAssist:
            return try await performHybridAnalysis(ocrResult: ocrResult, images: images, documentType: documentType)
        }
    }

    // MARK: - Private Helpers

    private func performLocalAnalysis(
        ocrResult: OCRResult,
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {
        return try await localService.analyzeDocument(ocrResult: ocrResult, documentType: documentType)
    }

    private func performCloudAnalysis(
        ocrResult: OCRResult,
        images: [UIImage],
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {

        guard await cloudGateway.isAvailable else {
            throw CloudExtractionError.notAvailable
        }

        stats.cloudAssisted += 1

        // Extract OCR text from result
        let ocrText = buildOCRText(from: ocrResult)

        // PRIVACY: Log only metrics, not OCR content
        PrivacyLogger.cloud.info("Cloud analysis started: textLength=\(ocrText.count), imageCount=\(images.count)")

        // Try text-only first (privacy-first)
        do {
            let result = try await cloudGateway.analyzeText(
                ocrText: ocrText,
                documentType: documentType,
                languageHints: ["pl", "en"],
                currencyHints: ["PLN", "EUR", "USD"]
            )

            // PRIVACY: Log success metrics only
            PrivacyLogger.cloud.info("Cloud analysis completed: hasVendor=\(result.vendorName != nil), hasAmount=\(result.amount != nil), hasDate=\(result.dueDate != nil)")

            return result
        } catch let error as CloudExtractionError {
            // Log error type for monitoring (privacy-safe)
            if error.isRateLimitError {
                PrivacyLogger.cloud.warning("Cloud analysis rate limited after retries")
            } else {
                PrivacyLogger.cloud.warning("Cloud text-only analysis failed: errorType=\(error.isRetryable ? "retryable" : "permanent")")
            }
            throw error
        } catch {
            logger.warning("Cloud text-only analysis failed, will not use images for privacy")
            throw error
        }
    }

    private func performCloudPrimaryAnalysis(
        ocrResult: OCRResult,
        images: [UIImage],
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {

        guard await cloudGateway.isAvailable else {
            // Fallback to local if cloud not available
            logger.warning("Cloud not available, falling back to local")
            stats.localFallbacks += 1
            return try await performLocalAnalysis(ocrResult: ocrResult, documentType: documentType)
        }

        do {
            return try await performCloudAnalysis(ocrResult: ocrResult, images: images, documentType: documentType)
        } catch {
            // Fallback to local on cloud failure
            logger.error("Cloud analysis failed, falling back to local: \(error.localizedDescription)")
            stats.localFallbacks += 1
            return try await performLocalAnalysis(ocrResult: ocrResult, documentType: documentType)
        }
    }

    private func performHybridAnalysis(
        ocrResult: OCRResult,
        images: [UIImage],
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {

        logger.info("Starting hybrid analysis (local first, cloud assist if needed)")

        // Step 1: Try local analysis first
        let localResult = try await performLocalAnalysis(ocrResult: ocrResult, documentType: documentType)
        stats.localOnly += 1

        // Step 2: Evaluate confidence
        let confidence = evaluateConfidence(localResult)
        logger.info("Local analysis confidence: \(confidence, format: .fixed(precision: 2))")

        // Step 3: Decide if cloud assist is needed
        if confidence >= config.cloudAssistThreshold {
            logger.info("Local result accepted (confidence >= \(self.config.cloudAssistThreshold, format: .fixed(precision: 2)))")
            return localResult
        }

        if confidence >= config.minimumAcceptableConfidence {
            logger.info("Local result acceptable (confidence >= \(self.config.minimumAcceptableConfidence, format: .fixed(precision: 2))), skipping cloud")
            return localResult
        }

        // Step 4: Low confidence - use cloud assist
        logger.info("Low confidence (\(confidence, format: .fixed(precision: 2))), requesting cloud assist")
        stats.cloudFallbacks += 1
        stats.avgLocalConfidenceBeforeCloud = (stats.avgLocalConfidenceBeforeCloud * Double(stats.cloudFallbacks - 1) + confidence) / Double(stats.cloudFallbacks)

        guard await cloudGateway.isAvailable else {
            logger.warning("Cloud not available, returning local result")
            return localResult
        }

        do {
            let cloudResult = try await performCloudAnalysis(ocrResult: ocrResult, images: images, documentType: documentType)
            logger.info("Cloud assist successful")
            return cloudResult
        } catch {
            logger.error("Cloud assist failed: \(error.localizedDescription), returning local result")
            return localResult
        }
    }

    private func evaluateConfidence(_ result: DocumentAnalysisResult) -> Double {
        var totalConfidence = 0.0
        var fieldCount = 0

        // Weight critical fields higher
        let criticalFieldWeight = 2.0
        let normalFieldWeight = 1.0

        // Critical fields
        if let vendorConfidence = (result.vendorCandidates ?? []).first?.confidence {
            totalConfidence += vendorConfidence * criticalFieldWeight
            fieldCount += Int(criticalFieldWeight)
        }

        if let amountConfidence = (result.amountCandidates ?? []).first?.confidence {
            totalConfidence += amountConfidence * criticalFieldWeight
            fieldCount += Int(criticalFieldWeight)
        }

        // Date candidates use score instead of confidence, normalize to 0-1 range
        if let dateScore = (result.dateCandidates ?? []).first?.score {
            let normalizedConfidence = min(Double(dateScore) / 100.0, 1.0)
            totalConfidence += normalizedConfidence * criticalFieldWeight
            fieldCount += Int(criticalFieldWeight)
        }

        // Normal fields
        if let nipConfidence = (result.nipCandidates ?? []).first?.confidence {
            totalConfidence += nipConfidence * normalFieldWeight
            fieldCount += Int(normalFieldWeight)
        }

        if let docNumConfidence = (result.documentNumberCandidates ?? []).first?.confidence {
            totalConfidence += docNumConfidence * normalFieldWeight
            fieldCount += Int(normalFieldWeight)
        }

        if let bankConfidence = (result.bankAccountCandidates ?? []).first?.confidence {
            totalConfidence += bankConfidence * normalFieldWeight
            fieldCount += Int(normalFieldWeight)
        }

        return fieldCount > 0 ? totalConfidence / Double(fieldCount) : 0.0
    }

    private func buildOCRText(from result: OCRResult) -> String {
        // Use lineData if available, otherwise use text directly
        if let lineData = result.lineData, !lineData.isEmpty {
            return lineData.map { $0.text }.joined(separator: "\n")
        }
        return result.text
    }
}
