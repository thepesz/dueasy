import SwiftUI

/// A form field that displays extraction evidence, confidence, and alternatives.
/// Designed for production UX in document review screens.
struct FieldWithEvidence: View {

    let label: String
    let isRequired: Bool
    @Binding var selectedValue: String
    let alternatives: [ExtractionCandidate]
    let evidence: BoundingBox?
    let confidence: Double
    let reviewMode: ReviewMode
    let onAlternativeSelected: (ExtractionCandidate) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        label: String,
        isRequired: Bool = false,
        selectedValue: Binding<String>,
        alternatives: [ExtractionCandidate] = [],
        evidence: BoundingBox? = nil,
        confidence: Double = 0.0,
        reviewMode: ReviewMode = .suggested,
        onAlternativeSelected: @escaping (ExtractionCandidate) -> Void = { _ in }
    ) {
        self.label = label
        self.isRequired = isRequired
        self._selectedValue = selectedValue
        self.alternatives = alternatives
        self.evidence = evidence
        self.confidence = confidence
        self.reviewMode = reviewMode
        self.onAlternativeSelected = onAlternativeSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header with label and confidence badge
            HStack(spacing: Spacing.xs) {
                headerLabel

                Spacer()

                if confidence > 0 {
                    ConfidenceBadge(confidence: confidence, reviewMode: reviewMode)
                }
            }

            // Main text field
            TextField("", text: $selectedValue, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .reviewModeBorder(reviewMode)

            // Evidence indicator
            if let evidence = evidence {
                EvidenceIndicator(bbox: evidence, confidence: confidence)
            }

            // Alternatives row (if multiple candidates available)
            if alternatives.count > 1 {
                AlternativesRow(
                    alternatives: alternatives,
                    selected: selectedValue,
                    onSelect: { candidate in
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
                            selectedValue = candidate.value
                        }
                        onAlternativeSelected(candidate)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var headerLabel: some View {
        HStack(spacing: Spacing.xxs) {
            Text(label)
                .font(Typography.caption1)
                .foregroundStyle(.secondary)

            if isRequired {
                Text("*")
                    .font(Typography.caption1)
                    .foregroundStyle(AppColors.error)
            }

            // Review mode indicator
            if reviewMode == .required {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColors.warning)
            }
        }
    }
}

// MARK: - Confidence Badge

/// Visual indicator showing extraction confidence level.
struct ConfidenceBadge: View {

    let confidence: Double
    let reviewMode: ReviewMode

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.caption2)

            Text(confidenceText)
                .font(Typography.caption2)
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch reviewMode {
        case .autoFilled:
            return "checkmark.circle.fill"
        case .suggested:
            return "questionmark.circle"
        case .required:
            return "exclamationmark.triangle.fill"
        }
    }

    private var confidenceText: String {
        "\(Int(confidence * 100))%"
    }

    private var badgeColor: Color {
        switch reviewMode {
        case .autoFilled:
            return AppColors.success
        case .suggested:
            return AppColors.warning
        case .required:
            return AppColors.error
        }
    }
}

// MARK: - Evidence Indicator

/// Shows where in the document a field value was found.
struct EvidenceIndicator: View {

    let bbox: BoundingBox
    let confidence: Double

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(regionDescription)
                .font(Typography.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, Spacing.xxs)
    }

    private var regionDescription: String {
        // Convert normalized bbox to human-readable region
        let verticalPosition: String
        let horizontalPosition: String

        // Vertical position
        if bbox.centerY < 0.33 {
            verticalPosition = "Top"
        } else if bbox.centerY < 0.66 {
            verticalPosition = "Middle"
        } else {
            verticalPosition = "Bottom"
        }

        // Horizontal position
        if bbox.centerX < 0.33 {
            horizontalPosition = "left"
        } else if bbox.centerX < 0.66 {
            horizontalPosition = "center"
        } else {
            horizontalPosition = "right"
        }

        return "Found in \(verticalPosition.lowercased())-\(horizontalPosition) region"
    }
}

// MARK: - Alternatives Row

/// Horizontal scrolling row of alternative extraction candidates.
struct AlternativesRow: View {

