import Foundation
import SwiftData

/// Core document entity for DuEasy.
/// Represents an invoice, contract, or receipt with associated metadata.
///
/// Schema includes Iteration 2 nullable fields to prevent migration pain later.
///
/// ## Path Storage Strategy
/// iOS container paths change with app updates (the UUID-based container path changes).
/// To prevent broken file references, we store only the **relative path** (filename/subdirectory)
/// and build the full URL dynamically at runtime using `FileManager.documentDirectory`.
///
/// **Example:**
/// - Stored: `"ScannedDocuments/ABC123/page_000.jpg"` (relative path)
/// - Runtime: `/var/mobile/Containers/Data/Application/{UUID}/Documents/ScannedDocuments/ABC123/page_000.jpg`
///
/// This ensures file access works after app updates when the container UUID changes.
@Model
final class FinanceDocument {

    // MARK: - Primary Fields

    /// Unique identifier
    @Attribute(.unique)
    var id: UUID

    /// Document type (invoice, contract, receipt)
    var typeRaw: String

    /// Document title or vendor name
    var title: String

    /// Total amount (stored as Double for SwiftData compatibility)
    var amountValue: Double

    /// Currency code (e.g., "PLN", "EUR", "USD")
    var currency: String

    /// Payment due date
    var dueDate: Date?

    /// Document creation timestamp
    var createdAt: Date

    /// Last modification timestamp
    var updatedAt: Date

    /// Current status (draft, scheduled, paid, archived)
    var statusRaw: String

    /// Optional notes
    var notes: String?

    /// Relative path for scanned document (filename or subdirectory path within Documents).
    /// **IMPORTANT:** This stores only the relative path, not the full absolute path.
    /// Use `resolvedSourceFileURL` to get the full runtime URL.
    /// Use `sourceFileURL` computed property for backward-compatible get/set.
    private var sourceFileRelativePath: String?

    /// Invoice/document number
    var documentNumber: String?

    /// Vendor address (street, city, postal code)
    var vendorAddress: String?

    /// Vendor NIP (Polish tax ID number)
    var vendorNIP: String?

    /// Bank account number for payment (IBAN or Polish 26-digit)
    var bankAccountNumber: String?

    // MARK: - Calendar & Notifications

    /// EventKit event identifier (if calendar event created)
    var calendarEventId: String?

    /// Reminder offsets in days before due date (e.g., [7, 1, 0])
    var reminderOffsetsDays: [Int]

    /// Whether notifications are enabled for this document
    var notificationsEnabled: Bool

    // MARK: - Iteration 2 Fields (nullable for future sync)

    /// Vendor profile ID for keyword learning and intelligent parsing
    var vendorProfileId: UUID?

    /// Remote document ID from backend (Iteration 2)
    var remoteDocumentId: String?

    /// Remote file ID from backend storage (Iteration 2)
    var remoteFileId: String?

    /// Analysis version for schema evolution (Iteration 2)
    var analysisVersion: Int

    /// Analysis provider identifier (e.g., "local", "openai", "gemini")
    var analysisProvider: String?

    // MARK: - Recurring Payment Fields

    /// Document category for recurring detection (utility, telecom, etc.)
    var documentCategoryRaw: String?

    /// Vendor fingerprint for matching recurring payments (SHA256 of normalized vendor name + NIP)
    var vendorFingerprint: String?

    /// ID of the RecurringTemplate this document is associated with (if any)
    var recurringTemplateId: UUID?

    /// ID of the RecurringInstance this document is matched to (if any)
    var recurringInstanceId: UUID?

    // MARK: - Computed Properties

    var type: DocumentType {
        get { DocumentType(rawValue: typeRaw) ?? .invoice }
        set { typeRaw = newValue.rawValue }
    }

