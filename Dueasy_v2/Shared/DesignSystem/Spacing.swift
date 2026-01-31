import SwiftUI

/// Design system spacing scale based on 4pt grid.
/// Use these values consistently across all UI components.
enum Spacing {
    /// 4pt - Minimal spacing (tight groupings)
    static let xxs: CGFloat = 4

    /// 8pt - Small spacing (related elements)
    static let xs: CGFloat = 8

    /// 12pt - Default compact spacing
    static let sm: CGFloat = 12

    /// 16pt - Standard spacing (default margins)
    static let md: CGFloat = 16

    /// 24pt - Medium-large spacing (section separation)
    static let lg: CGFloat = 24

    /// 32pt - Large spacing (major sections)
    static let xl: CGFloat = 32

    /// 48pt - Extra-large spacing (screen-level padding)
    static let xxl: CGFloat = 48

    /// 64pt - Maximum spacing (hero sections)
    static let xxxl: CGFloat = 64
}

// MARK: - View Extensions

extension View {
    /// Applies standard horizontal padding (16pt)
    func horizontalPadding() -> some View {
        padding(.horizontal, Spacing.md)
    }

    /// Applies standard vertical padding (16pt)
    func verticalPadding() -> some View {
        padding(.vertical, Spacing.md)
    }

    /// Applies standard card padding (16pt all sides)
    func cardPadding() -> some View {
        padding(Spacing.md)
    }

    /// Applies compact card padding (12pt all sides)
    func compactCardPadding() -> some View {
        padding(Spacing.sm)
    }
}
