import Foundation

/// Gateway for cloud-based document analysis (OpenAI via Firebase).
/// This protocol defines the contract for cloud analysis providers.
///
/// Iteration 1: Mock implementation for testing.
/// Iteration 2: Firebase Functions integration with OpenAI Vision API.
///
/// ## Privacy and Consent
///
/// Cloud analysis requires **explicit user consent** via the `cloudAnalysisEnabled`
/// setting in `SettingsManager`. This setting:
/// - Defaults to `false` (local-only analysis by default)
/// - Must be explicitly enabled by the user in Settings
/// - Is clearly explained during Pro subscription onboarding
///
/// When enabled, OCR text is sent to cloud for enhanced analysis but:
/// - **NOT stored on our servers** (processed and discarded immediately)
/// - **Encrypted in transit** (TLS 1.3+)
/// - **No raw text retained** in cloud storage (only analysis results returned)
///
/// Privacy-first design:
/// - Primary: Text-only analysis (OCR text sent, images stay on device)
/// - Fallback: Cropped image snippets when text is insufficient
///
/// ## Rate Limiting and Retry
///
/// Implementations MUST handle rate limiting (HTTP 429) gracefully:
/// - Retry with exponential backoff (1s, 2s, 4s, 8s...)
/// - Maximum retry attempts configurable via `RetryConfiguration`
/// - Log rate limit events for monitoring (privacy-safe, no content)
/// - Return `CloudExtractionError.rateLimitExceeded` after max retries
protocol CloudExtractionGatewayProtocol: Sendable {

    /// Analyzes document using OCR text only (privacy-first approach).
    /// This is the preferred method - keeps images on device.
    /// - Parameters:
    ///   - ocrText: Pre-extracted OCR text from on-device Vision
    ///   - documentType: Expected document type for parsing hints
    ///   - languageHints: Language codes to assist parsing (e.g., ["pl", "en"])
    ///   - currencyHints: Currency codes expected in document (e.g., ["PLN", "EUR"])
    /// - Returns: Structured analysis result with extracted fields
    /// - Throws: `CloudExtractionError` on failure
    func analyzeText(
        ocrText: String,
        documentType: DocumentType,
        languageHints: [String],
        currencyHints: [String]
    ) async throws -> DocumentAnalysisResult

    /// Analyzes with cropped image snippets (fallback when text is insufficient).
    /// Used when text-only analysis returns low confidence and user opts in.
    /// - Parameters:
    ///   - ocrText: Pre-extracted OCR text (may be nil if OCR failed)
    ///   - croppedImages: JPEG data of cropped regions containing fields
    ///   - documentType: Expected document type for parsing hints
    ///   - languageHints: Language codes to assist parsing
    /// - Returns: Structured analysis result with extracted fields
    /// - Throws: `CloudExtractionError` on failure
    func analyzeWithImages(
        ocrText: String?,
        croppedImages: [Data],
        documentType: DocumentType,
        languageHints: [String]
    ) async throws -> DocumentAnalysisResult

    /// Check if cloud analysis is available (auth + subscription + network).
    /// Returns false if user is not signed in, not subscribed, or offline.
    var isAvailable: Bool { get async }

    /// Provider identifier for this gateway (e.g., "openai-firebase", "mock-cloud").
    var providerIdentifier: String { get }
}

// MARK: - Cloud Extraction Errors

/// Errors specific to cloud-based document extraction.
///
/// ## Rate Limit Handling
///
/// When `rateLimitExceeded` is thrown:
/// - **DO NOT** silently fall back to local extraction
/// - **DO** propagate to ViewModel for paywall presentation
/// - This preserves the monetization model
///
/// The associated values in `rateLimitExceeded` allow the UI to show:
/// - How many extractions were used
/// - What the monthly limit is
/// - When the limit resets
enum CloudExtractionError: LocalizedError {
    case notAvailable
    case authenticationRequired
    case subscriptionRequired
    case networkError(Error)

    /// Monthly extraction limit exceeded.
    /// - Parameters:
    ///   - used: Number of extractions used this month
    ///   - limit: Maximum extractions allowed for the user's tier
    ///   - resetDate: When the monthly limit resets (start of next month)
    case rateLimitExceeded(used: Int, limit: Int, resetDate: Date?)