    var status: DocumentStatus {
        get { DocumentStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    /// Document category for recurring payment detection
    var documentCategory: DocumentCategory {
        get {
            guard let raw = documentCategoryRaw else { return .unknown }
            return DocumentCategory(rawValue: raw) ?? .unknown
        }
        set { documentCategoryRaw = newValue.rawValue }
    }

    var amount: Decimal {
        get { Decimal(amountValue) }
        set { amountValue = NSDecimalNumber(decimal: newValue).doubleValue }
    }

    // MARK: - File Path Computed Properties

    /// Documents directory URL (computed fresh each time to handle container changes).
    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Full runtime URL for the source file.
    /// Builds the absolute path dynamically from the stored relative path.
    /// Returns nil if no source file is associated.
    var resolvedSourceFileURL: URL? {
        guard let relativePath = sourceFileRelativePath, !relativePath.isEmpty else {
            return nil
        }
        return Self.documentsDirectory.appendingPathComponent(relativePath)
    }

    /// Computed property for backward-compatible get/set of source file path.
    ///
    /// **Getter:** Returns the full absolute path string (built dynamically from relative path).
    /// **Setter:** Extracts and stores only the relative path from the input.
    ///
    /// This property maintains API compatibility with existing code that reads/writes
    /// full path strings, while internally storing only the relative path.
    ///
    /// **Note:** The setter handles both:
    /// - Full absolute paths (extracts path relative to Documents directory)
    /// - Relative paths (stores as-is)
    var sourceFileURL: String? {
        get {
            // Return full path for backward compatibility with file operations
            return resolvedSourceFileURL?.path
        }
        set {
            guard let newPath = newValue, !newPath.isEmpty else {
                sourceFileRelativePath = nil
                return
            }

            // Extract relative path from the input
            sourceFileRelativePath = Self.extractRelativePath(from: newPath)
        }
    }

    /// Extracts the relative path component from a full path string.
    /// Handles both absolute paths (containing Documents directory) and relative paths.
    ///
    /// **Examples:**
    /// - Input: `/var/mobile/.../Documents/ScannedDocuments/ABC123`
    ///   Output: `ScannedDocuments/ABC123`
    /// - Input: `ScannedDocuments/ABC123`
    ///   Output: `ScannedDocuments/ABC123`
    /// - Input: `/var/mobile/.../Documents/file.pdf`
    ///   Output: `file.pdf`
    private static func extractRelativePath(from path: String) -> String {
        let documentsPath = documentsDirectory.path

        // Check if the path contains the Documents directory path
        if path.hasPrefix(documentsPath) {
            // Extract everything after Documents directory
            var relativePath = String(path.dropFirst(documentsPath.count))
            // Remove leading slash if present
            if relativePath.hasPrefix("/") {
                relativePath = String(relativePath.dropFirst())
            }
            return relativePath
        }

        // Check for common iOS container path patterns and extract relative portion
        // Pattern: /var/mobile/Containers/Data/Application/{UUID}/Documents/...
        // or: /Users/.../Library/Developer/CoreSimulator/.../Documents/...
        if let range = path.range(of: "/Documents/") {
            return String(path[range.upperBound...])
        }

        // Already a relative path or unknown format - use filename as fallback
        // This handles edge cases and prevents data loss
        let url = URL(fileURLWithPath: path)
        if path.contains("/") && !path.hasPrefix("/") {
            // Looks like a relative path already
            return path
        }

        // Last resort: extract just the last path component(s)
        // For directory paths like "UUID-STRING" (our document IDs), keep the full identifier
        return url.lastPathComponent
    }

    /// Whether this document is overdue
    var isOverdue: Bool {
        guard let dueDate = dueDate, status != .paid else { return false }
        return dueDate < Date()
    }

    /// Days until due date (negative if overdue)
    var daysUntilDue: Int? {
        guard let dueDate = dueDate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: dueDate))
        return components.day
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        type: DocumentType = .invoice,
        title: String = "",
        amount: Decimal = 0,
        currency: String = "PLN",
        dueDate: Date? = nil,
        status: DocumentStatus = .draft,
        notes: String? = nil,
        sourceFileURL: String? = nil,
        documentNumber: String? = nil,
        vendorAddress: String? = nil,
        vendorNIP: String? = nil,
        bankAccountNumber: String? = nil,
        calendarEventId: String? = nil,
        reminderOffsetsDays: [Int] = [7, 1, 0],
        notificationsEnabled: Bool = true,
        vendorProfileId: UUID? = nil,
        remoteDocumentId: String? = nil,
        remoteFileId: String? = nil,
        analysisVersion: Int = 1,
        analysisProvider: String? = "local",
        documentCategory: DocumentCategory = .unknown,
        vendorFingerprint: String? = nil,
        recurringTemplateId: UUID? = nil,
        recurringInstanceId: UUID? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.title = title
        self.amountValue = NSDecimalNumber(decimal: amount).doubleValue
        self.currency = currency
        self.dueDate = dueDate
        self.createdAt = Date()
        self.updatedAt = Date()
        self.statusRaw = status.rawValue
        self.notes = notes
        // Extract relative path from input (handles both absolute and relative paths)
        if let path = sourceFileURL, !path.isEmpty {
            self.sourceFileRelativePath = Self.extractRelativePath(from: path)
        } else {
            self.sourceFileRelativePath = nil
        }
        self.documentNumber = documentNumber
        self.vendorAddress = vendorAddress
        self.vendorNIP = vendorNIP
        self.bankAccountNumber = bankAccountNumber
        self.calendarEventId = calendarEventId
        self.reminderOffsetsDays = reminderOffsetsDays
        self.notificationsEnabled = notificationsEnabled
        self.vendorProfileId = vendorProfileId
        self.remoteDocumentId = remoteDocumentId
        self.remoteFileId = remoteFileId
        self.analysisVersion = analysisVersion
        self.analysisProvider = analysisProvider
        self.documentCategoryRaw = documentCategory.rawValue
        self.vendorFingerprint = vendorFingerprint
        self.recurringTemplateId = recurringTemplateId
        self.recurringInstanceId = recurringInstanceId
    }

    // MARK: - Update Methods

    /// Marks the document as updated (sets updatedAt timestamp)
    func markUpdated() {
        updatedAt = Date()
    }

    /// Applies analysis result to this document
    func applyAnalysisResult(_ result: DocumentAnalysisResult) {
        if let vendorName = result.vendorName, !vendorName.isEmpty {
            title = vendorName
        }
        if let vendorAddress = result.vendorAddress, !vendorAddress.isEmpty {
            self.vendorAddress = vendorAddress
        }
        if let vendorNIP = result.vendorNIP, !vendorNIP.isEmpty {
            self.vendorNIP = vendorNIP
        }
        if let amount = result.amount {
            self.amount = amount
        }
        if let currency = result.currency, !currency.isEmpty {
            self.currency = currency
        }
        if let dueDate = result.dueDate {
            self.dueDate = dueDate
        }
        if let documentNumber = result.documentNumber, !documentNumber.isEmpty {
            self.documentNumber = documentNumber
        }
        if let bankAccountNumber = result.bankAccountNumber, !bankAccountNumber.isEmpty {
            self.bankAccountNumber = bankAccountNumber
        }
        analysisVersion = result.version
        analysisProvider = result.provider
        markUpdated()
    }
}

// MARK: - Identifiable
// Note: Hashable and Equatable are synthesized by @Model macro
