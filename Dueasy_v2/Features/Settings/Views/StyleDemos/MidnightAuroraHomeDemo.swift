import SwiftUI

/// Midnight Aurora Home Demo - Bold, Premium, Luxurious
/// Electric blue and purple-pink colors with glassmorphism and gradient cards.
/// Large corner radii create fluid shapes. Deep dark backgrounds with vibrant accents.
struct MidnightAuroraHomeDemo: View {

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Color Palette

    private let bgGradientStart = Color(red: 0.12, green: 0.12, blue: 0.22)
    private let bgGradientEnd = Color(red: 0.18, green: 0.10, blue: 0.28)
    private let accentBlue = Color(red: 0.3, green: 0.5, blue: 1.0)
    private let accentPurple = Color(red: 0.6, green: 0.3, blue: 0.9)
    private let accentPink = Color(red: 0.95, green: 0.4, blue: 0.6)

    // MARK: - High Contrast Card System (improved for sunlight readability)
    // Solid dark backing layer for cards - ensures text readability in bright light
    private let cardBackingColor = Color(red: 0.08, green: 0.08, blue: 0.14)
    // Slightly lighter glass layer on top of backing
    private let cardGlassLayer = Color.white.opacity(0.12)
    // Stronger border for card definition
    private let cardBorder = Color.white.opacity(0.35)
    // Secondary border for gradient effects
    private let cardBorderHighlight = Color.white.opacity(0.5)

    private let textPrimary = Color.white
    private let textSecondary = Color.white.opacity(0.75)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Logo / Brand
                headerSection

                // Hero Card - Due in 7 Days
                heroCard

                // Two-column tiles
                HStack(spacing: 12) {
                    overdueTile
                    recurringTile
                }

                // Next Payments
                nextPaymentsSection

                // Month Summary
                monthSummaryCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(backgroundGradient)
        .navigationTitle("Midnight Aurora - Home")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            LinearGradient(
                colors: [bgGradientStart, bgGradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft glow circles (static, no animation to avoid crashes)
            Circle()
                .fill(accentBlue.opacity(0.15))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -100, y: -200)

            Circle()
                .fill(accentPurple.opacity(0.12))
                .frame(width: 250, height: 250)
                .blur(radius: 60)
                .offset(x: 150, y: 100)

            Circle()
                .fill(accentPink.opacity(0.08))
                .frame(width: 200, height: 200)
                .blur(radius: 50)
                .offset(x: -50, y: 400)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 2) {
                Text("Du")
                    .font(.system(size: 42, weight: .medium, design: .default))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentBlue, accentPurple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("Easy")
                    .font(.system(size: 42, weight: .light, design: .default))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentPurple, accentPink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }

