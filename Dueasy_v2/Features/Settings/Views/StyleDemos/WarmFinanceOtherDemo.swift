import SwiftUI

/// Warm Finance Document List Demo - Friendly, Trustworthy, Organized
/// Document list with teal/amber palette, soft shadows, and medium rounded corners.
struct WarmFinanceOtherDemo: View {

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Color Palette

    private var bgColor: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.09, blue: 0.1)
            : Color(red: 0.97, green: 0.96, blue: 0.94)
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
                        icon: "phone.fill",
                        iconColor: accentAmber
                    )

                    documentCard(
                        title: "Allegro Order #12847",
                        vendor: "Allegro",
                        amount: "245,50 zl",
                        dueDate: "3 days overdue",
                        status: .overdue,
                        icon: "cart.fill",
                        iconColor: accentCoral
                    )

                    documentCard(
                        title: "PGE Electric Bill",
                        vendor: "PGE Energia",
                        amount: "312,40 zl",
                        dueDate: "Due in 5 days",
                        status: .pending,
                        icon: "bolt.fill",
                        iconColor: accentTeal
                    )

                    documentCard(
                        title: "Spotify Premium",
                        vendor: "Spotify AB",
                        amount: "23,99 zl",
                        dueDate: "Paid Jan 15",
                        status: .paid,
                        icon: "music.note",
                        iconColor: Color.green
                    )

                    documentCard(
                        title: "Netflix Subscription",
                        vendor: "Netflix International",
                        amount: "52,00 zl",
                        dueDate: "Paid Jan 10",
                        status: .paid,
                        icon: "play.tv.fill",
                        iconColor: Color.green
                    )

                    documentCard(
                        title: "UPC Internet",
                        vendor: "UPC Polska",
                        amount: "99,00 zl",
                        dueDate: "Due in 12 days",
                        status: .pending,
                        icon: "wifi",
                        iconColor: accentTeal
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(bgColor.ignoresSafeArea())
        .navigationTitle("Warm Finance - Docs")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(textSecondary)

            Text("Search documents...")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(textSecondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBg)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 6, y: 3)
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
        }
    }

    private func filterChip(title: String, icon: String, count: Int? = nil, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))

            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))

            if let count = count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.25) : accentTeal.opacity(0.2))
                    )
            }
        }
        .foregroundStyle(isSelected ? .white : textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(isSelected ?
                    LinearGradient(
                        colors: [accentTeal, accentTeal.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ) : LinearGradient(
                        colors: [cardBg, cardBg],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: isSelected ? accentTeal.opacity(0.3) : Color.black.opacity(colorScheme == .dark ? 0.15 : 0.04), radius: isSelected ? 6 : 4, y: isSelected ? 3 : 2)
        )
    }

    // MARK: - Document Card

    private enum DocStatus {
        case overdue, dueSoon, pending, paid

        var color: Color {
            switch self {
            case .overdue: return Color(red: 0.95, green: 0.45, blue: 0.4)
            case .dueSoon: return Color(red: 0.95, green: 0.65, blue: 0.25)
            case .pending: return Color(red: 0.0, green: 0.6, blue: 0.6)
            case .paid: return Color.green
            }
        }

        var label: String {
            switch self {
            case .overdue: return "Overdue"
            case .dueSoon: return "Due Soon"
            case .pending: return "Pending"
            case .paid: return "Paid"
            }
        }
    }

    private func documentCard(
        title: String,
        vendor: String,
        amount: String,
        dueDate: String,
        status: DocStatus,
        icon: String,
        iconColor: Color
    ) -> some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(status.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(status.color.opacity(0.15))
                        )
                }

                Text(vendor)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(textSecondary)

                HStack {
                    Text(dueDate)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(status == .overdue ? status.color : textSecondary)

                    Spacer()

                    Text(amount)
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(textPrimary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBg)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 8, y: 4)
        )
    }
}

#Preview {
    NavigationStack {
        WarmFinanceOtherDemo()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        WarmFinanceOtherDemo()
    }
    .preferredColorScheme(.dark)
}
