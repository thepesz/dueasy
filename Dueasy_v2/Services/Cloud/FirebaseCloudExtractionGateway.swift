import Foundation
import SwiftData
import os

#if canImport(UIKit)
import UIKit
#endif

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

/// Firebase Cloud Functions gateway for OpenAI-powered document analysis.
///
/// ## Rate Limiting and Retry
///
/// This gateway implements exponential backoff retry for transient errors:
/// - HTTP 429 (Too Many Requests) - rate limit exceeded
/// - HTTP 5xx (Server Errors) - transient server issues
/// - Network timeouts
///
/// Retry behavior is controlled by `CloudRetryConfiguration`:
/// - Default: 3 retries with 1s, 2s, 4s delays
/// - Jitter added to prevent thundering herd
/// - Privacy-safe logging of retry events
final class FirebaseCloudExtractionGateway: CloudExtractionGatewayProtocol {

    // MARK: - Properties

    #if canImport(FirebaseFunctions)
    private let functions: Functions
    #endif

    private let authService: AuthServiceProtocol
    private let retryConfig: CloudRetryConfiguration
    private let logger = Logger(subsystem: "com.dueasy.app", category: "CloudExtraction")

    // MARK: - Initialization

    init(
        authService: AuthServiceProtocol,
        retryConfig: CloudRetryConfiguration = .default
    ) {
        self.authService = authService
        self.retryConfig = retryConfig
        #if canImport(FirebaseFunctions)
        // Use Europe region for GDPR compliance - functions deployed to europe-west1
        self.functions = Functions.functions(region: "europe-west1")
        // self.functions.useEmulator(withHost: "localhost", port: 5001) // Development only
        #endif
    }

    // MARK: - CloudExtractionGatewayProtocol

    var providerIdentifier: String {
        return "openai-firebase"
    }

    var isAvailable: Bool {
        get async {
            #if canImport(FirebaseFunctions)
            return await authService.isSignedIn
            #else
            return false
            #endif
        }
    }

    func analyzeText(
        ocrText: String,
        documentType: DocumentType,
        languageHints: [String],
        currencyHints: [String]
    ) async throws -> DocumentAnalysisResult {
        #if canImport(FirebaseFunctions)
        let isSignedIn = await authService.isSignedIn

        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().log("🔑 Firebase auth check: signedIn=\(isSignedIn)")
        Crashlytics.crashlytics().setCustomValue(isSignedIn, forKey: "firebaseAuthSignedIn")
        #endif

        guard isSignedIn else {
            #if canImport(FirebaseCrashlytics)
            Crashlytics.crashlytics().log("⚠️ Auth required: User not signed in with Apple")
            #endif
            throw CloudExtractionError.authenticationRequired
        }

        let payload: [String: Any] = [
            "ocrText": ocrText,
            "documentType": documentType.rawValue,
            "languageHints": languageHints,
            "currencyHints": currencyHints,
            "mode": "textOnly"
        ]

        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().log("📡 Calling Firebase function: analyzeDocument")
        #endif

        // Use retry wrapper for resilient API calls
        return try await executeWithRetry(functionName: "analyzeDocument", payload: payload)
        #else
        throw AppError.featureUnavailable("Firebase SDK not available")
        #endif
    }

    // MARK: - Retry Logic

