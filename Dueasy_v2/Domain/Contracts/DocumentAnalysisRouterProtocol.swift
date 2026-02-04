import Foundation
import UIKit

/// Routes document analysis to appropriate provider (local or cloud).
///
/// ## Routing Strategy (Cloud-First for All Users)
///
/// Both Free and Pro users follow the same cloud-first routing logic:
/// 1. **If online and backend available**: Try cloud extraction first
///    - Backend enforces monthly limits (Free: 3/month, Pro: 100/month)
///    - If limit exceeded: propagate rate limit error to UI
/// 2. **If offline or backend error (not rate limit)**: Fall back to local analysis
/// 3. **If cloud analysis disabled in settings**: Use local-only
///
/// ## Key Design Decisions
///
/// - **NO client-side monthly limit enforcement** - Backend is source of truth
/// - **Free tier gets cloud extraction** (within backend-enforced limits)
/// - **Graceful degradation** to local when offline/backend errors
/// - **Rate limit errors propagate** to UI (not silent fallback)
///
/// ## ExtractionMode Tracking
///
/// Results include `extractionMode` field:
/// - `.cloud` - Cloud AI extraction succeeded
/// - `.localFallback` - Backend error caused fallback
/// - `.offlineFallback` - Device offline
/// - `.localOnly` - Cloud disabled in settings
protocol DocumentAnalysisRouterProtocol: Sendable {

    /// Analyze document with automatic routing.
    /// Routes to appropriate provider(s) based on settings and availability.
    /// - Parameters:
    ///   - ocrResult: Pre-extracted OCR result with text and line data
    ///   - images: Original document images (for cloud vision if needed)
    ///   - documentType: Expected document type for parsing hints
    ///   - forceCloud: Override routing to use cloud (ignored if offline)
    /// - Returns: Best analysis result from available providers
    /// - Throws: `CloudExtractionError.rateLimitExceeded` if monthly limit exceeded,
    ///           `CloudExtractionError.authenticationRequired` if sign-in needed,
    ///           `AppError` if all providers fail
    func analyzeDocument(
        ocrResult: OCRResult,
        images: [UIImage],
        documentType: DocumentType,
        forceCloud: Bool
    ) async throws -> DocumentAnalysisResult

    /// Current analysis mode based on settings.
    var analysisMode: AnalysisMode { get }

    /// Check if cloud analysis is currently available.
    /// Returns false if not signed in or offline.
    var isCloudAvailable: Bool { get async }

    /// Routing statistics for debugging and analytics.
    var routingStats: RoutingStats { get }
}

// MARK: - Analysis Mode

/// Analysis mode determines routing behavior.
/// Note: Cloud extraction is available to ALL users (within backend-enforced limits).
enum AnalysisMode: String, Sendable, Codable {

    /// Local-only parsing (cloud disabled in settings)
    case localOnly = "local_only"

    /// Cloud-first with local fallback (default for all users)
    /// Tries cloud extraction first, falls back to local on errors.
    /// Backend enforces monthly limits (Free: 3, Pro: 100).
    case cloudWithLocalFallback = "cloud_with_local_fallback"

    /// Always use cloud for maximum accuracy.
    /// Falls back to local only if offline.
    case alwaysCloud = "always_cloud"

    var displayName: String {
        switch self {
        case .localOnly:
            return "Local Only"
        case .cloudWithLocalFallback:
            return "Smart (Cloud + Local)"
        case .alwaysCloud:
            return "Maximum Accuracy"
        }
    }

    var description: String {
        switch self {
        case .localOnly:
            return "All processing happens on your device. Fast and private."
        case .cloudWithLocalFallback:
            return "Uses cloud AI for best accuracy. Falls back to on-device when offline."
        case .alwaysCloud:
            return "Always uses cloud AI for highest accuracy. Requires internet connection."
        }
    }
}

// MARK: - Routing Stats

/// Statistics for routing decisions (for debugging/analytics).
struct RoutingStats: Sendable {
    /// Total documents routed
    var totalRouted: Int = 0

    /// Documents analyzed locally only
    var localOnly: Int = 0

    /// Documents analyzed with cloud
    var cloudAssisted: Int = 0

    /// Cloud fallbacks due to low local confidence (deprecated - kept for compatibility)
    var cloudFallbacks: Int = 0

    /// Local fallbacks due to cloud failure
    var localFallbacks: Int = 0

    /// Average local confidence when cloud was used (deprecated - kept for compatibility)
    var avgLocalConfidenceBeforeCloud: Double = 0.0

    /// Cloud success rate
    var cloudSuccessRate: Double {
        guard cloudAssisted > 0 else { return 0.0 }
        return Double(cloudAssisted - localFallbacks) / Double(cloudAssisted)
    }

    /// Percentage of documents using cloud
    var cloudAssistRate: Double {
        guard totalRouted > 0 else { return 0.0 }
        return Double(cloudAssisted) / Double(totalRouted)
    }
}

// MARK: - Routing Configuration

/// Configuration for routing decisions.
struct RoutingConfiguration: Sendable {

    /// Minimum local confidence to skip cloud assist (deprecated - cloud-first routing)
    var cloudAssistThreshold: Double = 0.99

    /// Minimum confidence to consider a result usable (deprecated - cloud-first routing)
    var minimumAcceptableConfidence: Double = 0.99

    /// Maximum wait time for cloud analysis before falling back
    var cloudTimeoutSeconds: TimeInterval = 30.0

    /// Whether to prefer speed over accuracy
    var preferSpeed: Bool = false

    /// Whether to retry cloud on transient errors
    var retryCloudOnError: Bool = true

    /// Maximum cloud retries
    var maxCloudRetries: Int = 2

    /// Default configuration
    static let `default` = RoutingConfiguration()

    /// Speed-optimized configuration
    static let fast = RoutingConfiguration(
        cloudTimeoutSeconds: 15.0,
        preferSpeed: true,
        retryCloudOnError: false,
        maxCloudRetries: 0
    )

    /// Accuracy-optimized configuration
    static let accurate = RoutingConfiguration(
        cloudTimeoutSeconds: 60.0,
        retryCloudOnError: true,
        maxCloudRetries: 3
    )
}