    let alternatives: [ExtractionCandidate]
    let selected: String
    let onSelect: (ExtractionCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Alternatives")
                .font(Typography.caption2)
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(alternatives, id: \.value) { candidate in
                        AlternativeChip(
                            value: candidate.value,
                            confidence: candidate.confidence,
                            source: candidate.source,
                            isSelected: candidate.value == selected,
                            onTap: { onSelect(candidate) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Alternative Chip

/// Tappable chip showing an alternative extraction candidate.
struct AlternativeChip: View {

    let value: String
    let confidence: Double
    let source: String
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(truncatedValue)
                    .font(Typography.caption1.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    // Confidence indicator dots
                    HStack(spacing: 2) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(dotColor(for: index))
                                .frame(width: 4, height: 4)
                        }
                    }

                    Text(truncatedSource)
                        .font(Typography.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(isSelected ? AppColors.primary : AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .strokeBorder(AppColors.primary, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value), confidence \(Int(confidence * 100)) percent")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var truncatedValue: String {
        if value.count > 25 {
            return String(value.prefix(22)) + "..."
        }
        return value
    }

    private var truncatedSource: String {
        // Clean up source description
        let cleaned = source
            .replacingOccurrences(of: "anchor-", with: "")
            .replacingOccurrences(of: "region: ", with: "")
            .replacingOccurrences(of: "pattern: ", with: "")

        if cleaned.count > 15 {
            return String(cleaned.prefix(12)) + "..."
        }
        return cleaned
    }

    private func dotColor(for index: Int) -> Color {
        // Show 1-3 filled dots based on confidence
        let filledDots = Int(ceil(confidence * 3))
        if index < filledDots {
            return isSelected ? .white : AppColors.primary
        }
        return isSelected ? .white.opacity(0.3) : Color.secondary.opacity(0.3)
    }
}

// MARK: - Review Mode Border Modifier

extension View {
    /// Applies a border based on the review mode
    func reviewModeBorder(_ mode: ReviewMode) -> some View {
        self.overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(borderColor(for: mode), lineWidth: mode == .required ? 2 : 0)
        }
    }

    private func borderColor(for mode: ReviewMode) -> Color {
        switch mode {
        case .autoFilled:
            return .clear
        case .suggested:
            return .clear
        case .required:
            return AppColors.warning.opacity(0.5)
        }
    }
}

// MARK: - Date Field with Evidence

/// Specialized date field with evidence and alternatives.
struct DateFieldWithEvidence: View {

    let label: String
    let isRequired: Bool
    @Binding var selectedDate: Date
    let alternatives: [DateCandidate]
    let evidence: BoundingBox?
    let confidence: Double
    let reviewMode: ReviewMode
    let onAlternativeSelected: (DateCandidate) -> Void
    let showPastDateWarning: Bool

    @State private var showDatePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header with label and confidence badge
            HStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xxs) {
                    Text(label)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)

                    if isRequired {
                        Text("*")
                            .font(Typography.caption1)
                            .foregroundStyle(AppColors.error)
                    }
                }

                Spacer()

                if confidence > 0 {
                    ConfidenceBadge(confidence: confidence, reviewMode: reviewMode)
                }
            }

            // Date picker
            DatePicker(
                "",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()

            // Past date warning
            if showPastDateWarning {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("This date is in the past")
                        .font(Typography.caption1)
                }
                .foregroundStyle(AppColors.warning)
            }

            // Evidence indicator
            if let evidence = evidence {
                EvidenceIndicator(bbox: evidence, confidence: confidence)
            }

            // Date alternatives
            if alternatives.count > 1 {
                DateAlternativesRow(
                    alternatives: alternatives,
                    selected: selectedDate,
                    onSelect: onAlternativeSelected
                )
            }
        }
    }
}

// MARK: - Date Alternatives Row

struct DateAlternativesRow: View {

    let alternatives: [DateCandidate]
    let selected: Date
    let onSelect: (DateCandidate) -> Void

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Other dates found")
                .font(Typography.caption2)
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(alternatives, id: \.date) { candidate in
                        DateAlternativeChip(
                            date: candidate.date,
                            reason: candidate.scoreReason,
                            isSelected: Calendar.current.isDate(candidate.date, inSameDayAs: selected),
                            onTap: { onSelect(candidate) }
                        )
                    }
                }
            }
        }
    }
}

struct DateAlternativeChip: View {

