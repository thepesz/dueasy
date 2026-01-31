import SwiftUI

/// Row component for displaying a document in a list.
/// Shows vendor name, amount, due date, and status.
struct DocumentRow: View {

    let document: FinanceDocument
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(document: FinanceDocument, onTap: @escaping () -> Void = {}) {
        self.document = document
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                // Document type icon
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

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(Spacing.sm)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view details")
    }

    // MARK: - Subviews

    private var documentTypeIcon: some View {
        Image(systemName: document.type.iconName)
            .font(.title3)
            .foregroundStyle(document.status.color)
            .frame(width: 40, height: 40)
            .background(document.status.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
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
