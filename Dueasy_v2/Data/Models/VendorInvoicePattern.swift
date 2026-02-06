import Foundation
import SwiftData

// MARK: - Vendor Invoice Pattern Model

/// Tracks learned invoice patterns for a vendor.
/// Used for anomaly detection by comparing new invoices against established patterns.
///
/// Patterns are built over time as more invoices are processed.
/// Once sufficient data is collected (typically 3+ invoices), the pattern is
/// considered "established" and can be used for reliable anomaly detection.
///
/// Tracks both timing patterns (when invoices typically arrive) and
/// amount patterns (typical invoice amounts and variance).
@Model
final class VendorInvoicePattern {

    // MARK: - Primary Fields

    /// Unique identifier
    @Attribute(.unique)
    var id: UUID

    /// Vendor fingerprint for matching (same as used in documents and templates)
    @Attribute(.spotlight)
    var vendorFingerprint: String

    // MARK: - Timing Pattern Fields

    /// Days of month when invoices typically appear (e.g., [1, 15] for bi-monthly)
    /// Stored as comma-separated string for SwiftData compatibility
    private var typicalDaysOfMonthRaw: String?

    /// Median day of month across all invoices
    var medianDayOfMonth: Int?

    /// Standard deviation of day of month (for variability assessment)
    var dayOfMonthStdDev: Double?

    /// Typical interval between invoices in days (e.g., 30 for monthly)
    var typicalIntervalDays: Int?

    /// Variance in interval (to determine acceptable range)
    var intervalVarianceDays: Double?

    // MARK: - Amount Pattern Fields

    /// Average invoice amount stored as Double for SwiftData
    var averageAmountValue: Double?

    /// Minimum invoice amount observed
    var minAmountValue: Double?

    /// Maximum invoice amount observed
    var maxAmountValue: Double?

    /// Standard deviation of amounts
    var amountStdDevValue: Double?

    /// Currency code (for validation)
    var currency: String?

    // MARK: - Statistics Fields

    /// Number of invoices used to build this pattern
    var invoiceCount: Int

    /// When the pattern was first created
    var createdAt: Date

    /// When the pattern was last updated
    var updatedAt: Date

    /// When the pattern was considered "established" (sufficient data)
    var patternEstablishedAt: Date?

    /// Minimum invoices required to consider pattern established
    static let minimumInvoicesForPattern = 3

    // MARK: - Computed Properties

    /// Days of month when invoices typically appear
    var typicalDaysOfMonth: [Int] {
        get {
            guard let raw = typicalDaysOfMonthRaw, !raw.isEmpty else { return [] }
            return raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }
        set {
            typicalDaysOfMonthRaw = newValue.map { String($0) }.joined(separator: ",")
        }
    }

    /// Average amount as Decimal
    var averageAmount: Decimal? {
        get {
            guard let value = averageAmountValue else { return nil }
            return Decimal(value)
        }
        set {
            averageAmountValue = newValue.map { NSDecimalNumber(decimal: $0).doubleValue }
        }
    }

    /// Minimum amount as Decimal
    var minAmount: Decimal? {
        get {
            guard let value = minAmountValue else { return nil }
            return Decimal(value)
        }
        set {
            minAmountValue = newValue.map { NSDecimalNumber(decimal: $0).doubleValue }
        }
    }

    /// Maximum amount as Decimal
    var maxAmount: Decimal? {
        get {
            guard let value = maxAmountValue else { return nil }
            return Decimal(value)
        }
        set {
            maxAmountValue = newValue.map { NSDecimalNumber(decimal: $0).doubleValue }
        }
    }

    /// Standard deviation of amounts as Decimal
    var amountStdDev: Decimal? {
        get {
            guard let value = amountStdDevValue else { return nil }
            return Decimal(value)
        }
        set {
            amountStdDevValue = newValue.map { NSDecimalNumber(decimal: $0).doubleValue }
        }
    }

    /// Whether this pattern has enough data to be considered established
    var hasEstablishedPattern: Bool {
        invoiceCount >= Self.minimumInvoicesForPattern && patternEstablishedAt != nil
    }

    /// Amount range for anomaly detection (average +/- 2 standard deviations)
    var normalAmountRange: ClosedRange<Decimal>? {
        guard let avg = averageAmount, let stdDev = amountStdDev else { return nil }
        let twoStdDev = stdDev * 2
        let lower = max(Decimal.zero, avg - twoStdDev)
        let upper = avg + twoStdDev
        return lower...upper
    }

    /// Day of month range for anomaly detection
    var normalDayOfMonthWindow: ClosedRange<Int>? {
        guard let median = medianDayOfMonth, let stdDev = dayOfMonthStdDev else { return nil }
        // Use 2 standard deviations as the window, minimum 3 days
        let windowSize = max(3, Int(stdDev * 2.0))
        let lower = max(1, median - windowSize)
        let upper = min(31, median + windowSize)
        return lower...upper
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        vendorFingerprint: String,
        currency: String? = nil
    ) {
        self.id = id
        self.vendorFingerprint = vendorFingerprint
        self.currency = currency
        self.typicalDaysOfMonthRaw = nil
        self.medianDayOfMonth = nil
        self.dayOfMonthStdDev = nil
        self.typicalIntervalDays = nil
        self.intervalVarianceDays = nil
        self.averageAmountValue = nil
        self.minAmountValue = nil
        self.maxAmountValue = nil
        self.amountStdDevValue = nil
        self.invoiceCount = 0
        self.createdAt = Date()
        self.updatedAt = Date()
        self.patternEstablishedAt = nil
    }

