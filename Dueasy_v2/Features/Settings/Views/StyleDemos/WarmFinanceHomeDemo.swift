import SwiftUI

/// Warm Finance Home Demo - Friendly, Trustworthy, Organized
/// Teal and warm amber colors with soft shadows and subtle gradients.
/// Medium rounded corners create an approachable, personal finance app feel.
struct WarmFinanceHomeDemo: View {

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Color Palette

    private var bgColor: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.09, blue: 0.1)
            : Color(red: 0.97, green: 0.96, blue: 0.94)
    }

    private var bgSecondary: Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.13, blue: 0.14)
            : Color(red: 0.98, green: 0.97, blue: 0.95)
    }

    private let accentTeal = Color(red: 0.0, green: 0.6, blue: 0.6)
    private let accentAmber = Color(red: 0.95, green: 0.65, blue: 0.25)
    private let accentCoral = Color(red: 0.95, green: 0.45, blue: 0.4)

    private var cardBg: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.15, blue: 0.16)
            : Color.white
    }

    private var textPrimary: Color {
        colorScheme == .dark ? Color.white : Color(red: 0.15, green: 0.15, blue: 0.15)
    }

    private var textSecondary: Color {
        colorScheme == .dark ? Color.white.opacity(0.65) : Color(red: 0.4, green: 0.4, blue: 0.4)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Logo / Brand
                headerSection

                // Hero Card - Due in 7 Days
                heroCard

                // Quick Stats Row
                quickStatsRow

                // Next Payments
                nextPaymentsSection

                // Month Summary
                monthSummaryCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(bgColor.ignoresSafeArea())
        .navigationTitle("Warm Finance - Home")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                // Simple teal circle logo
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentTeal, accentTeal.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: accentTeal.opacity(0.3), radius: 6, y: 3)

                Text("DuEasy")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)
            }

            Text("Your payments, organized")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textSecondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Due in 7 days")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentTeal)

                    Text("2 450,00 zl")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(textPrimary)
                }

                Spacer()

                // Friendly icon
                ZStack {
                    Circle()
                        .fill(accentTeal.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(accentTeal)
                }
            }

            Text("3 payments coming up this week")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(textSecondary)

            // Alert pills
            HStack(spacing: 10) {
                alertPill(text: "1 overdue", color: accentCoral, icon: "exclamationmark.circle.fill")
                alertPill(text: "2 due soon", color: accentAmber, icon: "clock.fill")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBg)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, y: 6)
        )
    }

    private func alertPill(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))

            Text(text)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
    }

    // MARK: - Quick Stats Row

    private var quickStatsRow: some View {
        HStack(spacing: 12) {
            statCard(title: "Overdue", value: "350 zl", subtitle: "1 invoice", color: accentCoral, icon: "exclamationmark.triangle.fill")
            statCard(title: "Recurring", value: "5 active", subtitle: "Next: Spotify", color: accentTeal, icon: "arrow.triangle.2.circlepath")
        }
    }

    private func statCard(title: String, value: String, subtitle: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textSecondary)
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(textPrimary)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBg)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 8, y: 4)
        )
    }

    // MARK: - Next Payments

    private var nextPaymentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Next Payments")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)

                Spacer()

                Button(action: {}) {
                    Text("See all")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentTeal)
                }
            }

            VStack(spacing: 12) {
                paymentRow(vendor: "Orange Mobile", due: "Due tomorrow", amount: "89,00 zl", icon: "phone.fill", iconColor: accentAmber, isOverdue: false)
                paymentRow(vendor: "Allegro", due: "3 days overdue", amount: "245,50 zl", icon: "cart.fill", iconColor: accentCoral, isOverdue: true)
                paymentRow(vendor: "PGE Energia", due: "Due in 5 days", amount: "312,40 zl", icon: "bolt.fill", iconColor: accentTeal, isOverdue: false)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardBg)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 8, y: 4)
            )
        }
    }

    private func paymentRow(vendor: String, due: String, amount: String, icon: String, iconColor: Color, isOverdue: Bool) -> some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(vendor)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(textPrimary)

                Text(due)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isOverdue ? accentCoral : textSecondary)
            }

            Spacer()

            Text(amount)
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(textPrimary)
        }
    }

    // MARK: - Month Summary

    private var monthSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("This Month")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)

                Spacer()

                Text("60% paid")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentTeal)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [accentTeal, accentTeal.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * 0.6, height: 12)
                }
            }
            .frame(height: 12)

            // Stats
            HStack(spacing: 20) {
                statPill(label: "Paid", value: "6", color: Color.green)
                statPill(label: "Due", value: "3", color: accentAmber)
                statPill(label: "Overdue", value: "1", color: accentCoral)
            }

            Text("Unpaid total: 646,90 zl")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(textSecondary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBg)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 8, y: 4)
        )
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textSecondary)

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(textPrimary)
        }
    }
}

#Preview {
    NavigationStack {
        WarmFinanceHomeDemo()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        WarmFinanceHomeDemo()
    }
    .preferredColorScheme(.dark)
}
