import Foundation

// MARK: - Insights Date Range

/// Date range options for fetching anomaly summaries in the Insights dashboard.
enum InsightsDateRange: Sendable, CaseIterable {
    case last7Days
    case last30Days
    case last90Days
    case thisMonth
    case lastMonth
    case thisYear
    case allTime

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .last90Days: return "Last 90 Days"
        case .thisMonth: return "This Month"
        case .lastMonth: return "Last Month"
        case .thisYear: return "This Year"
        case .allTime: return "All Time"
        }
    }

    /// Computed start date for this range
    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .last7Days:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30Days:
            return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .last90Days:
            return calendar.date(byAdding: .day, value: -90, to: now) ?? now
        case .thisMonth:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        case .lastMonth:
            let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            return calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? now
        case .thisYear:
            return calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        case .allTime:
            return Date.distantPast
        }
    }

    /// Computed end date for this range
    var endDate: Date {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .lastMonth:
            let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            return calendar.date(byAdding: .day, value: -1, to: startOfThisMonth) ?? now
        default:
            return now
        }
    }
}

// MARK: - Insights Anomaly Summary

/// Summary of anomalies for the Insights dashboard.
/// Provides aggregated counts and severity breakdowns.
struct InsightsAnomalySummary: Sendable, Equatable {

    /// Total number of anomalies detected in the date range
    let totalCount: Int

    /// Number of critical severity anomalies
    let criticalCount: Int

    /// Number of warning severity anomalies
    let warningCount: Int

    /// Number of info severity anomalies
    let infoCount: Int

    /// Number of unresolved anomalies
    let unresolvedCount: Int

    /// Number of resolved anomalies
    let resolvedCount: Int

    /// Breakdown by anomaly type (type raw value -> count)
    let countsByType: [String: Int]

    /// List of anomalies in the date range (for detailed view)
    let anomalies: [DocumentAnomaly]

    /// Whether there are any critical anomalies requiring immediate attention
    var hasCriticalIssues: Bool {
        criticalCount > 0
    }

    /// Whether there are any unresolved anomalies
    var hasUnresolvedIssues: Bool {
        unresolvedCount > 0
    }

    /// Empty summary (no anomalies)
    static let empty = InsightsAnomalySummary(
        totalCount: 0,
        criticalCount: 0,
        warningCount: 0,
        infoCount: 0,
        unresolvedCount: 0,
        resolvedCount: 0,
        countsByType: [:],
        anomalies: []
    )

    init(
        totalCount: Int,
        criticalCount: Int,
        warningCount: Int,
        infoCount: Int,
        unresolvedCount: Int,
        resolvedCount: Int,
        countsByType: [String: Int],
        anomalies: [DocumentAnomaly]
    ) {
        self.totalCount = totalCount
        self.criticalCount = criticalCount
        self.warningCount = warningCount
        self.infoCount = infoCount
        self.unresolvedCount = unresolvedCount
        self.resolvedCount = resolvedCount
        self.countsByType = countsByType
        self.anomalies = anomalies
    }
}

// MARK: - Vendor History Analysis Result

/// Result of deep vendor analysis including all historical anomalies and patterns.
struct VendorHistoryAnalysisResult: Sendable {

    /// Vendor fingerprint that was analyzed
    let vendorFingerprint: String

    /// All anomalies associated with this vendor
    let anomalies: [DocumentAnomaly]

    /// All bank accounts used by this vendor
    let bankAccounts: [VendorBankAccountHistory]

    /// Invoice pattern for this vendor (if established)
    let invoicePattern: VendorInvoicePattern?

    /// Total number of documents from this vendor
    let documentCount: Int

    /// Risk assessment based on history
    let riskLevel: VendorRiskLevel

    /// Summary of findings
    let summary: String
}

/// Risk level assessment for a vendor based on their history.
enum VendorRiskLevel: String, Sendable, CaseIterable {
    case low
    case medium
    case high
    case critical

    var displayName: String {
        switch self {
        case .low: return "Low Risk"
        case .medium: return "Medium Risk"
        case .high: return "High Risk"
        case .critical: return "Critical Risk"
        }
    }
}

// MARK: - Fraud Detection Service Protocol

