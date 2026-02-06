import SwiftUI

// MARK: - Vendor History Anomaly View

/// View showing all anomalies and history for a specific vendor.
/// Displays risk assessment, bank account history, and invoice patterns.
/// Follows iOS 26 Liquid Glass design system.
///
/// Features:
/// - Risk level indicator (low/medium/high/critical)
/// - Bank account history with verification status
/// - Invoice pattern visualization
/// - All historical anomalies for the vendor
struct VendorHistoryAnomalyView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    /// The vendor fingerprint to analyze
    let vendorFingerprint: String

    /// The vendor display name
    let vendorName: String

    @State private var viewModel: AnomalyViewModel?

    private var isAurora: Bool {
        style == .midnightAurora
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            backgroundView
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.md) {
                    if let viewModel = viewModel, let history = viewModel.vendorHistory {
                        vendorHistoryContent(history: history)
                    } else if viewModel?.isLoading == true {
                        loadingView
                    } else {
                        loadingView
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Vendor History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            setupViewModel()
            await viewModel?.loadVendorHistory(vendorFingerprint: vendorFingerprint)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundView: some View {
        if isAurora {
            EnhancedMidnightAuroraBackground()
        } else {
            Color(UIColor.systemGroupedBackground)
        }
    }

    // MARK: - Loading State

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .tint(isAurora ? Color.white : nil)

            Text("Analyzing vendor history...")
                .font(Typography.bodyText)
                .foregroundStyle(isAurora ? Color.white.opacity(0.7) : .secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Main Content

    @ViewBuilder
    private func vendorHistoryContent(history: VendorHistoryAnalysisResult) -> some View {
        VStack(spacing: Spacing.lg) {
            // Vendor header with risk indicator
            vendorHeaderCard(history: history)

            // Risk assessment summary
            riskAssessmentCard(history: history)

            // Bank account history
            if !history.bankAccounts.isEmpty {
                bankAccountHistorySection(accounts: history.bankAccounts)
            }

            // Invoice pattern
            if let pattern = history.invoicePattern, pattern.hasEstablishedPattern {
                invoicePatternSection(pattern: pattern)
            }

            // Anomaly history
            if !history.anomalies.isEmpty {
                anomalyHistorySection(anomalies: history.anomalies)
            }
        }
    }

    // MARK: - Vendor Header Card

    @ViewBuilder
    private func vendorHeaderCard(history: VendorHistoryAnalysisResult) -> some View {
        StyledDetailCard {
            HStack(spacing: Spacing.md) {
                // Vendor icon
                ZStack {
                    Circle()
                        .fill(riskLevelColor(history.riskLevel).opacity(isAurora ? 0.25 : 0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: "building.2")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(riskLevelColor(history.riskLevel))
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(vendorName)
                        .font(Typography.title3)
                        .foregroundStyle(isAurora ? Color.white : .primary)

                    HStack(spacing: Spacing.xs) {
                        // Document count
                        Label("\(history.documentCount) documents", systemImage: "doc.text")
                            .font(Typography.caption1)
                            .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)

                        // Risk level badge
                        riskLevelBadge(history.riskLevel)
                    }
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func riskLevelBadge(_ level: VendorRiskLevel) -> some View {
        let color = riskLevelColor(level)

        HStack(spacing: 4) {
            if isAurora {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }

            Text(level.displayName)
                .font(Typography.stat.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background {
            Capsule()
                .fill(color.opacity(isAurora ? 0.25 : 0.15))
                .overlay {
                    if isAurora {
                        Capsule()
                            .strokeBorder(color.opacity(0.5), lineWidth: 1)
                    }
                }
        }
    }

    // MARK: - Risk Assessment Card

    @ViewBuilder
    private func riskAssessmentCard(history: VendorHistoryAnalysisResult) -> some View {
        StyledDetailCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Section header
                HStack {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(riskLevelColor(history.riskLevel))

                    Text("Risk Assessment")
                        .font(Typography.headline)
                        .foregroundStyle(isAurora ? Color.white : .primary)

                    Spacer()
                }

                // Summary text
                Text(history.summary)
                    .font(Typography.bodyText)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.8) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Risk factors
                VStack(spacing: Spacing.xs) {
                    riskFactorRow(
                        icon: "exclamationmark.triangle",
                        label: "Open Anomalies",
                        value: "\(history.anomalies.filter { !$0.isResolved }.count)",
                        isWarning: history.anomalies.filter { !$0.isResolved }.count > 0
                    )

                    riskFactorRow(
                        icon: "creditcard",
                        label: "Bank Accounts",
                        value: "\(history.bankAccounts.count)",
                        isWarning: history.bankAccounts.count > 1
                    )

                    riskFactorRow(
                        icon: "chart.line.uptrend.xyaxis",
                        label: "Billing Pattern",
                        value: history.invoicePattern?.hasEstablishedPattern == true ? "Established" : "Not Established",
                        isWarning: false
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func riskFactorRow(icon: String, label: String, value: String, isWarning: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(isWarning ? AppColors.warning : (isAurora ? Color.white.opacity(0.5) : .secondary))
                .frame(width: 20)

            Text(label)
                .font(Typography.caption1)
                .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)

            Spacer()

            Text(value)
                .font(Typography.caption1.weight(.medium))
                .foregroundStyle(isWarning ? AppColors.warning : (isAurora ? Color.white : .primary))
        }
        .padding(.vertical, Spacing.xxs)
    }

    // MARK: - Bank Account History Section

    @ViewBuilder
    private func bankAccountHistorySection(accounts: [VendorBankAccountHistory]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header
            sectionHeader(title: "Bank Account History", icon: "creditcard.fill")

            StyledDetailCard {
                VStack(spacing: Spacing.sm) {
                    ForEach(accounts, id: \.id) { account in
                        bankAccountRow(account: account)

                        if account.id != accounts.last?.id {
                            Divider()
                                .background(isAurora ? Color.white.opacity(0.1) : nil)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bankAccountRow(account: VendorBankAccountHistory) -> some View {
        HStack(spacing: Spacing.sm) {
            // Status icon
            ZStack {
                Circle()
                    .fill(accountStatusColor(account).opacity(isAurora ? 0.25 : 0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: accountStatusIcon(account))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accountStatusColor(account))
            }

            VStack(alignment: .leading, spacing: 2) {
                // Masked IBAN
                Text(account.maskedIBAN)
                    .font(Typography.monospacedBody)
                    .foregroundStyle(isAurora ? Color.white : .primary)

                HStack(spacing: Spacing.xs) {
                    // Primary badge
                    if account.isPrimary {
                        Text("Primary")
                            .font(Typography.caption2)
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.primary.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    // Usage count
                    Text("\(account.documentCount) uses")
                        .font(Typography.caption1)
                        .foregroundStyle(isAurora ? Color.white.opacity(0.5) : .secondary)

                    // Verification status
                    Text(account.verificationStatus.displayName)
                        .font(Typography.caption2)
                        .foregroundStyle(accountStatusColor(account))
                }
            }

            Spacer()

            // First seen date
            VStack(alignment: .trailing, spacing: 2) {
                Text("First seen")
                    .font(Typography.caption2)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.4) : Color.secondary.opacity(0.7))

                Text(formattedDate(account.firstSeenAt))
                    .font(Typography.caption1)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
            }
        }
    }

    private func accountStatusIcon(_ account: VendorBankAccountHistory) -> String {
        switch account.verificationStatus {
        case .verified: return "checkmark.circle.fill"
        case .unverified: return "questionmark.circle"
        case .suspicious: return "exclamationmark.triangle.fill"
        case .fraudulent: return "xmark.octagon.fill"
        }
    }

    private func accountStatusColor(_ account: VendorBankAccountHistory) -> Color {
        switch account.verificationStatus {
        case .verified: return AppColors.success
        case .unverified: return .secondary
        case .suspicious: return AppColors.warning
        case .fraudulent: return AppColors.error
        }
    }

    // MARK: - Invoice Pattern Section

    @ViewBuilder
    private func invoicePatternSection(pattern: VendorInvoicePattern) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header
            sectionHeader(title: "Invoice Pattern", icon: "chart.bar.fill")

            StyledDetailCard {
                VStack(spacing: Spacing.md) {
                    // Pattern stats
                    HStack(spacing: Spacing.lg) {
                        patternStatView(
                            label: "Invoices",
                            value: "\(pattern.invoiceCount)"
                        )

                        if let medianDay = pattern.medianDayOfMonth {
                            patternStatView(
                                label: "Typical Day",
                                value: "Day \(medianDay)"
                            )
                        }

                        if let avgAmount = pattern.averageAmount {
                            patternStatView(
                                label: "Avg Amount",
                                value: formatCurrency(avgAmount, currency: pattern.currency ?? "USD")
                            )
                        }
                    }

                    // Amount range
                    if let minAmount = pattern.minAmountValue, let maxAmount = pattern.maxAmountValue {
                        HStack {
                            Text("Amount Range")
                                .font(Typography.caption1)
                                .foregroundStyle(isAurora ? Color.white.opacity(0.5) : .secondary)

                            Spacer()

                            Text(formatAmountRange(min: minAmount, max: maxAmount, currency: pattern.currency ?? "USD"))
                                .font(Typography.caption1.weight(.medium))
                                .foregroundStyle(isAurora ? Color.white : .primary)
                        }
                    }

                    // Typical days visualization
                    if !pattern.typicalDaysOfMonth.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Typical Invoice Days")
                                .font(Typography.caption1)
                                .foregroundStyle(isAurora ? Color.white.opacity(0.5) : .secondary)

                            HStack(spacing: Spacing.xs) {
                                ForEach(pattern.typicalDaysOfMonth.sorted(), id: \.self) { day in
                                    Text("\(day)")
                                        .font(Typography.stat.weight(.medium))
                                        .foregroundStyle(isAurora ? Color.white : .primary)
                                        .padding(.horizontal, Spacing.xs)
                                        .padding(.vertical, Spacing.xxs)
                                        .background {
                                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                                .fill(AppColors.primary.opacity(isAurora ? 0.25 : 0.15))
                                        }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func patternStatView(label: String, value: String) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(value)
                .font(Typography.heroNumber())
                .foregroundStyle(isAurora ? Color.white : .primary)

            Text(label)
                .font(Typography.caption2)
                .foregroundStyle(isAurora ? Color.white.opacity(0.5) : .secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Anomaly History Section

    @ViewBuilder
    private func anomalyHistorySection(anomalies: [DocumentAnomaly]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header
            sectionHeader(
                title: "Anomaly History",
                icon: "exclamationmark.shield.fill",
                count: anomalies.count
            )

            // Group by resolved status
            let unresolved = anomalies.filter { !$0.isResolved }
            let resolved = anomalies.filter { $0.isResolved }

            if !unresolved.isEmpty {
                ForEach(unresolved, id: \.id) { anomaly in
                    compactAnomalyRow(anomaly: anomaly, isResolved: false)
                }
            }

            if !resolved.isEmpty {
                Text("Resolved")
                    .font(Typography.sectionTitle)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.5) : .secondary)
                    .padding(.top, Spacing.xs)

                ForEach(resolved, id: \.id) { anomaly in
                    compactAnomalyRow(anomaly: anomaly, isResolved: true)
                }
            }
        }
    }

    @ViewBuilder
    private func compactAnomalyRow(anomaly: DocumentAnomaly, isResolved: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            // Type icon
            Image(systemName: anomaly.type.iconName)
                .font(.caption)
                .foregroundStyle(isResolved ? .secondary : colorForSeverity(anomaly.severity))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(anomaly.type.displayName)
                    .font(Typography.caption1.weight(.medium))
                    .foregroundStyle(isResolved ? (isAurora ? Color.white.opacity(0.5) : .secondary) : (isAurora ? Color.white : .primary))

                Text(formattedDate(anomaly.detectedAt))
                    .font(Typography.caption2)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.4) : Color.secondary.opacity(0.7))
            }

            Spacer()

            // Resolution or severity badge
            if isResolved, let resolution = anomaly.resolution {
                Text(resolution.displayName)
                    .font(Typography.caption2)
                    .foregroundStyle(resolutionColor(resolution))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(resolutionColor(resolution).opacity(0.15))
                    .clipShape(Capsule())
            } else {
                severityBadge(anomaly.severity)
            }
        }
        .padding(Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(isAurora ? AuroraPalette.sectionGlass : Color(UIColor.secondarySystemGroupedBackground))
        }
    }

    @ViewBuilder
    private func severityBadge(_ severity: AnomalySeverity) -> some View {
        let color = colorForSeverity(severity)

        Text(severity.displayName)
            .font(Typography.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(color.opacity(isAurora ? 0.25 : 0.15))
            }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(title: String, icon: String, count: Int? = nil) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isAurora ? AuroraPalette.accentBlue : AppColors.primary)

            Text(title)
                .font(Typography.sectionTitle.weight(.semibold))
                .foregroundStyle(isAurora ? Color.white.opacity(0.8) : .secondary)
                .textCase(.uppercase)

            if let count = count {
                Text("(\(count))")
                    .font(Typography.sectionTitle)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.5) : Color.secondary.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.xxs)
    }

    // MARK: - Helpers

    private func riskLevelColor(_ level: VendorRiskLevel) -> Color {
        switch level {
        case .low: return AppColors.success
        case .medium: return AppColors.warning
        case .high: return AppColors.warning
        case .critical: return AppColors.error
        }
    }

    private func colorForSeverity(_ severity: AnomalySeverity) -> Color {
        switch severity {
        case .critical: return AppColors.error
        case .warning: return AppColors.warning
        case .info: return AppColors.info
        }
    }

    private func resolutionColor(_ resolution: AnomalyResolution) -> Color {
        switch resolution {
        case .dismissed: return .secondary
        case .confirmedSafe: return AppColors.success
        case .confirmedFraud: return AppColors.error
        case .autoResolved: return AppColors.info
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func setupViewModel() {
        guard viewModel == nil else { return }
        viewModel = environment.makeAnomalyViewModel()
    }

    private func formatCurrency(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "-"
    }

    private func formatAmountRange(min: Double, max: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let minStr = formatter.string(from: NSNumber(value: min)) ?? "-"
        let maxStr = formatter.string(from: NSNumber(value: max)) ?? "-"
        return "\(minStr) - \(maxStr)"
    }
}

// MARK: - VendorBankAccountHistory Extensions

extension VendorBankAccountHistory {
    /// Returns a masked version of the IBAN (shows first 4 and last 4 characters)
    var maskedIBAN: String {
        guard iban.count > 8 else { return "****" }
        let prefix = String(iban.prefix(4))
        let suffix = String(iban.suffix(4))
        return "\(prefix) **** \(suffix)"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VendorHistoryAnomalyView(
            vendorFingerprint: "test-fingerprint",
            vendorName: "Electric Company"
        )
    }
    .environment(AppEnvironment.preview)
}
