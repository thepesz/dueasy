import Foundation
import SwiftData
import os.log

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

// MARK: - Crashlytics Logger Helper

/// Helper for Crashlytics logging.
/// Encapsulates conditional compilation for Crashlytics SDK availability.
enum CrashlyticsLogger {

    /// Logs fraud detection metrics to Crashlytics.
    /// PRIVACY: Only logs counts and types, never amounts or vendor names.
    static func logFraudDetection(anomalyCount: Int, typeCounts: [String: Int]) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().log("Detected \(anomalyCount) anomalies")
        for (type, count) in typeCounts {
            Crashlytics.crashlytics().log("Anomaly type \(type): \(count)")
        }
        #endif
    }
}

// MARK: - Fraud Detection Service

/// Implementation of FraudDetectionServiceProtocol.
/// Analyzes documents for anomalies, fraud indicators, and suspicious patterns.
///
/// Detection algorithms:
/// 1. IBAN Change: Compares current IBAN against vendor's historical bank accounts
/// 2. Vendor Spoofing: Detects similar names with different identifiers
/// 3. Timing Anomaly: Checks invoice day against established patterns
/// 4. Amount Anomaly: Checks amount against historical average
/// 5. First Invoice: Info-level indicator for new vendors
///
/// Privacy considerations:
/// - Logs only counts and types, never amounts or vendor names
/// - Uses Crashlytics logging only in production builds
@MainActor
final class FraudDetectionService: FraudDetectionServiceProtocol {

    // MARK: - Constants

    /// Levenshtein distance threshold for long names (>= 10 characters)
    private static let levenshteinThresholdLong = 3

    /// Levenshtein distance threshold for short names (< 10 characters)
    private static let levenshteinThresholdShort = 2

    /// Minimum documents required for amount anomaly detection
    private static let minHistoricalDocsForAmount = 2

    /// Minimum extra fee amount to flag (prevents noise from small variances)
    private static let minExtraFeeAmount: Double = 20.0

    /// Hours after which patterns are considered stale
    private static let stalePatternHours = 24

    /// Default amount change threshold percentage
    private static let defaultAmountChangeThresholdPercent = 20.0

    /// Default timing window tolerance in days
    private static let defaultTimingWindowDays = 7

