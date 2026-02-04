import SwiftUI

/// Pro subscription paywall screen.
/// Displays Pro features and handles subscription purchases via RevenueCat.
struct SubscriptionPaywallView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - State

    /// Available products from RevenueCat (or fallback placeholders)
    @State private var products: [SubscriptionProduct] = []

    /// Currently selected product for purchase
    @State private var selectedProduct: SubscriptionProduct?

    /// Loading state for fetching products
    @State private var isLoadingProducts = true

    /// Loading state for purchase in progress
    @State private var isPurchasing = false

    /// Loading state for restore in progress
    @State private var isRestoring = false

    /// Error alert state
    @State private var showError = false
    @State private var errorMessage = ""

    /// Success state - Pro subscription activated
    @State private var showSuccess = false

    /// Animation state
    @State private var appeared = false

    /// Optional: specific feature that triggered paywall
    let requiredFeature: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Modern gradient background
                GradientBackground()

                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        // Header
                        headerSection

                        // Feature list
                        featureListSection

                        // Pricing
                        pricingSection

                        // CTA Button
                        purchaseButton

                        // Legal text
                        legalSection
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
                    .disabled(isPurchasing || isRestoring)
                }
            }
            .alert(L10n.Subscription.purchaseError.localized, isPresented: $showError) {
                Button(L10n.Common.ok.localized, role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Welcome to Pro!", isPresented: $showSuccess) {
                Button("Continue", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Your Pro subscription is now active. Enjoy 100 cloud extractions per month!")
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
        .task {
            await loadProducts()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
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
    }

    // MARK: - Feature List Section

    private var featureListSection: some View {
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
    }

    // MARK: - Pricing Section

    private var pricingSection: some View {
        VStack(spacing: Spacing.md) {
            Text(L10n.Subscription.choosePlan.localized)
                .font(Typography.headline)
                .foregroundStyle(.secondary)

            if isLoadingProducts {
                // Loading indicator
                ProgressView()
                    .padding(Spacing.lg)
            } else if products.isEmpty {
                // No products available - show placeholder
                placeholderPlanCards
            } else {
                // Show actual products from RevenueCat
                ForEach(products) { product in
                    PlanCard(
                        title: product.displayName,
                        price: product.displayPrice,
                        period: periodString(for: product.subscriptionPeriod),
                        description: descriptionForProduct(product),
                        isSelected: selectedProduct?.id == product.id,
                        isRecommended: product.subscriptionPeriod == .yearly,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedProduct = product
                            }
                        }
                    )
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? .none : .easeOut(duration: 0.5).delay(0.8), value: appeared)
    }

    private var placeholderPlanCards: some View {
        VStack(spacing: Spacing.md) {
            // Monthly plan placeholder
            PlanCard(
                title: L10n.Subscription.monthly.localized,
                price: "$4.99",
                period: L10n.Subscription.perMonth.localized,
                description: L10n.Subscription.cancelAnytime.localized,
                isSelected: false,
                onTap: {
                    errorMessage = "Products not available. Please try again later."
                    showError = true
                }
            )

            // Yearly plan placeholder
            PlanCard(
                title: L10n.Subscription.yearly.localized,
                price: "$39.99",
                period: L10n.Subscription.perYear.localized,
                description: L10n.Subscription.bestValue.localized,
                isSelected: false,
                isRecommended: true,
                onTap: {
                    errorMessage = "Products not available. Please try again later."
                    showError = true
                }
            )
        }
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        PrimaryButton(
            purchaseButtonTitle,
            icon: "arrow.right",
            isLoading: isPurchasing
        ) {
            handlePurchase()
        }
        .padding(.horizontal, Spacing.md)
        .disabled(isPurchasing || isRestoring || (selectedProduct == nil && !products.isEmpty))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? .none : .easeOut(duration: 0.5).delay(1.0), value: appeared)
    }

    private var purchaseButtonTitle: String {
        if let product = selectedProduct {
            if let intro = product.introductoryOffer, intro.type == .freeTrial {
                return L10n.Subscription.startFreeTrial.localized
            }
            return "Subscribe for \(product.displayPrice)"
        }
        return L10n.Subscription.startFreeTrial.localized
    }

    // MARK: - Legal Section

    private var legalSection: some View {
        VStack(spacing: Spacing.xs) {
            if let product = selectedProduct, let intro = product.introductoryOffer, intro.type == .freeTrial {
                Text(L10n.Subscription.trialInfo.localized)
                    .font(Typography.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(L10n.Subscription.cancelInSettings.localized)
                .font(Typography.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.xs) {
                Button(L10n.Subscription.termsOfService.localized) {
                    openTermsOfService()
                }
                .font(Typography.caption2)
                .foregroundStyle(.secondary)

                Text("-")
                    .font(Typography.caption2)
                    .foregroundStyle(.secondary)

                Button(L10n.Subscription.privacyPolicy.localized) {
                    openPrivacyPolicy()
                }
                .font(Typography.caption2)
                .foregroundStyle(.secondary)

                Text("-")
                    .font(Typography.caption2)
                    .foregroundStyle(.secondary)

                Button(L10n.Subscription.restore.localized) {
                    handleRestore()
                }
                .font(Typography.caption2)
                .foregroundStyle(.secondary)
                .disabled(isRestoring || isPurchasing)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.xl)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? .none : .easeOut(duration: 0.5).delay(1.1), value: appeared)
    }

    // MARK: - Actions

    private func loadProducts() async {
        isLoadingProducts = true

        let fetchedProducts = await environment.subscriptionService.availableProducts

        await MainActor.run {
            products = fetchedProducts

            // Auto-select yearly (best value) if available
            if let yearlyProduct = fetchedProducts.first(where: { $0.subscriptionPeriod == .yearly }) {
                selectedProduct = yearlyProduct
            } else if let firstProduct = fetchedProducts.first {
                selectedProduct = firstProduct
            }

            isLoadingProducts = false
        }
    }

    private func handlePurchase() {
        guard let product = selectedProduct else {
            errorMessage = "Please select a subscription plan"
            showError = true
            return
        }

        isPurchasing = true

        Task {
            do {
                let status = try await environment.subscriptionService.purchase(productId: product.id)

                await MainActor.run {
                    isPurchasing = false

                    if status.isActive && status.tier == .pro {
                        // Purchase successful
                        showSuccess = true
                    } else {
                        // Purchase completed but not activated
                        errorMessage = "Purchase completed but subscription not activated. Please try restoring purchases."
                        showError = true
                    }
                }
            } catch let error as SubscriptionError {
                await MainActor.run {
                    isPurchasing = false
                    handleSubscriptionError(error)
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
        isRestoring = true

        Task {
            do {
                let status = try await environment.subscriptionService.restorePurchases()

                await MainActor.run {
                    isRestoring = false

                    if status.isActive && status.tier == .pro {
                        // Restore successful
                        showSuccess = true
                    } else {
                        // No active subscription found
                        errorMessage = "No active subscription found. If you believe this is an error, please contact support."
                        showError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func handleSubscriptionError(_ error: SubscriptionError) {
        switch error {
        case .purchaseCancelled:
            // User cancelled - don't show error
            break
        case .notAvailable:
            errorMessage = "Subscriptions are not available on this device."
            showError = true
        case .productNotFound:
            errorMessage = "Selected product not found. Please try again."
            showError = true
        case .purchaseFailed(let reason):
            errorMessage = "Purchase failed: \(reason)"
            showError = true
        case .verificationFailed:
            errorMessage = "Could not verify your purchase. Please try again or contact support."
            showError = true
        case .networkError:
            errorMessage = "Network error. Please check your connection and try again."
            showError = true
        case .storeKitError(let message):
            errorMessage = "Store error: \(message)"
            showError = true
        case .unknown(let message):
            errorMessage = message
            showError = true
        }
    }

    private func openTermsOfService() {
        if let url = URL(string: "https://dueasy.app/terms") {
            UIApplication.shared.open(url)
        }
    }

    private func openPrivacyPolicy() {
        if let url = URL(string: "https://dueasy.app/privacy") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Helpers

    private func periodString(for period: SubscriptionPeriod) -> String {
        switch period {
        case .weekly:
            return "/week"
        case .monthly:
            return L10n.Subscription.perMonth.localized
        case .yearly:
            return L10n.Subscription.perYear.localized
        }
    }

    private func descriptionForProduct(_ product: SubscriptionProduct) -> String {
        switch product.subscriptionPeriod {
        case .yearly:
            return L10n.Subscription.bestValue.localized
        case .monthly:
            return L10n.Subscription.cancelAnytime.localized
        case .weekly:
            return "Billed weekly"
        }
    }

    // MARK: - Feature Data

    private let proFeatures: [(icon: String, title: String, description: String)] = [
        ("sparkles", "100 Cloud Extractions/Month", "Free tier includes 3/month. Pro gives you 100 high-accuracy AI extractions."),
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
