import SwiftUI

/// Design system typography scale using SF Pro.
/// All text styles support Dynamic Type.
enum Typography {

    // MARK: - Display Styles

    /// Large title - 34pt Bold
    static let largeTitle = Font.largeTitle.weight(.bold)

    /// Title 1 - 28pt Bold
    static let title1 = Font.title.weight(.bold)

    /// Title 2 - 22pt Bold
    static let title2 = Font.title2.weight(.bold)

    /// Title 3 - 20pt Semibold
    static let title3 = Font.title3.weight(.semibold)

    // MARK: - Body Styles

    /// Headline - 17pt Semibold
    static let headline = Font.headline

    /// Body - 17pt Regular
    static let body = Font.body

    /// Body Bold - 17pt Semibold
    static let bodyBold = Font.body.weight(.semibold)

    /// Callout - 16pt Regular
    static let callout = Font.callout

    /// Subheadline - 15pt Regular
    static let subheadline = Font.subheadline

    // MARK: - Small Styles

    /// Footnote - 13pt Regular
    static let footnote = Font.footnote

    /// Caption 1 - 12pt Regular
    static let caption1 = Font.caption

    /// Caption 2 - 11pt Regular
    static let caption2 = Font.caption2

    // MARK: - Numeric Styles

    /// Monospaced numbers for amounts and dates
    static let monospacedBody = Font.body.monospacedDigit()

    /// Large monospaced for prominent amounts
    static let monospacedTitle = Font.title.weight(.semibold).monospacedDigit()
}

// MARK: - View Extensions

extension View {
    /// Applies body text styling with primary color
    func bodyStyle() -> some View {
        font(Typography.body)
            .foregroundStyle(.primary)
    }

    /// Applies secondary text styling
    func secondaryStyle() -> some View {
        font(Typography.subheadline)
            .foregroundStyle(.secondary)
    }

    /// Applies caption styling
    func captionStyle() -> some View {
        font(Typography.caption1)
            .foregroundStyle(.secondary)
    }
}