    /// Detection algorithm version for tracking
    private static let detectionVersion = "1.0"

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let stringMatchingService: StringMatchingServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "FraudDetection")

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        stringMatchingService: StringMatchingServiceProtocol
    ) {
        self.modelContext = modelContext
        self.stringMatchingService = stringMatchingService
    }

    // MARK: - Core Analysis Methods

    func analyzeDocument(_ document: FinanceDocument) async throws -> [DocumentAnomaly] {
        // PRIVACY: Log only that we're analyzing, not document details
        logger.info("Analyzing document for anomalies")

        var detectedAnomalies: [DocumentAnomaly] = []

        // Run all checks in parallel for performance
        async let ibanCheck = checkIBANChange(document: document)
        async let spoofingCheck = checkVendorSpoofing(document: document)
        async let timingCheck = checkTimingAnomaly(document: document)
        async let amountCheck = checkAmountAnomaly(document: document)
        async let firstInvoiceCheck = checkFirstInvoiceFromVendor(document: document)

        // Collect results
        do {
            if let anomaly = try await ibanCheck {
                detectedAnomalies.append(anomaly)
            }
        } catch {
            logger.error("IBAN check failed: \(error.localizedDescription)")
        }

        do {
            if let anomaly = try await spoofingCheck {
                detectedAnomalies.append(anomaly)
            }
        } catch {
            logger.error("Spoofing check failed: \(error.localizedDescription)")
        }

        do {
            if let anomaly = try await timingCheck {
                detectedAnomalies.append(anomaly)
            }
        } catch {
            logger.error("Timing check failed: \(error.localizedDescription)")
        }

        do {
            if let anomaly = try await amountCheck {
                detectedAnomalies.append(anomaly)
            }
        } catch {
            logger.error("Amount check failed: \(error.localizedDescription)")
        }

        do {
            if let anomaly = try await firstInvoiceCheck {
                detectedAnomalies.append(anomaly)
            }
        } catch {
            logger.error("First invoice check failed: \(error.localizedDescription)")
        }

        // Save detected anomalies to SwiftData
        for anomaly in detectedAnomalies {
            modelContext.insert(anomaly)
        }

        if !detectedAnomalies.isEmpty {
            try modelContext.save()

            // PRIVACY: Log only counts and types
            logAnomaliesDetected(detectedAnomalies)
        }

        logger.info("Analysis complete: \(detectedAnomalies.count) anomalies detected")

        return detectedAnomalies
    }

    func analyzeVendorHistory(vendorFingerprint: String) async throws -> VendorHistoryAnalysisResult {
        logger.info("Analyzing vendor history")

        // Fetch all anomalies for this vendor
        let anomalies = try await fetchAnomalies(forVendorFingerprint: vendorFingerprint)

        // Fetch bank account history
        let bankAccounts = try await fetchBankAccountHistory(forVendorFingerprint: vendorFingerprint)

        // Fetch invoice pattern
        let pattern = try await fetchInvoicePattern(forVendorFingerprint: vendorFingerprint)

        // Count documents for this vendor
        let documentCount = try await countDocuments(forVendorFingerprint: vendorFingerprint)

        // Assess risk level
        let riskLevel = assessRiskLevel(
            anomalies: anomalies,
            bankAccounts: bankAccounts
        )

        // Generate summary
        let summary = generateVendorSummary(
            anomalyCount: anomalies.count,
            bankAccountCount: bankAccounts.count,
            hasPattern: pattern != nil,
            riskLevel: riskLevel
        )

        return VendorHistoryAnalysisResult(
            vendorFingerprint: vendorFingerprint,
            anomalies: anomalies,
            bankAccounts: bankAccounts,
            invoicePattern: pattern,
            documentCount: documentCount,
            riskLevel: riskLevel,
            summary: summary
        )
    }

    func fetchInsightsAnomalies(dateRange: InsightsDateRange) async throws -> InsightsAnomalySummary {
        let startDate = dateRange.startDate
        let endDate = dateRange.endDate

        let descriptor = FetchDescriptor<DocumentAnomaly>(
            predicate: #Predicate<DocumentAnomaly> {
                $0.detectedAt >= startDate && $0.detectedAt <= endDate
            },
            sortBy: [SortDescriptor(\.detectedAt, order: .reverse)]
        )

        let anomalies = try modelContext.fetch(descriptor)

        if anomalies.isEmpty {
            return .empty
        }

        // Calculate counts
        var criticalCount = 0
        var warningCount = 0
        var infoCount = 0
        var unresolvedCount = 0
        var resolvedCount = 0
        var countsByType: [String: Int] = [:]

        for anomaly in anomalies {
            // Severity counts
            switch anomaly.severity {
            case .critical: criticalCount += 1
            case .warning: warningCount += 1
            case .info: infoCount += 1
            }

            // Resolution counts
            if anomaly.isResolved {
                resolvedCount += 1
            } else {
                unresolvedCount += 1
            }

            // Type counts
            let typeKey = anomaly.typeRaw
            countsByType[typeKey, default: 0] += 1
        }

        return InsightsAnomalySummary(
            totalCount: anomalies.count,
            criticalCount: criticalCount,
            warningCount: warningCount,
            infoCount: infoCount,
            unresolvedCount: unresolvedCount,
            resolvedCount: resolvedCount,
            countsByType: countsByType,
            anomalies: anomalies
        )
    }

    @discardableResult
    func refreshStalePatterns() async throws -> Int {
        let staleThreshold = Calendar.current.date(
            byAdding: .hour,
            value: -Self.stalePatternHours,
            to: Date()
        ) ?? Date()

        let descriptor = FetchDescriptor<VendorInvoicePattern>(
            predicate: #Predicate<VendorInvoicePattern> {
                $0.updatedAt < staleThreshold
            }
        )

        let stalePatterns = try modelContext.fetch(descriptor)

        logger.info("Found \(stalePatterns.count) stale patterns to refresh")

        var refreshedCount = 0

        for pattern in stalePatterns {
            // Re-analyze documents for this vendor
            do {
                try await refreshPattern(pattern)
                refreshedCount += 1
            } catch {
                logger.error("Failed to refresh pattern: \(error.localizedDescription)")
            }
        }

        if refreshedCount > 0 {
            try modelContext.save()
        }

        return refreshedCount
    }

    // MARK: - Individual Detection Methods

    func checkIBANChange(document: FinanceDocument) async throws -> DocumentAnomaly? {
        guard let vendorFingerprint = document.vendorFingerprint,
              let currentIBAN = document.bankAccountNumber,
              !currentIBAN.isEmpty else {
            return nil
        }

        // Normalize the IBAN
        let normalizedIBAN = VendorBankAccountHistory.normalizeIBAN(currentIBAN)

        // Fetch existing bank accounts for this vendor
        let existingAccounts = try await fetchBankAccountHistory(forVendorFingerprint: vendorFingerprint)

        if existingAccounts.isEmpty {
            // First IBAN seen - create history entry and return info
            let newHistory = VendorBankAccountHistory(
                vendorFingerprint: vendorFingerprint,
                iban: normalizedIBAN,
                isPrimary: true
            )
            modelContext.insert(newHistory)

            logger.debug("First IBAN recorded for vendor")

            // Return info-level anomaly for first IBAN (not critical)
            return DocumentAnomaly(
                documentId: document.id,
                vendorFingerprint: vendorFingerprint,
                type: .bankAccountChanged,
                severity: .info,
                detectionVersion: Self.detectionVersion,
                summary: "First bank account recorded for this vendor",
                contextData: AnomalyContextData(
                    newBankAccount: maskIBAN(normalizedIBAN),
                    additionalNotes: "No previous bank account on file",
                    algorithmVersion: Self.detectionVersion
                )
            )
        }

        // Check if current IBAN exists in history
        let matchingAccount = existingAccounts.first { $0.iban == normalizedIBAN }

        if let existing = matchingAccount {
            // IBAN exists - update usage and return nil (no anomaly)
            existing.recordUsage()
            return nil
        }

        // NEW IBAN detected - this is critical!
        // Find the primary/most-used account for comparison
        let primaryAccount = existingAccounts
            .sorted { $0.documentCount > $1.documentCount }
            .first

        // Create new history entry for this IBAN
        let newHistory = VendorBankAccountHistory(
            vendorFingerprint: vendorFingerprint,
            iban: normalizedIBAN,
            isPrimary: false
        )
        modelContext.insert(newHistory)

        logger.warning("IBAN change detected for vendor")

        // Create critical anomaly
        return DocumentAnomaly(
            documentId: document.id,
            vendorFingerprint: vendorFingerprint,
            type: .bankAccountChanged,
            severity: .critical,
            detectionVersion: Self.detectionVersion,
            summary: "Bank account changed from previously known account",
            contextData: AnomalyContextData(
                previousBankAccount: primaryAccount.map { maskIBAN($0.iban) },
                newBankAccount: maskIBAN(normalizedIBAN),
                additionalNotes: "Verify this change is legitimate before making payment",
                algorithmVersion: Self.detectionVersion,
                confidenceScore: 0.95
            )
        )
    }

    func checkVendorSpoofing(document: FinanceDocument) async throws -> DocumentAnomaly? {
        guard let vendorFingerprint = document.vendorFingerprint,
              !document.title.isEmpty else {
            return nil
        }

        let currentVendorName = document.title
        let currentNIP = document.vendorNIP
        let currentIBAN = document.bankAccountNumber

        // Fetch all known vendor templates
        let templateDescriptor = FetchDescriptor<RecurringTemplate>()
        let existingTemplates = try modelContext.fetch(templateDescriptor)

        // Check each existing vendor for similarity
        for template in existingTemplates {
            // Skip if same vendor (same fingerprint)
            if template.vendorFingerprint == vendorFingerprint {
                continue
            }

            let existingName = template.vendorDisplayName

            // Check for homoglyphs
            let homoglyphResult = stringMatchingService.detectHomoglyphs(
                in: currentVendorName,
                comparing: existingName
            )

            if homoglyphResult.hasHomoglyphs && homoglyphResult.spoofingConfidence > 0.3 {
                // Homoglyphs detected - likely spoofing attempt
                return createSpoofingAnomaly(
                    document: document,
                    existingTemplate: template,
                    reason: "Homoglyphs detected",
                    confidence: homoglyphResult.spoofingConfidence
                )
            }

            // Check Levenshtein distance
            let distance = stringMatchingService.levenshteinDistance(currentVendorName, existingName)
            let threshold = existingName.count >= 10
                ? Self.levenshteinThresholdLong
                : Self.levenshteinThresholdShort

            if distance > 0 && distance <= threshold {
                // Names are very similar but not identical
                // Check if identifiers are different
                let hasDifferentNIP = isDifferent(currentNIP, template.vendorFingerprint)
                let hasDifferentIBAN = isDifferent(currentIBAN, template.iban)

                if hasDifferentNIP || hasDifferentIBAN {
                    // Similar name + different identifiers = spoofing
                    let similarity = stringMatchingService.similarityScore(currentVendorName, existingName)
                    return createSpoofingAnomaly(
                        document: document,
                        existingTemplate: template,
                        reason: "Similar name with different identifiers (edit distance: \(distance))",
                        confidence: similarity
                    )
                }
            }
        }

        return nil
    }

    func checkTimingAnomaly(document: FinanceDocument) async throws -> DocumentAnomaly? {
        guard let vendorFingerprint = document.vendorFingerprint,
              let dueDate = document.dueDate else {
            return nil
        }

        // Fetch or create invoice pattern
        var pattern = try await fetchInvoicePattern(forVendorFingerprint: vendorFingerprint)

        if pattern == nil {
            // Create new pattern
            pattern = VendorInvoicePattern(
                vendorFingerprint: vendorFingerprint,
                currency: document.currency
            )
            modelContext.insert(pattern!)
        }

        guard let invoicePattern = pattern else {
            return nil
        }

        let invoiceDay = Calendar.current.component(.day, from: dueDate)

        // Check if pattern is established (>= 3 invoices)
        if invoicePattern.hasEstablishedPattern {
            // Check if day is within normal window
            if !invoicePattern.isDayWithinNormalWindow(invoiceDay) {
                let expectedDay = invoicePattern.medianDayOfMonth ?? invoiceDay
                let daysDiff = abs(invoiceDay - expectedDay)

                // Only flag if significantly outside window
                if daysDiff > Self.defaultTimingWindowDays {
                    return DocumentAnomaly(
                        documentId: document.id,
                        vendorFingerprint: vendorFingerprint,
                        type: .unusualTimingPattern,
                        severity: .warning,
                        detectionVersion: Self.detectionVersion,
                        summary: "Invoice day is outside normal billing cycle",
                        contextData: AnomalyContextData(
                            expectedDayOfMonth: expectedDay,
                            actualDayOfMonth: invoiceDay,
                            daysDifference: daysDiff,
                            algorithmVersion: Self.detectionVersion,
                            confidenceScore: min(1.0, Double(daysDiff) / 15.0)
                        )
                    )
                }
            }
        }

        // Update pattern with new invoice data
        invoicePattern.updateWithInvoice(
            dayOfMonth: invoiceDay,
            amount: document.amount
        )

        return nil
    }

    func checkAmountAnomaly(document: FinanceDocument) async throws -> DocumentAnomaly? {
        guard let vendorFingerprint = document.vendorFingerprint else {
            return nil
        }

        let currentAmount = document.amount

        // Fetch invoice pattern
        let pattern = try await fetchInvoicePattern(forVendorFingerprint: vendorFingerprint)

        guard let invoicePattern = pattern,
              invoicePattern.hasEstablishedPattern else {
            // No established pattern - can't determine anomaly
            return nil
        }

        // Check if amount change is significant
        guard invoicePattern.isAmountChangeSignificant(newAmount: currentAmount) else {
            return nil
        }

        // Get deviation details
        guard let deviationPercent = invoicePattern.deviationPercentage(for: currentAmount),
              let avgAmount = invoicePattern.averageAmount else {
            return nil
        }

        // Determine if spike up or down
        let isSpike = deviationPercent > 0
        let anomalyType: AnomalyType = isSpike ? .amountSpikeUp : .amountSpikeDrop

        // Determine severity based on deviation
        let severity = invoicePattern.amountAnomalySeverity(for: currentAmount) ?? .info

        // Only create anomaly if deviation is significant
        let absDeviation = abs(deviationPercent)
        if absDeviation < Self.defaultAmountChangeThresholdPercent {
            return nil
        }

        // For small absolute amounts, require larger percentage deviation
        let amountDouble = NSDecimalNumber(decimal: currentAmount).doubleValue
        let avgDouble = NSDecimalNumber(decimal: avgAmount).doubleValue
        let absoluteDiff = abs(amountDouble - avgDouble)

        if absoluteDiff < Self.minExtraFeeAmount {
            return nil
        }

        let directionText = isSpike ? "higher" : "lower"
        let summary = "Amount is \(Int(absDeviation))% \(directionText) than typical"

        return DocumentAnomaly(
            documentId: document.id,
            vendorFingerprint: vendorFingerprint,
            type: anomalyType,
            severity: severity,
            detectionVersion: Self.detectionVersion,
            summary: summary,
            contextData: AnomalyContextData(
                currentAmount: amountDouble,
                expectedAmount: avgDouble,
                historicalMin: invoicePattern.minAmountValue,
                historicalMax: invoicePattern.maxAmountValue,
                historicalStdDev: invoicePattern.amountStdDevValue,
                deviationPercentage: deviationPercent,
                algorithmVersion: Self.detectionVersion,
                confidenceScore: min(1.0, absDeviation / 100.0)
            )
        )
    }

    func checkFirstInvoiceFromVendor(document: FinanceDocument) async throws -> DocumentAnomaly? {
        guard let vendorFingerprint = document.vendorFingerprint else {
            return nil
        }

        // Count existing documents for this vendor (excluding current document)
        let documentCount = try await countDocuments(
            forVendorFingerprint: vendorFingerprint,
            excludingId: document.id
        )

        if documentCount == 0 {
            // This is the first invoice from this vendor
            return DocumentAnomaly(
                documentId: document.id,
                vendorFingerprint: vendorFingerprint,
                type: .unusualFirstInvoiceAmount, // Repurposing for "first invoice" indicator
                severity: .info,
                detectionVersion: Self.detectionVersion,
                summary: "First invoice received from this vendor",
                contextData: AnomalyContextData(
                    additionalNotes: "Verify vendor legitimacy for first-time payments",
                    algorithmVersion: Self.detectionVersion
                )
            )
        }

        return nil
    }

    // MARK: - Anomaly Management

    func fetchUnresolvedAnomalies(forDocumentId documentId: UUID) async throws -> [DocumentAnomaly] {
        let descriptor = FetchDescriptor<DocumentAnomaly>(
            predicate: #Predicate<DocumentAnomaly> {
                $0.documentId == documentId && $0.resolutionRaw == nil
            },
            sortBy: [SortDescriptor(\.detectedAt, order: .reverse)]
        )

        return try modelContext.fetch(descriptor)
    }

    func fetchAnomalies(forVendorFingerprint vendorFingerprint: String) async throws -> [DocumentAnomaly] {
        let descriptor = FetchDescriptor<DocumentAnomaly>(
            predicate: #Predicate<DocumentAnomaly> {
                $0.vendorFingerprint == vendorFingerprint
            },
            sortBy: [SortDescriptor(\.detectedAt, order: .reverse)]
        )

        return try modelContext.fetch(descriptor)
    }

    func acknowledgeAnomaly(
        _ anomaly: DocumentAnomaly,
        resolution: AnomalyResolution,
        notes: String?
    ) async throws {
        anomaly.acknowledge(resolution: resolution, notes: notes)
        try modelContext.save()

        logger.info("Anomaly acknowledged with resolution: \(resolution.rawValue)")
    }

    // MARK: - Private Helpers

    private func fetchBankAccountHistory(
        forVendorFingerprint vendorFingerprint: String
    ) async throws -> [VendorBankAccountHistory] {
        let descriptor = FetchDescriptor<VendorBankAccountHistory>(
            predicate: #Predicate<VendorBankAccountHistory> {
                $0.vendorFingerprint == vendorFingerprint
            },
            sortBy: [SortDescriptor(\.documentCount, order: .reverse)]
        )

        return try modelContext.fetch(descriptor)
    }

    private func fetchInvoicePattern(
        forVendorFingerprint vendorFingerprint: String
    ) async throws -> VendorInvoicePattern? {
        let descriptor = FetchDescriptor<VendorInvoicePattern>(
            predicate: #Predicate<VendorInvoicePattern> {
                $0.vendorFingerprint == vendorFingerprint
            }
        )

        let patterns = try modelContext.fetch(descriptor)
        return patterns.first
    }

    private func countDocuments(
        forVendorFingerprint vendorFingerprint: String,
        excludingId: UUID? = nil
    ) async throws -> Int {
        if let excludeId = excludingId {
            let descriptor = FetchDescriptor<FinanceDocument>(
                predicate: #Predicate<FinanceDocument> {
                    $0.vendorFingerprint == vendorFingerprint && $0.id != excludeId
                }
            )
            return try modelContext.fetchCount(descriptor)
        } else {
            let descriptor = FetchDescriptor<FinanceDocument>(
                predicate: #Predicate<FinanceDocument> {
                    $0.vendorFingerprint == vendorFingerprint
                }
            )
            return try modelContext.fetchCount(descriptor)
        }
    }

    private func refreshPattern(_ pattern: VendorInvoicePattern) async throws {
        // Fetch all documents for this vendor
        // Capture fingerprint into local constant for Sendable predicate closure
        let targetFingerprint = pattern.vendorFingerprint
        let descriptor = FetchDescriptor<FinanceDocument>(
            predicate: #Predicate<FinanceDocument> {
                $0.vendorFingerprint == targetFingerprint
            },
            sortBy: [SortDescriptor(\.dueDate)]
        )

        let documents = try modelContext.fetch(descriptor)

        // Reset pattern and rebuild from documents
        pattern.invoiceCount = 0
        pattern.typicalDaysOfMonth = []
        pattern.medianDayOfMonth = nil
        pattern.averageAmountValue = nil
        pattern.minAmountValue = nil
        pattern.maxAmountValue = nil
        pattern.patternEstablishedAt = nil

        for document in documents {
            if let dueDate = document.dueDate {
                let day = Calendar.current.component(.day, from: dueDate)
                pattern.updateWithInvoice(dayOfMonth: day, amount: document.amount)
            }
        }

        pattern.updatedAt = Date()
    }

    private func createSpoofingAnomaly(
        document: FinanceDocument,
        existingTemplate: RecurringTemplate,
        reason: String,
        confidence: Double
    ) -> DocumentAnomaly {
        return DocumentAnomaly(
            documentId: document.id,
            vendorFingerprint: document.vendorFingerprint,
            type: .vendorImpersonation,
            severity: .critical,
            detectionVersion: Self.detectionVersion,
            summary: "Vendor name is suspiciously similar to known vendor",
            contextData: AnomalyContextData(
                similarVendorFingerprint: existingTemplate.vendorFingerprint,
                similarVendorName: existingTemplate.vendorDisplayName,
                additionalNotes: reason,
                algorithmVersion: Self.detectionVersion,
                confidenceScore: confidence
            )
        )
    }

    private func assessRiskLevel(
        anomalies: [DocumentAnomaly],
        bankAccounts: [VendorBankAccountHistory]
    ) -> VendorRiskLevel {
        // Check for critical anomalies
        let criticalCount = anomalies.filter { $0.severity == .critical && !$0.isResolved }.count
        if criticalCount > 0 {
            return .critical
        }

        // Check for suspicious/fraudulent bank accounts
        let suspiciousAccounts = bankAccounts.filter { $0.verificationStatus.isProblem }
        if !suspiciousAccounts.isEmpty {
            return .high
        }

        // Check for multiple unresolved warnings
        let unresolvedWarnings = anomalies.filter { $0.severity == .warning && !$0.isResolved }.count
        if unresolvedWarnings >= 3 {
            return .high
        } else if unresolvedWarnings >= 1 {
            return .medium
        }

        return .low
    }

    private func generateVendorSummary(
        anomalyCount: Int,
        bankAccountCount: Int,
        hasPattern: Bool,
        riskLevel: VendorRiskLevel
    ) -> String {
        var parts: [String] = []

        if anomalyCount > 0 {
            parts.append("\(anomalyCount) anomal\(anomalyCount == 1 ? "y" : "ies") detected")
        }

        if bankAccountCount > 1 {
            parts.append("\(bankAccountCount) bank accounts on file")
        }

        if hasPattern {
            parts.append("Established billing pattern")
        } else {
            parts.append("No billing pattern established")
        }

        parts.append("Risk level: \(riskLevel.displayName)")

        return parts.joined(separator: ". ") + "."
    }

    /// Masks an IBAN for privacy-safe logging (shows first 4 and last 4 characters)
    private func maskIBAN(_ iban: String) -> String {
        guard iban.count > 8 else { return "****" }
        let prefix = String(iban.prefix(4))
        let suffix = String(iban.suffix(4))
        return "\(prefix)****\(suffix)"
    }

    /// Checks if two optional strings are different (both must be non-nil and non-empty)
    private func isDifferent(_ s1: String?, _ s2: String?) -> Bool {
        guard let str1 = s1, !str1.isEmpty,
              let str2 = s2, !str2.isEmpty else {
            return false // Can't determine if different
        }
        return str1.lowercased() != str2.lowercased()
    }

    /// Privacy-safe logging of detected anomalies
    private func logAnomaliesDetected(_ anomalies: [DocumentAnomaly]) {
        // Log counts by type and severity only
        let typeCounts = Dictionary(grouping: anomalies) { $0.typeRaw }
            .mapValues { $0.count }
        let severityCounts = Dictionary(grouping: anomalies) { $0.severityRaw }
            .mapValues { $0.count }

        logger.info("Anomalies detected: types=\(typeCounts), severities=\(severityCounts)")

        // Crashlytics logging (production only)
        // Note: FirebaseCrashlytics must be imported at file scope.
        // The logToCrashlytics helper handles the actual logging.
        logToCrashlytics(anomalies: anomalies, typeCounts: typeCounts)
    }

    /// Helper for Crashlytics logging to work around conditional import limitations.
    private func logToCrashlytics(anomalies: [DocumentAnomaly], typeCounts: [String: Int]) {
        // Crashlytics is available - log anomaly metrics
        // PRIVACY: Only log counts and types, never amounts or vendor names
        CrashlyticsLogger.logFraudDetection(
            anomalyCount: anomalies.count,
            typeCounts: typeCounts
        )
    }
}
