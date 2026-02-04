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
/// - Adapts to current UI style (Midnight Aurora, Paper Minimal, Warm Finance)
/// - Midnight Aurora: LuxuryHomeBackground with glass effects
/// - Paper Minimal: Flat solid background with sharp corners
/// - Warm Finance: Warm gradient with soft shadows
struct HomeView: View {

    // MARK: - Typography Hierarchy
    // Standardized font definitions for consistent visual hierarchy across all cards/sections

    /// Level 1: Section/Card Titles (e.g., "Do zaplaty w ciagu 7 dni", "Zalegle", "Cykliczne")
    private var sectionTitleFont: Font { .system(size: 12, weight: .medium) }
    private var sectionTitleTracking: CGFloat { currentStyle == .midnightAurora ? 0.5 : 0 }

    /// Level 2: Primary Content/Body Text (e.g., "Brak nadchodzacych platnosci", empty states)
    private var bodyFont: Font { .system(size: 13) }

    /// Level 3: Large Numbers/Amounts (hero amounts, overdue amounts, recurring counts)
    private func heroNumberFont(design: Font.Design) -> Font {
        .system(size: 24, weight: .medium, design: design).monospacedDigit()
    }

    /// Level 4: Subtitles/Secondary Info (e.g., "Wszystko oplacone", recurring subtitle)
    private var subtitleFont: Font { .system(size: 13) }

    /// Level 5: Button Text (e.g., "Sprawdz", "Zarzadzaj")
    private var buttonFont: Font { .system(size: 13, weight: .medium) }

    /// Level 6: Section Header Icons
    private var sectionIconFont: Font { .system(size: 12) }

    /// Level 7: Payment Row - Vendor Name (primary row text)
    private var paymentRowPrimaryFont: Font { .system(size: 16, weight: .medium) }

    /// Level 8: Payment Row - Due Info (secondary row text)
    private var paymentRowSecondaryFont: Font { .system(size: 13) }

    /// Level 9: Payment Row - Amount
    private func paymentRowAmountFont(design: Font.Design) -> Font {
        .system(size: 17, weight: .medium, design: design).monospacedDigit()
    }

    /// Level 10: Stat Row Labels/Values (month summary)
    private var statFont: Font { Typography.caption1 }
    private var statBoldFont: Font { Typography.caption1.weight(.bold).monospacedDigit() }

    /// Level 11: Info/Footnote Text
    private var footnoteFont: Font { Typography.footnote }

    /// Level 12: Recurring Tile Content Font (14pt, 2 points larger than section title)
    /// Used for company names and active counts in the recurring tile
    private var recurringTileContentFont: Font { .system(size: 14, weight: .medium) }

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    /// Current UI style from settings
    private var currentStyle: UIStyleProposal {
        environment.settingsManager.uiStyleHome
    }

    /// Design tokens for the current style
    private var tokens: UIStyleTokens {
        UIStyleTokens(style: currentStyle)
    }

    @State private var viewModel: HomeViewModel?
    @State private var appeared = false

    /// External trigger from MainTabView to refresh after adding documents.
    /// When this value changes, HomeView reloads its metrics.
    var refreshTrigger: Int = 0

    /// Callback for navigating to Documents tab
    var onNavigateToDocuments: (() -> Void)?

    /// Callback for navigating to Documents tab with overdue filter
    var onNavigateToOverdue: (() -> Void)?

    /// Callback for navigating to scan/add document
    var onNavigateToScan: (() -> Void)?

