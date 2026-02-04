import Foundation
import SwiftData
import Combine
import os.log

#if canImport(UIKit)
import UIKit
#endif

/// Routes document analysis with cloud-first strategy for all users.
///
/// ## Routing Strategy (Cloud-First with Network Awareness)
///
/// All users (Free and Pro) follow the same routing logic:
/// 1. **If online and backend available**: Try cloud extraction first
///    - Backend enforces monthly limits (3 for Free, 100 for Pro)
///    - If limit exceeded, backend returns rate limit error -> propagate to UI
/// 2. **If offline or backend error (not rate limit)**: Fall back to local analysis
/// 3. **If cloud analysis disabled in settings**: Use local-only
///
/// ## Network-Aware Decision Making
///
/// Uses `NetworkMonitorProtocol` to determine device connectivity:
/// - Checks network status BEFORE making cloud requests
/// - Tracks backend health from previous request outcomes
/// - Uses `ExtractionDecision` for clean routing logic
///
/// ## Critical: Rate Limit Handling
///
/// When rate limit is exceeded:
/// - **DO NOT** fall back to local silently
/// - **THROW** `CloudExtractionError.rateLimitExceeded` to ViewModel
/// - ViewModel presents paywall to preserve monetization
///
/// ## Key Design Decisions
///
/// - **NO client-side monthly limit enforcement** - Backend is the source of truth
/// - **Free tier gets cloud extraction** (within backend-enforced limits)
/// - **Graceful degradation** to local when offline or on backend errors
/// - **Rate limit errors propagate** to UI for user feedback (not silent fallback)
///
/// ## ExtractionMode Tracking
///
/// Results include `extractionMode` field indicating how analysis was performed:
/// - `.cloud` - Cloud AI extraction succeeded
/// - `.localFallback` - Backend error caused fallback to local
/// - `.offlineFallback` - Device offline, used local analysis
/// - `.localOnly` - Cloud disabled in settings
final class HybridAnalysisRouter: DocumentAnalysisRouterProtocol {

    // MARK: - Properties

    private let localService: DocumentAnalysisServiceProtocol
    private let cloudGateway: CloudExtractionGatewayProtocol
    private let networkMonitor: NetworkMonitorProtocol
    private let settingsManager: SettingsManager
    private let logger = Logger(subsystem: "com.dueasy.app", category: "HybridRouter")

    // Routing configuration
    private let config: RoutingConfiguration

    // Statistics tracking
    private var stats = RoutingStats()

    // Backend health tracking
    private var lastBackendHealth: BackendHealthStatus = .unknown

    // MARK: - Initialization

