import Foundation
import os.log

/// Use case for creating a new document.
/// Creates a draft document with the specified type.
/// Sets vendorFingerprint and documentCategory if title is provided.
struct CreateDocumentUseCase: Sendable {

    private let repository: DocumentRepositoryProtocol
    private let vendorFingerprintService: VendorFingerprintServiceProtocol
    private let classifierService: DocumentClassifierServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "CreateDocument")

    init(
        repository: DocumentRepositoryProtocol,
        vendorFingerprintService: VendorFingerprintServiceProtocol,
        classifierService: DocumentClassifierServiceProtocol
    ) {
        self.repository = repository
        self.vendorFingerprintService = vendorFingerprintService
        self.classifierService = classifierService
    }

    /// Creates a new draft document.
    /// - Parameters:
    ///   - type: Document type (invoice, contract, receipt)
    ///   - title: Optional initial title (vendor name)
    ///   - vendorNIP: Optional vendor NIP for fingerprint generation
    /// - Returns: The created document
    @MainActor
    func execute(
        type: DocumentType = .invoice,
        title: String = "",
        vendorNIP: String? = nil
    ) async throws -> FinanceDocument {
        let document = FinanceDocument(
            type: type,
            title: title,
            status: .draft
        )

        // Set vendor fingerprint if title is provided
        // This enables recurring payment detection even for manually created documents
        if !title.isEmpty {
            let fingerprint = vendorFingerprintService.generateFingerprint(
                vendorName: title,
                nip: vendorNIP
            )
            document.vendorFingerprint = fingerprint
            logger.info("Created document with vendor fingerprint: \(fingerprint.prefix(16))...")

            // Classify document category
            let classification = classifierService.classify(
                vendorName: title,
                ocrText: nil,
                amount: nil
            )
            document.documentCategoryRaw = classification.category.rawValue
            logger.info("Classified new document as category: \(classification.category.rawValue)")
        } else {
            logger.info("Created draft document without title - fingerprint will be set on finalize")
        }

        try await repository.create(document)
        return document
    }
}

// MARK: - Fetch Documents Use Case

/// Use case for fetching documents from repository
struct FetchDocumentsUseCase: Sendable {

    private let repository: DocumentRepositoryProtocol

    init(repository: DocumentRepositoryProtocol) {
        self.repository = repository
    }

    /// Fetch all documents sorted by due date
    func execute() async throws -> [FinanceDocument] {
        return try await repository.fetchAll()
    }

    /// Fetch documents filtered by status
    func execute(status: DocumentStatus) async throws -> [FinanceDocument] {
        return try await repository.fetch(byStatus: status)
    }

    /// Fetch upcoming documents (due within next N days)
    func fetchUpcoming(days: Int) async throws -> [FinanceDocument] {
        let calendar = Calendar.current
        let now = Date()
        guard let futureDate = calendar.date(byAdding: .day, value: days, to: now) else {
            return []
        }

        let allDocuments = try await repository.fetchAll()
        return allDocuments.filter { document in
            guard let dueDate = document.dueDate else { return false }
            return dueDate >= now && dueDate <= futureDate && document.status == .scheduled
        }
    }
}

// MARK: - Count Documents By Status Use Case

/// Use case for counting documents by status
struct CountDocumentsByStatusUseCase: Sendable {

    private let repository: DocumentRepositoryProtocol

    init(repository: DocumentRepositoryProtocol) {
        self.repository = repository
    }

    /// Count documents by status
    func execute(status: DocumentStatus) async throws -> Int {
        let allCounts = try await repository.countByStatus()
        return allCounts[status] ?? 0
    }

    /// Count documents for all statuses
    func executeAll() async throws -> [DocumentStatus: Int] {
        return try await repository.countByStatus()
    }

    /// Count overdue documents (past due date and not paid)
    func countOverdue() async throws -> Int {
        let allDocuments = try await repository.fetchAll()
        let now = Date()

        return allDocuments.filter { document in
            guard let dueDate = document.dueDate else { return false }
            return dueDate < now && document.status != .paid
        }.count
    }
}

// MARK: - Check Permissions Use Case

/// Use case for checking and requesting app permissions (calendar, notifications)
struct CheckPermissionsUseCase: Sendable {

    private let calendarService: CalendarServiceProtocol
    private let notificationService: NotificationServiceProtocol

    init(
        calendarService: CalendarServiceProtocol,
        notificationService: NotificationServiceProtocol
    ) {
        self.calendarService = calendarService
        self.notificationService = notificationService
    }

    /// Check current authorization status for calendar and notifications
    func checkPermissions() async -> (calendarGranted: Bool, notificationsGranted: Bool) {
        let calendarStatus = await calendarService.authorizationStatus
        let notificationStatus = await notificationService.authorizationStatus

        return (
            calendarGranted: calendarStatus.hasWriteAccess,
            notificationsGranted: notificationStatus.isAuthorized
        )
    }

    /// Request calendar permission
    func requestCalendarPermission() async -> Bool {
        return await calendarService.requestAccess()
    }

    /// Request notification permission
    func requestNotificationPermission() async -> Bool {
        return await notificationService.requestAuthorization()
    }

    /// Request both calendar and notification permissions
    func requestAllPermissions() async -> (calendarGranted: Bool, notificationsGranted: Bool) {
        let calendarGranted = await requestCalendarPermission()
        let notificationsGranted = await requestNotificationPermission()

        return (calendarGranted: calendarGranted, notificationsGranted: notificationsGranted)
    }
}
