import Foundation
import SwiftData
import Observation
import Combine
import os.log

/// ViewModel for anomaly-related views.
/// Handles loading anomalies, resolution actions, and vendor history analysis.
/// Follows MVVM pattern with protocol-based service injection.
@Observable
@MainActor
final class AnomalyViewModel {

    // MARK: - State

    /// Anomalies for the current document
    private(set) var documentAnomalies: [DocumentAnomaly] = []

    /// Vendor history analysis result (populated when viewing vendor history)
    private(set) var vendorHistory: VendorHistoryAnalysisResult?

    /// Whether data is currently loading
    private(set) var isLoading = false

    /// Error state
    private(set) var error: AppError?

    /// Whether resolution is in progress
    private(set) var isResolving = false

    // MARK: - Computed Properties

    /// Anomalies grouped by severity (critical first, then warning, then info)
    var anomaliesBySeverity: [(severity: AnomalySeverity, anomalies: [DocumentAnomaly])] {
        let grouped = Dictionary(grouping: documentAnomalies) { $0.severity }
        return [AnomalySeverity.critical, .warning, .info].compactMap { severity in
            guard let anomalies = grouped[severity], !anomalies.isEmpty else { return nil }
            return (severity: severity, anomalies: anomalies)
        }
    }

    /// Count of unresolved critical anomalies
    var unresolvedCriticalCount: Int {
        documentAnomalies.filter { $0.severity == .critical && !$0.isResolved }.count
    }

    /// Count of unresolved warning anomalies
    var unresolvedWarningCount: Int {
        documentAnomalies.filter { $0.severity == .warning && !$0.isResolved }.count
    }

    /// Count of unresolved info anomalies
    var unresolvedInfoCount: Int {
        documentAnomalies.filter { $0.severity == .info && !$0.isResolved }.count
    }

    /// Total unresolved anomaly count
    var totalUnresolvedCount: Int {
        documentAnomalies.filter { !$0.isResolved }.count
    }

    /// Whether there are any critical or warning anomalies requiring attention
    var hasUrgentAnomalies: Bool {
        unresolvedCriticalCount > 0 || unresolvedWarningCount > 0
    }

    /// Highest severity level among unresolved anomalies
    var highestUnresolvedSeverity: AnomalySeverity? {
        if unresolvedCriticalCount > 0 { return .critical }
        if unresolvedWarningCount > 0 { return .warning }
        if unresolvedInfoCount > 0 { return .info }
        return nil
    }

    // MARK: - Dependencies