    let date: Date
    let reason: String
    let isSelected: Bool
    let onTap: () -> Void

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        return formatter
    }()

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateFormatter.string(from: date))
                    .font(Typography.caption1.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(truncatedReason)
                    .font(Typography.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(isSelected ? AppColors.primary : AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var truncatedReason: String {
        if reason.count > 20 {
            return String(reason.prefix(17)) + "..."
        }
        return reason
    }
}

// MARK: - Amount Field with Evidence

/// Specialized amount field with currency and alternatives.
struct AmountFieldWithEvidence: View {

    let label: String
    let isRequired: Bool
    @Binding var amount: String
    @Binding var currency: String
    let alternatives: [(Decimal, String)]
    let confidence: Double
    let reviewMode: ReviewMode
    let onAlternativeSelected: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header with label and confidence badge
            HStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xxs) {
                    Text(label)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)

                    if isRequired {
                        Text("*")
                            .font(Typography.caption1)
                            .foregroundStyle(AppColors.error)
                    }
                }

                Spacer()

                if confidence > 0 {
                    ConfidenceBadge(confidence: confidence, reviewMode: reviewMode)
                }
            }

            // Amount and currency row
            HStack(spacing: Spacing.sm) {
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)

                Picker("Currency", selection: $currency) {
                    ForEach(SettingsManager.availableCurrencies, id: \.self) { curr in
                        Text(curr).tag(curr)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
            }

            // Amount alternatives
            if alternatives.count > 1 {
                AmountAlternativesRow(
                    alternatives: alternatives,
                    selectedAmount: amount,
                    currency: currency,
                    onSelect: onAlternativeSelected
                )
            }
        }
    }
}

// MARK: - Amount Alternatives Row

struct AmountAlternativesRow: View {

    let alternatives: [(Decimal, String)]
    let selectedAmount: String
    let currency: String
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Detected amounts")
                .font(Typography.caption2)
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(Array(alternatives.enumerated()), id: \.offset) { index, alternative in
                        AmountSuggestionChip(
                            amount: alternative.0,
                            context: alternative.1,
                            currency: currency,
                            isSelected: isSelected(alternative.0)
                        ) {
                            onSelect(index)
                        }
                    }
                }
            }
        }
    }

    private func isSelected(_ amount: Decimal) -> Bool {
        // Parse selected amount and compare
        let normalized = selectedAmount
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let selectedDecimal = Decimal(string: normalized) else { return false }
        return selectedDecimal == amount
    }
}

// NOTE: WarningBanner is defined in ErrorBanner.swift

// MARK: - Previews

#Preview("FieldWithEvidence") {
    VStack(spacing: Spacing.md) {
        FieldWithEvidence(
            label: "Vendor Name",
            isRequired: true,
            selectedValue: .constant("Acme Corporation Sp. z o.o."),
            alternatives: [
                ExtractionCandidate(
                    value: "Acme Corporation Sp. z o.o.",
                    confidence: 0.92,
                    bbox: BoundingBox(x: 0.1, y: 0.1, width: 0.3, height: 0.05),
                    method: .anchorBased,
                    source: "anchor: Sprzedawca"
                ),
                ExtractionCandidate(
                    value: "ACME Corp.",
                    confidence: 0.75,
                    bbox: BoundingBox(x: 0.1, y: 0.2, width: 0.2, height: 0.05),
                    method: .regionHeuristic,
                    source: "region: topLeft"
                )
            ],
            evidence: BoundingBox(x: 0.1, y: 0.1, width: 0.3, height: 0.05),
            confidence: 0.92,
            reviewMode: .autoFilled
        )

        FieldWithEvidence(
            label: "Amount",
            isRequired: true,
            selectedValue: .constant("1,234.56"),
            alternatives: [
                ExtractionCandidate(
                    value: "1,234.56",
                    confidence: 0.78,
                    bbox: BoundingBox(x: 0.7, y: 0.8, width: 0.2, height: 0.05),
                    method: .anchorBased,
                    source: "anchor: Do zaplaty"
                ),
                ExtractionCandidate(
                    value: "1,500.00",
                    confidence: 0.65,
                    bbox: BoundingBox(x: 0.7, y: 0.7, width: 0.2, height: 0.05),
                    method: .regionHeuristic,
                    source: "region: bottomRight"
                )
            ],
            evidence: BoundingBox(x: 0.7, y: 0.8, width: 0.2, height: 0.05),
            confidence: 0.78,
            reviewMode: .suggested
        )

        FieldWithEvidence(
            label: "Due Date",
            isRequired: true,
            selectedValue: .constant("15.02.2024"),
            confidence: 0.55,
            reviewMode: .required
        )
    }
    .padding()
    .gradientBackground()
}

#Preview("ConfidenceBadge") {
    HStack(spacing: Spacing.md) {
        ConfidenceBadge(confidence: 0.95, reviewMode: .autoFilled)
        ConfidenceBadge(confidence: 0.78, reviewMode: .suggested)
        ConfidenceBadge(confidence: 0.45, reviewMode: .required)
    }
    .padding()
}
