import Foundation

// MARK: - ExtractionProgress

/// Progress states for document extraction workflow.
/// Used by ViewModels to communicate extraction status to the UI.
///
/// ## State Flow
///
/// ```
/// idle -> scanning -> ocrProcessing -> extracting -> parsing -> saving -> completed
///                                                                      -> failed
/// ```
///
/// ## UI Usage
///
/// Each state maps to specific UI feedback:
/// - `.idle` - No activity, ready for user action
/// - `.scanning` - Camera/scanner active
/// - `.ocrProcessing` - "Reading document..."
/// - `.extracting` - "Analyzing with AI..."
/// - `.parsing` - "Extracting fields..."
/// - `.saving` - "Saving document..."
/// - `.completed` - Success state
/// - `.failed` - Error state with recovery options
enum ExtractionProgress: Equatable, Sendable {

    /// No extraction in progress
    case idle

    /// Camera/scanner capturing document images
    case scanning

    /// Running OCR on captured images
    case ocrProcessing

    /// Analyzing document content (local or cloud AI)
    case extracting(mode: ExtractionMode?)

    /// Parsing extracted text into structured fields
    case parsing

    /// Saving document to database
    case saving

    /// Extraction completed successfully
    case completed(result: ExtractionResult)

    /// Extraction failed with error
    case failed(ExtractionFailure)

    // MARK: - Convenience Properties

    /// Whether extraction is currently in progress
    var isInProgress: Bool {
        switch self {
        case .scanning, .ocrProcessing, .extracting, .parsing, .saving:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    /// Whether the state indicates a completed extraction (success or failure)
    var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            return true
        default:
            return false
        }
    }

    /// User-facing message for current progress state
    var progressMessage: String {
        switch self {
        case .idle:
            return ""
        case .scanning:
            return "Scanning document..."
        case .ocrProcessing:
            return "Reading document..."
        case .extracting(let mode):
            switch mode {
            case .cloud:
                return "Analyzing with cloud AI..."
            case .localFallback, .offlineFallback, .localOnly, .rateLimitFallback:
                return "Analyzing locally..."
            case nil:
                return "Analyzing document..."
            }
        case .parsing:
            return "Extracting fields..."
        case .saving:
            return "Saving document..."
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        }
    }

    /// Progress percentage (0.0 to 1.0) for progress indicators
    var progressPercentage: Double {
        switch self {
        case .idle:
            return 0.0
        case .scanning:
            return 0.1
        case .ocrProcessing:
            return 0.3
        case .extracting:
            return 0.5
        case .parsing:
            return 0.7
        case .saving:
            return 0.9
        case .completed:
            return 1.0
        case .failed:
            return 0.0
        }
    }

    // MARK: - Equatable

    static func == (lhs: ExtractionProgress, rhs: ExtractionProgress) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.scanning, .scanning),
             (.ocrProcessing, .ocrProcessing),
             (.parsing, .parsing),
             (.saving, .saving):
            return true
        case (.extracting(let lhsMode), .extracting(let rhsMode)):
            return lhsMode == rhsMode
        case (.completed(let lhsResult), .completed(let rhsResult)):
            return lhsResult == rhsResult
        case (.failed(let lhsFailure), .failed(let rhsFailure)):
            return lhsFailure == rhsFailure
        default:
            return false
        }
    }
}

// MARK: - ExtractionResult

/// Result of successful extraction
struct ExtractionResult: Equatable, Sendable {

    /// How the extraction was performed
    let mode: ExtractionMode

    /// Overall confidence of the extraction
    let confidence: Double

    /// Whether any fields were extracted
    let hasExtractedFields: Bool

    /// Summary for logging (privacy-safe)
    var summary: String {
        "mode=\(mode.rawValue), confidence=\(String(format: "%.2f", confidence)), hasFields=\(hasExtractedFields)"
    }
}

// MARK: - ExtractionFailure

/// Categorized extraction failure with recovery options
struct ExtractionFailure: Equatable, Sendable {

    /// Type of failure
    let type: FailureType

    /// User-facing error message
    let message: String

    /// Underlying error (for logging)
    let underlyingError: String?

