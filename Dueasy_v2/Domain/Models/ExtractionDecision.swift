import Foundation

// MARK: - ExtractionDecision

/// Decision for how to route document extraction.
///
/// ## Routing Rules
///
/// 1. **Online + Backend Healthy** -> `.cloud`
///    - Always attempt cloud extraction first
///    - Backend enforces monthly limits
///
/// 2. **Offline OR Backend Down** -> `.offlineFallback`
///    - Use local extraction immediately
///    - No network request attempted
///
/// 3. **Rate Limit Exceeded** -> NOT handled here
///    - This is determined AFTER cloud attempt
///    - Router throws error, ViewModel shows paywall
///    - NEVER silently fall back to local
enum ExtractionDecision: Equatable, Sendable {

    /// Online and backend available - attempt cloud extraction first.
    /// This is the preferred path for best accuracy.
    case cloud

    /// Device is offline or backend is known to be down.
    /// Use local extraction immediately without network request.
    case offlineFallback
}

// MARK: - Backend Health Status

/// Health status of the cloud extraction backend.
/// Used to avoid unnecessary requests when backend is known to be down.
enum BackendHealthStatus: String, Equatable, Sendable, Codable {

    /// Backend is responding normally
    case healthy

    /// Backend is responding but with degraded performance
    case degraded

    /// Backend is not responding
    case down

    /// No health information available yet
    case unknown

    /// Whether requests should be attempted
    var shouldAttemptRequest: Bool {
        switch self {
        case .healthy, .degraded, .unknown:
            return true
        case .down:
            return false
        }
    }
}

// MARK: - Decision Function

/// Makes the extraction routing decision based on network state and backend health.
///
/// ## Decision Logic
///
/// ```
/// if networkMonitor.isOnline AND backendHealth != .down:
///     return .cloud
/// else:
///     return .offlineFallback
/// ```
///
/// ## Critical Note
///
/// This function does NOT handle rate limit decisions. Rate limits are discovered
/// AFTER a cloud request is made. When rate limit is exceeded:
/// - The router throws `CloudExtractionError.rateLimitExceeded`
/// - ViewModel catches and presents paywall
/// - NO silent fallback to local
///
/// - Parameters:
///   - isOnline: Current network connectivity status
///   - backendHealth: Last known backend health status (default: .unknown)
/// - Returns: Routing decision for the extraction request
func makeExtractionDecision(
    isOnline: Bool,
    backendHealth: BackendHealthStatus = .unknown
) -> ExtractionDecision {

    // Rule 1: Must be online
    guard isOnline else {
        return .offlineFallback
    }

    // Rule 2: Backend must not be known to be down
    guard backendHealth != .down else {
        return .offlineFallback
    }

    // All conditions met - try cloud
    return .cloud
}

// MARK: - Extraction Routing Context

/// Context for extraction routing decisions.
/// Encapsulates all factors that influence routing.
struct ExtractionRoutingContext: Sendable {

    /// Current network connectivity
    let isOnline: Bool

    /// Last known backend health status
    let backendHealth: BackendHealthStatus

    /// Whether cloud analysis is enabled in settings
    let cloudAnalysisEnabled: Bool

    /// Whether high accuracy mode is enabled (always prefer cloud)
    let highAccuracyMode: Bool

    /// Makes the extraction decision based on this context.
    func makeDecision() -> ExtractionDecision {

        // Setting override: if cloud disabled, always local
        guard cloudAnalysisEnabled else {
            return .offlineFallback
        }

        // Network and backend check
        return makeExtractionDecision(
            isOnline: isOnline,
            backendHealth: backendHealth
        )
    }
}