    case serverError(statusCode: Int, message: String)
    case invalidResponse
    case timeout
    case imageUploadFailed
    case analysisIncomplete(partialResult: DocumentAnalysisResult?)
    case backendUnavailable

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Cloud analysis is not available"
        case .authenticationRequired:
            return "Sign in required for cloud analysis"
        case .subscriptionRequired:
            return "Pro subscription required for cloud analysis"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimitExceeded(let used, let limit, _):
            return "Monthly limit reached (\(used)/\(limit) extractions used)"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .timeout:
            return "Request timed out"
        case .imageUploadFailed:
            return "Failed to upload images"
        case .analysisIncomplete(let partialResult):
            if partialResult != nil {
                return "Analysis partially completed"
            }
            return "Analysis incomplete"
        case .backendUnavailable:
            return "Cloud service is temporarily unavailable"
        }
    }

    /// Whether the error is recoverable with retry.
    /// Note: Rate limit is NOT retryable - it requires user action (upgrade or wait).
    var isRetryable: Bool {
        switch self {
        case .networkError, .timeout:
            return true
        case .serverError(let statusCode, _):
            return statusCode >= 500 // Server errors may be transient
        case .rateLimitExceeded:
            // CRITICAL: Rate limit is NOT retryable
            // User must upgrade or wait for reset
            return false
        default:
            return false
        }
    }

    /// Whether this is a rate limit error (monthly limit exceeded).
    /// Used for routing decisions - must NOT fall back to local silently.
    var isRateLimitError: Bool {
        if case .rateLimitExceeded = self {
            return true
        }
        return false
    }

    /// Suggested delay before retry (in seconds).
    /// Returns nil for non-retryable errors.
    var suggestedRetryDelay: TimeInterval? {
        switch self {
        case .networkError, .timeout:
            return 1.0 // 1 second for transient network issues
        case .serverError(let statusCode, _) where statusCode >= 500:
            return 1.0
        case .rateLimitExceeded:
            // No retry delay - user action required
            return nil
        default:
            return nil
        }
    }

    /// User-facing message for rate limit errors.
    /// Includes upgrade prompt and reset date if available.
    var rateLimitMessage: String? {
        guard case .rateLimitExceeded(let used, let limit, let resetDate) = self else {
            return nil
        }

        var message = "You've used all \(limit) cloud extractions this month."

        if let reset = resetDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            message += " Your limit resets on \(formatter.string(from: reset))."
        }

        message += " Upgrade to Pro for 100 extractions/month."
        return message
    }
}

// MARK: - Retry Configuration

/// Configuration for retry behavior in cloud extraction.
/// Implements exponential backoff with jitter for optimal retry patterns.
struct CloudRetryConfiguration: Sendable {

    /// Maximum number of retry attempts (not including initial attempt).
    /// Total attempts = 1 (initial) + maxRetries
    let maxRetries: Int

    /// Base delay for exponential backoff (in seconds).
    /// Actual delay = baseDelay * 2^(attemptNumber - 1)
    let baseDelay: TimeInterval

    /// Maximum delay cap (in seconds).
    /// Prevents excessively long waits on many retries.
    let maxDelay: TimeInterval

    /// Whether to add random jitter to delays.
    /// Jitter helps prevent thundering herd when many clients retry simultaneously.
    let useJitter: Bool

    /// Default configuration: 3 retries, 1s base, 16s max, with jitter
    static let `default` = CloudRetryConfiguration(
        maxRetries: 3,
        baseDelay: 1.0,
        maxDelay: 16.0,
        useJitter: true
    )

    /// Aggressive configuration: 5 retries, 0.5s base, 32s max
    /// Use for critical operations where success is essential
    static let aggressive = CloudRetryConfiguration(
        maxRetries: 5,
        baseDelay: 0.5,
        maxDelay: 32.0,
        useJitter: true
    )

    /// Conservative configuration: 2 retries, 2s base, 8s max
    /// Use when quick feedback is more important than success
    static let conservative = CloudRetryConfiguration(
        maxRetries: 2,
        baseDelay: 2.0,
        maxDelay: 8.0,
        useJitter: true
    )

    /// Calculate delay for a given attempt number (1-indexed).
    /// - Parameter attempt: The attempt number (1 = first retry, 2 = second retry, etc.)
    /// - Returns: Delay in seconds with optional jitter
    func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        let cappedDelay = min(exponentialDelay, maxDelay)

        if useJitter {
            // Add 0-25% random jitter to prevent thundering herd
            let jitter = Double.random(in: 0...0.25)
            return cappedDelay * (1.0 + jitter)
        }

        return cappedDelay
    }
}
