import Foundation
import SwiftData
import Combine
import os.log

#if canImport(UIKit)
import UIKit
#endif

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

/// Routes document analysis with cloud-first strategy for authenticated users.
///
/// ## Simplified Architecture
///
/// The router receives a pre-computed `ExtractionModeDecision` from `AccessManager`
/// and simply executes it. No client-side rate limiting, no subscription checks.
///
/// ## Routing Strategy
///
/// 1. `AccessManager.makeAnalysisDecision()` determines the mode
/// 2. Router executes the decision:
///    - `.localOnly(reason:)` -> Run local OCR/parsing only
///    - `.cloudAllowed(remaining:)` -> Try cloud, fall back to local on error
///
/// ## Backend is Source of Truth
///
/// - Backend enforces monthly limits (Free: 3, Pro: 100)
/// - Rate limit errors from backend fall back to local with upgrade banner
/// - No client-side failsafe counter needed
///
/// ## ExtractionMode Tracking
///
/// Results include `extractionMode` field indicating how analysis was performed:
/// - `.cloud` - Cloud AI extraction succeeded
/// - `.localFallback` - Backend error caused fallback to local
/// - `.offlineFallback` - Device offline, used local analysis
/// - `.localOnly` - Cloud disabled in settings
/// - `.rateLimitFallback` - Backend rate limit, fell back to local with banner
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

    /// Timestamp of the last backend failure that set health to `.down`.
    private var lastBackendFailureAt: Date?

    /// Cooldown duration (in seconds) before retrying a "down" backend.
    private static let backendHealthCooldownSeconds: TimeInterval = 60

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

    /// Legacy method - delegates to decision-based routing.
    /// Kept for protocol conformance. New code should use the decision-based method.
    ///
    /// SECURITY FIX: This method now defaults to localOnly when no decision is provided.
    /// Previously, it defaulted to .cloudAllowed(remaining: Int.max), which allowed
    /// ALL users (including guests/anonymous) to reach cloud analysis. This was the
    /// root cause of the guest cloud access bug.
    ///
    /// The correct flow is: AccessManager.makeAnalysisDecision() -> decision-based method.
    /// This legacy path exists only for backward compatibility and defaults to safe behavior.
    func analyzeDocument(
        ocrResult: OCRResult,
        images: [UIImage],
        documentType: DocumentType,
        forceCloud: Bool
    ) async throws -> DocumentAnalysisResult {

        // SECURITY: Default to local-only in the legacy path.
        // The legacy path has no access to AccessManager and cannot verify
        // whether the user is a guest, free, or pro. Defaulting to cloud
        // allowed guest users to bypass access controls entirely.
        //
        // Only settings-disabled and offline checks are safe to make here
        // because they don't depend on auth state.
        let decision: ExtractionModeDecision
        if !settingsManager.cloudAnalysisEnabled {
            decision = .localOnly(reason: .disabledInSettings)
        } else if !networkMonitor.isOnline {
            decision = .localOnly(reason: .offline)
        } else {
            // SECURITY FIX: Do NOT default to cloudAllowed.
            // Without AccessManager context, we cannot verify auth/tier.
            // Default to localOnly to prevent unauthorized cloud access.
            logger.warning("Legacy routing path used without AccessManager decision - defaulting to localOnly for security")
            decision = .localOnly(reason: .cloudUnavailable)
        }

        return try await analyzeDocument(
            ocrResult: ocrResult,
            images: images,
            documentType: documentType,
            decision: decision
        )
    }

    // MARK: - Decision-Based Routing (Primary Path)

    func analyzeDocument(
        ocrResult: OCRResult,
        images: [UIImage],
        documentType: DocumentType,
        decision: ExtractionModeDecision
    ) async throws -> DocumentAnalysisResult {

        stats.totalRouted += 1

        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().log("Document analysis (decision-based): type=\(documentType.rawValue), decision=\(String(describing: decision))")
        Crashlytics.crashlytics().setCustomValue(documentType.rawValue, forKey: "lastDocumentType")
        #endif

        switch decision {
        case .localOnly(let reason):
            // AccessManager decided: local only
            let mode: ExtractionMode
            switch reason {
            case .offline:
                mode = .offlineFallback
                stats.localFallbacks += 1
            case .notSignedIn, .quotaExhausted, .cloudUnavailable, .disabledInSettings:
                mode = reason == .disabledInSettings ? .localOnly : .localFallback
                if reason == .disabledInSettings {
                    stats.localOnly += 1
                } else {
                    stats.localFallbacks += 1
                }
            }

            logger.info("Decision-based routing: localOnly reason=\(reason.rawValue)")

            #if canImport(FirebaseCrashlytics)
            Crashlytics.crashlytics().setCustomValue("local_\(reason.rawValue)", forKey: "lastExtractionMode")
            #endif

            var result = try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: mode
            )

            // If quota exhausted, attach rate limit info for UI banner
            if reason == .quotaExhausted {
                result = result.withExtractionMode(.rateLimitFallback)
            }

            return result

        case .cloudAllowed(let remaining):
            // AccessManager decided: cloud is allowed
            logger.info("Decision-based routing: cloudAllowed, remaining=\(remaining)")

            #if canImport(FirebaseCrashlytics)
            Crashlytics.crashlytics().log("Cloud allowed: remaining=\(remaining)")
            #endif

            // Check cloud gateway availability (auth readiness)
            let cloudAvailable = await cloudGateway.isAvailable
            guard cloudAvailable else {
                logger.info("Cloud gateway not available (auth not ready), falling back to local")
                stats.localFallbacks += 1
                return try await performLocalAnalysis(
                    ocrResult: ocrResult,
                    documentType: documentType,
                    extractionMode: .localFallback
                )
            }

            // Attempt cloud extraction with local fallback on error
            do {
                let result = try await performCloudAnalysis(
                    ocrResult: ocrResult,
                    images: images,
                    documentType: documentType
                )

                // Cloud succeeded - update backend health
                lastBackendHealth = .healthy
                lastBackendFailureAt = nil

                #if canImport(FirebaseCrashlytics)
                Crashlytics.crashlytics().setCustomValue("cloud", forKey: "lastExtractionMode")
                #endif

                return result

            } catch let error as CloudExtractionError {
                updateBackendHealth(from: error)

                #if canImport(FirebaseCrashlytics)
                Crashlytics.crashlytics().log("Cloud failed (decision-based): \(error.localizedDescription)")
                #endif

                return try await handleCloudError(
                    error: error,
                    ocrResult: ocrResult,
                    documentType: documentType
                )
            } catch {
                logger.error("Cloud analysis unexpected error: \(error.localizedDescription)")
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

    /// Updates backend health status based on error type.
    private func updateBackendHealth(from error: CloudExtractionError) {
        switch error {
        case .networkError, .timeout, .backendUnavailable:
            lastBackendHealth = .down
            lastBackendFailureAt = Date()
            logger.info("Backend marked as down, cooldown recovery in \(Self.backendHealthCooldownSeconds)s")
        case .serverError(let statusCode, _) where statusCode >= 500:
            lastBackendHealth = .degraded
        case .rateLimitExceeded:
            // Rate limit is not a backend health issue - backend is working fine
            lastBackendHealth = .healthy
            lastBackendFailureAt = nil
        default:
            break
        }
    }

    /// Handle cloud extraction errors with appropriate fallback.
    ///
    /// Rate limit errors fall back to local with upgrade banner info attached.
    /// Network errors fall back to local silently.
    private func handleCloudError(
        error: CloudExtractionError,
        ocrResult: OCRResult,
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {

        switch error {
        case .rateLimitExceeded(let used, let limit, let resetDate):
            // Rate limit exceeded from backend - fall back to local parsing.
            // Attach rate limit info so ViewModel shows upgrade banner on results.
            PrivacyLogger.cloud.warning("Cloud extraction rate limited: \(used)/\(limit), resets: \(resetDate?.description ?? "unknown"). Falling back to local with upgrade prompt.")

            #if canImport(FirebaseCrashlytics)
            Crashlytics.crashlytics().log("Rate limit exceeded: \(used)/\(limit), falling back to local")
            Crashlytics.crashlytics().setCustomValue("rate_limit_local_fallback", forKey: "lastExtractionMode")
            #endif

            stats.localFallbacks += 1

            var localResult = try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: .rateLimitFallback
            )
            localResult = localResult.withRateLimitInfo(
                RateLimitInfo(used: used, limit: limit, resetDate: resetDate)
            )
            return localResult

        case .authenticationRequired:
            // Auth not available - fall back to local.
            PrivacyLogger.cloud.info("Cloud extraction requires authentication - falling back to local")
            stats.localFallbacks += 1
            return try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: .localFallback
            )

        case .networkError, .timeout, .backendUnavailable:
            logger.warning("Cloud analysis failed due to network/backend issue, falling back to local")
            stats.localFallbacks += 1
            return try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: .localFallback
            )

        case .serverError(let statusCode, _):
            logger.warning("Cloud analysis failed with server error (\(statusCode)), falling back to local")
            stats.localFallbacks += 1
            return try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: .localFallback
            )

        case .notAvailable, .subscriptionRequired:
            logger.warning("Cloud not available or subscription required, falling back to local")
            stats.localFallbacks += 1
            return try await performLocalAnalysis(
                ocrResult: ocrResult,
                documentType: documentType,
                extractionMode: .localFallback
            )

        case .invalidResponse, .analysisIncomplete:
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

        // Run cloud extraction and local parsing in parallel.
        // Cloud provides the primary field values (high accuracy from AI).
        // Local provides candidate arrays (alternative values for user selection).
        async let cloudResultTask = cloudGateway.analyzeText(
            ocrText: ocrText,
            documentType: documentType,
            languageHints: ["pl", "en"],
            currencyHints: ["PLN", "EUR", "USD"]
        )

        // Local parsing for candidates only -- errors are non-fatal
        async let localResultTask = localCandidates(ocrResult: ocrResult, documentType: documentType)

        let cloudResult = try await cloudResultTask
        let localResult = await localResultTask

        // PRIVACY: Log success metrics only
        PrivacyLogger.cloud.info("Cloud analysis completed: hasVendor=\(cloudResult.vendorName != nil), hasAmount=\(cloudResult.amount != nil), hasDate=\(cloudResult.dueDate != nil)")

        // Merge local candidates into the cloud result
        let mergedResult = mergeLocalCandidates(localResult, into: cloudResult)

        // Return result with cloud extraction mode
        return mergedResult.withExtractionMode(.cloud)
    }

    /// Runs local parsing to generate candidate arrays for alternatives UI.
    /// Returns nil on any error -- candidates are optional enhancement.
    private func localCandidates(
        ocrResult: OCRResult,
        documentType: DocumentType
    ) async -> DocumentAnalysisResult? {
        do {
            let result = try await localService.analyzeDocument(
                ocrResult: ocrResult,
                documentType: documentType
            )
            let vc = result.vendorCandidates?.count ?? 0
            let ac = result.amountCandidates?.count ?? 0
            let dc = result.dateCandidates?.count ?? 0
            let nc = result.nipCandidates?.count ?? 0
            let bc = result.bankAccountCandidates?.count ?? 0
            let dnc = result.documentNumberCandidates?.count ?? 0
            let candidateCount = vc + ac + dc + nc + bc + dnc
            logger.info("Local candidate generation completed: \(candidateCount) total candidates")
            return result
        } catch {
            logger.warning("Local candidate generation failed (non-fatal): \(error.localizedDescription)")
            return nil
        }
    }

    /// Merges candidate arrays and evidence bounding boxes from local parsing
    /// into a cloud extraction result. Cloud field values take priority;
    /// local parsing fills in candidates and evidence that cloud doesn't provide.
    private func mergeLocalCandidates(
        _ local: DocumentAnalysisResult?,
        into cloud: DocumentAnalysisResult
    ) -> DocumentAnalysisResult {
        guard let local else { return cloud }

        return DocumentAnalysisResult(
            documentType: cloud.documentType,
            vendorName: cloud.vendorName,
            vendorAddress: cloud.vendorAddress,
            vendorNIP: cloud.vendorNIP,
            vendorREGON: cloud.vendorREGON,
            amount: cloud.amount,
            currency: cloud.currency,
            dueDate: cloud.dueDate,
            documentNumber: cloud.documentNumber,
            bankAccountNumber: cloud.bankAccountNumber,
            suggestedAmounts: cloud.suggestedAmounts.isEmpty ? local.suggestedAmounts : cloud.suggestedAmounts,
            amountCandidates: cloud.amountCandidates ?? local.amountCandidates,
            dateCandidates: cloud.dateCandidates ?? local.dateCandidates,
            vendorCandidates: cloud.vendorCandidates ?? local.vendorCandidates,
            nipCandidates: cloud.nipCandidates ?? local.nipCandidates,
            bankAccountCandidates: cloud.bankAccountCandidates ?? local.bankAccountCandidates,
            documentNumberCandidates: cloud.documentNumberCandidates ?? local.documentNumberCandidates,
            vendorEvidence: cloud.vendorEvidence ?? local.vendorEvidence,
            amountEvidence: cloud.amountEvidence ?? local.amountEvidence,
            dueDateEvidence: cloud.dueDateEvidence ?? local.dueDateEvidence,
            documentNumberEvidence: cloud.documentNumberEvidence ?? local.documentNumberEvidence,
            nipEvidence: cloud.nipEvidence ?? local.nipEvidence,
            bankAccountEvidence: cloud.bankAccountEvidence ?? local.bankAccountEvidence,
            vendorExtractionMethod: cloud.vendorExtractionMethod,
            amountExtractionMethod: cloud.amountExtractionMethod,
            dueDateExtractionMethod: cloud.dueDateExtractionMethod,
            nipExtractionMethod: cloud.nipExtractionMethod,
            overallConfidence: cloud.overallConfidence,
            fieldConfidences: cloud.fieldConfidences,
            provider: cloud.provider,
            version: cloud.version,
            extractionMode: cloud.extractionMode,
            rateLimitInfo: cloud.rateLimitInfo,
            rawHints: cloud.rawHints,
            rawOCRText: cloud.rawOCRText
        )
    }

    private func buildOCRText(from result: OCRResult) -> String {
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

    /// Returns a copy of this result with the specified rate limit info.
    func withRateLimitInfo(_ info: RateLimitInfo) -> DocumentAnalysisResult {
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
            extractionMode: extractionMode,
            rateLimitInfo: info,
            rawHints: rawHints,
            rawOCRText: rawOCRText
        )
    }

}