    /// State for showing the RecurringOverviewView sheet
    @State private var showRecurringOverview: Bool = false

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
        .onChange(of: refreshTrigger) { _, _ in
            // CRITICAL: Reload metrics when refresh is triggered (e.g., after adding a document)
            Task {
                await viewModel?.loadMetrics()
            }
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
            // Style-aware background
            StyledHomeBackground()
        }
        .environment(\.uiStyle, currentStyle)
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
        .navigationDestination(for: DocumentNavigationValue.self) { navValue in
            DocumentDetailView(documentId: navValue.documentId)
                .environment(environment)
                .environment(\.uiStyle, currentStyle)
        }
    }

    // MARK: - Hero Card

    @ViewBuilder
    private func heroCard(viewModel: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Title with icon - LEVEL 1: Section Title
            HStack(spacing: Spacing.xs) {
                Image(systemName: "calendar.badge.clock")
                    .font(sectionIconFont)
                    .foregroundStyle(currentStyle == .midnightAurora ? AuroraPalette.accentBlue : tokens.primaryColor(for: colorScheme).opacity(0.8))

                Text(L10n.Home.dueIn7Days.localized)
                    .font(sectionTitleFont)
                    .tracking(sectionTitleTracking)
                    .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
            }

            if viewModel.state.hasUpcomingPayments {
                // Amount with style-appropriate treatment - LEVEL 3: Large Numbers (handled by StyledHomeHeroAmount)
                StyledHomeHeroAmount(amount: viewModel.formattedHeroAmount)

                // Subtitle - LEVEL 4: Subtitles/Secondary Info
                Text(viewModel.heroSubtitle)
                    .font(subtitleFont)
                    .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))

                // Status capsules with styled appearance
                if viewModel.state.overdueCount > 0 || viewModel.state.dueSoonCount > 0 {
                    HStack(spacing: Spacing.xs) {
                        if viewModel.state.overdueCount > 0 {
                            StyledHomeStatusCapsule(
                                text: String.localized(L10n.Home.overdue, with: viewModel.state.overdueCount),
                                color: tokens.errorColor(for: colorScheme)
                            )
                        }

                        if viewModel.state.dueSoonCount > 0 {
                            StyledHomeStatusCapsule(
                                text: String.localized(L10n.Home.dueSoon, with: viewModel.state.dueSoonCount),
                                color: tokens.warningColor(for: colorScheme)
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
                            .foregroundStyle(tokens.successColor(for: colorScheme))

                        // LEVEL 2: Primary Content/Body Text
                        Text(L10n.Home.noUpcoming.localized)
                            .font(bodyFont)
                            .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))
                    }

                    // LEVEL 4: Subtitles/Secondary Info
                    Text(L10n.Home.allSet.localized)
                        .font(subtitleFont)
                        .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(tokens.cardPadding)
        .background {
            StyledHomeCardBackground(accentColor: tokens.primaryColor(for: colorScheme), cardType: .hero)
        }
        .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
        .modifier(HomeCardBorderModifier(tokens: tokens, accentColor: tokens.primaryColor(for: colorScheme)))
        .modifier(HomeCardShadowModifier(tokens: tokens, accentColor: tokens.primaryColor(for: colorScheme), cardType: .hero))
    }

    // MARK: - Tile Row

    /// Fixed tile height for visual consistency.
    /// Both tiles maintain this height regardless of content state.
    private let tileHeight: CGFloat = 160

    @ViewBuilder
    private func tileRow(viewModel: HomeViewModel) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Overdue Tile - strict height constraint
            overdueTile(viewModel: viewModel)
                .frame(minHeight: tileHeight, maxHeight: tileHeight)

            // Recurring Tile - strict height constraint
            recurringTile(viewModel: viewModel)
                .frame(minHeight: tileHeight, maxHeight: tileHeight)
        }
    }

    @ViewBuilder
    private func overdueTile(viewModel: HomeViewModel) -> some View {
        let accentColor = viewModel.state.isOverdueClear
            ? tokens.successColor(for: colorScheme)
            : tokens.errorColor(for: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            // Title with icon - LEVEL 1: Section Title
            HStack(spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(sectionIconFont)
                    .foregroundStyle(accentColor)

                Text(L10n.Home.overdueTitle.localized)
                    .font(sectionTitleFont)
                    .tracking(sectionTitleTracking)
                    .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))
            }
            .padding(.bottom, Spacing.sm)

            if viewModel.state.isOverdueClear {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(tokens.successColor(for: colorScheme))
                    // LEVEL 2: Primary Content/Body Text
                    Text(L10n.Home.allClear.localized)
                        .font(bodyFont)
                        .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                }
            } else {
                // LEVEL 3: Large Numbers/Amounts
                Text(viewModel.formattedOverdueAmount)
                    .font(heroNumberFont(design: tokens.heroNumberDesign))
                    .foregroundStyle(tokens.errorColor(for: colorScheme))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.bottom, 4)

                // LEVEL 4: Subtitles/Secondary Info
                if let subtitle = viewModel.overdueSubtitle {
                    Text(subtitle)
                        .font(subtitleFont)
                        .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Check CTA - always show at bottom, hidden when clear
            // LEVEL 5: Button Text
            if !viewModel.state.isOverdueClear {
                Button {
                    onNavigateToOverdue?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(buttonFont)
                        Text(L10n.Home.check.localized)
                            .font(buttonFont)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(ctaButtonBackground(color: tokens.errorColor(for: colorScheme)))
                    .clipShape(ctaButtonShape)
                    .modifier(CTAButtonShadowModifier(tokens: tokens, color: tokens.errorColor(for: colorScheme)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background {
            StyledHomeCardBackground(accentColor: accentColor, cardType: .tile)
        }
        .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
        .modifier(HomeCardBorderModifier(tokens: tokens, accentColor: accentColor))
        .modifier(HomeCardShadowModifier(tokens: tokens, accentColor: accentColor, cardType: .tile))
    }

    @ViewBuilder
    private func recurringTile(viewModel: HomeViewModel) -> some View {
        let accentColor = tokens.primaryColor(for: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            // Line 1: Title with icon - LEVEL 1: Section Title (12pt)
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(sectionIconFont)
                    .foregroundStyle(currentStyle == .midnightAurora ? AuroraPalette.accentBlue : accentColor)

                Text(L10n.Home.recurringTitle.localized)
                    .font(sectionTitleFont)
                    .tracking(sectionTitleTracking)
                    .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))
            }
            .padding(.bottom, Spacing.sm)

            if viewModel.state.hasNoRecurringTemplates {
                // Empty state
                Text(L10n.Home.setupRecurring.localized)
                    .font(bodyFont)
                    .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                    .lineLimit(2)
            } else {
                // Line 2: Active count (14pt medium) - e.g., "Aktywne: 2"
                Text(viewModel.recurringActiveCountText)
                    .font(recurringTileContentFont)
                    .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))
                    .lineLimit(1)
                    .padding(.bottom, 4)

                // Line 3: Next vendor (13pt) - e.g., "Nastepna: Lantech"
                if let nextVendor = viewModel.recurringNextVendorText {
                    Text(nextVendor)
                        .font(subtitleFont)
                        .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                        .lineLimit(1)
                }

                // Line 4: Days until (13pt) - e.g., "Za 12 dni"
                if let daysUntil = viewModel.recurringDaysUntilText {
                    Text(daysUntil)
                        .font(subtitleFont)
                        .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                        .lineLimit(1)
                }

                // Warning: Missing recurring count (if any)
                if viewModel.state.missingRecurringCount > 0 {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                        Text(String.localized(L10n.Home.missingCount, with: viewModel.state.missingRecurringCount))
                    }
                    .font(statFont)
                    .foregroundStyle(tokens.warningColor(for: colorScheme))
                    .lineLimit(1)
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            // Manage CTA - always at bottom - LEVEL 5: Button Text
            // Opens the RecurringOverviewView as a sheet
            Button {
                showRecurringOverview = true
            } label: {
                HStack(spacing: 4) {
                    Text(L10n.Home.manage.localized)
                        .font(buttonFont)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(currentStyle == .midnightAurora ? AuroraPalette.accentBlue : accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background {
            StyledHomeCardBackground(accentColor: accentColor, cardType: .tile)
        }
        .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
        .modifier(HomeCardBorderModifier(tokens: tokens, accentColor: accentColor))
        .modifier(HomeCardShadowModifier(tokens: tokens, accentColor: accentColor, cardType: .tile))
        .sheet(isPresented: $showRecurringOverview) {
            RecurringOverviewView()
                .environment(environment)
        }
    }

    // MARK: - Next Payments Section

    @ViewBuilder
    private func nextPaymentsSection(viewModel: HomeViewModel) -> some View {
        let accentColor = currentStyle == .midnightAurora
            ? AuroraPalette.accentBlue
            : tokens.primaryColor(for: colorScheme)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header with icon and "See All" button - LEVEL 1: Section Title
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(sectionIconFont)
                        .foregroundStyle(accentColor)

                    Text(L10n.Home.nextPayments.localized)
                        .font(sectionTitleFont)
                        .tracking(sectionTitleTracking)
                        .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))
                }

                Spacer()

                // "See All" button - navigates to Documents tab - LEVEL 5: Button Text
                Button {
                    onNavigateToDocuments?()
                } label: {
                    HStack(spacing: 4) {
                        Text(L10n.Home.seeAllUpcoming.localized)
                            .font(buttonFont)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        seeAllButtonBackground(color: accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, tokens.cardPadding)

            // Payment rows with styled appearance
            VStack(spacing: 0) {
                ForEach(Array(viewModel.state.nextPayments.enumerated()), id: \.element.id) { index, payment in
                    NavigationLink(value: DocumentNavigationValue(documentId: payment.documentId)) {
                        paymentRow(payment: payment)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    // Divider between rows (not after last) - matches demo line 406-408
                    if index < viewModel.state.nextPayments.count - 1 {
                        Divider()
                            .frame(height: 1)
                            .background(currentStyle == .midnightAurora ? Color.white.opacity(0.15) : tokens.separatorColor(for: colorScheme))
                            .padding(.leading, 40)
                    }
                }
            }
            .padding(12)
            .background {
                StyledHomeCardBackground(accentColor: nil, cardType: .standard)
            }
            .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
            .modifier(HomeCardBorderModifier(tokens: tokens, accentColor: nil))
            .modifier(HomeCardShadowModifier(tokens: tokens, accentColor: nil, cardType: .standard))
        }
    }

    @ViewBuilder
    private func paymentRow(payment: HomePaymentItem) -> some View {
        HStack(spacing: 12) {
            // Vendor name and due info
            VStack(alignment: .leading, spacing: 4) {
                // LEVEL 7: Payment Row - Vendor Name
                Text(payment.vendorName)
                    .font(paymentRowPrimaryFont)
                    .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))
                    .lineLimit(1)

                // LEVEL 8: Payment Row - Due Info
                Text(dueDateLabel(for: payment))
                    .font(paymentRowSecondaryFont)
                    .foregroundStyle(payment.isOverdue ? tokens.errorColor(for: colorScheme) : tokens.textSecondaryColor(for: colorScheme))
            }

            Spacer()

            // LEVEL 9: Payment Row - Amount
            Text(formatCurrency(payment.amount, currency: payment.currency))
                .font(paymentRowAmountFont(design: tokens.heroNumberDesign))
                .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))
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
        let accentColor = currentStyle == .midnightAurora
            ? AuroraPalette.accentBlue
            : tokens.primaryColor(for: colorScheme)

        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header with icon - LEVEL 1: Section Title
            HStack(spacing: Spacing.xs) {
                Image(systemName: "chart.pie.fill")
                    .font(sectionIconFont)
                    .foregroundStyle(accentColor.opacity(0.7))

                Text(L10n.Home.thisMonth.localized)
                    .font(sectionTitleFont)
                    .tracking(sectionTitleTracking)
                    .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))

                Text("- \(L10n.Home.paymentStatus.localized)")
                    .font(sectionTitleFont)
                    .tracking(sectionTitleTracking)
                    .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
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

                // Stats column with styled appearance - LEVEL 10: Stat Row Labels/Values
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    styledStatRow(
                        label: L10n.Home.Donut.paid.localized,
                        value: "\(viewModel.state.monthPaidCount)",
                        color: tokens.successColor(for: colorScheme)
                    )
                    styledStatRow(
                        label: L10n.Home.Donut.due.localized,
                        value: "\(viewModel.state.monthDueCount)",
                        color: tokens.warningColor(for: colorScheme)
                    )
                    styledStatRow(
                        label: L10n.Home.Donut.overdue.localized,
                        value: "\(viewModel.state.monthOverdueCount)",
                        color: tokens.errorColor(for: colorScheme)
                    )
                }
            }

            // Bottom line: unpaid total - LEVEL 11: Info/Footnote Text
            if viewModel.state.monthUnpaidTotal > 0 {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))

                    Text(String.localized(L10n.Home.unpaidTotal, with: viewModel.formattedMonthUnpaidTotal))
                        .font(footnoteFont)
                        .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                }
                .padding(.top, Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(tokens.cardPadding)
        .background {
            StyledHomeCardBackground(accentColor: nil, cardType: .standard)
        }
        .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
        .modifier(HomeCardBorderModifier(tokens: tokens, accentColor: nil))
        .modifier(HomeCardShadowModifier(tokens: tokens, accentColor: nil, cardType: .standard))
    }

    /// Styled stat row that adapts to current UI style - LEVEL 10: Stat Row Labels/Values
    @ViewBuilder
    private func styledStatRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            // Color indicator - style-dependent
            if currentStyle == .midnightAurora {
                // Glow effect for Midnight Aurora
                ZStack {
                    Circle()
                        .fill(color.opacity(0.3))
                        .frame(width: 16, height: 16)

                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .shadow(color: color.opacity(0.5), radius: 2)
                }
            } else if currentStyle == .paperMinimal {
                // Simple line for Paper Minimal
                Rectangle()
                    .fill(color)
                    .frame(width: 12, height: 2)
            } else {
                // Filled circle for Warm Finance
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
            }

            Text(label)
                .font(statFont)
                .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))

            Spacer()

            Text(value)
                .font(statBoldFont)
                .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        let accentColor = currentStyle == .midnightAurora
            ? AuroraPalette.accentBlue
            : tokens.primaryColor(for: colorScheme)

        VStack(spacing: Spacing.xl) {
            Spacer()

            // Icon with glow effect
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)

                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(accentColor.opacity(0.7))
            }

            VStack(spacing: Spacing.sm) {
                // LEVEL 2: Primary Content/Body Text (empty state title is more prominent)
                Text(L10n.Home.noPaymentsTitle.localized)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))

                // LEVEL 2: Primary Content/Body Text
                Text(L10n.Home.noPaymentsMessage.localized)
                    .font(bodyFont)
                    .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                    .multilineTextAlignment(.center)
            }

            // Link to scan - LEVEL 5: Button Text
            Button {
                onNavigateToScan?()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "doc.viewfinder")
                    Text(L10n.Home.goToScan.localized)
                }
                .font(buttonFont)
                .foregroundStyle(accentColor)
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
            // Large style-aware logo
            LargeHomeHandwrittenLogo()

            // Tagline - adapts font design to current style
            Text(currentStyle == .midnightAurora ? L10n.Home.paymentTracker.localized : L10n.App.tagline.localized)
                .font(.system(size: currentStyle == .midnightAurora ? 11 : 12, weight: .medium, design: currentStyle == .midnightAurora ? .default : .rounded))
                .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                .tracking(currentStyle == .midnightAurora ? 3 : 1.2)
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
                recurringDateService: environment.recurringDateService,
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

