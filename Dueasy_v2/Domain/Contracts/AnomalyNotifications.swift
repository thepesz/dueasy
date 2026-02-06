import Foundation

// MARK: - Anomaly Notification Names

/// NotificationCenter notification names for the fraud detection system.
/// Used to communicate anomaly detection results from the background to the UI layer.
extension Notification.Name {

    /// Posted when anomalies are detected after document finalization.
    /// UserInfo contains:
    /// - "documentId": UUID - The document that was analyzed
    /// - "anomalyCount": Int - Total number of anomalies detected
    /// - "hasCritical": Bool - Whether any critical severity anomalies were found
    /// - "hasWarning": Bool - Whether any warning severity anomalies were found
    /// - "anomalyTypes": [String] - Raw type values of detected anomalies
    static let anomaliesDetected = Notification.Name("com.dueasy.anomaliesDetected")

    /// Posted when an anomaly is resolved by the user.
    /// UserInfo contains:
    /// - "anomalyId": UUID - The anomaly that was resolved
    /// - "documentId": UUID - The associated document
    /// - "resolution": String - The resolution type raw value
    static let anomalyResolved = Notification.Name("com.dueasy.anomalyResolved")
}

// MARK: - Anomaly Notification UserInfo Keys

/// Keys for accessing values in anomaly notification userInfo dictionaries.
enum AnomalyNotificationKey: String {
    case documentId
    case anomalyCount
    case hasCritical
    case hasWarning
    case anomalyTypes
    case anomalyId
    case resolution
}
