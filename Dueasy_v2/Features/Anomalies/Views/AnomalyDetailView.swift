import SwiftUI

// MARK: - Anomaly Detail View

/// Full-screen view showing all anomalies for a document.
/// Displays anomalies grouped by severity with resolution actions.
/// Follows iOS 26 Liquid Glass design system.
///
/// Features:
/// - Anomalies grouped by severity (critical first)
/// - Shows type, summary, detection timestamp, context data
/// - Resolution actions: Dismiss, Confirm Safe, Confirm Fraud
/// - Vendor history link
struct AnomalyDetailView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    /// The document ID to load anomalies for
    let documentId: UUID

    /// The vendor fingerprint for linking to vendor history
    let vendorFingerprint: String?

    /// The document title for display
    let documentTitle: String

    @State private var viewModel: AnomalyViewModel?
    @State private var selectedAnomaly: DocumentAnomaly?
    @State private var showingResolutionSheet = false
    @State private var showingVendorHistory = false
    @State private var resolutionNotes = ""

    private var isAurora: Bool {
        style == .midnightAurora
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundView
                    .ignoresSafeArea()

                // Content
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        if let viewModel = viewModel {
                            if viewModel.isLoading {
                                loadingView
                            } else if viewModel.documentAnomalies.isEmpty {
                                emptyStateView
                            } else {
                                anomalyListContent(viewModel: viewModel)
                            }
                        } else {
                            loadingView
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Security Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(isAurora ? AuroraPalette.accentBlue : AppColors.primary)
                }

                if vendorFingerprint != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingVendorHistory = true
                        } label: {
                            Label("Vendor History", systemImage: "person.crop.circle.badge.clock")
                        }
                        .foregroundStyle(isAurora ? AuroraPalette.accentBlue : AppColors.primary)
                    }
                }
            }
            .task {
                setupViewModel()
                await viewModel?.loadAnomalies(forDocumentId: documentId)
            }
            .sheet(isPresented: $showingResolutionSheet) {
                if let anomaly = selectedAnomaly {
                    resolutionSheet(for: anomaly)
                }
            }
            .navigationDestination(isPresented: $showingVendorHistory) {
                if let fingerprint = vendorFingerprint {
                    VendorHistoryAnomalyView(
                        vendorFingerprint: fingerprint,
                        vendorName: documentTitle
                    )
                }
            }
        }
        .presentationDragIndicator(.visible)
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

    // MARK: - Loading & Empty States

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .tint(isAurora ? Color.white : nil)

            Text("Loading security alerts...")
                .font(Typography.bodyText)
                .foregroundStyle(isAurora ? Color.white.opacity(0.7) : .secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.success)

            Text("All Clear")
                .font(Typography.title3)
                .foregroundStyle(isAurora ? Color.white : .primary)

            Text("No security concerns detected for this document.")
                .font(Typography.bodyText)
                .foregroundStyle(isAurora ? Color.white.opacity(0.7) : .secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(Spacing.lg)
    }

    // MARK: - Anomaly List Content

    @ViewBuilder
    private func anomalyListContent(viewModel: AnomalyViewModel) -> some View {
        VStack(spacing: Spacing.lg) {
            // Summary header
            summaryHeader(viewModel: viewModel)

            // Anomalies by severity
            ForEach(viewModel.anomaliesBySeverity, id: \.severity) { group in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Section header
                    severitySectionHeader(severity: group.severity, count: group.anomalies.count)

                    // Anomaly cards
                    ForEach(group.anomalies, id: \.id) { anomaly in
                        AnomalyCardView(
                            anomaly: anomaly,
                            onResolve: {
                                selectedAnomaly = anomaly
                                showingResolutionSheet = true
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Summary Header

    @ViewBuilder
    private func summaryHeader(viewModel: AnomalyViewModel) -> some View {
        StyledDetailCard {
            HStack(spacing: Spacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(summaryIconBackgroundColor(viewModel: viewModel))
                        .frame(width: 48, height: 48)

                    Image(systemName: summaryIconName(viewModel: viewModel))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(summaryIconColor(viewModel: viewModel))
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(documentTitle)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(isAurora ? Color.white : .primary)
                        .lineLimit(1)

                    Text("\(viewModel.totalUnresolvedCount) issue\(viewModel.totalUnresolvedCount == 1 ? "" : "s") requiring attention")
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(isAurora ? Color.white.opacity(0.7) : .secondary)
                }

                Spacer()
            }
        }
    }

    private func summaryIconName(viewModel: AnomalyViewModel) -> String {
        guard let severity = viewModel.highestUnresolvedSeverity else {
            return "checkmark.shield.fill"
        }
        switch severity {
        case .critical: return "shield.slash.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func summaryIconColor(viewModel: AnomalyViewModel) -> Color {
        guard let severity = viewModel.highestUnresolvedSeverity else {
            return AppColors.success
        }
        return colorForSeverity(severity)
    }

    private func summaryIconBackgroundColor(viewModel: AnomalyViewModel) -> Color {
        summaryIconColor(viewModel: viewModel).opacity(isAurora ? 0.25 : 0.15)
    }

    // MARK: - Section Header

    @ViewBuilder
    private func severitySectionHeader(severity: AnomalySeverity, count: Int) -> some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(colorForSeverity(severity))
                .frame(width: 8, height: 8)

            Text(severity.displayName)
                .font(Typography.sectionTitle.weight(.semibold))
                .foregroundStyle(isAurora ? Color.white.opacity(0.8) : .secondary)
                .textCase(.uppercase)

            Text("(\(count))")
                .font(Typography.sectionTitle)
                .foregroundStyle(isAurora ? Color.white.opacity(0.5) : Color.secondary.opacity(0.7))

            Spacer()
        }
        .padding(.horizontal, Spacing.xxs)
    }

    // MARK: - Resolution Sheet

    @ViewBuilder
    private func resolutionSheet(for anomaly: DocumentAnomaly) -> some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                // Anomaly summary
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Image(systemName: anomaly.type.iconName)
                            .foregroundStyle(colorForSeverity(anomaly.severity))

                        Text(anomaly.type.displayName)
                            .font(Typography.headline)
                    }

                    Text(anomaly.summary)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))

                // Resolution options
                VStack(spacing: Spacing.sm) {
                    // Dismiss
                    resolutionButton(
                        title: "Dismiss",
                        subtitle: "I've reviewed this and it's not a concern",
                        icon: "xmark.circle",
                        color: .secondary,
                        action: {
                            Task {
                                await viewModel?.dismissAnomaly(anomaly)
                                showingResolutionSheet = false
                                selectedAnomaly = nil
                            }
                        }
                    )

                    // Confirm Safe
                    resolutionButton(
                        title: "Confirm Safe",
                        subtitle: "I've verified this is legitimate",
                        icon: "checkmark.circle",
                        color: AppColors.success,
                        action: {
                            Task {
                                await viewModel?.confirmSafe(anomaly, notes: resolutionNotes.isEmpty ? nil : resolutionNotes)
                                showingResolutionSheet = false
                                selectedAnomaly = nil
                            }
                        }
                    )

                    // Confirm Fraud
                    resolutionButton(
                        title: "Confirm Fraud",
                        subtitle: "This is a fraudulent document",
                        icon: "exclamationmark.octagon",
                        color: AppColors.error,
                        action: {
                            Task {
                                await viewModel?.confirmFraud(anomaly, notes: resolutionNotes.isEmpty ? nil : resolutionNotes)
                                showingResolutionSheet = false
                                selectedAnomaly = nil
                            }
                        }
                    )
                }

                // Optional notes
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Notes (optional)")
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)

                    TextField("Add any notes about this resolution...", text: $resolutionNotes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Resolve Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingResolutionSheet = false
                        selectedAnomaly = nil
                        resolutionNotes = ""
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func resolutionButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func colorForSeverity(_ severity: AnomalySeverity) -> Color {
        switch severity {
        case .critical: return AppColors.error
        case .warning: return AppColors.warning
        case .info: return AppColors.info
        }
    }

    private func setupViewModel() {
        guard viewModel == nil else { return }
        viewModel = environment.makeAnomalyViewModel()
    }
}