            Text("PAYMENT TRACKER")
                .font(.system(size: 11, weight: .medium))
                .tracking(3)
                .foregroundStyle(textSecondary)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accentBlue)

                Text("DUE IN 7 DAYS")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(textSecondary)
            }

            Text("2 450,00 zl")
                .font(.system(size: 48, weight: .light, design: .default).monospacedDigit())
                .foregroundStyle(
                    LinearGradient(
                        colors: [textPrimary, accentBlue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("3 payments upcoming")
                .font(.system(size: 15))
                .foregroundStyle(textSecondary)

            HStack(spacing: 10) {
                statusPill(text: "1 overdue", color: accentPink)
                statusPill(text: "2 due soon", color: Color.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            ZStack {
                // Solid dark backing for sunlight readability
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cardBackingColor)

                // Subtle glass layer on top
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cardGlassLayer)

                // Colored gradient overlay (reduced opacity for balance)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentBlue.opacity(0.20), accentPurple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Stronger gradient border for definition
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [cardBorderHighlight, cardBorder],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        // Stronger shadow for depth and card separation
        .shadow(color: Color.black.opacity(0.4), radius: 12, y: 6)
        .shadow(color: accentBlue.opacity(0.25), radius: 20, y: 10)
    }

    private func statusPill(text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.8), radius: 4)

            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                // Darker backing for better text contrast
                .fill(Color.black.opacity(0.5))
                .overlay(
                    Capsule()
                        .fill(color.opacity(0.25))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.6), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Tiles

    private var overdueTile: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(accentPink)

                Text("OVERDUE")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(textPrimary)
            }

            Text("350,00 zl")
                .font(.system(size: 24, weight: .medium, design: .default).monospacedDigit())
                .foregroundStyle(accentPink)

            Text("1 invoice")
                .font(.system(size: 13))
                .foregroundStyle(textSecondary)

            Spacer()

            Button(action: {}) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13, weight: .medium))
                    Text("Check")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accentPink, accentPink.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .shadow(color: accentPink.opacity(0.4), radius: 6, y: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 140)
        .padding(16)
        .background(
            ZStack {
                // Solid dark backing
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardBackingColor)

                // Glass layer
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardGlassLayer)

                // Accent color tint
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentPink.opacity(0.15), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Stronger border
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1.5)
            }
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
    }

    private var recurringTile: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(accentBlue)

                Text("RECURRING")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(textPrimary)
            }

            Text("5 active")
                .font(.system(size: 24, weight: .medium, design: .default).monospacedDigit())
                .foregroundStyle(textPrimary)

            Text("Next: Spotify")
                .font(.system(size: 13))
                .foregroundStyle(textSecondary)

            Spacer()

            Button(action: {}) {
                HStack(spacing: 4) {
                    Text("Manage")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(accentBlue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 140)
        .padding(16)
        .background(
            ZStack {
                // Solid dark backing
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardBackingColor)

                // Glass layer
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardGlassLayer)

                // Stronger border
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1.5)
            }
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
    }

    // MARK: - Next Payments

    private var nextPaymentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(accentBlue)

                    Text("NEXT PAYMENTS")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(textPrimary)
                }

                Spacer()

                Button(action: {}) {
                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(accentBlue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.4))
                            .overlay(
                                Capsule()
                                    .fill(accentBlue.opacity(0.2))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(accentBlue.opacity(0.5), lineWidth: 1)
                            )
                    )
                }
            }

            VStack(spacing: 0) {
                paymentRow(vendor: "Orange Mobile", due: "Due tomorrow", amount: "89,00 zl", isOverdue: false)
                Divider()
                    .frame(height: 1)
                    .background(Color.white.opacity(0.15))
                    .padding(.leading, 40)
                paymentRow(vendor: "Allegro", due: "3 days overdue", amount: "245,50 zl", isOverdue: true)
                Divider()
                    .frame(height: 1)
                    .background(Color.white.opacity(0.15))
                    .padding(.leading, 40)
                paymentRow(vendor: "PGE Energia", due: "Due in 5 days", amount: "312,40 zl", isOverdue: false)
            }
            .padding(12)
            .background(
                ZStack {
                    // Solid dark backing
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(cardBackingColor)

                    // Glass layer
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(cardGlassLayer)

                    // Stronger border
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(cardBorder, lineWidth: 1.5)
                }
            )
            .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
        }
    }

    private func paymentRow(vendor: String, due: String, amount: String, isOverdue: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vendor)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(textPrimary)

                Text(due)
                    .font(.system(size: 13))
                    .foregroundStyle(isOverdue ? accentPink : textSecondary)
            }

            Spacer()

            Text(amount)
                .font(.system(size: 17, weight: .medium, design: .default).monospacedDigit())
                .foregroundStyle(textPrimary)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Month Summary

    private var monthSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(accentPurple)

                Text("THIS MONTH")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(textPrimary)
            }

            HStack(spacing: 24) {
                // Simple donut representation
                ZStack {
                    Circle()
                        .stroke(cardBorder, lineWidth: 12)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: 0.6)
                        .stroke(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("60%")
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .foregroundStyle(textPrimary)
                        Text("paid")
                            .font(.system(size: 11))
                            .foregroundStyle(textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    statRow(label: "Paid", value: "6", color: Color.green)
                    statRow(label: "Due", value: "3", color: Color.orange)
                    statRow(label: "Overdue", value: "1", color: accentPink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            ZStack {
                // Solid dark backing
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardBackingColor)

                // Glass layer
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardGlassLayer)

                // Stronger border
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1.5)
            }
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
    }

    private func statRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
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
                .font(.system(size: 13))
                .foregroundStyle(textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(textPrimary)
        }
    }
}

#Preview {
    NavigationStack {
        MidnightAuroraHomeDemo()
    }
}