    #if canImport(FirebaseFunctions)
    /// Executes a Firebase Function call with exponential backoff retry.
    ///
    /// Handles the following transient errors:
    /// - Rate limiting (HTTP 429 / FunctionsErrorCode.resourceExhausted)
    /// - Server errors (HTTP 5xx / FunctionsErrorCode.internal, .unavailable)
    /// - Network timeouts
    ///
    /// - Parameters:
    ///   - functionName: Name of the Firebase Function to call
    ///   - payload: Request payload dictionary
    /// - Returns: Parsed `DocumentAnalysisResult`
    /// - Throws: `CloudExtractionError` after max retries or on non-retryable errors
    private func executeWithRetry(
        functionName: String,
        payload: [String: Any]
    ) async throws -> DocumentAnalysisResult {

        var lastError: Error?
        var attempt = 0

        // Total attempts = 1 (initial) + maxRetries
        let totalAttempts = 1 + retryConfig.maxRetries

        while attempt < totalAttempts {
            attempt += 1

            do {
                let result = try await functions.httpsCallable(functionName).call(payload)

                // PRIVACY: Log success metrics only
                if attempt > 1 {
                    PrivacyLogger.cloud.info("Cloud extraction succeeded after \(attempt) attempts")
                }

                return try parseAnalysisResult(from: result.data)

            } catch {
                lastError = error
                let cloudError = mapFirebaseError(error)

                // Check if error is retryable
                guard cloudError.isRetryable else {
                    // PRIVACY: Log error type, not content
                    PrivacyLogger.cloud.warning("Cloud extraction failed with non-retryable error: type=\(String(describing: type(of: cloudError)))")
                    throw cloudError
                }

                // Check if we have retries left
                guard attempt < totalAttempts else {
                    // PRIVACY: Log final failure without sensitive data
                    PrivacyLogger.cloud.error("Cloud extraction failed after \(attempt) attempts, error type=\(String(describing: type(of: cloudError)))")
                    throw cloudError
                }

                // Calculate delay with exponential backoff
                let delay = retryConfig.delay(forAttempt: attempt)

                // PRIVACY: Log retry event without sensitive data
                PrivacyLogger.cloud.info("Cloud extraction retry: attempt=\(attempt)/\(totalAttempts), delay=\(String(format: "%.2f", delay))s, errorType=\(cloudError.isRateLimitError ? "rateLimit" : "transient")")

                // Wait before retry
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // Should not reach here, but handle edge case
        throw lastError.map { mapFirebaseError($0) } ?? CloudExtractionError.invalidResponse
    }

    /// Maps Firebase Functions errors to CloudExtractionError.
    /// Handles FunctionsErrorCode cases for proper retry classification.
    ///
    /// ## Rate Limit Response Format
    ///
    /// Backend returns rate limit info in error details:
    /// ```json
    /// {
    ///   "used": 3,
    ///   "limit": 3,
    ///   "resetDate": "2024-02-01T00:00:00Z"
    /// }
    /// ```
    private func mapFirebaseError(_ error: Error) -> CloudExtractionError {
        // Check for Firebase Functions specific errors
        let nsError = error as NSError

        // Firebase Functions errors have domain "com.firebase.functions"
        if nsError.domain == "com.firebase.functions" || nsError.domain.contains("FIRFunctions") {
            // FunctionsErrorCode raw values:
            // 8 = resourceExhausted (429 rate limit)
            // 13 = internal (500)
            // 14 = unavailable (503)
            // 4 = deadlineExceeded (timeout)
            switch nsError.code {
            case 8: // resourceExhausted - Rate limit
                // Extract rate limit details from error userInfo if available
                let rateLimitInfo = extractRateLimitInfo(from: nsError)
                return .rateLimitExceeded(
                    used: rateLimitInfo.used,
                    limit: rateLimitInfo.limit,
                    resetDate: rateLimitInfo.resetDate
                )
            case 4: // deadlineExceeded - Timeout
                return .timeout
            case 13, 14: // internal, unavailable - Server errors
                return .serverError(statusCode: nsError.code == 13 ? 500 : 503, message: nsError.localizedDescription)
            case 16: // unauthenticated
                return .authenticationRequired
            case 7: // permissionDenied
                return .subscriptionRequired
            default:
                // Check if it's a network-related error
                if nsError.localizedDescription.lowercased().contains("network") ||
                   nsError.localizedDescription.lowercased().contains("connection") {
                    return .networkError(error)
                }
                return .serverError(statusCode: nsError.code, message: nsError.localizedDescription)
            }
        }

        // Handle URLError for network issues
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkError(error)
            default:
                return .networkError(error)
            }
        }

        // Generic error mapping
        if nsError.domain == NSURLErrorDomain {
            return .networkError(error)
        }

        return .serverError(statusCode: -1, message: error.localizedDescription)
    }

