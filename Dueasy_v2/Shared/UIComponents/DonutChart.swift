import SwiftUI

/// A reusable donut chart component for displaying segmented data.
///
/// Displays up to 3 segments with colors and a center label.
/// Supports animation on appear (respecting Reduce Motion).
/// Designed for the Home screen month summary section.
struct DonutChart: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Data segments to display
    let segments: [DonutSegment]

    /// Center label text (e.g., "75%")
    let centerText: String

    /// Center subtitle (e.g., "12 invoices")
    let centerSubtitle: String

    /// Chart diameter
    let size: CGFloat

    /// Stroke width
    let strokeWidth: CGFloat

    @State private var animatedProgress: CGFloat = 0

    init(
        segments: [DonutSegment],
        centerText: String,
        centerSubtitle: String,
        size: CGFloat = 120,
        strokeWidth: CGFloat = 16
    ) {
        self.segments = segments
        self.centerText = centerText
        self.centerSubtitle = centerSubtitle
        self.size = size
        self.strokeWidth = strokeWidth
    }

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(
                    colorScheme == .light
                        ? Color.gray.opacity(0.15)
                        : Color.gray.opacity(0.2),
                    lineWidth: strokeWidth
                )
                .frame(width: size, height: size)

            // Segments
            ForEach(Array(segmentArcs.enumerated()), id: \.offset) { index, arc in
                Circle()
                    .trim(from: arc.start * animatedProgress, to: arc.end * animatedProgress)
                    .stroke(
                        arc.color,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
            }

            // Center content
            VStack(spacing: Spacing.xxs) {
                Text(centerText)
                    .font(Typography.title3)
                    .foregroundStyle(.primary)

                Text(centerSubtitle)
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .onAppear {
            if reduceMotion {
                animatedProgress = 1
            } else {
                withAnimation(.easeOut(duration: 0.8)) {
                    animatedProgress = 1
                }
            }
        }
    }

    // MARK: - Computed Properties

    /// Computes arc start/end positions for each segment
    private var segmentArcs: [(start: CGFloat, end: CGFloat, color: Color)] {
        let total = segments.reduce(0) { $0 + CGFloat($1.value) }
        guard total > 0 else { return [] }

        var arcs: [(start: CGFloat, end: CGFloat, color: Color)] = []
        var currentPosition: CGFloat = 0

        for segment in segments where segment.value > 0 {
            let segmentSize = CGFloat(segment.value) / total
            let start = currentPosition
            let end = currentPosition + segmentSize

            // Add small gap between segments
            let gap: CGFloat = segments.count > 1 ? 0.005 : 0
            arcs.append((start: start + gap, end: end - gap, color: segment.color))

            currentPosition = end
        }

        return arcs
    }

    private var accessibilityDescription: String {
        let segmentDescriptions = segments.map { segment in
            "\(segment.label): \(segment.value)"
        }.joined(separator: ", ")
        return "\(centerText) paid. \(segmentDescriptions)"
    }
}

// MARK: - Donut Segment

/// Represents a single segment in the donut chart.
struct DonutSegment: Identifiable {
    let id = UUID()
    let label: String
    let value: Int
    let color: Color

    init(label: String, value: Int, color: Color) {
        self.label = label
        self.value = value
        self.color = color
    }
}

// MARK: - Convenience Factory

extension DonutChart {
    /// Creates a payment status donut chart for the Home screen.
    static func paymentStatus(
        paidCount: Int,
        dueCount: Int,
        overdueCount: Int,
        paidPercent: Int,
        totalCount: Int
    ) -> DonutChart {
        DonutChart(
            segments: [
                DonutSegment(label: L10n.Home.Donut.paid.localized, value: paidCount, color: AppColors.success),
                DonutSegment(label: L10n.Home.Donut.due.localized, value: dueCount, color: AppColors.warning),
                DonutSegment(label: L10n.Home.Donut.overdue.localized, value: overdueCount, color: AppColors.error)
            ],
            centerText: "\(paidPercent)%",
            centerSubtitle: String.localized(L10n.Home.invoicesCount, with: totalCount)
        )
    }
}

// MARK: - Preview

#Preview("Donut Chart") {
    VStack(spacing: Spacing.xl) {
        DonutChart(
            segments: [
                DonutSegment(label: "Paid", value: 8, color: AppColors.success),
                DonutSegment(label: "Due", value: 3, color: AppColors.warning),
                DonutSegment(label: "Overdue", value: 1, color: AppColors.error)
            ],
            centerText: "67%",
            centerSubtitle: "12 invoices"
        )

        DonutChart(
            segments: [
                DonutSegment(label: "Paid", value: 10, color: AppColors.success),
                DonutSegment(label: "Due", value: 0, color: AppColors.warning),
                DonutSegment(label: "Overdue", value: 0, color: AppColors.error)
            ],
            centerText: "100%",
            centerSubtitle: "10 invoices"
        )

        DonutChart(
            segments: [
                DonutSegment(label: "Paid", value: 0, color: AppColors.success),
                DonutSegment(label: "Due", value: 5, color: AppColors.warning),
                DonutSegment(label: "Overdue", value: 2, color: AppColors.error)
            ],
            centerText: "0%",
            centerSubtitle: "7 invoices"
        )
    }
    .padding()
    .gradientBackground()
}
