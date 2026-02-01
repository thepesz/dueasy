import Foundation

/// Unified error types for DuEasy application.
/// Each service domain has specific error cases with user-friendly messages.
enum AppError: LocalizedError, Equatable {

    // MARK: - File Storage Errors

    case fileStorageSaveFailed(String)
    case fileStorageLoadFailed(String)
    case fileStorageDeleteFailed(String)
    case fileStorageNotFound(String)

    // MARK: - Scanner Errors

    case scannerUnavailable
    case scannerCancelled
    case scannerFailed(String)
    case cameraPermissionDenied

    // MARK: - OCR Errors

    case ocrFailed(String)
    case ocrNoTextFound
    case ocrLowConfidence

    // MARK: - Parsing Errors

    case parsingFailed(String)
    case parsingNoDataExtracted

    // MARK: - Calendar Errors

    case calendarPermissionDenied
    case calendarAccessRestricted
    case calendarEventCreationFailed(String)
    case calendarEventUpdateFailed(String)
    case calendarEventDeletionFailed(String)
    case calendarNotFound

    // MARK: - Notification Errors

    case notificationPermissionDenied
    case notificationSchedulingFailed(String)
    case notificationCancellationFailed(String)

    // MARK: - Repository Errors

    case repositorySaveFailed(String)
    case repositoryFetchFailed(String)
    case repositoryDeleteFailed(String)
    case documentNotFound(String)

    // MARK: - Validation Errors

    case validationAmountInvalid
    case validationDueDateInPast
    case validationMissingRequiredField(String)

    // MARK: - Authentication Errors

    case authenticationRequired
    case authenticationFailed(String)

    // MARK: - Cloud Feature Errors

    case featureUnavailable(String)
    case cloudServiceUnavailable

    // MARK: - General Errors

    case unknown(String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        // File Storage
        case .fileStorageSaveFailed:
            return L10n.Errors.fileStorageSaveFailed.localized
        case .fileStorageLoadFailed:
            return L10n.Errors.fileStorageLoadFailed.localized
        case .fileStorageDeleteFailed:
            return L10n.Errors.fileStorageDeleteFailed.localized
        case .fileStorageNotFound:
            return L10n.Errors.fileStorageNotFound.localized

        // Scanner
        case .scannerUnavailable:
            return L10n.Errors.scannerUnavailable.localized
        case .scannerCancelled:
            return L10n.Errors.scannerCancelled.localized
        case .scannerFailed:
            return L10n.Errors.scannerFailed.localized
        case .cameraPermissionDenied:
            return L10n.Errors.cameraPermissionDenied.localized

        // OCR
        case .ocrFailed:
            return L10n.Errors.ocrFailed.localized
        case .ocrNoTextFound:
            return L10n.Errors.ocrNoTextFound.localized
        case .ocrLowConfidence:
            return L10n.Errors.ocrLowConfidence.localized

        // Parsing
        case .parsingFailed:
            return L10n.Errors.parsingFailed.localized
        case .parsingNoDataExtracted:
            return L10n.Errors.parsingNoData.localized

        // Calendar
        case .calendarPermissionDenied:
            return L10n.Errors.calendarPermissionDenied.localized
        case .calendarAccessRestricted:
            return L10n.Errors.calendarAccessRestricted.localized
        case .calendarEventCreationFailed:
            return L10n.Errors.calendarEventCreationFailed.localized
        case .calendarEventUpdateFailed:
            return L10n.Errors.calendarEventUpdateFailed.localized
        case .calendarEventDeletionFailed:
            return L10n.Errors.calendarEventDeletionFailed.localized
        case .calendarNotFound:
            return L10n.Errors.calendarNotFound.localized

        // Notifications
        case .notificationPermissionDenied:
            return L10n.Errors.notificationPermissionDenied.localized
        case .notificationSchedulingFailed:
            return L10n.Errors.notificationSchedulingFailed.localized
        case .notificationCancellationFailed:
            return L10n.Errors.notificationCancellationFailed.localized

        // Repository
        case .repositorySaveFailed:
            return L10n.Errors.repositorySaveFailed.localized
        case .repositoryFetchFailed:
            return L10n.Errors.repositoryFetchFailed.localized
        case .repositoryDeleteFailed:
            return L10n.Errors.repositoryDeleteFailed.localized
        case .documentNotFound:
            return L10n.Errors.documentNotFound.localized

        // Validation
        case .validationAmountInvalid:
            return L10n.Errors.validationAmountInvalid.localized
        case .validationDueDateInPast:
            return L10n.Errors.validationDueDateInPast.localized
        case .validationMissingRequiredField(let field):
            return L10n.Errors.validationMissingField.localized(with: field)

        // Authentication
        case .authenticationRequired:
            return "Authentication required"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"

        // Cloud Features
        case .featureUnavailable(let reason):
            return "Feature unavailable: \(reason)"
        case .cloudServiceUnavailable:
            return "Cloud service unavailable"

        // General
        case .unknown:
            return L10n.Errors.unknown.localized
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .cameraPermissionDenied:
            return L10n.Errors.recoveryCameraSettings.localized
        case .calendarPermissionDenied:
            return L10n.Errors.recoveryCalendarSettings.localized
        case .notificationPermissionDenied:
            return L10n.Errors.recoveryNotificationSettings.localized
        case .ocrLowConfidence, .parsingNoDataExtracted:
            return L10n.Errors.recoveryManualEntry.localized
        case .validationDueDateInPast:
            return L10n.Errors.recoveryDueDatePast.localized
        default:
            return nil
        }
    }

    /// Whether this error is recoverable through user action
    var isRecoverable: Bool {
        switch self {
        case .scannerCancelled,
             .ocrLowConfidence,
             .parsingNoDataExtracted,
             .validationDueDateInPast:
            return true
        default:
            return false
        }
    }
}
