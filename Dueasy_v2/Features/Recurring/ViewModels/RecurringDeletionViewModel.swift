import Foundation
import Observation

/// Options for deleting a document linked to a recurring payment.
/// Scenario 1: User tries to delete a document that is matched to a recurring instance.
enum RecurringDocumentDeletionOption: String, CaseIterable, Identifiable {
    /// Unlink the document from the recurring instance and delete only this invoice.
    /// The instance reverts to "expected" status. Template and future instances remain active.
    /// Calendar events remain scheduled.
    case deleteOnlyThisInvoice

    /// Deactivate the recurring template and delete all future instances.
    /// Delete the current document (if future). Keep template in database for history.
    /// DELETE all calendar events for cancelled instances.
    case cancelRecurringPayments

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .deleteOnlyThisInvoice:
            return "doc.badge.minus"
        case .cancelRecurringPayments:
            return "calendar.badge.minus"
        }
    }

    var isDestructive: Bool {
        // Both options are destructive (delete something)
        true
    }
}

/// Options for deleting a recurring instance directly (from calendar view).
/// Scenario 2: User tries to delete a recurring instance or template from the calendar.
enum RecurringInstanceDeletionOption: String, CaseIterable, Identifiable {
    /// Delete only this specific instance (mark as cancelled).
    /// Keep the template active. Keep all other future instances.
    /// DELETE the calendar event for this instance.
    case deleteThisMonthOnly

    /// Delete all future occurrences and deactivate the template.
    /// Keep template in database for history.
    /// DELETE all calendar events for cancelled instances.
    case deleteAllFutureOccurrences

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .deleteThisMonthOnly:
            return "calendar.badge.minus"
        case .deleteAllFutureOccurrences:
            return "calendar.badge.exclamationmark"
        }
    }

    var isDestructive: Bool {
        // Both options are destructive (delete something)
        true
    }
}

/// Result of a recurring deletion operation.
struct RecurringDeletionResult: Equatable {
    let success: Bool
    let option: String
    let deletedInstanceCount: Int
    let templateDeactivated: Bool
    let documentDeleted: Bool
}

/// ViewModel for handling recurring payment deletion scenarios.
/// Delegates all business logic to Use Cases following MVVM pattern.
///
/// Handles two scenarios:
/// 1. Deleting a document linked to a recurring payment
/// 2. Deleting a recurring instance directly from calendar
@Observable
@MainActor
final class RecurringDeletionViewModel {

    // MARK: - State

    private(set) var isLoading = false
    private(set) var error: AppError?
    private(set) var lastResult: RecurringDeletionResult?

    /// The document being deleted (Scenario 1)
    private(set) var document: FinanceDocument?

    /// The instance being deleted (Scenario 2)
    private(set) var instance: RecurringInstance?

    /// The template associated with the deletion
    private(set) var template: RecurringTemplate?

    // MARK: - Dependencies

    private let unlinkDocumentUseCase: UnlinkDocumentFromRecurringUseCase
    private let deactivateTemplateUseCase: DeactivateRecurringTemplateUseCase
    private let deleteInstanceUseCase: DeleteRecurringInstanceUseCase
    private let deleteFutureInstancesUseCase: DeleteFutureRecurringInstancesUseCase
    private let deleteDocumentUseCase: DeleteDocumentUseCase
    private let templateService: RecurringTemplateServiceProtocol

    // MARK: - Initialization

    init(
        unlinkDocumentUseCase: UnlinkDocumentFromRecurringUseCase,
        deactivateTemplateUseCase: DeactivateRecurringTemplateUseCase,
        deleteInstanceUseCase: DeleteRecurringInstanceUseCase,
        deleteFutureInstancesUseCase: DeleteFutureRecurringInstancesUseCase,
        deleteDocumentUseCase: DeleteDocumentUseCase,
        templateService: RecurringTemplateServiceProtocol
    ) {
        self.unlinkDocumentUseCase = unlinkDocumentUseCase
        self.deactivateTemplateUseCase = deactivateTemplateUseCase
        self.deleteInstanceUseCase = deleteInstanceUseCase
        self.deleteFutureInstancesUseCase = deleteFutureInstancesUseCase
        self.deleteDocumentUseCase = deleteDocumentUseCase
        self.templateService = templateService
    }

    // MARK: - Setup

    /// Sets up the ViewModel for Scenario 1: deleting a document linked to recurring.
    /// - Parameters:
    ///   - document: The document to delete
    ///   - template: The recurring template (optional, will be fetched if not provided)
    func setupForDocumentDeletion(document: FinanceDocument, template: RecurringTemplate? = nil) async {
        self.document = document
        self.template = template
        self.instance = nil

        // Fetch template if not provided
        if template == nil, let templateId = document.recurringTemplateId {
            do {
                self.template = try await templateService.fetchTemplate(byId: templateId)
            } catch {
                // Template might have been deleted, continue without it
            }
        }
    }

