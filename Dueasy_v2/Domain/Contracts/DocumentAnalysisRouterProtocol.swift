import Foundation
import UIKit

/// Routes document analysis to appropriate provider (local or cloud).
/// Implements the routing logic based on tier, settings, and document complexity.
///
/// Routing Strategy:
/// 1. Free tier: Always local analysis
/// 2. Pro tier (local-with-assist): Local first, cloud fallback on low confidence
/// 3. Pro tier (always-cloud): Cloud primary, local fallback on network failure
///
/// The router handles:
/// - Provider selection based on tier and settings
/// - Graceful fallback between providers
/// - Result merging when multiple providers are used
/// - Confidence thresholds for routing decisions
protocol DocumentAnalysisRouterProtocol: Sendable {

    /// Analyze document with automatic routing.
    /// Routes to appropriate provider(s) based on tier and settings.
    /// - Parameters:
    ///   - ocrResult: Pre-extracted OCR result with text and line data
    ///   - images: Original document images (for cloud vision if needed)
    ///   - documentType: Expected document type for parsing hints
    ///   - forceCloud: Override routing to use cloud (Pro tier only)
    /// - Returns: Best analysis result from available providers
    /// - Throws: `AppError` if all providers fail
    func analyzeDocument(
        ocrResult: OCRResult,
        images: [UIImage],
        documentType: DocumentType,
        forceCloud: Bool
    ) async throws -> DocumentAnalysisResult

    /// Current analysis mode based on tier and settings.
    var analysisMode: AnalysisMode { get }

    /// Check if cloud analysis is currently available.
    /// Returns false if not Pro, not signed in, or offline.
    var isCloudAvailable: Bool { get async }

    /// Routing statistics for debugging and analytics.
    var routingStats: RoutingStats { get }
}

// MARK: - Analysis Mode

/// Analysis mode determines routing behavior.
enum AnalysisMode: String, Sendable, Codable {
    /// Free tier - always use local parsing
    case localOnly = "local_only"

    /// Pro tier default - local first, cloud fallback on low confidence
    case localWithCloudAssist = "local_with_cloud_assist"

    /// Pro tier option - always use cloud for maximum accuracy
    case alwaysCloud = "always_cloud"

    var displayName: String {
        switch self {
        case .localOnly:
            return "Local Only"
        case .localWithCloudAssist:
            return "Smart (Local + Cloud)"
        case .alwaysCloud:
            return "Maximum Accuracy"
        }
    }

    var description: String {
        switch self {
        case .localOnly:
            return "All processing happens on your device. Fast and private."
        case .localWithCloudAssist:
            return "Uses on-device parsing first. Falls back to cloud AI when confidence is low."
        case .alwaysCloud:
            return "Always uses cloud AI for highest accuracy. Requires internet connection."
        }
    }

    /// Whether this mode requires Pro subscription
    var requiresPro: Bool {
        switch self {
        case .localOnly:
            return false
        case .localWithCloudAssist, .alwaysCloud:
            return true
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

    /// Cloud fallbacks due to low local confidence
    var cloudFallbacks: Int = 0

    /// Local fallbacks due to cloud failure
    var localFallbacks: Int = 0

    /// Average local confidence when cloud was used
    var avgLocalConfidenceBeforeCloud: Double = 0.0

    /// Cloud success rate
    var cloudSuccessRate: Double {
        guard cloudAssisted > 0 else { return 0.0 }
        return Double(cloudAssisted - localFallbacks) / Double(cloudAssisted)
    }

    /// Percentage of documents needing cloud assist
    var cloudAssistRate: Double {
        guard totalRouted > 0 else { return 0.0 }
        return Double(cloudAssisted) / Double(totalRouted)
    }
}

// MARK: - Routing Configuration

/// Configuration for routing decisions.
struct RoutingConfiguration: Sendable {

    /// Minimum local confidence to skip cloud assist
    /// Below this threshold, cloud is consulted (if available)
    var cloudAssistThreshold: Double = 0.99  // Set to 0.99 for testing - forces cloud for almost all scans

    /// Minimum confidence to consider a result usable
    /// Below this, we try another provider
    var minimumAcceptableConfidence: Double = 0.99  // Set to 0.99 for testing - forces cloud assist

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
        cloudAssistThreshold: 0.90,
        cloudTimeoutSeconds: 15.0,
        preferSpeed: true,
        retryCloudOnError: false,
        maxCloudRetries: 0
    )

    /// Accuracy-optimized configuration
    static let accurate = RoutingConfiguration(
        cloudAssistThreshold: 0.60,
        minimumAcceptableConfidence: 0.40,
        cloudTimeoutSeconds: 60.0,
        retryCloudOnError: true,
        maxCloudRetries: 3
    )
}
