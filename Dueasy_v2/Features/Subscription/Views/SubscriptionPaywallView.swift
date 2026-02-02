import SwiftUI

/// Pro subscription paywall screen.
/// Displays Pro features and handles subscription purchases.
struct SubscriptionPaywallView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var selectedProduct: SubscriptionProduct?
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var appeared = false

    let requiredFeature: String? // Optional: specific feature that triggered paywall

    var body: some View {
        NavigationStack {
            ZStack {
                // Modern gradient background
                GradientBackground()

                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        // Header
                        VStack(spacing: Spacing.md) {
                            // Premium badge
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.9, green: 0.7, blue: 0.2),
                                                Color(red: 1.0, green: 0.8, blue: 0.3)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .shadow(color: Color(red: 0.9, green: 0.7, blue: 0.2).opacity(0.5), radius: 20, y: 8)

                                Image(systemName: "crown.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.white)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .opacity(appeared ? 1 : 0)
                            .scaleEffect(appeared ? 1 : 0.8)
                            .animation(reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: appeared)

                            Text(L10n.Subscription.upgradeTitle.localized)
                                .font(Typography.largeTitle)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(reduceMotion ? .none : .easeOut(duration: 0.5).delay(0.2), value: appeared)

                            if let feature = requiredFeature {
                                Text(L10n.Subscription.unlockFeature.localized(with: feature))
                                    .font(Typography.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, Spacing.lg)
                                    .opacity(appeared ? 1 : 0)
                                    .animation(reduceMotion ? .none : .easeOut(duration: 0.5).delay(0.3), value: appeared)
                            }
                        }
                        .padding(.top, Spacing.xl)

                        // Feature list
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            ForEach(Array(proFeatures.enumerated()), id: \.offset) { index, feature in
                                FeatureRow(
                                    icon: feature.icon,
                                    title: feature.title,
                                    description: feature.description
                                )
                                .opacity(appeared ? 1 : 0)
                                .offset(x: appeared ? 0 : -20)
                                .animation(
                                    reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(0.4 + Double(index) * 0.1),
                                    value: appeared
                                )
                            }
                        }
                        .padding(.horizontal, Spacing.md)

                        // Pricing (placeholder - will be loaded from StoreKit)
                        VStack(spacing: Spacing.md) {
                            Text(L10n.Subscription.choosePlan.localized)
                                .font(Typography.headline)
                                .foregroundStyle(.secondary)

                            // Monthly plan (placeholder)
                            PlanCard(
                                title: L10n.Subscription.monthly.localized,
                                price: "$4.99",
                                period: L10n.Subscription.perMonth.localized,
                                description: L10n.Subscription.cancelAnytime.localized,
                                isSelected: selectedProduct?.id == "monthly",
                                onTap: {
                                    // Will be replaced with actual product selection
                                }
                            )

                            // Yearly plan (placeholder)
                            PlanCard(
                                title: L10n.Subscription.yearly.localized,
                                price: "$39.99",
                                period: L10n.Subscription.perYear.localized,
                                description: L10n.Subscription.bestValue.localized,
                                isSelected: selectedProduct?.id == "yearly",
                                isRecommended: true,
                                onTap: {
                                    // Will be replaced with actual product selection
                                }
                            )
                        }
                        .padding(.horizontal, Spacing.md)
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.5).delay(0.8), value: appeared)

                        // CTA Button
                        PrimaryButton(
                            L10n.Subscription.startFreeTrial.localized,
                            icon: "arrow.right",
                            isLoading: isPurchasing
                        ) {
                            handlePurchase()
                        }
                        .padding(.horizontal, Spacing.md)
                        .disabled(isPurchasing)
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.5).delay(1.0), value: appeared)

                        // Legal text
                        VStack(spacing: Spacing.xs) {
                            Text(L10n.Subscription.trialInfo.localized)
                                .font(Typography.caption2)
                                .foregroundStyle(.secondary)

                            Text(L10n.Subscription.cancelInSettings.localized)
                                .font(Typography.caption2)
                                .foregroundStyle(.secondary)

                            HStack(spacing: Spacing.xs) {
                                Button(L10n.Subscription.termsOfService.localized) {
                                    // Open terms
                                }
                                .font(Typography.caption2)
                                .foregroundStyle(.secondary)

                                Text("•")
                                    .font(Typography.caption2)
                                    .foregroundStyle(.secondary)

                                Button(L10n.Subscription.privacyPolicy.localized) {
                                    // Open privacy
                                }
                                .font(Typography.caption2)
                                .foregroundStyle(.secondary)

                                Text("•")
                                    .font(Typography.caption2)
                                    .foregroundStyle(.secondary)

                                Button(L10n.Subscription.restore.localized) {
                                    handleRestore()
                                }
                                .font(Typography.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.xl)
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.5).delay(1.1), value: appeared)
                    }
                }
            }
            .navigationTitle(L10n.Subscription.upgradeTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Subscription.maybeLater.localized) {
                        dismiss()
                    }
                }
            }
            .alert(L10n.Subscription.purchaseError.localized, isPresented: $showError) {
                Button(L10n.Common.ok.localized, role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.3)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }

    // MARK: - Actions

    private func handlePurchase() {
        isPurchasing = true

        Task {
            do {
                // ITERATION 2: Implement actual purchase flow with StoreKit
                // For Iteration 1, in-app purchases are deferred.
                // This placeholder shows user feedback until StoreKit integration.
                try await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    isPurchasing = false
                    errorMessage = L10n.Subscription.comingSoon.localized
                    showError = true
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func handleRestore() {
        Task {
            do {
                _ = try await environment.subscriptionService.restorePurchases()
                // If successful and subscription found, dismiss
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Feature Data

    private let proFeatures: [(icon: String, title: String, description: String)] = [
        ("sparkles", "AI-Powered Analysis", "Get 99% accuracy with cloud AI when local analysis has low confidence"),
        ("icloud", "Cloud Vault", "Encrypted backup of your documents (optional, opt-in only)"),
        ("bolt.fill", "Enhanced Accuracy", "Advanced parsing algorithms and vendor-specific templates"),
        ("lock.shield", "Priority Support", "Get help faster with priority email support"),
        ("arrow.triangle.2.circlepath", "Unlimited Sync", "Sync across all your devices with end-to-end encryption"),
        ("chart.line.uptrend.xyaxis", "Advanced Analytics", "Spending insights and payment trends")
    ]
}

// MARK: - Feature Row

struct FeatureRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.primary.opacity(0.2), AppColors.primary.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AppColors.primary)
                    .symbolRenderingMode(.hierarchical)
            }

            // Text
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.headline)
                    .foregroundStyle(.primary)

                Text(description)
                    .font(Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(AppColors.secondaryBackground)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .light ? 0.5 : 0.1),
                                    Color.white.opacity(colorScheme == .light ? 0.2 : 0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .light ? 0.6 : 0.2),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Plan Card

struct PlanCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let title: String
    let price: String
    let period: String
    let description: String
    let isSelected: Bool
    let isRecommended: Bool
    let onTap: () -> Void

    init(
        title: String,
        price: String,
        period: String,
        description: String,
        isSelected: Bool = false,
        isRecommended: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.price = price
        self.period = period
        self.description = description
        self.isSelected = isSelected
        self.isRecommended = isRecommended
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Spacing.md) {
                // Recommended badge
                if isRecommended {
                    Text(L10n.Subscription.bestValueBadge.localized)
                        .font(Typography.caption1.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.9, green: 0.7, blue: 0.2), Color(red: 1.0, green: 0.8, blue: 0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(title)
                            .font(Typography.title3)
                            .fontWeight(.semibold)

                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                            Text(price)
                                .font(Typography.monospacedTitle)

                            Text(period)
                                .font(Typography.caption1)
                                .foregroundStyle(.secondary)
                        }

                        Text(description)
                            .font(Typography.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Selection indicator
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? AppColors.primary : .secondary.opacity(0.5))
                }
            }
            .padding(Spacing.md)
        }
        .buttonStyle(.plain)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(isSelected ? AppColors.primary.opacity(0.08) : AppColors.secondaryBackground)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(.ultraThinMaterial)

                    if isSelected {
                        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                            .fill(AppColors.primary.opacity(0.1))
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: isSelected
                            ? [AppColors.primary.opacity(0.6), AppColors.primary.opacity(0.3)]
                            : [Color.white.opacity(colorScheme == .light ? 0.6 : 0.2), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isSelected ? 2 : 0.5
                )
        }
        .shadow(
            color: isSelected ? AppColors.primary.opacity(0.2) : Color.black.opacity(0.05),
            radius: isSelected ? 12 : 6,
            y: isSelected ? 6 : 3
        )
    }
}

// MARK: - Preview

#Preview {
    SubscriptionPaywallView(requiredFeature: "Cloud AI Analysis")
        .environment(AppEnvironment.preview)
}
