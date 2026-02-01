import SwiftUI

/// Row component for displaying a document in a list.
/// Shows vendor name, amount, due date, and status.
struct DocumentRow: View {

    let document: FinanceDocument
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @State private var isPressed = false

    init(document: FinanceDocument, onTap: @escaping () -> Void = {}) {
        self.document = document
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                // Document type icon with gradient ring
                documentTypeIcon

                // Main content
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    // Title and status
                    HStack {
                        Text(document.title.isEmpty ? "Untitled" : document.title)
                            .font(Typography.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        StatusBadge(status: document.status, size: .small)
                    }

                    // Amount and due date
                    HStack {
                        Text(formattedAmount)
                            .font(Typography.monospacedBody)
                            .foregroundStyle(.primary)

                        Spacer()

                        if let dueDate = document.dueDate {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                Text(formattedDate(dueDate))
                                    .font(Typography.caption1)
                            }
                            .foregroundStyle(AppColors.dueDateColor(daysUntilDue: document.daysUntilDue))
                        }
                    }

                    // Document number if available
                    if let number = document.documentNumber, !number.isEmpty {
                        Text("No. \(number)")
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                    }
                }

                // Chevron with subtle animation
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .offset(x: isPressed ? 2 : 0)
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
                                Color.white.opacity(colorScheme == .light ? 0.7 : 0.2),
                                Color.white.opacity(colorScheme == .light ? 0.2 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .light ? 0.06 : 0.2),
                radius: 8,
                x: 0,
                y: 4
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity) {
            // Never triggers - just for press state
        } onPressingChanged: { pressing in
            if !reduceMotion {
                withAnimation(pressing ? .easeInOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = pressing
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view details")
    }

    // MARK: - Subviews

    private var documentTypeIcon: some View {
        ZStack {
            // Gradient ring background
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            document.status.color.opacity(0.2),
                            document.status.color.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)

            // Icon
            Image(systemName: document.type.iconName)
                .font(.title3.weight(.medium))
                .foregroundStyle(document.status.color)
                .symbolRenderingMode(.hierarchical)
        }
        .overlay {
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            document.status.color.opacity(0.5),
                            document.status.color.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
    }

    // MARK: - Formatting

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = document.currency

        let number = NSDecimalNumber(decimal: document.amount)
        return formatter.string(from: number) ?? "\(document.amount) \(document.currency)"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var accessibilityLabel: String {
        var label = "\(document.type.displayName): \(document.title.isEmpty ? "Untitled" : document.title)"
        label += ", \(formattedAmount)"
        label += ", Status: \(document.status.displayName)"

        if let dueDate = document.dueDate {
            if let days = document.daysUntilDue {
                if days < 0 {
                    label += ", \(abs(days)) days overdue"
                } else if days == 0 {
                    label += ", due today"
                } else {
                    label += ", due in \(days) days"
                }
            }
        }

        return label
    }
}

// MARK: - Compact Row Variant

/// Compact document row for tighter list layouts
struct CompactDocumentRow: View {

    let document: FinanceDocument
    let onTap: () -> Void

    init(document: FinanceDocument, onTap: @escaping () -> Void = {}) {
        self.document = document
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title.isEmpty ? "Untitled" : document.title)
                        .font(Typography.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let dueDate = document.dueDate {
                        Text(formattedDate(dueDate))
                            .font(Typography.caption1)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(formattedAmount)
                    .font(Typography.subheadline.monospacedDigit())
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = document.currency
        let number = NSDecimalNumber(decimal: document.amount)
        return formatter.string(from: number) ?? "\(document.amount)"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Document Rows") {
    let sampleDocuments = [
        FinanceDocument(
            type: .invoice,
            title: "Acme Corporation",
            amount: 1250.00,
            currency: "PLN",
            dueDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
            status: .scheduled,
            documentNumber: "INV-2024-001"
        ),
        FinanceDocument(
            type: .invoice,
            title: "Electric Company",
            amount: 342.50,
            currency: "PLN",
            dueDate: Calendar.current.date(byAdding: .day, value: -2, to: Date()),
            status: .scheduled
        ),
        FinanceDocument(
            type: .invoice,
            title: "Internet Provider",
            amount: 89.99,
            currency: "PLN",
            dueDate: Date(),
            status: .paid
        )
    ]

    ScrollView {
        VStack(spacing: Spacing.sm) {
            ForEach(sampleDocuments) { doc in
                DocumentRow(document: doc)
            }

            Divider()
                .padding(.vertical)

            ForEach(sampleDocuments) { doc in
                CompactDocumentRow(document: doc)
            }
        }
        .padding()
    }
}
