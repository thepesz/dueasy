import Foundation
import os.log

/// Local failsafe counter for cloud analysis attempts.
///
/// ## Purpose
///
/// Client-side enforcement of the free tier monthly limit (3 documents/month).
/// The backend also enforces limits server-side as a secondary check.
///
/// ## How It Works
///
/// - Tracks "attempted cloud analyses this month" in UserDefaults
/// - Before each cloud call, the router checks: if local counter >= freeLimit
///   AND user is NOT a Pro subscriber -> fall back to local with upgrade banner
/// - Counter resets automatically at the start of each month
///
/// ## Subscription-Aware Enforcement
///
/// - **Free/Anonymous users**: Blocked at 3/month (client-side + backend)
/// - **Pro users**: Client-side failsafe is SKIPPED by the router.
///   Backend enforces 100/month for Pro users server-side.
///   The counter still increments for tracking purposes but does not block.
///
/// ## Edge Cases
///
/// - If local counter drifts from backend (e.g., user reinstalls, changes device),
///   the counter resets. This means a reinstall grants a fresh 3 local attempts,
///   but the backend still enforces the true limit server-side.
/// - The counter is intentionally stored in UserDefaults (not Keychain) because
///   it is a non-sensitive, best-effort safety measure.
///
/// ## Thread Safety
///
/// This class is designed to be called from the HybridAnalysisRouter, which
/// runs on a single task at a time. No additional synchronization is required.
protocol CloudAnalysisFailsafeCounterProtocol: Sendable {

    /// Current count of cloud analysis attempts this month.
    var currentMonthCount: Int { get }

    /// The free tier limit used by the failsafe.
    var freeLimit: Int { get }

    /// Whether the failsafe has been tripped (count >= freeLimit).
    /// This uses the free tier limit (3/month).
    /// For Pro users, use `isFailsafeTripped(forLimit:)` with the Pro limit.
    var isFailsafeTripped: Bool { get }

    /// Whether the failsafe has been tripped for a specific limit.
    /// Use this to check against subscription-specific limits:
    /// - Free tier: 3/month (use `freeLimit`)
    /// - Pro tier: 100/month (backend enforces, client failsafe skipped)
    ///
    /// - Parameter limit: The monthly limit to check against
    /// - Returns: true if currentMonthCount >= limit
    func isFailsafeTripped(forLimit limit: Int) -> Bool

    /// Records a cloud analysis attempt. Call this before each cloud request.
    func recordAttempt()

    /// Resets the counter for the current month.
    /// Called automatically when the month changes, but can be called manually.
    func resetIfNewMonth()
}

/// Production implementation using UserDefaults.
final class CloudAnalysisFailsafeCounter: CloudAnalysisFailsafeCounterProtocol, @unchecked Sendable {

    // MARK: - Constants

    /// UserDefaults key prefix for the monthly counter.
    /// Full key format: "dueasy.cloudAnalysisCount_YYYY-MM"
    private static let counterKeyPrefix = "dueasy.cloudAnalysisCount_"

    /// UserDefaults key for the last recorded month (for reset detection).
    private static let lastMonthKey = "dueasy.cloudAnalysisLastMonth"

    // MARK: - Properties

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.dueasy.app", category: "CloudFailsafe")

    /// The free tier limit. Matches the backend limit of 3 per month.
    let freeLimit: Int

    // MARK: - Initialization

    init(defaults: UserDefaults = .standard, freeLimit: Int = 3) {
        self.defaults = defaults
        self.freeLimit = freeLimit

        // Ensure month is current on init
        resetIfNewMonth()
    }

    // MARK: - CloudAnalysisFailsafeCounterProtocol

    var currentMonthCount: Int {
        let key = Self.counterKeyPrefix + currentMonthKey()
        return defaults.integer(forKey: key)
    }

    var isFailsafeTripped: Bool {
        return currentMonthCount >= freeLimit
    }

    func isFailsafeTripped(forLimit limit: Int) -> Bool {
        return currentMonthCount >= limit
    }

    func recordAttempt() {
        resetIfNewMonth()

        let key = Self.counterKeyPrefix + currentMonthKey()
        let newCount = defaults.integer(forKey: key) + 1
        defaults.set(newCount, forKey: key)

        PrivacyLogger.cloud.info("Cloud analysis failsafe: count=\(newCount)/\(self.freeLimit) for month \(self.currentMonthKey())")
    }

    func resetIfNewMonth() {
        let month = currentMonthKey()
        let lastMonth = defaults.string(forKey: Self.lastMonthKey)

        if lastMonth != month {
            // Month changed - clean up old key if it exists
            if let oldMonth = lastMonth {
                let oldKey = Self.counterKeyPrefix + oldMonth
                defaults.removeObject(forKey: oldKey)
                logger.info("Cloud failsafe: month changed from \(oldMonth) to \(month), counter reset")
            }

            defaults.set(month, forKey: Self.lastMonthKey)
        }
    }

    // MARK: - Private

    /// Returns the current month key in "YYYY-MM" format.
    private func currentMonthKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
