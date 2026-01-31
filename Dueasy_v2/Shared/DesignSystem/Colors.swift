import SwiftUI

/// Design system color tokens.
/// Semantic colors that adapt to light/dark mode and accessibility settings.
enum AppColors {

    // MARK: - Semantic Colors

    /// Primary brand color
    static let primary = Color.accentColor

    /// Secondary color for less prominent elements
    static let secondary = Color.secondary

    /// Success state (paid, completed)
    static let success = Color.green

    /// Warning state (due soon, low confidence)
    static let warning = Color.orange

    /// Error state (overdue, failed)
    static let error = Color.red

    /// Informational state
    static let info = Color.blue

    // MARK: - Background Colors

    /// Primary background
    static let background = Color(uiColor: .systemBackground)

    /// Secondary background (cards, grouped content)
    static let secondaryBackground = Color(uiColor: .secondarySystemBackground)

    /// Tertiary background (nested cards)
    static let tertiaryBackground = Color(uiColor: .tertiarySystemBackground)

    /// Grouped background
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)

    // MARK: - Glass Effect Colors

    /// Light glass background (for glass cards in light mode)
    static let glassLight = Color.white.opacity(0.7)

    /// Dark glass background (for glass cards in dark mode)
    static let glassDark = Color.black.opacity(0.3)

    /// Glass border color
    static let glassBorder = Color.white.opacity(0.2)

    // MARK: - Document Status Colors

    /// Returns the appropriate color for a document status
    static func statusColor(for status: DocumentStatus) -> Color {
        status.color
    }

    /// Returns the appropriate color for days until due
    static func dueDateColor(daysUntilDue: Int?) -> Color {
        guard let days = daysUntilDue else { return .secondary }

        switch days {
        case ..<0:
            return error // Overdue
        case 0:
            return error // Due today
        case 1...3:
            return warning // Due soon
        default:
            return .primary // Normal
        }
    }
}

// MARK: - Color Extensions

extension Color {
    /// Creates a color from a hex string (e.g., "#FF5733" or "FF5733")
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count
        if length == 6 {
            self.init(
                red: Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x0000FF) / 255.0
            )
        } else if length == 8 {
            self.init(
                red: Double((rgb & 0xFF000000) >> 24) / 255.0,
                green: Double((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: Double((rgb & 0x0000FF00) >> 8) / 255.0,
                opacity: Double(rgb & 0x000000FF) / 255.0
            )
        } else {
            return nil
        }
    }
}
