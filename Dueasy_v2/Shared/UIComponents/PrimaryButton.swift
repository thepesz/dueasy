import SwiftUI

/// Primary action button with consistent styling.
/// Supports loading state and disabled state.
struct PrimaryButton: View {

    let title: String
    let icon: String?
    let style: ButtonStyle
    let isLoading: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        style: ButtonStyle = .primary,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(style.foregroundColor)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                }

                Text(title)
                    .font(Typography.bodyBold)
            }
            .frame(maxWidth: style.isFullWidth ? .infinity : nil)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(style.backgroundColor)
            .foregroundStyle(style.foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        }
        .disabled(isLoading)
    }

    /// Button style options
    enum ButtonStyle {
        case primary
        case secondary
        case destructive
        case ghost

        var backgroundColor: Color {
            switch self {
            case .primary:
                return AppColors.primary
            case .secondary:
                return AppColors.secondaryBackground
            case .destructive:
                return AppColors.error
            case .ghost:
                return .clear
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary:
                return .white
            case .secondary:
                return .primary
            case .destructive:
                return .white
            case .ghost:
                return AppColors.primary
            }
        }

        var isFullWidth: Bool {
            switch self {
            case .primary, .destructive:
                return true
            case .secondary, .ghost:
                return false
            }
        }
    }
}

// MARK: - Convenience Initializers

extension PrimaryButton {
    /// Creates a secondary style button
    static func secondary(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> PrimaryButton {
        PrimaryButton(title, icon: icon, style: .secondary, isLoading: isLoading, action: action)
    }

    /// Creates a destructive style button
    static func destructive(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> PrimaryButton {
        PrimaryButton(title, icon: icon, style: .destructive, isLoading: isLoading, action: action)
    }

    /// Creates a ghost style button
    static func ghost(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> PrimaryButton {
        PrimaryButton(title, icon: icon, style: .ghost, isLoading: isLoading, action: action)
    }
}

// MARK: - Icon Button

/// Compact icon-only button
struct IconButton: View {

    let icon: String
    let size: IconButtonSize
    let action: () -> Void

    init(_ icon: String, size: IconButtonSize = .regular, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(size.font)
                .frame(width: size.dimension, height: size.dimension)
                .contentShape(Rectangle())
        }
    }

    enum IconButtonSize {
        case small
        case regular
        case large

        var font: Font {
            switch self {
            case .small: return .caption
            case .regular: return .body
            case .large: return .title3
            }
        }

        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .regular: return 44
            case .large: return 56
            }
        }
    }
}

// MARK: - Preview

#Preview("Primary Buttons") {
    VStack(spacing: Spacing.md) {
        PrimaryButton("Save & Add to Calendar", icon: "calendar.badge.plus") {}

        PrimaryButton("Loading...", isLoading: true) {}

        PrimaryButton.secondary("Cancel", icon: "xmark") {}

        PrimaryButton.destructive("Delete", icon: "trash") {}

        PrimaryButton.ghost("Learn more", icon: "questionmark.circle") {}

        HStack {
            IconButton("chevron.left") {}
            IconButton("plus", size: .large) {}
            IconButton("ellipsis") {}
        }
    }
    .padding()
}
