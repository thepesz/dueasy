import SwiftUI

/// Accessibility-related view modifiers and helpers.

// MARK: - Environment Values

extension EnvironmentValues {
    /// Convenience accessor for reduce motion preference
    var prefersReducedMotion: Bool {
        accessibilityReduceMotion
    }

    /// Convenience accessor for reduce transparency preference
    var prefersReducedTransparency: Bool {
        accessibilityReduceTransparency
    }
}

// MARK: - View Modifiers

extension View {
    /// Applies animation only if user hasn't enabled Reduce Motion
    func animationIfAllowed<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(ConditionalAnimationModifier(animation: animation, value: value))
    }

    /// Provides a solid background fallback when Reduce Transparency is enabled
    func accessibleBackground(_ glassStyle: some ShapeStyle, fallback: some ShapeStyle) -> some View {
        modifier(AccessibleBackgroundModifier(glassStyle: glassStyle, fallback: fallback))
    }
}

// MARK: - Conditional Animation Modifier

struct ConditionalAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Accessible Background Modifier

struct AccessibleBackgroundModifier<GlassStyle: ShapeStyle, FallbackStyle: ShapeStyle>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let glassStyle: GlassStyle
    let fallback: FallbackStyle

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    Rectangle().fill(fallback)
                } else {
                    Rectangle().fill(glassStyle)
                }
            }
    }
}

// MARK: - Accessibility Label Helpers

extension FinanceDocument {
    /// Comprehensive accessibility label for VoiceOver
    var accessibilityDescription: String {
        var parts: [String] = []

        // Type and title
        parts.append("\(type.displayName): \(title.isEmpty ? "Untitled" : title)")

        // Amount
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        if let amountString = formatter.string(from: NSDecimalNumber(decimal: amount)) {
            parts.append(amountString)
        }

        // Status
        parts.append("Status: \(status.displayName)")

        // Due date
        if dueDate != nil {
            if let days = daysUntilDue {
                if days < 0 {
                    parts.append("\(abs(days)) days overdue")
                } else if days == 0 {
                    parts.append("Due today")
                } else if days == 1 {
                    parts.append("Due tomorrow")
                } else {
                    parts.append("Due in \(days) days")
                }
            }
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - Button Accessibility

extension PrimaryButton {
    /// Adds standard accessibility traits for buttons
    func accessibleButton(hint: String? = nil) -> some View {
        self
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(hint ?? "")
    }
}
