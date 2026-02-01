import Foundation

/// Methods for adding documents to the app.
/// Each method has different flows and capabilities.
enum DocumentInputMethod: String, CaseIterable, Identifiable {
    /// Camera-based document scanning via VisionKit
    /// - Automatic edge detection and perspective correction
    /// - Optimal quality for OCR
    case scan

    /// Import PDF file from Files app
    /// - Extracts pages as images for analysis
    /// - Supports multi-page PDFs
    case importPDF

    /// Import photo from photo library
    /// - Analyze existing photo of document
    /// - May have lower OCR quality than scan
    case importPhoto

    /// Manual entry without scanning
    /// - User fills in all fields manually
    /// - No OCR/analysis performed
    case manualEntry

    var id: String { rawValue }

    /// Display name for UI (localized)
    var displayName: String {
        switch self {
        case .scan:
            return L10n.AddDocument.InputMethod.scan.localized
        case .importPDF:
            return L10n.AddDocument.InputMethod.importPDF.localized
        case .importPhoto:
            return L10n.AddDocument.InputMethod.importPhoto.localized
        case .manualEntry:
            return L10n.AddDocument.InputMethod.manualEntry.localized
        }
    }

    /// Description text for UI (localized)
    var description: String {
        switch self {
        case .scan:
            return L10n.AddDocument.InputMethod.scanDescription.localized
        case .importPDF:
            return L10n.AddDocument.InputMethod.importPDFDescription.localized
        case .importPhoto:
            return L10n.AddDocument.InputMethod.importPhotoDescription.localized
        case .manualEntry:
            return L10n.AddDocument.InputMethod.manualEntryDescription.localized
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .scan:
            return "doc.text.viewfinder"
        case .importPDF:
            return "doc.fill"
        case .importPhoto:
            return "photo.on.rectangle"
        case .manualEntry:
            return "square.and.pencil"
        }
    }

    /// Whether this method performs automatic analysis
    var performsAnalysis: Bool {
        switch self {
        case .scan, .importPDF, .importPhoto:
            return true
        case .manualEntry:
            return false
        }
    }

    /// Whether this method is recommended (best quality)
    var isRecommended: Bool {
        self == .scan
    }
}