/// Large prominent logo for the Home view scrolling header.
/// Adapts styling based on the current UI style:
/// - Midnight Aurora: Clean gradient text without rotation (matches demo)
/// - Other styles: Handwritten style with italic and rotation effects
///
/// Accessibility:
/// - Respects reduceTransparency: disables blur/shadow layers
/// - Respects reduceMotion: disables animated scan effect
/// - Works in both light and dark mode
struct LargeHomeHandwrittenLogo: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.uiStyle) private var style

    @State private var scanPosition: CGFloat = -1.0

    /// Logo gradient colors - sophisticated blue tones (for non-Aurora styles)
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
        if style == .midnightAurora {
            // Midnight Aurora style: clean gradient logo without rotation (matches demo)
            midnightAuroraLogo
        } else {
            // Other styles: handwritten style with effects
            handwrittenLogo
        }
    }

    // MARK: - Midnight Aurora Logo (matches demo)

    private var midnightAuroraLogo: some View {
        HStack(alignment: .bottom, spacing: 2) {
            Text("Du")
                .font(.system(size: 42, weight: .medium, design: .default))
                .foregroundStyle(AuroraGradients.logoDu)

            Text("Easy")
                .font(.system(size: 42, weight: .light, design: .default))
                .foregroundStyle(AuroraGradients.logoEasy)
        }
    }

    // MARK: - Handwritten Logo (for other styles)

    private var handwrittenLogo: some View {
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

// MARK: - Home Card Modifiers

/// Border modifier that adapts to current style tokens
/// NOTE: For midnightAurora, EnhancedMidnightAuroraCard already includes a border,
/// so we do NOT add another border here to avoid double borders.
private struct HomeCardBorderModifier: ViewModifier {
    let tokens: UIStyleTokens
    let accentColor: Color?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency || !tokens.usesCardBorders {
            content
        } else {
            switch tokens.style {
            case .defaultStyle:
                // Default style uses separate border modifier
                content.luxuryCardBorder(accentColor: accentColor, cornerRadius: tokens.cardCornerRadius)

            case .midnightAurora:
                // EnhancedMidnightAuroraCard already has border built-in (Layer 4)
                // Do NOT add another border to avoid double borders
                content

            case .paperMinimal:
                content.overlay {
                    RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                        .strokeBorder(tokens.cardBorderColor(for: colorScheme), lineWidth: 1)
                }

            case .warmFinance:
                content
            }
        }
    }
}

