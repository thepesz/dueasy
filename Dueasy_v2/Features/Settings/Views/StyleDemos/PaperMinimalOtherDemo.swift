import SwiftUI

/// Paper Minimal Document List Demo - Calm, Focused, Professional
/// Clean list with sharp corners, horizontal lines, and minimal visual noise.
struct PaperMinimalOtherDemo: View {

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
                // Search Bar
                searchBar
                    .padding(.bottom, 16)

                // Filter Tabs
                filterTabs
                    .padding(.bottom, 16)

                divider

                // Document List
                documentList
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(bgColor.ignoresSafeArea())
        .navigationTitle("Paper Minimal - Docs")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(borderColor)
            .frame(height: 1)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(textSecondary)

            Text("Search documents...")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(textSecondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    // MARK: - Filter Tabs

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                filterTab(title: "All", isSelected: true)
                filterTab(title: "Pending (2)", isSelected: false)
                filterTab(title: "Scheduled (3)", isSelected: false)
                filterTab(title: "Paid", isSelected: false)
                filterTab(title: "Overdue (1)", isSelected: false)
            }
        }
    }

    private func filterTab(title: String, isSelected: Bool) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? textPrimary : textSecondary)

            Rectangle()
                .fill(isSelected ? textPrimary : Color.clear)
                .frame(height: 2)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Document List

    private var documentList: some View {
        VStack(spacing: 0) {
            documentRow(
                title: "Orange Mobile - January",
                vendor: "Orange Polska",
                amount: "89,00 zl",
                date: "Due tomorrow",
                status: .dueSoon
            )

            divider

            documentRow(
                title: "Allegro Order #12847",
                vendor: "Allegro",
                amount: "245,50 zl",
                date: "3 days overdue",
                status: .overdue
            )

            divider

            documentRow(
                title: "PGE Electric Bill",
                vendor: "PGE Energia",
                amount: "312,40 zl",
                date: "Due in 5 days",
                status: .pending
            )

            divider

            documentRow(
                title: "Spotify Premium",
                vendor: "Spotify AB",
                amount: "23,99 zl",
                date: "Paid Jan 15",
                status: .paid
            )

            divider

            documentRow(
                title: "Netflix Subscription",
                vendor: "Netflix International",
                amount: "52,00 zl",
                date: "Paid Jan 10",
                status: .paid
            )

            divider

            documentRow(
                title: "UPC Internet",
                vendor: "UPC Polska",
                amount: "99,00 zl",
                date: "Due in 12 days",
                status: .pending
            )
        }
    }

    private enum DocStatus {
        case overdue, dueSoon, pending, paid

        var color: Color {
            switch self {
            case .overdue: return Color.red
            case .dueSoon: return Color.orange
            case .pending: return Color.gray
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

    private func documentRow(
        title: String,
        vendor: String,
        amount: String,
        date: String,
        status: DocStatus
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Status indicator line
            Rectangle()
                .fill(status.color)
                .frame(width: 3)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(status.label)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(status.color)
                }

                Text(vendor)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(textSecondary)

                HStack {
                    Text(date)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(status == .overdue ? status.color : textSecondary)

                    Spacer()

                    Text(amount)
                        .font(.system(size: 17, weight: .medium, design: .default).monospacedDigit())
                        .foregroundStyle(textPrimary)
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.trailing, 4)
    }
}

#Preview {
    NavigationStack {
        PaperMinimalOtherDemo()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        PaperMinimalOtherDemo()
    }
    .preferredColorScheme(.dark)
}