    init(
        localService: DocumentAnalysisServiceProtocol,
        cloudGateway: CloudExtractionGatewayProtocol,
        networkMonitor: NetworkMonitorProtocol,
        settingsManager: SettingsManager,
        config: RoutingConfiguration = .default
    ) {
        self.localService = localService
        self.cloudGateway = cloudGateway
        self.networkMonitor = networkMonitor
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

        return .cloudWithLocalFallback
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

        // Route based on mode
        switch analysisMode {
        case .localOnly:
            logger.info("Using local-only analysis (cloud disabled in settings)")
            stats.localOnly += 1
            return try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: .localOnly
            )

        case .alwaysCloud, .cloudWithLocalFallback:
            // Cloud-first routing for all users
            // Backend enforces monthly limits (Free: 3, Pro: 100)
            return try await performCloudFirstAnalysis(
                ocrResult: ocrResult,
                images: images,
                documentType: documentType
            )
        }
    }

    // MARK: - Private Helpers

    private func performLocalAnalysis(
        ocrResult: OCRResult,
        documentType: DocumentType,
        extractionMode: ExtractionMode
    ) async throws -> DocumentAnalysisResult {
        let result = try await localService.analyzeDocument(ocrResult: ocrResult, documentType: documentType)

        // Return result with extraction mode set
        return result.withExtractionMode(extractionMode)
    }

    /// Cloud-first analysis: Try cloud, fall back to local on errors (except rate limit).
    ///
    /// ## Network-Aware Routing
    ///
    /// Uses `ExtractionDecision` to determine routing:
    /// 1. Check network status via `NetworkMonitor`
    /// 2. Consider last known backend health
    /// 3. Route accordingly
    ///
    /// ## Critical: Rate Limit Handling
    ///
    /// Rate limit errors (monthly limit exceeded) are **NEVER** silently handled.
    /// They propagate to the UI so users get clear feedback and paywall presentation.
    private func performCloudFirstAnalysis(
        ocrResult: OCRResult,
        images: [UIImage],
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {

        // Step 1: Make extraction decision based on network state and backend health
        let decision = makeExtractionDecision(
            isOnline: networkMonitor.isOnline,
            backendHealth: lastBackendHealth
        )

        logger.info("Extraction decision: \(String(describing: decision)), online=\(self.networkMonitor.isOnline), backendHealth=\(self.lastBackendHealth.rawValue)")

        switch decision {
        case .offlineFallback:
            // Device offline or backend known to be down - use local immediately
            logger.info("Using offline fallback (device offline or backend down)")
            stats.localFallbacks += 1
            return try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: .offlineFallback
            )

        case .cloud:
            // Online and backend available - try cloud extraction
            // Step 2: Verify cloud gateway is available (auth check)
            let cloudAvailable = await cloudGateway.isAvailable

            guard cloudAvailable else {
                // Auth not available - use local fallback
                logger.info("Cloud gateway not available (auth required), using local fallback")
                stats.localFallbacks += 1
                return try await performLocalAnalysis(
                    ocrResult: ocrResult,
                    documentType: documentType,
                    extractionMode: .offlineFallback
                )
            }

            // Step 3: Try cloud extraction (for both Free and Pro users)
            // Backend enforces monthly limits
            do {
                let result = try await performCloudAnalysis(
                    ocrResult: ocrResult,
                    images: images,
                    documentType: documentType
                )

                // Success - mark backend as healthy
                lastBackendHealth = .healthy

                return result
            } catch let error as CloudExtractionError {
                // Update backend health based on error type
                updateBackendHealth(from: error)

                return try await handleCloudError(
                    error: error,
                    ocrResult: ocrResult,
                    documentType: documentType
                )
            } catch {
                // Unknown error - fall back to local
                logger.error("Cloud analysis failed with unexpected error: \(error.localizedDescription)")
                lastBackendHealth = .degraded
                stats.localFallbacks += 1
                return try await performLocalAnalysis(
                    ocrResult: ocrResult,
                    documentType: documentType,
                    extractionMode: .localFallback
                )
            }
        }
    }

    /// Updates backend health status based on error type.
    private func updateBackendHealth(from error: CloudExtractionError) {
        switch error {
        case .networkError, .timeout, .backendUnavailable:
            lastBackendHealth = .down
        case .serverError(let statusCode, _) where statusCode >= 500:
            lastBackendHealth = .degraded
        case .rateLimitExceeded:
            // Rate limit is not a backend health issue - backend is working fine
            lastBackendHealth = .healthy
        default:
            // Don't change health status for other errors
            break
        }
    }

    /// Handle cloud extraction errors with appropriate fallback or propagation.
    ///
    /// ## Critical: Rate Limit Errors
    ///
    /// Rate limit errors are **NEVER** handled with silent fallback.
    /// They MUST propagate to the ViewModel for paywall presentation.
    /// This preserves the monetization model.
    private func handleCloudError(
        error: CloudExtractionError,
        ocrResult: OCRResult,
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {

        switch error {
        case .rateLimitExceeded(let used, let limit, let resetDate):
            // Rate limit exceeded: Fall back to local, but carry rate limit info
            // This allows the UI to show an informative banner with upgrade option
            // User is NOT blocked - they can continue with local extraction
            PrivacyLogger.cloud.warning("Cloud extraction rate limited: \(used)/\(limit), resets: \(resetDate?.description ?? "unknown"). Falling back to local.")
            stats.localFallbacks += 1

            // Perform local analysis
            let localResult = try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: .rateLimitFallback
            )

            // Return result with rate limit info for banner display
            return localResult.withRateLimitFallback(used: used, limit: limit, resetDate: resetDate)

        case .authenticationRequired:
            // User needs to sign in - propagate error
            PrivacyLogger.cloud.info("Cloud extraction requires authentication")
            throw error

        case .networkError, .timeout, .backendUnavailable:
            // Transient network/backend issue - fall back to local
            logger.warning("Cloud analysis failed due to network/backend issue, falling back to local")
            stats.localFallbacks += 1
            return try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: .localFallback
            )

        case .serverError(let statusCode, _):
            // Server error - fall back to local
            logger.warning("Cloud analysis failed with server error (\(statusCode)), falling back to local")
            stats.localFallbacks += 1
            return try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: .localFallback
            )

        case .notAvailable, .subscriptionRequired:
            // This shouldn't happen with the new routing (no client-side checks)
            // but handle gracefully by falling back to local
            logger.warning("Cloud not available or subscription required, falling back to local")
            stats.localFallbacks += 1
            return try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: .localFallback
            )

        case .invalidResponse, .imageUploadFailed, .analysisIncomplete:
            // Backend returned bad data - fall back to local
            logger.warning("Cloud analysis returned invalid data, falling back to local")
            stats.localFallbacks += 1
            return try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: .localFallback
            )
        }
    }

    private func performCloudAnalysis(
        ocrResult: OCRResult,
        images: [UIImage],
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {

        stats.cloudAssisted += 1

        // Extract OCR text from result
        let ocrText = buildOCRText(from: ocrResult)

        // PRIVACY: Log only metrics, not OCR content
        PrivacyLogger.cloud.info("Cloud analysis started: textLength=\(ocrText.count), imageCount=\(images.count)")

        // Try text-only first (privacy-first)
        let result = try await cloudGateway.analyzeText(
            ocrText: ocrText,
            documentType: documentType,
            languageHints: ["pl", "en"],
            currencyHints: ["PLN", "EUR", "USD"]
        )

        // PRIVACY: Log success metrics only
        PrivacyLogger.cloud.info("Cloud analysis completed: hasVendor=\(result.vendorName != nil), hasAmount=\(result.amount != nil), hasDate=\(result.dueDate != nil)")

        // Return result with cloud extraction mode
        return result.withExtractionMode(.cloud)
    }

    private func buildOCRText(from result: OCRResult) -> String {
        // Use lineData if available, otherwise use text directly
        if let lineData = result.lineData, !lineData.isEmpty {
            return lineData.map { $0.text }.joined(separator: "\n")
        }
        return result.text
    }
}

