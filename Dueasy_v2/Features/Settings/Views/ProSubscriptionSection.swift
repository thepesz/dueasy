import SwiftUI

/// Pro subscription management section in Settings.
/// Shows subscription status and allows upgrading/managing subscription.
struct ProSubscriptionSection: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    @State private var subscriptionStatus: SubscriptionStatus = .free
    @State private var isLoading = true
    @State private var showPaywall = false
    @State private var showManageSheet = false

    var body: some View {
        Section {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading subscription status...")
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Spacing.sm)
            } else {
                // Subscription status display
                subscriptionStatusRow

                // Action buttons
                if subscriptionStatus.isActive {
                    // Active Pro subscription
                    Button {
                        showManageSheet = true
                    } label: {
                        HStack {
                            Text("Manage Subscription")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    // Free tier - show upgrade button
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(red: 0.9, green: 0.7, blue: 0.2), Color(red: 1.0, green: 0.8, blue: 0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            Text("Upgrade to Pro")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Subscription")
        } footer: {
            if !subscriptionStatus.isActive {
                Text("Upgrade to Pro for AI-powered analysis, cloud backup, and enhanced accuracy.")
                    .font(Typography.caption1)
            } else if let expirationDate = subscriptionStatus.expirationDate {
                if subscriptionStatus.willAutoRenew {
                    Text("Your subscription will renew on \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(Typography.caption1)
                } else {
                    Text("Your subscription expires on \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(Typography.caption1)
                }
            }
        }
        .task {
            await loadSubscriptionStatus()
        }
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView(requiredFeature: nil)
                .environment(environment)
        }
        .sheet(isPresented: $showManageSheet) {
            ManageSubscriptionView(status: subscriptionStatus)
                .environment(environment)
        }
    }

    // MARK: - Subscription Status Row

    @ViewBuilder
    private var subscriptionStatusRow: some View {
        HStack(spacing: Spacing.md) {
            // Tier icon
            ZStack {
                Circle()
                    .fill(
                        subscriptionStatus.tier == .pro
                            ? LinearGradient(
                                colors: [Color(red: 0.9, green: 0.7, blue: 0.2), Color(red: 1.0, green: 0.8, blue: 0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: subscriptionStatus.tier == .pro ? "crown.fill" : "person.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }

            // Status text
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(subscriptionStatus.tier.displayName)
                    .font(Typography.headline)

                if subscriptionStatus.tier == .pro {
                    if subscriptionStatus.isTrialPeriod {
                        Text("Free Trial")
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                    } else if subscriptionStatus.isInGracePeriod {
                        Text("Payment Issue")
                            .font(Typography.caption1)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Active")
                            .font(Typography.caption1)
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("Local-only features")
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Status indicator
            if subscriptionStatus.tier == .pro {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Actions

    private func loadSubscriptionStatus() async {
        isLoading = true

        do {
            subscriptionStatus = try await environment.subscriptionService.refreshStatus()
        } catch {
            // On error, default to free tier
            subscriptionStatus = .free
        }

        isLoading = false
    }
}

// MARK: - Manage Subscription View

struct ManageSubscriptionView: View {

    @Environment(\.dismiss) private var dismiss
    let status: SubscriptionStatus

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Status", value: status.isActive ? "Active" : "Inactive")
                    LabeledContent("Tier", value: status.tier.displayName)

                    if let productId = status.productId {
                        LabeledContent("Plan", value: productId)
                    }

                    if let expirationDate = status.expirationDate {
                        LabeledContent("Expires", value: expirationDate.formatted(date: .abbreviated, time: .omitted))
                    }

                    if let purchaseDate = status.originalPurchaseDate {
                        LabeledContent("Subscribed", value: purchaseDate.formatted(date: .abbreviated, time: .omitted))
                    }

                    LabeledContent("Auto-renew", value: status.willAutoRenew ? "On" : "Off")

                    if status.isTrialPeriod {
                        LabeledContent("Trial Period", value: "Yes")
                    }
                } header: {
                    Text("Subscription Details")
                }

                Section {
                    Button("Manage in App Store") {
                        openSubscriptionManagement()
                    }

                    Button("Cancel Subscription", role: .destructive) {
                        openSubscriptionManagement()
                    }
                } header: {
                    Text("Actions")
                } footer: {
                    Text("To cancel or modify your subscription, use the App Store settings. Changes will take effect at the end of the current billing period.")
                }
            }
            .navigationTitle("Manage Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func openSubscriptionManagement() {
        // Open App Store subscription management
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }
    }
}

// MARK: - Preview

#Preview("Free Tier") {
    NavigationStack {
        List {
            ProSubscriptionSection()
        }
    }
    .environment(AppEnvironment.preview)
}

#Preview("Pro Active") {
    struct PreviewWrapper: View {
        @State var env = AppEnvironment.preview

        var body: some View {
            NavigationStack {
                List {
                    ProSubscriptionSection()
                }
            }
            .environment(env)
        }
    }

    return PreviewWrapper()
}
