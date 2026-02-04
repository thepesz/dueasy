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

    // MARK: - App-Wide Typography Hierarchy (HomeView Standard)
    //
    // These constants define the standardized typography hierarchy used across all views.
    // All views should use these constants for consistent visual hierarchy.

    /// Level 1: Section/Card Titles (e.g., "Do zaplaty w ciagu 7 dni", "Zalegle", "Cykliczne")
    /// Usage: Card headers, section titles
    static let sectionTitle = Font.system(size: 12, weight: .medium)

    /// Level 2: Body/Primary Text (e.g., "Brak nadchodzacych platnosci", empty states)
    /// Usage: Primary content text, descriptions
    static let bodyText = Font.system(size: 13)

    /// Level 3: Large Numbers/Amounts (hero amounts, overdue amounts, recurring counts)
    /// Usage: Prominent amounts, hero numbers
    static func heroNumber(design: Font.Design = .default) -> Font {
        .system(size: 24, weight: .medium, design: design).monospacedDigit()
    }

    /// Level 4: Subtitles/Secondary Info (e.g., "Wszystko oplacone", recurring subtitle)
    /// Usage: Secondary information, subtitles
    static let subtitleText = Font.system(size: 13)

    /// Level 5: Button Text (e.g., "Sprawdz", "Zarzadzaj")
    /// Usage: Button labels, CTAs
    static let buttonText = Font.system(size: 13, weight: .medium)

    /// Level 6: Section Header Icons
    /// Usage: Icons in section headers
    static let sectionIcon = Font.system(size: 12)

    /// Level 7: List Row Primary (Vendor Name)
    /// Usage: Primary text in list rows
    static let listRowPrimary = Font.system(size: 16, weight: .medium)

    /// Level 8: List Row Secondary (Due Info)
    /// Usage: Secondary text in list rows, due dates
    static let listRowSecondary = Font.system(size: 13)

    /// Level 9: List Row Amount
    /// Usage: Amounts in list rows
    static func listRowAmount(design: Font.Design = .default) -> Font {
        .system(size: 17, weight: .medium, design: design).monospacedDigit()
    }

    /// Level 10: Stat Row Labels/Values (same as caption1)
    /// Usage: Statistics, small labels
    static let stat = Font.caption

    /// Level 10b: Stat Bold (for values in stat rows)
    /// Usage: Bold stat values
    static let statBold = Font.caption.weight(.bold).monospacedDigit()
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
