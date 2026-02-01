import Foundation
import SwiftData

/// Core document entity for DuEasy.
/// Represents an invoice, contract, or receipt with associated metadata.
///
/// Schema includes Iteration 2 nullable fields to prevent migration pain later.
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

    /// Local file path for scanned document
    var sourceFileURL: String?

    /// Invoice/document number
    var documentNumber: String?

    /// Vendor address (street, city, postal code)
    var vendorAddress: String?

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

    // MARK: - Computed Properties

    var type: DocumentType {
        get { DocumentType(rawValue: typeRaw) ?? .invoice }
        set { typeRaw = newValue.rawValue }
    }

    var status: DocumentStatus {
        get { DocumentStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var amount: Decimal {
        get { Decimal(amountValue) }
        set { amountValue = NSDecimalNumber(decimal: newValue).doubleValue }
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
        bankAccountNumber: String? = nil,
        calendarEventId: String? = nil,
        reminderOffsetsDays: [Int] = [7, 1, 0],
        notificationsEnabled: Bool = true,
        vendorProfileId: UUID? = nil,
        remoteDocumentId: String? = nil,
        remoteFileId: String? = nil,
        analysisVersion: Int = 1,
        analysisProvider: String? = "local"
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
        self.sourceFileURL = sourceFileURL
        self.documentNumber = documentNumber
        self.vendorAddress = vendorAddress
        self.bankAccountNumber = bankAccountNumber
        self.calendarEventId = calendarEventId
        self.reminderOffsetsDays = reminderOffsetsDays
        self.notificationsEnabled = notificationsEnabled
        self.vendorProfileId = vendorProfileId
        self.remoteDocumentId = remoteDocumentId
        self.remoteFileId = remoteFileId
        self.analysisVersion = analysisVersion
        self.analysisProvider = analysisProvider
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
