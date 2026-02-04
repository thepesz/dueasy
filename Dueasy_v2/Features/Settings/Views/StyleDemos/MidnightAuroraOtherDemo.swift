import SwiftUI

/// Midnight Aurora Document List Demo - Bold, Premium, Luxurious
/// Shows the document list and detail views with electric blue/purple aesthetic.
struct MidnightAuroraOtherDemo: View {

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Color Palette

    private let bgGradientStart = Color(red: 0.05, green: 0.05, blue: 0.12)
    private let bgGradientEnd = Color(red: 0.08, green: 0.04, blue: 0.15)
    private let accentBlue = Color(red: 0.3, green: 0.5, blue: 1.0)
    private let accentPurple = Color(red: 0.6, green: 0.3, blue: 0.9)
    private let accentPink = Color(red: 0.95, green: 0.4, blue: 0.6)
    private let cardBg = Color.white.opacity(0.08)
    private let cardBorder = Color.white.opacity(0.15)
    private let textPrimary = Color.white
    private let textSecondary = Color.white.opacity(0.7)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Search Bar
                searchBar

                // Filter Chips
                filterChips

                // Document Cards
                VStack(spacing: 12) {
                    documentCard(
                        title: "Orange Mobile - January",
                        vendor: "Orange Polska",
                        amount: "89,00 zl",
                        dueDate: "Due tomorrow",
                        status: .dueSoon,
                        category: "phone.fill"
                    )

                    documentCard(
                        title: "Allegro Order #12847",
                        vendor: "Allegro",
                        amount: "245,50 zl",
                        dueDate: "3 days overdue",
                        status: .overdue,
                        category: "cart.fill"
                    )

                    documentCard(
                        title: "PGE Electric Bill",
                        vendor: "PGE Energia",
                        amount: "312,40 zl",
                        dueDate: "Due in 5 days",
                        status: .pending,
                        category: "bolt.fill"
                    )

                    documentCard(
                        title: "Spotify Premium",
                        vendor: "Spotify AB",
                        amount: "23,99 zl",
                        dueDate: "Paid Jan 15",
                        status: .paid,
                        category: "music.note"
                    )

                    documentCard(
                        title: "Netflix Subscription",
                        vendor: "Netflix International",
                        amount: "52,00 zl",
                        dueDate: "Paid Jan 10",
                        status: .paid,
                        category: "play.tv.fill"
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(backgroundGradient)
        .navigationTitle("Midnight Aurora - Docs")
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

            Circle()
                .fill(accentBlue.opacity(0.12))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: 120, y: -100)

            Circle()
                .fill(accentPurple.opacity(0.1))
                .frame(width: 200, height: 200)
                .blur(radius: 50)
                .offset(x: -100, y: 300)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(textSecondary)

            Text("Search documents...")
                .font(.system(size: 16))
                .foregroundStyle(textSecondary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardBg)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
        )
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterChip(title: "All", icon: "doc.fill", isSelected: true)
                filterChip(title: "Pending", icon: "clock.fill", count: 2, isSelected: false)
                filterChip(title: "Scheduled", icon: "calendar", count: 3, isSelected: false)
                filterChip(title: "Paid", icon: "checkmark.circle.fill", isSelected: false)
                filterChip(title: "Overdue", icon: "exclamationmark.triangle.fill", count: 1, isSelected: false)
            }
            .padding(.horizontal, 4)
        }
    }

    private func filterChip(title: String, icon: String, count: Int? = nil, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))

            if let count = count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.25) : accentBlue.opacity(0.2))
                    )
            }
        }
        .foregroundStyle(isSelected ? .white : textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(isSelected ?
                    LinearGradient(
                        colors: [accentBlue, accentPurple],
                        startPoint: .leading,
                        endPoint: .trailing
                    ) : LinearGradient(
                        colors: [cardBg, cardBg],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(isSelected ? Color.clear : cardBorder, lineWidth: 1)
        )
        .shadow(color: isSelected ? accentBlue.opacity(0.3) : .clear, radius: 6, y: 3)
    }

    // MARK: - Document Card

    private enum DocStatus {
        case overdue, dueSoon, pending, paid

        var color: Color {
            switch self {
            case .overdue: return Color(red: 0.95, green: 0.4, blue: 0.6)
            case .dueSoon: return Color.orange
            case .pending: return Color(red: 0.3, green: 0.5, blue: 1.0)
            case .paid: return Color.green
            }
        }

        var label: String {
            switch self {
            case .overdue: return "OVERDUE"
            case .dueSoon: return "DUE SOON"
            case .pending: return "PENDING"
            case .paid: return "PAID"
            }
        }
    }

    private func documentCard(
        title: String,
        vendor: String,
        amount: String,
        dueDate: String,
        status: DocStatus,
        category: String
    ) -> some View {
        HStack(spacing: 14) {
            // Category Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentBlue.opacity(0.3), accentPurple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: category)
                    .font(.system(size: 20))
                    .foregroundStyle(accentBlue)
            }

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Status Badge
                    Text(status.label)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(status.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(status.color.opacity(0.2))
                        )
                }

                Text(vendor)
                    .font(.system(size: 13))
                    .foregroundStyle(textSecondary)

                HStack {
                    Text(dueDate)
                        .font(.system(size: 13))
                        .foregroundStyle(status == .overdue ? status.color : textSecondary)

                    Spacer()

                    Text(amount)
                        .font(.system(size: 18, weight: .semibold, design: .default).monospacedDigit())
                        .foregroundStyle(textPrimary)
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardBg)

                // Subtle status accent
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [status.color.opacity(0.08), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
        )
    }
}

#Preview {
    NavigationStack {
        MidnightAuroraOtherDemo()
    }
}
