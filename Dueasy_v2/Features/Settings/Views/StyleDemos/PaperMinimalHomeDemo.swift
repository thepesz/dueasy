import SwiftUI

/// Paper Minimal Home Demo - Calm, Focused, Professional
/// Pure black and white with no shadows or gradients. Completely flat design
/// with sharp corners and clean horizontal lines. High contrast for readability.
struct PaperMinimalHomeDemo: View {

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Color Palette (Pure B&W)

    private var bgColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var textPrimary: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var textSecondary: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.12)
    }

    private var accentRed: Color { Color.red }
    private var accentGreen: Color { Color.green }
    private var accentOrange: Color { Color.orange }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Logo / Brand
                headerSection
                    .padding(.bottom, 32)

                // Hero Section - Due in 7 Days
                heroSection
                    .padding(.bottom, 24)

                divider

                // Status Row
                statusRow
                    .padding(.vertical, 20)

                divider

                // Next Payments
                nextPaymentsSection
                    .padding(.vertical, 20)

                divider

                // Month Summary
                monthSummarySection
                    .padding(.vertical, 20)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(bgColor.ignoresSafeArea())
        .navigationTitle("Paper Minimal - Home")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(borderColor)
            .frame(height: 1)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 0) {
                Text("Du")
                    .font(.system(size: 36, weight: .medium))

                Text("Easy")
                    .font(.system(size: 36, weight: .light))
            }
            .foregroundStyle(textPrimary)

            Text("payment tracker")
                .font(.system(size: 12, weight: .regular))
                .tracking(2)
                .foregroundStyle(textSecondary)
                .textCase(.lowercase)
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Due in 7 days")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textSecondary)
                .textCase(.uppercase)
                .tracking(1)

            Text("2 450,00 zl")
                .font(.system(size: 52, weight: .light, design: .default).monospacedDigit())
                .foregroundStyle(textPrimary)

            Text("3 payments upcoming")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Status Row

    private var statusRow: some View {
        HStack(spacing: 0) {
            statusItem(label: "Overdue", value: "1", color: accentRed)

            Rectangle()
                .fill(borderColor)
                .frame(width: 1, height: 40)

            statusItem(label: "Due soon", value: "2", color: accentOrange)

            Rectangle()
                .fill(borderColor)
                .frame(width: 1, height: 40)

            statusItem(label: "Paid", value: "6", color: accentGreen)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .medium, design: .default).monospacedDigit())
                .foregroundStyle(textPrimary)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Next Payments

    private var nextPaymentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Next payments")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(textSecondary)
                    .textCase(.uppercase)
                    .tracking(1)

                Spacer()

                Button(action: {}) {
                    Text("See all")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textSecondary)
                        .underline()
                }
            }

            VStack(spacing: 0) {
                paymentRow(vendor: "Orange Mobile", due: "Due tomorrow", amount: "89,00 zl", isOverdue: false)
                    .padding(.vertical, 14)

                divider

                paymentRow(vendor: "Allegro", due: "3 days overdue", amount: "245,50 zl", isOverdue: true)
                    .padding(.vertical, 14)

                divider

                paymentRow(vendor: "PGE Energia", due: "Due in 5 days", amount: "312,40 zl", isOverdue: false)
                    .padding(.vertical, 14)
            }
        }
    }

    private func paymentRow(vendor: String, due: String, amount: String, isOverdue: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vendor)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(textPrimary)

                Text(due)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isOverdue ? accentRed : textSecondary)
            }

            Spacer()

            Text(amount)
                .font(.system(size: 17, weight: .medium, design: .default).monospacedDigit())
                .foregroundStyle(textPrimary)
        }
    }

    // MARK: - Month Summary

    private var monthSummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This month")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textSecondary)
                .textCase(.uppercase)
                .tracking(1)

            HStack(spacing: 32) {
                // Simple progress bar instead of donut
                VStack(alignment: .leading, spacing: 8) {
                    Text("60% paid")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(textPrimary)

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(borderColor)
                                .frame(height: 4)

                            Rectangle()
                                .fill(textPrimary)
                                .frame(width: geometry.size.width * 0.6, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                .frame(maxWidth: .infinity)

                // Stats
                VStack(alignment: .leading, spacing: 10) {
                    summaryRow(label: "Paid", value: "6", color: accentGreen)
                    summaryRow(label: "Due", value: "3", color: accentOrange)
                    summaryRow(label: "Overdue", value: "1", color: accentRed)
                }
            }

            Text("Unpaid total: 646,90 zl")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(textSecondary)
        }
    }

    private func summaryRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(color)
                .frame(width: 12, height: 2)

            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(textPrimary)
        }
        .frame(width: 100)
    }
}

#Preview {
    NavigationStack {
        PaperMinimalHomeDemo()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        PaperMinimalHomeDemo()
    }
    .preferredColorScheme(.dark)
}