// MARK: - Anomaly Card View

/// Individual anomaly card showing details and resolution action.
struct AnomalyCardView: View {

    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    let anomaly: DocumentAnomaly
    let onResolve: () -> Void

    private var isAurora: Bool {
        style == .midnightAurora
    }

    var body: some View {
        StyledDetailCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Header: Type and severity
                HStack {
                    // Type icon
                    Image(systemName: anomaly.type.iconName)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(colorForSeverity(anomaly.severity))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(anomaly.type.displayName)
                            .font(Typography.listRowPrimary)
                            .foregroundStyle(isAurora ? Color.white : .primary)

                        Text(formattedDate(anomaly.detectedAt))
                            .font(Typography.stat)
                            .foregroundStyle(isAurora ? Color.white.opacity(0.5) : .secondary)
                    }

                    Spacer()

                    // Severity badge
                    severityBadge
                }

                // Summary
                Text(anomaly.summary)
                    .font(Typography.bodyText)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.8) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Context details (if available)
                if let context = anomaly.contextData {
                    contextDetailsView(context: context)
                }

                // Detailed description
                Text(anomaly.type.detailedDescription)
                    .font(Typography.caption1)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.6) : Color.secondary.opacity(0.8))
                    .padding(.top, Spacing.xxs)

                // Resolve button
                Button(action: onResolve) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Resolve")
                    }
                    .font(Typography.buttonText)
                    .foregroundStyle(isAurora ? AuroraPalette.accentBlue : AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs)
                    .background {
                        if isAurora {
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(AuroraPalette.accentBlue.opacity(0.15))
                                .overlay {
                                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                                        .strokeBorder(AuroraPalette.accentBlue.opacity(0.3), lineWidth: 1)
                                }
                        } else {
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(AppColors.primary.opacity(0.1))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var severityBadge: some View {
        let color = colorForSeverity(anomaly.severity)

        HStack(spacing: 4) {
            if isAurora {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }

            Text(anomaly.severity.displayName)
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

    @ViewBuilder
    private func contextDetailsView(context: AnomalyContextData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Bank account change context
            if let previousBank = context.previousBankAccount, let newBank = context.newBankAccount {
                contextRow(label: "Previous Account", value: previousBank)
                contextRow(label: "New Account", value: newBank)
            }

            // Amount context
            if let currentAmount = context.currentAmount, let expectedAmount = context.expectedAmount {
                contextRow(label: "Current Amount", value: formatCurrency(currentAmount))
                contextRow(label: "Expected Amount", value: formatCurrency(expectedAmount))

                if let deviation = context.deviationPercentage {
                    contextRow(label: "Deviation", value: String(format: "%.1f%%", deviation))
                }
            }

            // Timing context
            if let expectedDay = context.expectedDayOfMonth, let actualDay = context.actualDayOfMonth {
                contextRow(label: "Expected Day", value: "Day \(expectedDay)")
                contextRow(label: "Actual Day", value: "Day \(actualDay)")
            }

            // Vendor spoofing context
            if let similarVendor = context.similarVendorName {
                contextRow(label: "Similar To", value: similarVendor)
            }

            // Confidence score
            if let confidence = context.confidenceScore {
                contextRow(label: "Confidence", value: String(format: "%.0f%%", confidence * 100))
            }
        }
        .padding(Spacing.xs)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(isAurora ? Color.white.opacity(0.05) : Color(UIColor.tertiarySystemGroupedBackground))
        }
    }

    @ViewBuilder
    private func contextRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Typography.caption1)
                .foregroundStyle(isAurora ? Color.white.opacity(0.5) : .secondary)

            Spacer()

            Text(value)
                .font(Typography.caption1.weight(.medium))
                .foregroundStyle(isAurora ? Color.white.opacity(0.8) : .primary)
        }
    }

    private func colorForSeverity(_ severity: AnomalySeverity) -> Color {
        switch severity {
        case .critical: return AppColors.error
        case .warning: return AppColors.warning
        case .info: return AppColors.info
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

// MARK: - AnomalyType Icon Extension

extension AnomalyType {
    var iconName: String {
        switch self {
        case .bankAccountChanged, .bankAccountCountryMismatch, .invalidIBAN, .suspiciousBankAccount:
            return "creditcard.trianglebadge.exclamationmark"
        case .amountSpikeUp:
            return "arrow.up.circle"
        case .amountSpikeDrop:
            return "arrow.down.circle"
        case .suspiciousRoundAmount, .unusualFirstInvoiceAmount:
            return "dollarsign.circle"
        case .unusualTimingPattern:
            return "clock.badge.exclamationmark"
        case .duplicateInvoice:
            return "doc.on.doc"
        case .futureDatedInvoice, .staleInvoice:
            return "calendar.badge.exclamationmark"
        case .vendorImpersonation, .vendorDetailsMismatch, .invalidVendorNIP:
            return "person.badge.shield.checkmark"
        case .documentTampering:
            return "doc.badge.ellipsis"
        case .missingRequiredFields:
            return "list.bullet.clipboard"
        case .internalInconsistency:
            return "exclamationmark.triangle"
        }
    }
}

// MARK: - Preview

#Preview {
    AnomalyDetailView(
        documentId: UUID(),
        vendorFingerprint: "test-fingerprint",
        documentTitle: "Electric Company"
    )
    .environment(AppEnvironment.preview)
}
