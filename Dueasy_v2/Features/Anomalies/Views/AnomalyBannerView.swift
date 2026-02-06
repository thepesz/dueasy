import SwiftUI

// MARK: - Anomaly Banner View

/// A compact banner showing anomaly summary for a document.
/// Displayed on DocumentDetailView when critical/warning anomalies are detected.
/// Follows iOS 26 Liquid Glass design system with accessibility fallbacks.
///
/// Features:
/// - Severity-based styling (critical=red, warning=orange, info=blue)
/// - Animated severity indicator
/// - Tap to expand/navigate to details
/// - Glass morphism styling with proper accessibility fallbacks
struct AnomalyBannerView: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Total count of unresolved anomalies
    let totalCount: Int

    /// Count of critical severity anomalies
    let criticalCount: Int

    /// Count of warning severity anomalies
    let warningCount: Int

    /// Count of info severity anomalies
    let infoCount: Int

    /// Action when banner is tapped
    let onTap: () -> Void

    /// State for pulse animation on critical alerts
    @State private var isPulsing = false

    // MARK: - Computed Properties

    private var highestSeverity: AnomalySeverity {
        if criticalCount > 0 { return .critical }
        if warningCount > 0 { return .warning }
        return .info
    }

    private var severityColor: Color {
        switch highestSeverity {
        case .critical:
            return AppColors.error
        case .warning:
            return AppColors.warning
        case .info:
            return AppColors.info
        }
    }

    private var severityIcon: String {
        switch highestSeverity {
        case .critical:
            return "shield.slash.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private var bannerTitle: String {
        switch highestSeverity {
        case .critical:
            return "Security Alert"
        case .warning:
            return "Attention Required"
        case .info:
            return "Information"
        }
    }

    private var bannerSubtitle: String {
        if totalCount == 1 {
            return "1 anomaly detected"
        } else {
            return "\(totalCount) anomalies detected"
        }
    }

    private var isAurora: Bool {
        style == .midnightAurora
    }

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                // Severity icon with optional pulse animation
                severityIconView

                // Text content
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(bannerTitle)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(textPrimaryColor)

                    Text(bannerSubtitle)
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(textSecondaryColor)
                }

                Spacer()

                // Severity counts
                severityCountBadges

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textTertiaryColor)
            }
            .padding(Spacing.sm)
            .background { bannerBackground }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            .overlay { bannerBorder }
            .modifier(BannerShadowModifier(severity: highestSeverity, isAurora: isAurora))
        }
        .buttonStyle(.plain)
        .onAppear {
            startPulseAnimationIfNeeded()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bannerTitle). \(bannerSubtitle). Tap to view details.")
        .accessibilityHint("Double tap to view anomaly details")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var severityIconView: some View {
        ZStack {
            // Pulse ring for critical
            if highestSeverity == .critical && !reduceMotion {
                Circle()
                    .stroke(severityColor.opacity(isPulsing ? 0 : 0.5), lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
            }

            // Icon background
            Circle()
                .fill(iconBackgroundGradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Circle()
                        .strokeBorder(severityColor.opacity(0.5), lineWidth: 1.5)
                }

            // Icon
            Image(systemName: severityIcon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(severityColor)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var iconBackgroundGradient: some ShapeStyle {
        if isAurora {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    severityColor.opacity(0.25),
                    severityColor.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        } else {
            return AnyShapeStyle(severityColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
        }
    }

    @ViewBuilder
    private var severityCountBadges: some View {
        HStack(spacing: Spacing.xxs) {
            if criticalCount > 0 {
                severityBadge(count: criticalCount, severity: .critical)
            }
            if warningCount > 0 {
                severityBadge(count: warningCount, severity: .warning)
            }
            if infoCount > 0 && criticalCount == 0 && warningCount == 0 {
                severityBadge(count: infoCount, severity: .info)
            }
        }
    }

    @ViewBuilder
    private func severityBadge(count: Int, severity: AnomalySeverity) -> some View {
        let badgeColor = colorForSeverity(severity)

        Text("\(count)")
            .font(Typography.stat.weight(.bold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background {
                Capsule()
                    .fill(badgeColor.opacity(isAurora ? 0.25 : 0.15))
                    .overlay {
                        if isAurora {
                            Capsule()
                                .strokeBorder(badgeColor.opacity(0.5), lineWidth: 1)
                        }
                    }
            }
    }

    @ViewBuilder
    private var bannerBackground: some View {
        let shape = RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)

        if reduceTransparency {
            shape.fill(solidBackgroundColor)
        } else if isAurora {
            ZStack {
                // Dark solid backing
                shape.fill(AuroraPalette.sectionBacking)
                // Glass layer
                shape.fill(AuroraPalette.sectionGlass)
                // Severity tint
                shape.fill(severityColor.opacity(0.08))
            }
        } else {
            ZStack {
                shape.fill(Color(UIColor.secondarySystemGroupedBackground))
                shape.fill(severityColor.opacity(0.05))
            }
        }
    }

    @ViewBuilder
    private var bannerBorder: some View {
        let shape = RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)

        if isAurora {
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        severityColor.opacity(0.5),
                        severityColor.opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.5
            )
        } else {
            shape.strokeBorder(severityColor.opacity(0.3), lineWidth: 1)
        }
    }

    // MARK: - Colors

    private var textPrimaryColor: Color {
        isAurora ? Color.white : .primary
    }

    private var textSecondaryColor: Color {
        isAurora ? Color.white.opacity(0.7) : .secondary
    }

    private var textTertiaryColor: Color {
        isAurora ? Color.white.opacity(0.5) : Color.secondary.opacity(0.7)
    }

    private var solidBackgroundColor: Color {
        isAurora
            ? Color(red: 0.08, green: 0.08, blue: 0.14)
            : Color(UIColor.secondarySystemGroupedBackground)
    }

    private func colorForSeverity(_ severity: AnomalySeverity) -> Color {
        switch severity {
        case .critical: return AppColors.error
        case .warning: return AppColors.warning
        case .info: return AppColors.info
        }
    }

    // MARK: - Animation

    private func startPulseAnimationIfNeeded() {
        guard highestSeverity == .critical && !reduceMotion else { return }

        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

// MARK: - Banner Shadow Modifier

private struct BannerShadowModifier: ViewModifier {
    let severity: AnomalySeverity
    let isAurora: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shadowColor: Color = {
            switch severity {
            case .critical: return AppColors.error
            case .warning: return AppColors.warning
            case .info: return AppColors.info
            }
        }()

        if isAurora {
            content
                .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)
                .shadow(color: shadowColor.opacity(0.25), radius: 12, y: 6)
        } else {
            content
                .shadow(
                    color: shadowColor.opacity(colorScheme == .dark ? 0.3 : 0.15),
                    radius: 8,
                    y: 4
                )
        }
    }
}

// MARK: - Compact Anomaly Indicator

/// A minimal indicator for showing anomaly status in list rows.
/// Shows just an icon and count, used in DocumentListView.
struct AnomalyIndicator: View {

    @Environment(\.uiStyle) private var style

    let criticalCount: Int
    let warningCount: Int

    private var isAurora: Bool {
        style == .midnightAurora
    }

    private var displayCount: Int {
        criticalCount > 0 ? criticalCount : warningCount
    }

    private var indicatorColor: Color {
        criticalCount > 0 ? AppColors.error : AppColors.warning
    }

    private var iconName: String {
        criticalCount > 0 ? "shield.slash.fill" : "exclamationmark.triangle.fill"
    }

    var body: some View {
        guard criticalCount > 0 || warningCount > 0 else {
            return AnyView(EmptyView())
        }

        return AnyView(
            HStack(spacing: 2) {
                Image(systemName: iconName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(indicatorColor)

                if displayCount > 1 {
                    Text("\(displayCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(indicatorColor)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(indicatorColor.opacity(isAurora ? 0.25 : 0.15))
                    .overlay {
                        if isAurora {
                            Capsule()
                                .strokeBorder(indicatorColor.opacity(0.5), lineWidth: 1)
                        }
                    }
            }
        )
    }
}

// MARK: - Preview

#Preview("Critical Anomaly Banner") {
    VStack(spacing: Spacing.md) {
        AnomalyBannerView(
            totalCount: 3,
            criticalCount: 2,
            warningCount: 1,
            infoCount: 0,
            onTap: {}
        )

        AnomalyBannerView(
            totalCount: 2,
            criticalCount: 0,
            warningCount: 2,
            infoCount: 0,
            onTap: {}
        )

        AnomalyBannerView(
            totalCount: 1,
            criticalCount: 0,
            warningCount: 0,
            infoCount: 1,
            onTap: {}
        )
    }
    .padding()
    .background(Color(UIColor.systemGroupedBackground))
}

#Preview("Aurora Style") {
    VStack(spacing: Spacing.md) {
        AnomalyBannerView(
            totalCount: 3,
            criticalCount: 1,
            warningCount: 2,
            infoCount: 0,
            onTap: {}
        )
    }
    .padding()
    .background { EnhancedMidnightAuroraBackground() }
    .environment(\.uiStyle, .midnightAurora)
}