/// Protocol for the fraud detection service.
/// Analyzes documents for anomalies, fraud indicators, and suspicious patterns.
///
/// Iteration 1: Local heuristic-based detection using historical patterns.
/// Iteration 2: Enhanced with AI-powered fraud detection from backend.
///
/// Detection Categories:
/// - IBAN Change Detection: Alerts when a vendor's bank account changes
/// - Vendor Spoofing: Detects similar vendor names with different identifiers
/// - Timing Anomalies: Detects invoices outside normal billing cycles
/// - Amount Anomalies: Detects significant deviations from historical amounts
protocol FraudDetectionServiceProtocol: Sendable {

    // MARK: - Core Analysis Methods

    /// Analyzes a document for all types of anomalies and fraud indicators.
    /// Runs all detection checks in parallel and saves detected anomalies to SwiftData.
    /// - Parameter document: The document to analyze
    /// - Returns: Array of detected anomalies (empty if none found)
    func analyzeDocument(_ document: FinanceDocument) async throws -> [DocumentAnomaly]

    /// Performs deep analysis of a vendor's history.
    /// Examines all documents, bank accounts, and patterns for the vendor.
    /// - Parameter vendorFingerprint: The vendor fingerprint to analyze
    /// - Returns: Comprehensive vendor history analysis result
    func analyzeVendorHistory(vendorFingerprint: String) async throws -> VendorHistoryAnalysisResult

    /// Fetches anomaly summary for the Insights dashboard.
    /// - Parameter dateRange: The date range to fetch anomalies for
    /// - Returns: Aggregated summary of anomalies
    func fetchInsightsAnomalies(dateRange: InsightsDateRange) async throws -> InsightsAnomalySummary

    /// Refreshes stale vendor patterns in the background.
    /// Patterns older than 24 hours are considered stale.
    /// - Returns: Number of patterns refreshed
    @discardableResult
    func refreshStalePatterns() async throws -> Int

    // MARK: - Individual Detection Methods

    /// Checks for IBAN change compared to vendor history.
    /// - Parameter document: Document with IBAN to check
    /// - Returns: Anomaly if IBAN changed, info if first seen, nil if unchanged
    func checkIBANChange(document: FinanceDocument) async throws -> DocumentAnomaly?

    /// Checks for potential vendor spoofing (similar name, different identifiers).
    /// Uses Levenshtein distance and homoglyph detection.
    /// - Parameter document: Document to check
    /// - Returns: Anomaly if spoofing detected, nil otherwise
    func checkVendorSpoofing(document: FinanceDocument) async throws -> DocumentAnomaly?

    /// Checks for timing anomalies against established patterns.
    /// - Parameter document: Document to check
    /// - Returns: Anomaly if invoice day is unusual, nil otherwise
    func checkTimingAnomaly(document: FinanceDocument) async throws -> DocumentAnomaly?

    /// Checks for amount anomalies against established patterns.
    /// - Parameter document: Document to check
    /// - Returns: Anomaly if amount is significantly different, nil otherwise
    func checkAmountAnomaly(document: FinanceDocument) async throws -> DocumentAnomaly?

    /// Checks if this is the first invoice from a vendor.
    /// Returns info-level indicator for user awareness.
    /// - Parameter document: Document to check
    /// - Returns: Info anomaly if first invoice, nil otherwise
    func checkFirstInvoiceFromVendor(document: FinanceDocument) async throws -> DocumentAnomaly?

    // MARK: - Anomaly Management

    /// Fetches all unresolved anomalies for a document.
    /// - Parameter documentId: Document ID to fetch anomalies for
    /// - Returns: Array of unresolved anomalies
    func fetchUnresolvedAnomalies(forDocumentId documentId: UUID) async throws -> [DocumentAnomaly]

    /// Fetches all anomalies for a vendor.
    /// - Parameter vendorFingerprint: Vendor fingerprint to fetch anomalies for
    /// - Returns: Array of all anomalies for the vendor
    func fetchAnomalies(forVendorFingerprint vendorFingerprint: String) async throws -> [DocumentAnomaly]

    /// Acknowledges an anomaly with a resolution.
    /// - Parameters:
    ///   - anomaly: The anomaly to acknowledge
    ///   - resolution: How the anomaly was resolved
    ///   - notes: Optional notes about the resolution
    func acknowledgeAnomaly(
        _ anomaly: DocumentAnomaly,
        resolution: AnomalyResolution,
        notes: String?
    ) async throws
}

// MARK: - Default Implementations

extension FraudDetectionServiceProtocol {

    /// Default implementation that returns info for first invoice.
    /// Subclasses should override with actual detection logic.
    func checkFirstInvoiceFromVendor(document: FinanceDocument) async throws -> DocumentAnomaly? {
        // Default: no-op, to be implemented by concrete service
        return nil
    }
}
