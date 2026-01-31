import SwiftUI

/// Banner view for displaying errors with optional retry action.
struct ErrorBanner: View {

    let error: AppError
    let onDismiss: (() -> Void)?
    let onRetry: (() -> Void)?

    init(
        error: AppError,
        onDismiss: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.error = error
        self.onDismiss = onDismiss
        self.onRetry = onRetry
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.error)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(error.localizedDescription)
                    .font(Typography.subheadline)
                    .foregroundStyle(.primary)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: Spacing.xs) {
                if let onRetry = onRetry, error.isRecoverable {
                    Button("Retry") {
                        onRetry()
                    }
                    .font(Typography.caption1.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                }

                if let onDismiss = onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .background(AppColors.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .strokeBorder(AppColors.error.opacity(0.3), lineWidth: 1)
        }
    }
}

/// Warning banner for non-critical alerts
struct WarningBanner: View {

    let message: String
    let suggestion: String?
    let onDismiss: (() -> Void)?

    init(
        message: String,
        suggestion: String? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.message = message
        self.suggestion = suggestion
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AppColors.warning)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(message)
                    .font(Typography.subheadline)
                    .foregroundStyle(.primary)

                if let suggestion = suggestion {
                    Text(suggestion)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let onDismiss = onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Spacing.sm)
        .background(AppColors.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .strokeBorder(AppColors.warning.opacity(0.3), lineWidth: 1)
        }
    }
}

/// Success banner for confirmations
struct SuccessBanner: View {

    let message: String
    let onDismiss: (() -> Void)?

    init(message: String, onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.success)

            Text(message)
                .font(Typography.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            if let onDismiss = onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Spacing.sm)
        .background(AppColors.success.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .strokeBorder(AppColors.success.opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: - Preview

#Preview("Banners") {
    VStack(spacing: Spacing.md) {
        ErrorBanner(
            error: .calendarPermissionDenied,
            onDismiss: {},
            onRetry: {}
        )

        ErrorBanner(
            error: .ocrLowConfidence,
            onDismiss: {},
            onRetry: {}
        )

        WarningBanner(
            message: "Due date is in the past",
            suggestion: "You can still save with this date if needed",
            onDismiss: {}
        )

        SuccessBanner(
            message: "Document saved and added to calendar",
            onDismiss: {}
        )
    }
    .padding()
}
