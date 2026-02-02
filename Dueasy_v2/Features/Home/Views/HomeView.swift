import SwiftUI

/// Home screen (Glance Dashboard) - the at-a-glance overview of payment status.
///
/// Answers three questions in under 3 seconds:
/// 1. How much is due soon?
/// 2. Is anything overdue or needs attention?
/// 3. What are the next 1-3 payments?
///
/// Layout (top to bottom):
/// - Navigation bar with centered logo
/// - Hero Card (due in 7 days)
/// - Two-column tiles (Overdue + Recurring)
/// - Next 3 Payments list
/// - Month Summary donut chart
///
/// Visual Design:
/// - Uses LuxuryHomeBackground for sophisticated, premium aesthetic
/// - Enhanced card shadows and glass effects for depth
/// - Subtle gradients on cards for visual hierarchy
/// - Animated ambient effects for premium feel
struct HomeView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel: HomeViewModel?
    @State private var appeared = false

    /// Callback for navigating to Documents tab
    var onNavigateToDocuments: (() -> Void)?

    /// Callback for navigating to Documents tab with overdue filter
    var onNavigateToOverdue: (() -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    homeContent(viewModel: viewModel)
                } else {
                    LoadingView(L10n.Common.loading.localized)
                        .luxuryHomeBackground()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            setupViewModel()
            await viewModel?.loadMetrics()

            // Trigger appearance animation after data loads
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.5)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func homeContent(viewModel: HomeViewModel) -> some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Large prominent header logo
                headerLogo
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8),
                        value: appeared
                    )

                if !viewModel.state.hasDocuments {
                    // Empty state
                    emptyState
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                } else {
                    // Hero Card with staggered animation
                    heroCard(viewModel: viewModel)
                        .padding(.horizontal, Spacing.md)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(
                            reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(0.05),
                            value: appeared
                        )

                    // Two-column tiles
                    tileRow(viewModel: viewModel)
                        .padding(.horizontal, Spacing.md)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(
                            reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(0.15),
                            value: appeared
                        )

                    // Next Payments
                    if !viewModel.state.nextPayments.isEmpty {
                        nextPaymentsSection(viewModel: viewModel)
                            .padding(.horizontal, Spacing.md)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(
                                reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(0.25),
                                value: appeared
                            )
                    }

                    // Month Summary
                    if viewModel.state.monthTotalCount > 0 {
                        monthSummaryCard(viewModel: viewModel)
                            .padding(.horizontal, Spacing.md)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(
                                reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(0.35),
                                value: appeared
                            )
                    }
                }
            }
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background {
            // Luxury sophisticated background with animated effects
            LuxuryHomeBackground()
        }
        .refreshable {
            await viewModel.loadMetrics()
        }
        .overlay(alignment: .top) {
            if let error = viewModel.error {
                ErrorBanner(
                    error: error,
                    onDismiss: { viewModel.clearError() },
                    onRetry: {
                        Task {
                            await viewModel.loadMetrics()
                        }
                    }
                )
                .padding()
            }
        }
        .navigationDestination(for: FinanceDocument.self) { document in
            DocumentDetailView(documentId: document.id)
                .environment(environment)
        }
    }

    // MARK: - Hero Card

    @ViewBuilder
    private func heroCard(viewModel: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Title with icon for premium feel
            HStack(spacing: Spacing.xs) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.primary.opacity(0.8))

                Text(L10n.Home.dueIn7Days.localized)
                    .font(Typography.headline)
                    .foregroundStyle(.secondary)
            }

            if viewModel.state.hasUpcomingPayments {
                // Amount with gradient effect
                Text(viewModel.formattedHeroAmount)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                .primary,
                                colorScheme == .light
                                    ? Color(red: 0.15, green: 0.35, blue: 0.65)
                                    : Color(red: 0.5, green: 0.7, blue: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                // Subtitle
                Text(viewModel.heroSubtitle)
                    .font(Typography.subheadline)
                    .foregroundStyle(.secondary)

                // Status capsules with enhanced styling
                if viewModel.state.overdueCount > 0 || viewModel.state.dueSoonCount > 0 {
                    HStack(spacing: Spacing.xs) {
                        if viewModel.state.overdueCount > 0 {
                            luxuryStatusCapsule(
                                text: String.localized(L10n.Home.overdue, with: viewModel.state.overdueCount),
                                color: AppColors.error
                            )
                        }

                        if viewModel.state.dueSoonCount > 0 {
                            luxuryStatusCapsule(
                                text: String.localized(L10n.Home.dueSoon, with: viewModel.state.dueSoonCount),
                                color: AppColors.warning
                            )
                        }
                    }
                }
            } else {
                // No upcoming payments - success state
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(AppColors.success)

                        Text(L10n.Home.noUpcoming.localized)
                            .font(Typography.title3)
                            .foregroundStyle(.primary)
                    }

                    Text(L10n.Home.allSet.localized)
                        .font(Typography.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background {
            LuxuryCardBackground(accentColor: AppColors.primary, style: .hero)
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
        .luxuryCardBorder(accentColor: AppColors.primary, cornerRadius: CornerRadius.xl)
        .luxuryCardShadow(accentColor: AppColors.primary, intensity: .high)
    }

    /// Luxury status capsule with gradient background, inner glow, and shadow
    private func luxuryStatusCapsule(text: String, color: Color) -> some View {
        HStack(spacing: Spacing.xxs) {
            // Animated indicator dot
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.6), radius: 2)

            Text(text)
                .font(Typography.caption1.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(colorScheme == .light ? 0.15 : 0.25),
                            color.opacity(colorScheme == .light ? 0.08 : 0.15)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    // Inner glow
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    color.opacity(0.4),
                                    color.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
        }
        .shadow(color: color.opacity(0.2), radius: 4, y: 2)
    }

    // MARK: - Tile Row

    @ViewBuilder
    private func tileRow(viewModel: HomeViewModel) -> some View {
        HStack(spacing: Spacing.sm) {
            // Overdue Tile
            overdueTile(viewModel: viewModel)

            // Recurring Tile
            recurringTile(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func overdueTile(viewModel: HomeViewModel) -> some View {
        let accentColor = viewModel.state.isOverdueClear ? AppColors.success : AppColors.error

        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Title with icon
            HStack(spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor.opacity(0.7))

                Text(L10n.Home.overdueTitle.localized)
                    .font(Typography.headline)
                    .foregroundStyle(.primary)
            }

            if viewModel.state.isOverdueClear {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                    Text(L10n.Home.allClear.localized)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(viewModel.formattedOverdueAmount)
                    .font(Typography.title2)
                    .foregroundStyle(AppColors.error)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                if let subtitle = viewModel.overdueSubtitle {
                    Text(subtitle)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Check CTA - prominent clickable button to navigate to overdue documents
                Button {
                    onNavigateToOverdue?()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                        Text(L10n.Home.check.localized)
                            .font(Typography.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs + 2)
                    .background(
                        LinearGradient(
                            colors: [AppColors.error, AppColors.error.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: AppColors.error.opacity(0.3), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 130)
        .padding(Spacing.md)
        .background {
            LuxuryCardBackground(accentColor: accentColor, style: .tile)
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .luxuryCardBorder(accentColor: accentColor, cornerRadius: CornerRadius.lg)
        .luxuryCardShadow(accentColor: accentColor, intensity: .medium)
    }

    @ViewBuilder
    private func recurringTile(viewModel: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Title with icon
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.primary.opacity(0.7))

                Text(L10n.Home.recurringTitle.localized)
                    .font(Typography.headline)
                    .foregroundStyle(.primary)
            }

            if viewModel.state.hasNoRecurringTemplates {
                Text(L10n.Home.setupRecurring.localized)
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)

                Spacer()

                // Setup CTA with enhanced styling
                Button {
                    // Navigate to recurring setup
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Text(L10n.Home.manage.localized)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .font(Typography.caption1.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                }
            } else {
                Text(viewModel.recurringBodyText)
                    .font(Typography.body)
                    .foregroundStyle(.primary)

                if let subtitle = viewModel.recurringSubtitle {
                    Text(subtitle)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if viewModel.state.missingRecurringCount > 0 {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                        Text(String.localized(L10n.Home.missingCount, with: viewModel.state.missingRecurringCount))
                    }
                    .font(Typography.caption1)
                    .foregroundStyle(AppColors.warning)
                }

                Spacer()

                // Manage CTA with enhanced styling
                Button {
                    // Navigate to recurring management
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Text(L10n.Home.manage.localized)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .font(Typography.caption1.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 130)
        .padding(Spacing.md)
        .background {
            LuxuryCardBackground(accentColor: AppColors.primary, style: .tile)
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .luxuryCardBorder(accentColor: AppColors.primary, cornerRadius: CornerRadius.lg)
        .luxuryCardShadow(accentColor: AppColors.primary, intensity: .medium)
    }

    // MARK: - Next Payments Section

    @ViewBuilder
    private func nextPaymentsSection(viewModel: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header with icon and "See All" button
            HStack {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.primary.opacity(0.7))

                    Text(L10n.Home.nextPayments.localized)
                        .font(Typography.headline)
                        .foregroundStyle(.primary)
                }

                Spacer()

                // "See All" button - navigates to Documents tab
                Button {
                    onNavigateToDocuments?()
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Text(L10n.Home.seeAllUpcoming.localized)
                            .font(Typography.caption1.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background {
                        Capsule()
                            .fill(AppColors.primary.opacity(colorScheme == .light ? 0.1 : 0.2))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)

            // Payment rows with enhanced styling and proper visual separation
            VStack(spacing: 0) {
                ForEach(Array(viewModel.state.nextPayments.enumerated()), id: \.element.id) { index, payment in
                    NavigationLink(value: FinanceDocument(id: payment.documentId, title: payment.vendorName)) {
                        paymentRow(payment: payment)
                            .padding(.vertical, Spacing.sm) // Add vertical breathing room to each row
                    }
                    .buttonStyle(.plain)

                    // Divider between rows (not after last)
                    if index < viewModel.state.nextPayments.count - 1 {
                        Divider()
                            .background(colorScheme == .light ? Color.gray.opacity(0.2) : Color.white.opacity(0.1))
                            .padding(.leading, Spacing.xl)
                    }
                }
            }
            .padding(.vertical, Spacing.xs) // Reduced outer padding since rows now have internal padding
            .padding(.horizontal, Spacing.md)
            .background {
                LuxuryCardBackground(accentColor: nil, style: .standard)
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .luxuryCardBorder(accentColor: nil, cornerRadius: CornerRadius.lg)
            .luxuryCardShadow(accentColor: nil, intensity: .medium)
        }
    }

    @ViewBuilder
    private func paymentRow(payment: HomePaymentItem) -> some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            // Vendor name and due info - takes available space but allows amount to be consistent
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(payment.vendorName)
                    .font(Typography.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Due info
                Text(dueDateLabel(for: payment))
                    .font(Typography.caption1)
                    .foregroundStyle(payment.isOverdue ? AppColors.error : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Amount - right-aligned with fixed minimum width for columnar alignment
            Text(formatCurrency(payment.amount, currency: payment.currency))
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(minWidth: 90, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .contentShape(Rectangle())
    }

    private func dueDateLabel(for payment: HomePaymentItem) -> String {
        if payment.isOverdue {
            return String.localized(L10n.Home.overdueDaysLabel, with: abs(payment.daysUntilDue))
        } else if payment.daysUntilDue == 0 {
            return L10n.Home.dueTodayLabel.localized
        } else {
            return String.localized(L10n.Home.dueInDaysLabel, with: payment.daysUntilDue)
        }
    }

    // MARK: - Month Summary Card

    @ViewBuilder
    private func monthSummaryCard(viewModel: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header with icon
            HStack(spacing: Spacing.xs) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.primary.opacity(0.7))

                Text(L10n.Home.thisMonth.localized)
                    .font(Typography.headline)
                    .foregroundStyle(.primary)

                Text("- \(L10n.Home.paymentStatus.localized)")
                    .font(Typography.headline)
                    .foregroundStyle(.secondary)
            }

            // Content: Donut + Stats
            HStack(alignment: .center, spacing: Spacing.lg) {
                // Donut chart
                DonutChart.paymentStatus(
                    paidCount: viewModel.state.monthPaidCount,
                    dueCount: viewModel.state.monthDueCount,
                    overdueCount: viewModel.state.monthOverdueCount,
                    paidPercent: viewModel.state.paidPercent,
                    totalCount: viewModel.state.monthTotalCount
                )

                // Stats column with enhanced styling
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    luxuryStatRow(
                        label: L10n.Home.Donut.paid.localized,
                        value: "\(viewModel.state.monthPaidCount)",
                        color: AppColors.success
                    )
                    luxuryStatRow(
                        label: L10n.Home.Donut.due.localized,
                        value: "\(viewModel.state.monthDueCount)",
                        color: AppColors.warning
                    )
                    luxuryStatRow(
                        label: L10n.Home.Donut.overdue.localized,
                        value: "\(viewModel.state.monthOverdueCount)",
                        color: AppColors.error
                    )
                }
            }

            // Bottom line: unpaid total with enhanced styling
            if viewModel.state.monthUnpaidTotal > 0 {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(String.localized(L10n.Home.unpaidTotal, with: viewModel.formattedMonthUnpaidTotal))
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background {
            LuxuryCardBackground(accentColor: nil, style: .standard)
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .luxuryCardBorder(accentColor: nil, cornerRadius: CornerRadius.lg)
        .luxuryCardShadow(accentColor: nil, intensity: .medium)
    }

    /// Luxury stat row with enhanced visual styling and glowing indicator
    @ViewBuilder
    private func luxuryStatRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            // Color indicator with glow effect
            ZStack {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 16, height: 16)

                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.5), radius: 2)
            }

            Text(label)
                .font(Typography.caption1)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(Typography.caption1.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Icon with glow effect
            ZStack {
                Circle()
                    .fill(AppColors.primary.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)

                Circle()
                    .fill(AppColors.primary.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(AppColors.primary.opacity(0.7))
            }

            VStack(spacing: Spacing.sm) {
                Text(L10n.Home.noPaymentsTitle.localized)
                    .font(Typography.title3)
                    .foregroundStyle(.primary)

                Text(L10n.Home.noPaymentsMessage.localized)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Link to scan
            Button {
                // Navigate to scan
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "doc.viewfinder")
                    Text(L10n.Home.goToScan.localized)
                }
                .font(Typography.body.weight(.medium))
                .foregroundStyle(AppColors.primary)
            }

            Spacer()
        }
        .padding(Spacing.xl)
    }

    // MARK: - Header Logo

    /// Large prominent logo displayed at the top of the ScrollView content.
    /// Provides brand identity while being part of the scrollable content.
    @ViewBuilder
    private var headerLogo: some View {
        VStack(spacing: Spacing.xs) {
            // Large handwritten logo
            LargeHomeHandwrittenLogo()

            // Tagline
            Text(L10n.App.tagline.localized)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1.2)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Helpers

    private func setupViewModel() {
        guard viewModel == nil else { return }
        viewModel = HomeViewModel(
            fetchHomeMetricsUseCase: FetchHomeMetricsUseCase(
                documentRepository: environment.documentRepository,
                recurringTemplateService: environment.recurringTemplateService,
                recurringSchedulerService: environment.recurringSchedulerService,
                appTier: environment.appTier
            )
        )
    }

    private func formatCurrency(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(currency)"
    }
}

// MARK: - Large Home Handwritten Logo Component

/// Large prominent handwritten logo for the Home view scrolling header.
/// Designed to be displayed at the top of the ScrollView content with strong brand presence.
///
/// Accessibility:
/// - Respects reduceTransparency: disables blur/shadow layers
/// - Respects reduceMotion: disables animated scan effect
/// - Works in both light and dark mode
struct LargeHomeHandwrittenLogo: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scanPosition: CGFloat = -1.0

    /// Logo gradient colors - sophisticated blue tones
    private var logoGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.35, blue: 0.65),  // Deep ink blue
                AppColors.primary,                          // Brand blue
                Color(red: 0.25, green: 0.45, blue: 0.75)   // Lighter accent
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Ink shadow color for pen effect
    private var inkShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.6)
            : Color(red: 0.1, green: 0.15, blue: 0.3).opacity(0.35)
    }

    var body: some View {
        ZStack {
            // Layer 1: Soft shadow for depth
            if !reduceTransparency {
                logoText
                    .foregroundStyle(inkShadowColor)
                    .blur(radius: 2)
                    .offset(x: 1, y: 2)
            }

            // Layer 2: Main text with gradient
            logoText
                .foregroundStyle(logoGradient)
                .overlay {
                    // Scanning light effect (green glow)
                    if !reduceMotion {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.green.opacity(0),
                                            Color.green.opacity(0.5),
                                            Color.green.opacity(0.7),
                                            Color.green.opacity(0.5),
                                            Color.green.opacity(0)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * 0.25)
                                .offset(x: geometry.size.width * scanPosition)
                                .blendMode(.plusLighter)
                        }
                        .mask(logoText)
                    }
                }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(
                    .linear(duration: 2.5)
                    .repeatForever(autoreverses: true)
                ) {
                    scanPosition = 1.0
                }
            }
        }
    }

    /// The main logo text with casual handmade styling (large version - 44pt)
    private var logoText: some View {
        HStack(alignment: .bottom, spacing: 2) {
            // "Du" with casual friendly style
            Text("Du")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .italic()
                .rotationEffect(.degrees(-2.5), anchor: .bottom)

            // "Easy" with playful handmade feel
            Text("Easy")
                .font(.system(size: 44, weight: .medium, design: .rounded))
                .italic()
                .rotationEffect(.degrees(2), anchor: .bottom)
                .offset(y: 2)
        }
        .kerning(-0.5)
    }
}

// MARK: - Home Handwritten Logo Component (Compact - kept for potential future use)

/// Compact handwritten logo for the Home view navigation bar.
/// Designed to be centered in the navigation bar with prominent brand identity.
///
/// Accessibility:
/// - Respects reduceTransparency: disables blur/shadow layers
/// - Respects reduceMotion: disables animated scan effect
/// - Works in both light and dark mode
struct HomeHandwrittenLogo: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scanPosition: CGFloat = -1.0

    /// Logo gradient colors - sophisticated blue tones
    private var logoGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.35, blue: 0.65),  // Deep ink blue
                AppColors.primary,                          // Brand blue
                Color(red: 0.25, green: 0.45, blue: 0.75)   // Lighter accent
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Ink shadow color for pen effect
    private var inkShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.5)
            : Color(red: 0.1, green: 0.15, blue: 0.3).opacity(0.3)
    }

    var body: some View {
        ZStack {
            // Layer 1: Soft shadow for depth
            if !reduceTransparency {
                logoText
                    .foregroundStyle(inkShadowColor)
                    .blur(radius: 1)
                    .offset(x: 0.5, y: 1)
            }

            // Layer 2: Main text with gradient
            logoText
                .foregroundStyle(logoGradient)
                .overlay {
                    // Scanning light effect (green glow)
                    if !reduceMotion {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.green.opacity(0),
                                            Color.green.opacity(0.5),
                                            Color.green.opacity(0.7),
                                            Color.green.opacity(0.5),
                                            Color.green.opacity(0)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * 0.25)
                                .offset(x: geometry.size.width * scanPosition)
                                .blendMode(.plusLighter)
                        }
                        .mask(logoText)
                    }
                }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(
                    .linear(duration: 2.5)
                    .repeatForever(autoreverses: true)
                ) {
                    scanPosition = 1.0
                }
            }
        }
    }

    /// The main logo text with casual handmade styling (compact version)
    private var logoText: some View {
        HStack(alignment: .bottom, spacing: 1) {
            // "Du" with casual friendly style
            Text("Du")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .italic()
                .rotationEffect(.degrees(-2), anchor: .bottom)

            // "Easy" with playful handmade feel
            Text("Easy")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .italic()
                .rotationEffect(.degrees(1.5), anchor: .bottom)
                .offset(y: 1)
        }
        .kerning(-0.3)
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environment(AppEnvironment.preview)
}
