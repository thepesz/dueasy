import OSLog

/// Privacy-first logging utility for Dueasy.
/// Provides sanitization helpers to ensure no PII (Personally Identifiable Information)
/// is ever logged. Only metrics and non-sensitive operational data should be logged.
///
/// PRIVACY PRINCIPLE: Log metrics, not data.
/// - OK to log: line counts, confidence scores, durations, success/failure rates, boolean flags
/// - NOT OK to log: vendor names, amounts, NIP numbers, addresses, dates, document content
///
/// USAGE:
/// Instead of: logger.info("Processing \(vendorName) for \(amount)")
/// Use: logger.info("Processing document: hasVendor=\(vendorName != nil), hasAmount=\(amount != nil)")
///
/// Or for dev debugging only:
/// #if DEBUG
///     logger.debug("Vendor: \(PrivacyLogger.sanitizeVendor(vendorName))")
/// #endif
enum PrivacyLogger {

    private static let subsystem = "com.dueasy.app"

    // MARK: - Debug Mode Flag

    /// Enable verbose logging in DEBUG builds only.
    /// Even in debug mode, actual values are sanitized - only metrics and redacted forms are shown.
    #if DEBUG
    static let isVerboseLoggingEnabled = true
    #else
    static let isVerboseLoggingEnabled = false
    #endif

    // MARK: - Category Loggers

    /// Logger for OCR-related operations
    static let ocr = Logger(subsystem: subsystem, category: "OCR")

    /// Logger for parsing and extraction operations
    static let parsing = Logger(subsystem: subsystem, category: "Parsing")

    /// Logger for file storage operations
    static let storage = Logger(subsystem: subsystem, category: "Storage")

    /// Logger for security-related operations
    static let security = Logger(subsystem: subsystem, category: "Security")

    /// Logger for calendar operations
    static let calendar = Logger(subsystem: subsystem, category: "Calendar")

    /// Logger for notification operations
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")

    /// Logger for vendor profile operations
    static let vendor = Logger(subsystem: subsystem, category: "Vendor")

    /// Logger for app lifecycle operations
    static let app = Logger(subsystem: subsystem, category: "App")

    /// Logger for recurring payment operations
    static let recurring = Logger(subsystem: subsystem, category: "Recurring")

    /// Logger for document operations
    static let document = Logger(subsystem: subsystem, category: "Document")

    /// Logger for cloud/backend operations
    static let cloud = Logger(subsystem: subsystem, category: "Cloud")

    /// Logger for learning/ML operations
    static let learning = Logger(subsystem: subsystem, category: "Learning")

    // MARK: - Sanitization Helpers

    /// Sanitizes an amount value, showing only that an amount exists (not the value)
    /// - Parameter amount: Optional decimal amount
    /// - Returns: Redacted string indicating presence/absence
    static func sanitizeAmount(_ amount: Decimal?) -> String {
        if amount != nil {
            return "[AMOUNT_REDACTED]"
        }
        return "nil"
    }

    /// Sanitizes a vendor name, showing only character count
    /// - Parameter vendor: Optional vendor name string
    /// - Returns: Redacted string with character count
    static func sanitizeVendor(_ vendor: String?) -> String {
        if let vendor = vendor, !vendor.isEmpty {
            return "[VENDOR:\(vendor.count)chars]"
        }
        return "nil"
    }

    /// Sanitizes a NIP (Polish tax ID), showing only last 3 digits
    /// - Parameter nip: Optional NIP string
    /// - Returns: Partially redacted NIP or "nil"
    static func sanitizeNIP(_ nip: String?) -> String {
        if let nip = nip, nip.count >= 3 {
            return "[NIP:***\(nip.suffix(3))]"
        } else if nip != nil {
            return "[NIP:***]"
        }
        return "nil"
    }

    /// Sanitizes a REGON (Polish business registry number)
    /// - Parameter regon: Optional REGON string
    /// - Returns: Redacted string indicating presence
    static func sanitizeREGON(_ regon: String?) -> String {
        if regon != nil {
            return "[REGON_REDACTED]"
        }
        return "nil"
    }

    /// Sanitizes address information
    /// - Parameter address: Optional address string
    /// - Returns: Redacted string with character count
    static func sanitizeAddress(_ address: String?) -> String {
        if let address = address, !address.isEmpty {
            return "[ADDRESS:\(address.count)chars]"
        }
        return "nil"
    }