    /// Sets up the ViewModel for Scenario 2: deleting a recurring instance.
    /// - Parameters:
    ///   - instance: The recurring instance to delete
    ///   - template: The recurring template (optional, will be fetched if not provided)
    func setupForInstanceDeletion(instance: RecurringInstance, template: RecurringTemplate? = nil) async {
        self.instance = instance
        self.template = template
        self.document = nil

        // Fetch template if not provided
        if template == nil {
            do {
                self.template = try await templateService.fetchTemplate(byId: instance.templateId)
            } catch {
                // Template might have been deleted, continue without it
            }
        }
    }

    // MARK: - Scenario 1: Document Deletion Actions

    /// Executes Scenario 1 deletion based on selected option.
    /// - Parameter option: The deletion option selected by user
    func executeDocumentDeletion(option: RecurringDocumentDeletionOption) async {
        guard let document = document else {
            error = .unknown("No document set for deletion")
            return
        }

        isLoading = true
        error = nil

        do {
            switch option {
            case .deleteOnlyThisInvoice:
                // Unlink document from instance, then delete document
                // Calendar events remain scheduled for the instance
                _ = try await unlinkDocumentUseCase.execute(document: document, deleteDocument: false)

                // Now delete the document
                try await deleteDocumentUseCase.execute(documentId: document.id)

                lastResult = RecurringDeletionResult(
                    success: true,
                    option: option.rawValue,
                    deletedInstanceCount: 0,
                    templateDeactivated: false,
                    documentDeleted: true
                )

            case .cancelRecurringPayments:
                print("🔴 CANCEL_RECURRING: Starting deletion for document \(document.id)")
                print("🔴 CANCEL_RECURRING: Document title: '\(document.title)'")
                print("🔴 CANCEL_RECURRING: Document due date: \(document.dueDate?.description ?? "nil")")

                // First unlink the document
                _ = try await unlinkDocumentUseCase.execute(document: document, deleteDocument: false)
                print("🔴 CANCEL_RECURRING: Document unlinked from recurring")

                // Deactivate template and cancel all future instances
                // This also deletes all calendar events for the instances
                let cancelledCount: Int
                if let templateId = template?.id {
                    print("🔴 CANCEL_RECURRING: Deactivating template \(templateId)")
                    cancelledCount = try await deactivateTemplateUseCase.execute(templateId: templateId)
                    print("🔴 CANCEL_RECURRING: Template deactivated, deleted \(cancelledCount) future instances")
                } else {
                    cancelledCount = 0
                    print("🔴 CANCEL_RECURRING: No template ID found")
                }

                // Always delete the current document when user chooses "Delete This Invoice and All Future"
                // User wants to delete the invoice they're looking at, regardless of its due date
                print("🔴 CANCEL_RECURRING: DELETING document \(document.id) from database")
                try await deleteDocumentUseCase.execute(documentId: document.id)
                print("🔴 CANCEL_RECURRING: Document deleted successfully")

                lastResult = RecurringDeletionResult(
                    success: true,
                    option: option.rawValue,
                    deletedInstanceCount: cancelledCount,
                    templateDeactivated: true,
                    documentDeleted: true
                )
                print("🔴 CANCEL_RECURRING: Result: success=true, documentDeleted=true, deletedInstances=\(cancelledCount)")
            }

            isLoading = false
        } catch let appError as AppError {
            error = appError
            isLoading = false
        } catch {
            self.error = .unknown(error.localizedDescription)
            isLoading = false
        }
    }

    // MARK: - Scenario 2: Instance Deletion Actions

    /// Executes Scenario 2 deletion based on selected option.
    /// - Parameter option: The deletion option selected by user
    func executeInstanceDeletion(option: RecurringInstanceDeletionOption) async {
        guard let instance = instance else {
            error = .unknown("No instance set for deletion")
            return
        }

        isLoading = true
        error = nil

        do {
            switch option {
            case .deleteThisMonthOnly:
                // Delete only this specific instance
                // This also deletes the calendar event for this instance
                _ = try await deleteInstanceUseCase.execute(instanceId: instance.id)

                lastResult = RecurringDeletionResult(
                    success: true,
                    option: option.rawValue,
                    deletedInstanceCount: 1,
                    templateDeactivated: false,
                    documentDeleted: false
                )

            case .deleteAllFutureOccurrences:
                // Delete all future occurrences and deactivate template
                // This also deletes all calendar events for the cancelled instances
                let cancelledCount = try await deleteFutureInstancesUseCase.execute(
                    templateId: instance.templateId,
                    deactivateTemplate: true
                )

                lastResult = RecurringDeletionResult(
                    success: true,
                    option: option.rawValue,
                    deletedInstanceCount: cancelledCount,
                    templateDeactivated: true,
                    documentDeleted: false
                )
            }

            isLoading = false
        } catch let appError as AppError {
            error = appError
            isLoading = false
        } catch {
            self.error = .unknown(error.localizedDescription)
            isLoading = false
        }
    }

    // MARK: - Helpers

    /// Clears the current error.
    func clearError() {
        error = nil
    }

    /// Clears all state for reuse.
    func reset() {
        document = nil
        instance = nil
        template = nil
        error = nil
        lastResult = nil
        isLoading = false
    }

    /// Whether the document has a recurring template associated.
    var hasRecurringTemplate: Bool {
        template != nil
    }

    /// The vendor name for display in the modal.
    var vendorName: String {
        template?.vendorDisplayName ?? document?.title ?? "Unknown"
    }
}
