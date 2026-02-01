import Foundation
import UIKit
import os

/// Analysis router that always uses local parsing (Free tier).
/// Provides a simple pass-through to the local analysis service.
///
/// Routing behavior:
/// - Always uses DocumentAnalysisServiceProtocol (local parsing)
/// - Ignores forceCloud parameter (not available in free tier)
/// - Never attempts cloud analysis
///
/// In Iteration 2, replace with HybridAnalysisRouter for Pro tier.
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

        PrivacyLogger.parsing.info("LocalOnlyAnalysisRouter: Analyzing document with local-only router")

        // Log if cloud was requested but not available
        if forceCloud {
            PrivacyLogger.parsing.debug("LocalOnlyAnalysisRouter: Cloud requested but not available in free tier")
        }

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

        return result
    }
}