    /// Sanitizes bank account number
    /// - Parameter account: Optional bank account string
    /// - Returns: Redacted string with length indication
    static func sanitizeBankAccount(_ account: String?) -> String {
        if let account = account, !account.isEmpty {
            return "[BANK_ACCOUNT:\(account.count)chars]"
        }
        return "nil"
    }

    /// Sanitizes document number (invoice number, etc.)
    /// - Parameter number: Optional document number
    /// - Returns: Redacted string indicating presence
    static func sanitizeDocumentNumber(_ number: String?) -> String {
        if number != nil {
            return "[DOC_NUM_REDACTED]"
        }
        return "nil"
    }

    /// Sanitizes a date value
    /// - Parameter date: Optional date
    /// - Returns: Redacted string indicating presence
    static func sanitizeDate(_ date: Date?) -> String {
        if date != nil {
            return "[DATE_REDACTED]"
        }
        return "nil"
    }

    /// Sanitizes arbitrary text content, showing only character count
    /// - Parameter text: Text to sanitize
    /// - Returns: Redacted string with character count
    static func sanitizeText(_ text: String) -> String {
        if text.isEmpty {
            return "[EMPTY]"
        }
        return "[TEXT:\(text.count)chars]"
    }

    /// Sanitizes arbitrary optional text content
    /// - Parameter text: Optional text to sanitize
    /// - Returns: Redacted string with character count or "nil"
    static func sanitizeText(_ text: String?) -> String {
        guard let text = text else { return "nil" }
        return sanitizeText(text)
    }

    /// Sanitizes a document/event title (often contains vendor info)
    /// - Parameter title: Optional title string
    /// - Returns: Redacted string with character count
    static func sanitizeTitle(_ title: String?) -> String {
        if let title = title, !title.isEmpty {
            return "[TITLE:\(title.count)chars]"
        }
        return "nil"
    }

    /// Sanitizes a vendor fingerprint hash (partial for debugging)
    /// - Parameter fingerprint: Optional fingerprint hash
    /// - Returns: Redacted string showing only prefix
    static func sanitizeFingerprint(_ fingerprint: String?) -> String {
        if let fp = fingerprint, fp.count >= 8 {
            return "[FP:\(fp.prefix(8))...]"
        } else if fingerprint != nil {
            return "[FP:***]"
        }
        return "nil"
    }

    /// Sanitizes an email address
    /// - Parameter email: Optional email string
    /// - Returns: Redacted string indicating presence
    static func sanitizeEmail(_ email: String?) -> String {
        if email != nil {
            return "[EMAIL_REDACTED]"
        }
        return "nil"
    }

    /// Sanitizes a phone number
    /// - Parameter phone: Optional phone string
    /// - Returns: Redacted string indicating presence
    static func sanitizePhone(_ phone: String?) -> String {
        if phone != nil {
            return "[PHONE_REDACTED]"
        }
        return "nil"
    }

    // MARK: - Metrics-Only Helpers

    /// Creates a metrics-only string for field presence
    /// Use this pattern: PrivacyLogger.fieldPresence(vendor: x, amount: y, date: z)
    /// - Returns: String like "hasVendor=true, hasAmount=true, hasDate=false"
    static func fieldPresence(
        vendor: String? = nil,
        amount: Decimal? = nil,
        date: Date? = nil,
        documentNumber: String? = nil,
        nip: String? = nil,
        bankAccount: String? = nil
    ) -> String {
        var parts: [String] = []

        if vendor != nil || amount != nil || date != nil || documentNumber != nil || nip != nil || bankAccount != nil {
            parts.append("hasVendor=\(vendor != nil && !vendor!.isEmpty)")
            parts.append("hasAmount=\(amount != nil)")
            parts.append("hasDate=\(date != nil)")
            parts.append("hasDocNum=\(documentNumber != nil && !documentNumber!.isEmpty)")
            parts.append("hasNIP=\(nip != nil && !nip!.isEmpty)")
            parts.append("hasBankAccount=\(bankAccount != nil && !bankAccount!.isEmpty)")
        }

        return parts.joined(separator: ", ")
    }

