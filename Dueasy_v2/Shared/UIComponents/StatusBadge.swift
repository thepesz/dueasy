import SwiftUI

/// Badge component displaying document status with icon and color.
struct StatusBadge: View {

    let status: DocumentStatus
    let size: BadgeSize

    init(status: DocumentStatus, size: BadgeSize = .regular) {
        self.status = status
        self.size = size
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            Image(systemName: status.iconName)
                .font(size.iconFont)

            Text(status.displayName)
                .font(size.textFont)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(status.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

/// Badge size options
enum BadgeSize {
    case small
    case regular
    case large

    var iconFont: Font {
        switch self {
        case .small: return .caption2
        case .regular: return .caption
        case .large: return .subheadline
        }
    }

    var textFont: Font {
        switch self {
        case .small: return Typography.caption2
        case .regular: return Typography.caption1
        case .large: return Typography.subheadline
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return Spacing.xs
        case .regular: return Spacing.sm
        case .large: return Spacing.md
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .small: return Spacing.xxs
        case .regular: return Spacing.xs
        case .large: return Spacing.xs
        }
    }

    var spacing: CGFloat {
        switch self {
        case .small: return Spacing.xxs
        case .regular: return Spacing.xxs
        case .large: return Spacing.xs
        }
    }
}

// MARK: - Due Date Badge

/// Badge showing days until due date
struct DueDateBadge: View {

    let daysUntilDue: Int?

    var body: some View {
        if let days = daysUntilDue {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: iconName)
                    .font(.caption2)

                Text(displayText)
                    .font(Typography.caption1)
            }
            .foregroundStyle(AppColors.dueDateColor(daysUntilDue: days))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(AppColors.dueDateColor(daysUntilDue: days).opacity(0.12))
            .clipShape(Capsule())
        }
    }

    private var iconName: String {
        guard let days = daysUntilDue else { return "calendar" }
        if days < 0 {
            return "exclamationmark.triangle.fill"
        } else if days == 0 {
            return "exclamationmark.circle.fill"
        } else {
            return "calendar"
        }
    }

    private var displayText: String {
        guard let days = daysUntilDue else { return L10n.DueDate.noDate.localized }

        switch days {
        case ..<0:
            let overdueDays = abs(days)
            return overdueDays == 1
                ? L10n.DueDate.overdueDay.localized
                : L10n.DueDate.overdueDays.localized(with: overdueDays)
        case 0:
            return L10n.DueDate.dueToday.localized
        case 1:
            return L10n.DueDate.dueTomorrow.localized
        default:
            return L10n.DueDate.dueInDays.localized(with: days)
        }
    }
}

// MARK: - Preview

#Preview("Status Badges") {
    VStack(spacing: Spacing.md) {
        ForEach(DocumentStatus.allCases) { status in
            HStack {
                StatusBadge(status: status, size: .small)
                StatusBadge(status: status, size: .regular)
                StatusBadge(status: status, size: .large)
            }
        }

        Divider()

        VStack(alignment: .leading, spacing: Spacing.xs) {
            DueDateBadge(daysUntilDue: -3)
            DueDateBadge(daysUntilDue: 0)
            DueDateBadge(daysUntilDue: 1)
            DueDateBadge(daysUntilDue: 7)
        }
    }
    .padding()
}