    private let fraudDetectionService: FraudDetectionServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "AnomalyViewModel")
    private var notificationCancellable: AnyCancellable?

    // MARK: - Initialization

    init(fraudDetectionService: FraudDetectionServiceProtocol) {
        self.fraudDetectionService = fraudDetectionService

        // Listen for anomaly detection notifications
        setupNotificationObserver()
    }

    // MARK: - Notification Handling

    private func setupNotificationObserver() {
        notificationCancellable = NotificationCenter.default
            .publisher(for: .anomaliesDetected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.handleAnomalyNotification(notification)
            }
    }

    private func handleAnomalyNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let documentId = userInfo[AnomalyNotificationKey.documentId.rawValue] as? UUID else {
            return
        }

        // Reload anomalies for this document
        Task {
            await loadAnomalies(forDocumentId: documentId)
        }
    }

    // MARK: - Loading Methods

    /// Loads all unresolved anomalies for a document.
    /// - Parameter documentId: The document ID to load anomalies for
    func loadAnomalies(forDocumentId documentId: UUID) async {
        isLoading = true
        error = nil

        do {
            documentAnomalies = try await fraudDetectionService.fetchUnresolvedAnomalies(forDocumentId: documentId)

            // PRIVACY: Log only counts, not document details
            logger.info("Loaded \(self.documentAnomalies.count) anomalies for document")

            isLoading = false
        } catch {
            logger.error("Failed to load anomalies: \(error.localizedDescription)")
            self.error = .repositoryFetchFailed(error.localizedDescription)
            isLoading = false
        }
    }

    /// Loads vendor history analysis.
    /// - Parameter vendorFingerprint: The vendor fingerprint to analyze
    func loadVendorHistory(vendorFingerprint: String) async {
        isLoading = true
        error = nil

        do {
            vendorHistory = try await fraudDetectionService.analyzeVendorHistory(vendorFingerprint: vendorFingerprint)

            // PRIVACY: Log only counts, not vendor details
            logger.info("Loaded vendor history: \(self.vendorHistory?.anomalies.count ?? 0) anomalies, \(self.vendorHistory?.bankAccounts.count ?? 0) bank accounts")

            isLoading = false
        } catch {
            logger.error("Failed to load vendor history: \(error.localizedDescription)")
            self.error = .repositoryFetchFailed(error.localizedDescription)
            isLoading = false
        }
    }

    // MARK: - Resolution Actions

    /// Dismisses an anomaly (user reviewed and doesn't consider it a concern).
    /// - Parameter anomaly: The anomaly to dismiss
    func dismissAnomaly(_ anomaly: DocumentAnomaly) async {
        await resolveAnomaly(anomaly, resolution: .dismissed, notes: nil)
    }

    /// Confirms an anomaly as safe (e.g., verified bank account change is legitimate).
    /// - Parameters:
    ///   - anomaly: The anomaly to confirm as safe
    ///   - notes: Optional notes explaining why it's safe
    func confirmSafe(_ anomaly: DocumentAnomaly, notes: String? = nil) async {
        await resolveAnomaly(anomaly, resolution: .confirmedSafe, notes: notes)
    }

    /// Confirms an anomaly as fraud (user has verified this is fraudulent).
    /// - Parameters:
    ///   - anomaly: The anomaly to confirm as fraud
    ///   - notes: Optional notes about the fraud
    func confirmFraud(_ anomaly: DocumentAnomaly, notes: String? = nil) async {
        await resolveAnomaly(anomaly, resolution: .confirmedFraud, notes: notes)
    }

    /// Resolves an anomaly with the specified resolution type.
    /// - Parameters:
    ///   - anomaly: The anomaly to resolve
    ///   - resolution: The resolution type
    ///   - notes: Optional notes
    private func resolveAnomaly(_ anomaly: DocumentAnomaly, resolution: AnomalyResolution, notes: String?) async {
        isResolving = true
        error = nil

        do {
            try await fraudDetectionService.acknowledgeAnomaly(anomaly, resolution: resolution, notes: notes)

            // Post notification that anomaly was resolved
            NotificationCenter.default.post(
                name: .anomalyResolved,
                object: nil,
                userInfo: [
                    AnomalyNotificationKey.anomalyId.rawValue: anomaly.id,
                    AnomalyNotificationKey.documentId.rawValue: anomaly.documentId,
                    AnomalyNotificationKey.resolution.rawValue: resolution.rawValue
                ]
            )

            // Remove from local list (or mark as resolved)
            if let index = documentAnomalies.firstIndex(where: { $0.id == anomaly.id }) {
                documentAnomalies.remove(at: index)
            }

            logger.info("Anomaly resolved with: \(resolution.rawValue)")
            isResolving = false
        } catch {
            logger.error("Failed to resolve anomaly: \(error.localizedDescription)")
            self.error = .unknown(error.localizedDescription)
            isResolving = false
        }
    }

    // MARK: - Error Handling

    /// Clears the current error state.
    func clearError() {
        error = nil
    }
}

// MARK: - Factory Extension for AppEnvironment

extension AppEnvironment {

    /// Creates an AnomalyViewModel with injected dependencies.
    func makeAnomalyViewModel() -> AnomalyViewModel {
        AnomalyViewModel(fraudDetectionService: fraudDetectionService)
    }
}
