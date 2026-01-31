import SwiftUI

/// Design system corner radius scale.
/// Consistent rounding across all UI components.
enum CornerRadius {
    /// 4pt - Minimal rounding (small buttons, tags)
    static let xs: CGFloat = 4

    /// 8pt - Small rounding (text fields, small cards)
    static let sm: CGFloat = 8

    /// 12pt - Medium rounding (cards, buttons)
    static let md: CGFloat = 12

    /// 16pt - Large rounding (large cards)
    static let lg: CGFloat = 16

    /// 20pt - Extra-large rounding (modal sheets)
    static let xl: CGFloat = 20

    /// 24pt - Maximum rounding (hero cards)
    static let xxl: CGFloat = 24

    /// Full rounding (circular elements)
    static let full: CGFloat = .infinity
}
