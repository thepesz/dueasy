import SwiftUI

/// Design system elevation/shadow definitions.
/// Creates visual hierarchy through depth.
enum Elevation {

    // MARK: - Shadow Definitions

    /// No elevation (flat)
    static let none = ElevationStyle(
        color: .clear,
        radius: 0,
        x: 0,
        y: 0
    )

    /// Low elevation (subtle lift)
    static let low = ElevationStyle(
        color: Color.black.opacity(0.08),
        radius: 4,
        x: 0,
        y: 2
    )

    /// Medium elevation (cards, buttons)
    static let medium = ElevationStyle(
        color: Color.black.opacity(0.12),
        radius: 8,
        x: 0,
        y: 4
    )

    /// High elevation (modals, popovers)
    static let high = ElevationStyle(
        color: Color.black.opacity(0.16),
        radius: 16,
        x: 0,
        y: 8
    )

    /// Highest elevation (floating action buttons)
    static let highest = ElevationStyle(
        color: Color.black.opacity(0.20),
        radius: 24,
        x: 0,
        y: 12
    )
}

/// Style definition for elevation
struct ElevationStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Extension

extension View {
    /// Applies an elevation style to the view
    func elevation(_ style: ElevationStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