    /// Whether user can retry the operation
    let canRetry: Bool

    /// Whether paywall should be shown
    let shouldShowPaywall: Bool

    /// Rate limit details (if applicable)
    let rateLimitInfo: RateLimitInfo?

    // MARK: - Failure Types

    enum FailureType: String, Equatable, Sendable {
        case ocrFailed
        case extractionFailed
        case networkUnavailable
        case backendUnavailable
        case rateLimitExceeded
        case authenticationRequired
        case saveFailed
        case unknown
    }

    // MARK: - Factory Methods

    /// Create failure from CloudExtractionError
    static func from(_ error: CloudExtractionError) -> ExtractionFailure {
        switch error {
        case .rateLimitExceeded(let used, let limit, let resetDate):
            return ExtractionFailure(
                type: .rateLimitExceeded,
                message: error.rateLimitMessage ?? error.localizedDescription,
                underlyingError: nil,
                canRetry: false,
                shouldShowPaywall: true,
                rateLimitInfo: RateLimitInfo(used: used, limit: limit, resetDate: resetDate)
            )

        case .networkError, .timeout:
            return ExtractionFailure(
                type: .networkUnavailable,
                message: "Network unavailable. Please check your connection.",
                underlyingError: error.localizedDescription,
                canRetry: true,
                shouldShowPaywall: false,
                rateLimitInfo: nil
            )

        case .backendUnavailable:
            return ExtractionFailure(
                type: .backendUnavailable,
                message: "Cloud service is temporarily unavailable.",
                underlyingError: error.localizedDescription,
                canRetry: true,
                shouldShowPaywall: false,
                rateLimitInfo: nil
            )

        case .authenticationRequired:
            return ExtractionFailure(
                type: .authenticationRequired,
                message: "Please sign in to use cloud extraction.",
                underlyingError: nil,
                canRetry: false,
                shouldShowPaywall: false,
                rateLimitInfo: nil
            )

        default:
            return ExtractionFailure(
                type: .extractionFailed,
                message: error.localizedDescription,
                underlyingError: error.localizedDescription,
                canRetry: true,
                shouldShowPaywall: false,
                rateLimitInfo: nil
            )
        }
    }

    /// Create failure from AppError
    static func from(_ error: AppError) -> ExtractionFailure {
        switch error {
        case .ocrFailed, .ocrNoTextFound, .ocrLowConfidence:
            return ExtractionFailure(
                type: .ocrFailed,
                message: error.localizedDescription,
                underlyingError: nil,
                canRetry: true,
                shouldShowPaywall: false,
                rateLimitInfo: nil
            )

        default:
            return ExtractionFailure(
                type: .unknown,
                message: error.localizedDescription,
                underlyingError: nil,
                canRetry: true,
                shouldShowPaywall: false,
                rateLimitInfo: nil
            )
        }
    }
}

// MARK: - RateLimitInfo

/// Information about rate limit status.
/// Codable to allow inclusion in DocumentAnalysisResult for persistence/serialization.
struct RateLimitInfo: Equatable, Sendable, Codable {

    /// Number of extractions used this period
    let used: Int

    /// Maximum extractions allowed
    let limit: Int

    /// When the limit resets
    let resetDate: Date?

    /// Formatted reset date for display
    var formattedResetDate: String? {
        guard let date = resetDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    /// Remaining extractions
    var remaining: Int {
        max(0, limit - used)
    }

    /// Usage percentage (0.0 to 1.0)
    var usagePercentage: Double {
        guard limit > 0 else { return 1.0 }
        return Double(used) / Double(limit)
    }

    /// User-facing message describing the rate limit status
    var statusMessage: String {
        if remaining > 0 {
            return "\(remaining) of \(limit) AI extractions remaining this month"
        } else {
            var message = "AI extraction limit reached (\(used)/\(limit))"
            if let resetStr = formattedResetDate {
                message += ". Resets \(resetStr)"
            }
            return message
        }
    }

    /// Short status for banner display
    var bannerMessage: String {
        "AI limit reached (\(used)/\(limit)). Upgrade to continue."
    }
}