// MARK: - DocumentAnalysisResult Extension

extension DocumentAnalysisResult {

    /// Returns a copy of this result with the specified extraction mode.
    func withExtractionMode(_ mode: ExtractionMode) -> DocumentAnalysisResult {
        return DocumentAnalysisResult(
            documentType: documentType,
            vendorName: vendorName,
            vendorAddress: vendorAddress,
            vendorNIP: vendorNIP,
            vendorREGON: vendorREGON,
            amount: amount,
            currency: currency,
            dueDate: dueDate,
            documentNumber: documentNumber,
            bankAccountNumber: bankAccountNumber,
            suggestedAmounts: suggestedAmounts,
            amountCandidates: amountCandidates,
            dateCandidates: dateCandidates,
            vendorCandidates: vendorCandidates,
            nipCandidates: nipCandidates,
            bankAccountCandidates: bankAccountCandidates,
            documentNumberCandidates: documentNumberCandidates,
            vendorEvidence: vendorEvidence,
            amountEvidence: amountEvidence,
            dueDateEvidence: dueDateEvidence,
            documentNumberEvidence: documentNumberEvidence,
            nipEvidence: nipEvidence,
            bankAccountEvidence: bankAccountEvidence,
            vendorExtractionMethod: vendorExtractionMethod,
            amountExtractionMethod: amountExtractionMethod,
            dueDateExtractionMethod: dueDateExtractionMethod,
            nipExtractionMethod: nipExtractionMethod,
            overallConfidence: overallConfidence,
            fieldConfidences: fieldConfidences,
            provider: provider,
            version: version,
            extractionMode: mode,
            rateLimitInfo: rateLimitInfo,
            rawHints: rawHints,
            rawOCRText: rawOCRText
        )
    }

    /// Returns a copy of this result with the specified extraction mode and rate limit info.
    /// Used when falling back to local extraction due to rate limit exceeded.
    func withRateLimitFallback(used: Int, limit: Int, resetDate: Date?) -> DocumentAnalysisResult {
        return DocumentAnalysisResult(
            documentType: documentType,
            vendorName: vendorName,
            vendorAddress: vendorAddress,
            vendorNIP: vendorNIP,
            vendorREGON: vendorREGON,
            amount: amount,
            currency: currency,
            dueDate: dueDate,
            documentNumber: documentNumber,
            bankAccountNumber: bankAccountNumber,
            suggestedAmounts: suggestedAmounts,
            amountCandidates: amountCandidates,
            dateCandidates: dateCandidates,
            vendorCandidates: vendorCandidates,
            nipCandidates: nipCandidates,
            bankAccountCandidates: bankAccountCandidates,
            documentNumberCandidates: documentNumberCandidates,
            vendorEvidence: vendorEvidence,
            amountEvidence: amountEvidence,
            dueDateEvidence: dueDateEvidence,
            documentNumberEvidence: documentNumberEvidence,
            nipEvidence: nipEvidence,
            bankAccountEvidence: bankAccountEvidence,
            vendorExtractionMethod: vendorExtractionMethod,
            amountExtractionMethod: amountExtractionMethod,
            dueDateExtractionMethod: dueDateExtractionMethod,
            nipExtractionMethod: nipExtractionMethod,
            overallConfidence: overallConfidence,
            fieldConfidences: fieldConfidences,
            provider: provider,
            version: version,
            extractionMode: .rateLimitFallback,
            rateLimitInfo: RateLimitInfo(used: used, limit: limit, resetDate: resetDate),
            rawHints: rawHints,
            rawOCRText: rawOCRText
        )
    }
}
