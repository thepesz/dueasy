import SwiftUI

/// Banner displayed when cloud extraction rate limit is exceeded.
/// Provides informative feedback about the limit status and offers an upgrade option.
///
/// ## Design
///
/// The banner is non-blocking - users can continue with local extraction.
/// It provides two key pieces of information:
/// 1. Current rate limit status (e.g., "3/3 AI extractions used")
/// 2. What's happening (using offline extraction with lower accuracy)
///
/// And one action:
/// - Upgrade button to show paywall for Pro tier
///
/// ## Usage
///
/// ```swift
/// if viewModel.shouldShowRateLimitBanner {
///     RateLimitBanner(
///         rateLimitInfo: viewModel.rateLimitInfo,
///         onUpgrade: { viewModel.showUpgradePaywall() },
///         onDismiss: { viewModel.dismissRateLimitBanner() }
///     )
/// }
/// ```
struct RateLimitBanner: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let rateLimitInfo: RateLimitInfo?
    let onUpgrade: () -> Void
    let onDismiss: (() -> Void)?

    init(
        rateLimitInfo: RateLimitInfo?,
        onUpgrade: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.rateLimitInfo = rateLimitInfo
        self.onUpgrade = onUpgrade
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(warningColor)

            // Message content
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                // Title with usage count
                Text(titleText)
                    .font(Typography.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)

                // Subtitle explaining current state
                Text(L10n.RateLimit.bannerSubtitle.localized)
                    .font(Typography.caption1)
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Upgrade button
            Button(action: onUpgrade) {
                Text(L10n.RateLimit.upgradeButton.localized)
                    .lineLimit(1)
                    .font(Typography.caption1.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(upgradeButtonBackground)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Optional dismiss button
            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }

    // MARK: - Computed Properties

    private var titleText: String {
        if let info = rateLimitInfo {
            return L10n.RateLimit.bannerTitle.localized(with: info.used, info.limit)
        }
        return L10n.RateLimit.bannerTitleDefault.localized
    }

    // MARK: - Style-Aware Colors

    private var warningColor: Color {
        style == .midnightAurora ? AuroraPalette.warning : AppColors.warning
    }

    private var primaryTextColor: Color {
        style == .midnightAurora ? AuroraPalette.textPrimary : .primary
    }

    private var secondaryTextColor: Color {
        style == .midnightAurora ? AuroraPalette.textSecondary : .secondary
    }

    @ViewBuilder
    private var bannerBackground: some View {
        if style == .midnightAurora {
            // Aurora-style glass background with warning tint
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(AuroraPalette.cardBacking)

                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(AuroraPalette.cardGlass)

                // Warning tint overlay
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(AuroraPalette.warning.opacity(0.12))
            }
        } else {
            // Standard warning background
            Color(uiColor: colorScheme == .dark
                ? UIColor(red: 0.3, green: 0.2, blue: 0.1, alpha: 1)
                : UIColor(red: 1.0, green: 0.95, blue: 0.9, alpha: 1)
            )
        }
    }

    private var borderColor: Color {
        if style == .midnightAurora {
            return AuroraPalette.warning.opacity(0.4)
        } else {
            return AppColors.warning.opacity(0.3)
        }
    }

    @ViewBuilder
    private var upgradeButtonBackground: some View {
        if style == .midnightAurora {
            AuroraGradients.primaryButton
        } else {
            AppColors.primary
        }
    }
}


// MARK: - Preview

#Preview("Rate Limit Banner - Aurora") {
    ZStack {
        AuroraBackground()

        VStack(spacing: Spacing.lg) {
            RateLimitBanner(
                rateLimitInfo: RateLimitInfo(used: 3, limit: 3, resetDate: Date().addingTimeInterval(86400 * 25)),
                onUpgrade: { print("Upgrade tapped") },
                onDismiss: { print("Dismiss tapped") }
            )
            .padding(.horizontal, Spacing.md)

            RateLimitBanner(
                rateLimitInfo: RateLimitInfo(used: 100, limit: 100, resetDate: nil),
                onUpgrade: { print("Upgrade tapped") }
            )
            .padding(.horizontal, Spacing.md)
        }
    }
    .environment(\.uiStyle, .midnightAurora)
}

#Preview("Rate Limit Banner - Standard") {
    VStack(spacing: Spacing.lg) {
        RateLimitBanner(
            rateLimitInfo: RateLimitInfo(used: 3, limit: 3, resetDate: Date().addingTimeInterval(86400 * 25)),
            onUpgrade: { print("Upgrade tapped") },
            onDismiss: { print("Dismiss tapped") }
        )
        .padding(.horizontal, Spacing.md)

        RateLimitBanner(
            rateLimitInfo: nil,
            onUpgrade: { print("Upgrade tapped") }
        )
        .padding(.horizontal, Spacing.md)
    }
    .padding(.vertical, Spacing.lg)
    .background(Color(uiColor: .systemGroupedBackground))
}
