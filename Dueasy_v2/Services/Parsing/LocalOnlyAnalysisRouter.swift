import Foundation
import UIKit
import os

/// Analysis router that always uses local parsing.
/// Used as a fallback when Firebase SDK is not available.
///
/// ## Usage
///
/// This router is only used when the Firebase SDK cannot be imported.
/// In normal builds with Firebase, HybridAnalysisRouter handles all routing
/// with cloud-first strategy for all tiers.
///
/// ## ExtractionMode
///
/// Results from this router have `extractionMode = .localOnly` since
/// cloud extraction is not attempted.
final class LocalOnlyAnalysisRouter: DocumentAnalysisRouterProtocol {

    // MARK: - Dependencies

    private let localService: DocumentAnalysisServiceProtocol

    // MARK: - Properties

    var analysisMode: AnalysisMode { .localOnly }

    var isCloudAvailable: Bool {
        get async { false }
    }

    private(set) var routingStats = RoutingStats()

    // MARK: - Initialization

    init(localService: DocumentAnalysisServiceProtocol) {
        self.localService = localService
    }

    // MARK: - Analysis

    func analyzeDocument(
        ocrResult: OCRResult,
        images: [UIImage],
        documentType: DocumentType,
        forceCloud: Bool
    ) async throws -> DocumentAnalysisResult {

        PrivacyLogger.parsing.info("LocalOnlyAnalysisRouter: Analyzing document (Firebase SDK unavailable)")

        // Log if cloud was requested but not available
        if forceCloud {
            PrivacyLogger.parsing.debug("LocalOnlyAnalysisRouter: Cloud requested but Firebase SDK not available")
        }

        return try await performLocalAnalysis(ocrResult: ocrResult, documentType: documentType)
    }

    func analyzeDocument(
        ocrResult: OCRResult,
        images: [UIImage],
        documentType: DocumentType,
        decision: ExtractionModeDecision
    ) async throws -> DocumentAnalysisResult {

        PrivacyLogger.parsing.info("LocalOnlyAnalysisRouter: Decision-based routing (always local, Firebase SDK unavailable)")

        return try await performLocalAnalysis(ocrResult: ocrResult, documentType: documentType)
    }

    // MARK: - Private

    private func performLocalAnalysis(
        ocrResult: OCRResult,
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {

        // Update stats
        routingStats.totalRouted += 1
        routingStats.localOnly += 1

        // Always use local analysis
        let result = try await localService.analyzeDocument(
            ocrResult: ocrResult,
            documentType: documentType
        )

        PrivacyLogger.parsing.info(
            "LocalOnlyAnalysisRouter: Analysis complete, confidence=\(String(format: "%.2f", result.overallConfidence))"
        )

        // Return result with localOnly extraction mode
        return result.withExtractionMode(.localOnly)
    }
}