    // MARK: - Update Methods

    /// Updates the pattern with a new invoice's data.
    /// - Parameters:
    ///   - dayOfMonth: Day of month of the invoice
    ///   - amount: Invoice amount
    func updateWithInvoice(dayOfMonth: Int, amount: Decimal) {
        let amountDouble = NSDecimalNumber(decimal: amount).doubleValue

        // Update invoice count
        invoiceCount += 1

        // Update day of month tracking
        updateDayOfMonthPattern(dayOfMonth)

        // Update amount pattern
        updateAmountPattern(amountDouble)

        // Check if pattern is now established
        if invoiceCount >= Self.minimumInvoicesForPattern && patternEstablishedAt == nil {
            patternEstablishedAt = Date()
        }

        updatedAt = Date()
    }

    /// Updates day of month statistics with a new value.
    private func updateDayOfMonthPattern(_ newDay: Int) {
        var days = typicalDaysOfMonth
        days.append(newDay)

        // Keep unique days sorted
        let uniqueDays = Array(Set(days)).sorted()
        typicalDaysOfMonth = uniqueDays

        // Calculate median
        let sortedDays = days.sorted()
        let count = sortedDays.count
        if count > 0 {
            if count % 2 == 0 {
                medianDayOfMonth = (sortedDays[count/2 - 1] + sortedDays[count/2]) / 2
            } else {
                medianDayOfMonth = sortedDays[count/2]
            }
        }

        // Calculate standard deviation
        if days.count >= 2 {
            let mean = Double(days.reduce(0, +)) / Double(days.count)
            let variance = days.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(days.count)
            dayOfMonthStdDev = sqrt(variance)
        }
    }

    /// Updates amount statistics with a new value using Welford's online algorithm.
    private func updateAmountPattern(_ newAmount: Double) {
        if invoiceCount == 1 {
            // First invoice
            averageAmountValue = newAmount
            minAmountValue = newAmount
            maxAmountValue = newAmount
            amountStdDevValue = 0
        } else {
            // Update min/max
            if newAmount < (minAmountValue ?? newAmount) {
                minAmountValue = newAmount
            }
            if newAmount > (maxAmountValue ?? newAmount) {
                maxAmountValue = newAmount
            }

            // Update running average and variance using Welford's algorithm
            guard let oldAverage = averageAmountValue else { return }
            let n = Double(invoiceCount)

            // New average
            let newAverage = oldAverage + (newAmount - oldAverage) / n
            averageAmountValue = newAverage

            // For standard deviation, we use a simplified update
            // This is an approximation but sufficient for our purposes
            if invoiceCount >= 2 {
                guard let min = minAmountValue, let max = maxAmountValue else { return }
                // Estimate std dev from range (rough but effective)
                amountStdDevValue = (max - min) / 4.0
            }
        }
    }

    // MARK: - Anomaly Detection Methods

    /// Checks if a day of month falls within the normal window.
    /// - Parameter day: The day of month to check
    /// - Returns: True if within normal window, false if anomalous
    func isDayWithinNormalWindow(_ day: Int) -> Bool {
        guard hasEstablishedPattern else {
            // No pattern established yet, consider all days normal
            return true
        }

        if let window = normalDayOfMonthWindow {
            return window.contains(day)
        }

        // Fallback: check if it matches any typical day (+/- 5 days tolerance)
        for typicalDay in typicalDaysOfMonth {
            let lower = max(1, typicalDay - 5)
            let upper = min(31, typicalDay + 5)
            if day >= lower && day <= upper {
                return true
            }
        }

        return typicalDaysOfMonth.isEmpty // If no days recorded, consider normal
    }

    /// Checks if an amount change from the average is significant.
    /// - Parameter newAmount: The new invoice amount
    /// - Returns: True if the change is significant (potential anomaly)
    func isAmountChangeSignificant(newAmount: Decimal) -> Bool {
        guard hasEstablishedPattern else {
            // No pattern established yet, can't determine significance
            return false
        }

        guard let range = normalAmountRange else {
            return false
        }

        // Amount outside 2 standard deviations is significant
        return !range.contains(newAmount)
    }

    /// Calculates the deviation percentage from the average amount.
    /// - Parameter amount: The amount to compare
    /// - Returns: Percentage deviation (positive for higher, negative for lower)
    func deviationPercentage(for amount: Decimal) -> Double? {
        guard let avg = averageAmount, avg != 0 else { return nil }
        let deviation = amount - avg
        let percentage = NSDecimalNumber(decimal: deviation / avg * 100).doubleValue
        return percentage
    }

    /// Determines severity of an amount anomaly.
    /// - Parameter amount: The anomalous amount
    /// - Returns: Severity level based on deviation
    func amountAnomalySeverity(for amount: Decimal) -> AnomalySeverity? {
        guard let avg = averageAmount, let stdDev = amountStdDev, stdDev > 0 else {
            return nil
        }

        let deviation = abs(NSDecimalNumber(decimal: amount - avg).doubleValue)
        let stdDevDouble = NSDecimalNumber(decimal: stdDev).doubleValue
        let zScore = deviation / stdDevDouble

        if zScore > 4 {
            return .critical  // More than 4 standard deviations
        } else if zScore > 3 {
            return .warning   // More than 3 standard deviations
        } else if zScore > 2 {
            return .info      // More than 2 standard deviations
        }

        return nil  // Within normal range
    }
}