    /// Creates a metrics-only string for a candidate/suggestion
    /// - Parameters:
    ///   - confidence: Confidence score (0.0-1.0)
    ///   - documentCount: Number of documents
    ///   - daySpan: Number of days spanned
    /// - Returns: Safe metrics string
    static func candidateMetrics(
        confidence: Double,
        documentCount: Int,
        daySpan: Int? = nil
    ) -> String {
        var result = "confidence=\(String(format: "%.2f", confidence)), docs=\(documentCount)"
        if let span = daySpan {
            result += ", span=\(span)d"
        }
        return result
    }

    // MARK: - Metrics Logging (Safe)

    /// Logs OCR processing metrics (safe - no PII)
    /// - Parameters:
    ///   - lineCount: Number of lines detected
    ///   - confidence: Average confidence score (0.0-1.0)
    ///   - duration: Processing duration in seconds
    static func logOCRMetrics(lineCount: Int, confidence: Double, duration: TimeInterval) {
        ocr.info("OCR completed: lines=\(lineCount), avgConfidence=\(String(format: "%.2f", confidence)), duration=\(String(format: "%.2f", duration))s")
    }

    /// Logs OCR pass metrics for multi-pass OCR
    /// - Parameters:
    ///   - passName: Name of the OCR pass (e.g., "Standard", "Sensitive")
    ///   - lineCount: Number of lines detected
    ///   - confidence: Average confidence score
    static func logOCRPassMetrics(passName: String, lineCount: Int, confidence: Double) {
        ocr.info("OCR pass '\(passName)': lines=\(lineCount), avgConfidence=\(String(format: "%.3f", confidence))")
    }

    /// Logs field extraction metrics (safe - no PII)
    /// - Parameters:
    ///   - fieldType: Type of field being extracted
    ///   - extractionMethod: Method used for extraction
    ///   - confidence: Extraction confidence score
    ///   - candidatesCount: Number of candidates found
    static func logFieldExtractionMetrics(
        fieldType: String,
        extractionMethod: String,
        confidence: Double,
        candidatesCount: Int
    ) {
        parsing.info("Field extracted: type=\(fieldType), method=\(extractionMethod), confidence=\(String(format: "%.2f", confidence)), candidates=\(candidatesCount)")
    }

    /// Logs parsing completion metrics
    /// - Parameters:
    ///   - fieldsFound: Number of fields successfully extracted
    ///   - totalFields: Total number of expected fields
    ///   - confidence: Overall parsing confidence
    static func logParsingMetrics(fieldsFound: Int, totalFields: Int, confidence: Double) {
        parsing.info("Parsing completed: fields=\(fieldsFound)/\(totalFields), confidence=\(String(format: "%.2f", confidence))")
    }

    /// Logs document analysis start
    /// - Parameters:
    ///   - documentType: Type of document being analyzed
    ///   - textLength: Character count of OCR text
    ///   - lineCount: Number of lines
    static func logAnalysisStart(documentType: String, textLength: Int, lineCount: Int) {
        parsing.info("Analysis started: type=\(documentType), textLength=\(textLength), lines=\(lineCount)")
    }

    /// Logs file storage operation metrics
    /// - Parameters:
    ///   - operation: Operation type (save, load, delete)
    ///   - pageCount: Number of pages (for multi-page documents)
    ///   - success: Whether operation succeeded
    static func logStorageMetrics(operation: String, pageCount: Int, success: Bool) {
        storage.info("Storage \(operation): pages=\(pageCount), success=\(success)")
    }

    /// Logs security event (authentication, lock state changes)
    /// - Parameters:
    ///   - event: Security event type
    ///   - success: Whether event succeeded
    static func logSecurityEvent(event: String, success: Bool) {
        security.info("Security event: \(event), success=\(success)")
    }

    /// Logs permission request result
    /// - Parameters:
    ///   - permission: Permission type (calendar, notifications)
    ///   - granted: Whether permission was granted
    static func logPermissionResult(permission: String, granted: Bool) {
        app.info("Permission \(permission): granted=\(granted)")
    }
}

// MARK: - Field Type Extension

extension PrivacyLogger {
    /// Field types for logging extraction metrics
    enum FieldType: String {
        case vendor = "vendor"
        case amount = "amount"
        case dueDate = "dueDate"
        case documentNumber = "documentNumber"
        case nip = "nip"
        case regon = "regon"
        case bankAccount = "bankAccount"
        case currency = "currency"
        case address = "address"
    }
}