/// Shadow modifier that adapts to current style tokens
private struct HomeCardShadowModifier: ViewModifier {
    let tokens: UIStyleTokens
    let accentColor: Color?
    let cardType: StyledHomeCardBackground.CardType

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if !tokens.usesShadows {
            content
        } else {
            switch tokens.style {
            case .defaultStyle:
                // Original luxury shadow
                let intensity: LuxuryCardShadowModifier.ShadowIntensity = {
                    switch cardType {
                    case .hero: return .high
                    case .tile, .standard: return .medium
                    }
                }()
                content.luxuryCardShadow(accentColor: accentColor, intensity: intensity)

            case .midnightAurora:
                // ENHANCED dual shadow system (from demo)
                content
                    .shadow(color: Color.black.opacity(0.4), radius: 12, y: 6)
                    .shadow(color: (accentColor ?? Color.blue).opacity(0.25), radius: 20, y: 10)

            case .paperMinimal:
                content

            case .warmFinance:
                let shadow = tokens.cardShadow(for: colorScheme)
                content.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
            }
        }
    }
}

/// CTA button shadow modifier
private struct CTAButtonShadowModifier: ViewModifier {
    let tokens: UIStyleTokens
    let color: Color

    func body(content: Content) -> some View {
        if tokens.usesShadows {
            content.shadow(color: color.opacity(0.3), radius: 4, y: 2)
        } else {
            content
        }
    }
}

// MARK: - Home View Helper Views

extension HomeView {
    /// CTA button background based on style
    @ViewBuilder
    func ctaButtonBackground(color: Color) -> some View {
        if currentStyle == .paperMinimal {
            color
        } else {
            LinearGradient(
                colors: [color, color.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// CTA button shape based on style
    var ctaButtonShape: AnyShape {
        if currentStyle == .paperMinimal {
            AnyShape(RoundedRectangle(cornerRadius: tokens.buttonCornerRadius, style: .continuous))
        } else {
            AnyShape(Capsule())
        }
    }

    /// "See All" button background based on style
    @ViewBuilder
    func seeAllButtonBackground(color: Color) -> some View {
        if currentStyle == .paperMinimal {
            RoundedRectangle(cornerRadius: tokens.badgeCornerRadius)
                .fill(color.opacity(colorScheme == .light ? 0.08 : 0.15))
        } else {
            Capsule()
                .fill(color.opacity(colorScheme == .light ? 0.1 : 0.2))
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environment(AppEnvironment.preview)
}
