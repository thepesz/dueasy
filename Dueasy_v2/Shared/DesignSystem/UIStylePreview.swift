import SwiftUI

// MARK: - UI Style Preview
//
// Preview components demonstrating the three UI style proposals.
// These can be used in SwiftUI Previews to visualize each style.

/// Preview card showing a sample finance dashboard in the given style
struct UIStylePreviewCard: View {

    let style: UIStyleProposal

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(style.displayName)
                    .font(.headline)
                Spacer()
                Image(systemName: style.iconName)
            }
            .padding()
            .background(UIStyleTokens(style: style).cardBackgroundColor(for: colorScheme))

            // Sample content
            sampleDashboard
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.uiStyle, style)
    }

    @ViewBuilder
    private var sampleDashboard: some View {
        let tokens = UIStyleTokens(style: style)

        ZStack {
            // Background
            if tokens.usesBackgroundGradients {
                LinearGradient(
                    colors: tokens.backgroundGradientColors(for: colorScheme),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                tokens.backgroundColor(for: colorScheme)
            }

            VStack(spacing: 12) {
                // Hero amount
                StyledHeroAmount(amount: "2,450.00 PLN")
                    .environment(\.uiStyle, style)

                Text("Due in next 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Sample badges
                HStack(spacing: 8) {
                    StyledStatusBadge("2 overdue", status: .error, size: .small)
                        .environment(\.uiStyle, style)

                    StyledStatusBadge("3 due soon", status: .warning, size: .small)
                        .environment(\.uiStyle, style)
                }

                Spacer()
            }
            .padding()
        }
        .frame(height: 180)
    }
}

// MARK: - Style Comparison Preview

/// Side-by-side comparison of all three styles
struct UIStyleComparisonPreview: View {

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(UIStyleProposal.availableStyles, id: \.id) { style in
                    UIStylePreviewCard(style: style)
                }
            }
            .padding()
        }
    }
}

// MARK: - Full Screen Style Preview

/// Full-screen preview of a single style
struct UIStyleFullPreview: View {

    let style: UIStyleProposal

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = UIStyleTokens(style: style)

        ZStack {
            StyledBackground()

            ScrollView {
                VStack(spacing: tokens.sectionSpacing) {
                    // Header
                    VStack(spacing: 8) {
                        Text("DuEasy")
                            .font(.system(size: 32, weight: tokens.titleWeight, design: .rounded))
                            .italic()

                        Text(style.tagline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // Hero Card
                    StyledCard(accentColor: tokens.primaryColor(for: colorScheme)) {
                        VStack(alignment: .leading, spacing: 12) {
                            StyledSectionHeader("Due in 7 days", icon: "calendar.badge.clock")

                            StyledHeroAmount(amount: "2,450.00 PLN")

                            Text("3 invoices")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                StyledStatusBadge("2 overdue", status: .error, size: .small)
                                StyledStatusBadge("1 due soon", status: .warning, size: .small)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Tiles
                    HStack(spacing: 12) {
                        StyledCard(accentColor: tokens.successColor(for: colorScheme)) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overdue")
                                    .font(.headline)
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(tokens.successColor(for: colorScheme))
                                    Text("All clear")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        StyledCard(accentColor: tokens.primaryColor(for: colorScheme)) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Recurring")
                                    .font(.headline)
                                Text("4 active")
                                    .font(.title2.weight(.semibold))
                                Text("Next in 5 days")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // List Section
                    VStack(alignment: .leading, spacing: 12) {
                        StyledSectionHeader("Next payments", icon: "clock.fill")

                        VStack(spacing: tokens.rowBackgroundStyle == .flat ? 0 : 8) {
                            StyledDocumentRow(
                                vendorName: "PGE Energia",
                                amount: "245.50 PLN",
                                dueInfo: "Due in 3 days",
                                statusType: .warning,
                                statusText: "Due soon"
                            )

                            if tokens.rowsHaveSeparators {
                                StyledDivider(inset: 16)
                            }

                            StyledDocumentRow(
                                vendorName: "Play Mobile",
                                amount: "89.99 PLN",
                                dueInfo: "Due in 7 days",
                                statusType: .info,
                                statusText: "Scheduled"
                            )

                            if tokens.rowsHaveSeparators {
                                StyledDivider(inset: 16)
                            }

                            StyledDocumentRow(
                                vendorName: "Netflix",
                                amount: "49.00 PLN",
                                dueInfo: "Paid today",
                                statusType: .success,
                                statusText: "Paid"
                            )
                        }
                    }

                    // Button
                    StyledPrimaryButton("Save Invoice", icon: "checkmark.circle.fill") {
                        // Action
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, tokens.screenHorizontalPadding)
                .padding(.bottom, 60)
            }
        }
        .environment(\.uiStyle, style)
    }
}

// MARK: - Previews

#Preview("Style Comparison") {
    UIStyleComparisonPreview()
}

#Preview("Midnight Aurora - Light") {
    UIStyleFullPreview(style: .midnightAurora)
        .preferredColorScheme(.light)
}

#Preview("Midnight Aurora - Dark") {
    UIStyleFullPreview(style: .midnightAurora)
        .preferredColorScheme(.dark)
}

#Preview("Paper Minimal - Light") {
    UIStyleFullPreview(style: .paperMinimal)
        .preferredColorScheme(.light)
}

#Preview("Paper Minimal - Dark") {
    UIStyleFullPreview(style: .paperMinimal)
        .preferredColorScheme(.dark)
}

#Preview("Warm Finance - Light") {
    UIStyleFullPreview(style: .warmFinance)
        .preferredColorScheme(.light)
}

#Preview("Warm Finance - Dark") {
    UIStyleFullPreview(style: .warmFinance)
        .preferredColorScheme(.dark)
}