    /// Extracts rate limit info from Firebase error userInfo.
    /// Falls back to defaults if info not available.
    private func extractRateLimitInfo(from error: NSError) -> (used: Int, limit: Int, resetDate: Date?) {
        // Firebase error details may be in userInfo under "details" key
        var used = 0
        var limit = 3 // Default to free tier limit
        var resetDate: Date?

        // Try to extract from userInfo
        if let details = error.userInfo["details"] as? [String: Any] {
            if let usedCount = details["used"] as? Int {
                used = usedCount
            }
            if let limitCount = details["limit"] as? Int {
                limit = limitCount
            }
            if let resetString = details["resetDate"] as? String {
                // Parse ISO8601 date
                let formatter = ISO8601DateFormatter()
                resetDate = formatter.date(from: resetString)
            }
        }

        // If we couldn't extract used, but have a limit, assume they've used all
        if used == 0 && limit > 0 {
            used = limit
        }

        // If no reset date, calculate start of next month
        if resetDate == nil {
            resetDate = calculateNextMonthStart()
        }

        return (used, limit, resetDate)
    }

    /// Calculates the start of next month for rate limit reset.
    private func calculateNextMonthStart() -> Date {
        let calendar = Calendar.current
        let now = Date()
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: now),
              let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth))
        else {
            // Fallback: return 30 days from now
            return calendar.date(byAdding: .day, value: 30, to: now) ?? now
        }
        return startOfMonth
    }
    #endif

    // MARK: - Private Helpers

    #if canImport(FirebaseFunctions)
    private func parseAnalysisResult(from data: Any) throws -> DocumentAnalysisResult {
        guard let dict = data as? [String: Any] else {
            throw CloudExtractionError.invalidResponse
        }

        // Extract main fields
        let vendorName = dict["vendorName"] as? String
        let vendorAddress = dict["vendorAddress"] as? String
        let vendorNIP = dict["vendorNIP"] as? String
        let vendorREGON = dict["vendorREGON"] as? String
        let documentNumber = dict["documentNumber"] as? String
        let bankAccountNumber = dict["bankAccount"] as? String
        let currency = dict["currency"] as? String ?? "PLN"

        // PRIVACY: Log only metrics, not actual data
        PrivacyLogger.cloud.info("OpenAI extraction: hasVendor=\(vendorName != nil), hasAddress=\(vendorAddress != nil), hasNIP=\(vendorNIP != nil)")

        // Extract document type
        let documentTypeStr = dict["documentType"] as? String ?? "invoice"
        let documentType = DocumentType(rawValue: documentTypeStr) ?? .invoice

        // Parse amount
        var amount: Decimal?
        if let amountStr = dict["amount"] as? String {
            amount = Decimal(string: amountStr)
        } else if let amountDouble = dict["amount"] as? Double {
            amount = Decimal(amountDouble)
        }

        // Parse issue date (ISO 8601 format: YYYY-MM-DD)
        var issueDate: Date?
        if let issueDateStr = dict["issueDate"] as? String, !issueDateStr.isEmpty {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            issueDate = isoFormatter.date(from: issueDateStr)
        }

        // Parse due date (ISO 8601 format: YYYY-MM-DD)
        var dueDate: Date?
        if let dueDateStr = dict["dueDate"] as? String, !dueDateStr.isEmpty {
            // PRIVACY: Log only that we received a date, not the actual value
            PrivacyLogger.cloud.debug("OpenAI returned dueDate string (length=\(dueDateStr.count))")

            // Try ISO 8601 format first (YYYY-MM-DD)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            if let parsed = isoFormatter.date(from: dueDateStr) {
                dueDate = parsed
                PrivacyLogger.cloud.debug("Parsed dueDate with ISO8601 format")
            } else {
                // Fallback: try standard date formatter with multiple formats
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")

                for format in ["yyyy-MM-dd", "dd-MM-yyyy", "dd.MM.yyyy", "yyyy/MM/dd"] {
                    dateFormatter.dateFormat = format
                    if let parsed = dateFormatter.date(from: dueDateStr) {
                        dueDate = parsed
                        PrivacyLogger.cloud.debug("Parsed dueDate with format: \(format)")
                        break
                    }
                }

                if dueDate == nil {
                    PrivacyLogger.cloud.warning("Failed to parse dueDate from OpenAI response")
                }
            }
        } else {
            PrivacyLogger.cloud.debug("OpenAI returned null/empty dueDate")
            // Fallback: If no due date, use issue date (invoice might be already paid)
            if let issueDate = issueDate {
                dueDate = issueDate
                PrivacyLogger.cloud.debug("Using issue date as due date fallback")
            }
        }

        // Extract candidate arrays from OpenAI
        let amountCandidatesArray = dict["amountCandidates"] as? [[String: Any]] ?? []
        let dateCandidatesArray = dict["dateCandidates"] as? [[String: Any]] ?? []
        let vendorCandidatesArray = dict["vendorCandidates"] as? [[String: Any]] ?? []
        let nipCandidatesArray = dict["nipCandidates"] as? [[String: Any]] ?? []

        // Build suggestedAmounts from OpenAI amount candidates (without provider text)
        var suggestedAmounts: [(Decimal, String)] = []
        for candidate in amountCandidatesArray {
            if let displayValue = candidate["displayValue"] as? String,
               let amount = Decimal(string: displayValue) {
                // Just use empty context - no provider/confidence text needed
                suggestedAmounts.append((amount, ""))
            }
        }

        // If no candidates but we have a main amount, add it
        if suggestedAmounts.isEmpty, let amount = amount {
            suggestedAmounts.append((amount, ""))
        }

        // Calculate field confidences from candidates
        let vendorConfidence = vendorCandidatesArray.first?["confidence"] as? Double ?? (vendorName != nil ? 0.95 : 0.0)
        let amountConfidence = amountCandidatesArray.first?["confidence"] as? Double ?? (amount != nil ? 0.95 : 0.0)
        let dateConfidence = dateCandidatesArray.first?["confidence"] as? Double ?? (dueDate != nil ? 0.95 : 0.0)
        let nipConfidence = nipCandidatesArray.first?["confidence"] as? Double ?? (vendorNIP != nil ? 0.95 : 0.0)

        let fieldConfidences = FieldConfidences(
            vendorName: vendorConfidence,
            amount: amountConfidence,
            dueDate: dateConfidence,
            documentNumber: documentNumber != nil ? 0.90 : 0.0,
            nip: nipConfidence,
            bankAccount: bankAccountNumber != nil ? 0.85 : 0.0
        )

        // Calculate overall confidence as average of non-zero field confidences
        let allConfidences = [vendorConfidence, amountConfidence, dateConfidence, nipConfidence]
            .filter { $0 > 0.0 }
        let overallConfidence = allConfidences.isEmpty ? 0.0 : allConfidences.reduce(0.0, +) / Double(allConfidences.count)

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
            amountCandidates: nil, // Cloud AI doesn't provide full candidate structures
            dateCandidates: nil,
            vendorCandidates: nil,
            nipCandidates: nil,
            bankAccountCandidates: nil,
            documentNumberCandidates: nil,
            vendorEvidence: nil, // No bounding boxes from cloud AI
            amountEvidence: nil,
            dueDateEvidence: nil,
            documentNumberEvidence: nil,
            nipEvidence: nil,
            bankAccountEvidence: nil,
            vendorExtractionMethod: .cloudAI,
            amountExtractionMethod: .cloudAI,
            dueDateExtractionMethod: .cloudAI,
            nipExtractionMethod: .cloudAI,
            overallConfidence: overallConfidence,
            fieldConfidences: fieldConfidences,
            provider: "openai-gpt4o",
            version: 1,
            rawOCRText: nil
        )
    }
    #endif
}
