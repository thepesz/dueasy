import Foundation
import SwiftData
import Combine
import os.log

/// Service for automatic encrypted backups to iCloud Drive.
///
/// Features:
/// - Automatic encrypted backups to app's iCloud Documents folder
/// - Daily rotation with 7-day retention
/// - Debounced trigger on document changes (5-minute delay)
/// - Daily scheduled backup
/// - Restore from latest or specific dated backup
///
/// Note: This is backup, not sync. CloudKit remains the sync mechanism.
@MainActor
final class iCloudBackupService: ObservableObject {

    // MARK: - Published State

    /// Whether iCloud auto-backup is enabled
    @Published private(set) var isEnabled: Bool = false

    /// Date of last successful backup
    @Published private(set) var lastBackupDate: Date?

    /// Whether a backup is currently in progress
    @Published private(set) var isBackingUp: Bool = false

    /// Last error that occurred during backup
    @Published private(set) var lastError: BackupError?

    /// Available backups in iCloud (newest first)
    @Published private(set) var availableBackups: [BackupInfo] = []

    // MARK: - Dependencies

    private let backupService: BackupServiceProtocol
    private let keychain: KeychainService
    private let authBootstrapper: AuthBootstrapper
    private let logger = Logger(subsystem: "com.dueasy.app", category: "iCloudBackup")

    // MARK: - Internal State

    private var debounceTask: Task<Void, Never>?
    private var dailyBackupTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Debounce delay for document changes (5 minutes)
    private let debounceDelay: TimeInterval = 5 * 60

    /// Maximum number of backups to retain
    private let maxBackupRetention = 7

    /// Keychain key for stored password
    private static let passwordKey = "backup.icloud.password"

    /// Keychain key for enabled state
    private static let enabledKey = "backup.icloud.enabled"

    /// Keychain key for last backup date
    private static let lastBackupKey = "backup.icloud.lastBackup"

    // MARK: - Initialization

    init(
        backupService: BackupServiceProtocol,
        keychain: KeychainService = KeychainService(),
        authBootstrapper: AuthBootstrapper
    ) {
        self.backupService = backupService
        self.keychain = keychain
        self.authBootstrapper = authBootstrapper
        loadState()
    }

    // MARK: - Access Control

    /// Validates that the user has access to backup features.
    /// Requires Sign in with Apple (isAppleLinked).
    /// - Throws: BackupError.requiresAppleSignIn if not authorized
    private func validateBackupAccess() throws {
        guard authBootstrapper.isAppleLinked else {
            logger.warning("Backup operation blocked: user not signed in with Apple")
            throw BackupError.requiresAppleSignIn
        }
    }

    // MARK: - Public Interface

    /// Enables iCloud auto-backup with the given password.
    /// Password is securely stored in Keychain.
    /// - Parameter password: Encryption password (minimum 8 characters)
    /// - Throws: BackupError.requiresAppleSignIn if user not signed in with Apple
    func enableAutoBackup(password: String) async throws {
        logger.info("Enabling iCloud auto-backup")

        // Defense in depth: validate user has backup access
        try validateBackupAccess()

        // Validate iCloud availability
        guard isiCloudAvailable() else {
            throw BackupError.iCloudUnavailable
        }

        // Validate password
        guard BackupEncryption.isPasswordValid(password) else {
            throw BackupError.passwordTooWeak
        }

        // Store password securely
        try keychain.save(key: Self.passwordKey, value: password)
        try keychain.save(key: Self.enabledKey, value: true)

        isEnabled = true

        // Trigger initial backup
        try await triggerBackup()

        // Start daily backup schedule
        scheduleDailyBackup()

        logger.info("iCloud auto-backup enabled successfully")
    }

    /// Disables iCloud auto-backup.
    /// Does not delete existing backups.
    func disableAutoBackup() async throws {
        logger.info("Disabling iCloud auto-backup")

        // Clear stored password
        try? keychain.delete(key: Self.passwordKey)
        try? keychain.delete(key: Self.enabledKey)

        // Cancel scheduled tasks
        debounceTask?.cancel()
        dailyBackupTask?.cancel()

        isEnabled = false
        logger.info("iCloud auto-backup disabled")
    }

    /// Triggers a backup immediately.
    /// Skips if a backup is already in progress.
    /// - Throws: BackupError.requiresAppleSignIn if user not signed in with Apple
    func triggerBackup() async throws {
        // Defense in depth: validate user has backup access
        try validateBackupAccess()

        guard isEnabled else {
            logger.warning("Backup triggered but auto-backup is disabled")
            return
        }

        guard !isBackingUp else {
            logger.info("Backup already in progress, skipping")
            return
        }

        guard let password = try? keychain.load(key: Self.passwordKey) else {
            logger.error("No password stored for backup")
            throw BackupError.decryptionFailed("No password available")
        }

        isBackingUp = true
        lastError = nil

        do {
            // Create backup
            let result = try await backupService.exportBackup(password: password)

            // Copy to iCloud
            try await copyToiCloud(from: result.fileURL)

            // Rotate old backups
            try await rotateBackups()

            // Update state
            lastBackupDate = result.exportedAt
            try? saveLastBackupDate(result.exportedAt)

            // Refresh backup list
            await refreshBackupList()

            logger.info("iCloud backup completed: \(result.documentCount) documents")
        } catch let error as BackupError {
            lastError = error
            logger.error("iCloud backup failed: \(error.localizedDescription)")
            throw error
        } catch {
            let backupError = BackupError.fileWriteFailed(error.localizedDescription)
            lastError = backupError
            logger.error("iCloud backup failed: \(error.localizedDescription)")
            throw backupError
        }

        isBackingUp = false
    }

    /// Restores from the latest iCloud backup.
    /// - Parameter password: Decryption password
    /// - Returns: Import result
    /// - Throws: BackupError.requiresAppleSignIn if user not signed in with Apple
    func restoreLatestBackup(password: String) async throws -> BackupImportResult {
        logger.info("Restoring from latest iCloud backup")

        // Defense in depth: validate user has backup access
        try validateBackupAccess()

        guard let latestBackup = availableBackups.first(where: { $0.isLatest }) ?? availableBackups.first else {
            throw BackupError.fileNotFound
        }

        return try await restoreBackup(id: latestBackup.id, password: password)
    }

    /// Restores from a specific backup.
    /// - Parameters:
    ///   - id: Backup identifier (filename)
    ///   - password: Decryption password
    /// - Returns: Import result
    /// - Throws: BackupError.requiresAppleSignIn if user not signed in with Apple
    func restoreBackup(id: String, password: String) async throws -> BackupImportResult {
        logger.info("Restoring from backup: \(id)")

        // Defense in depth: validate user has backup access
        try validateBackupAccess()

        guard let iCloudURL = getiCloudDocumentsURL() else {
            throw BackupError.iCloudUnavailable
        }

        let backupURL = iCloudURL.appendingPathComponent(id)

        // Ensure file is downloaded
        try await ensureFileDownloaded(at: backupURL)

        // Import using backup service
        return try await backupService.importBackup(from: backupURL, password: password)
    }

    /// Notifies the service that documents have changed.
    /// Triggers a debounced backup after the delay period.
    func notifyDocumentsChanged() {
        guard isEnabled else { return }

        // Cancel existing debounce task
        debounceTask?.cancel()

        // Schedule new debounced backup
        debounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))
                try await triggerBackup()
            } catch is CancellationError {
                // Task was cancelled, ignore
            } catch {
                logger.error("Debounced backup failed: \(error.localizedDescription)")
            }
        }
    }

    /// Refreshes the list of available backups.
    func refreshBackupList() async {
        availableBackups = await listBackups()
    }

    // MARK: - iCloud Helpers

    /// Returns the iCloud Documents URL for the app.
    private func getiCloudDocumentsURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    /// Checks if iCloud is available.
    private func isiCloudAvailable() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Copies a backup file to iCloud.
    private func copyToiCloud(from sourceURL: URL) async throws {
        guard let iCloudURL = getiCloudDocumentsURL() else {
            throw BackupError.iCloudUnavailable
        }

        // Ensure Documents folder exists
        try FileManager.default.createDirectory(
            at: iCloudURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Create filename with date for rotation
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        let latestFilename = "latest.dueasy"
        let datedFilename = "backup-\(dateString).dueasy"

        let latestURL = iCloudURL.appendingPathComponent(latestFilename)
        let datedURL = iCloudURL.appendingPathComponent(datedFilename)

        // Copy to both locations
        try FileManager.default.copyItem(at: sourceURL, to: datedURL)
        logger.info("Copied backup to iCloud: \(datedFilename)")

        // Remove existing latest if present
        try? FileManager.default.removeItem(at: latestURL)

        // Copy to latest
        try FileManager.default.copyItem(at: sourceURL, to: latestURL)
        logger.info("Updated latest.dueasy")

        // Clean up temp file
        try? FileManager.default.removeItem(at: sourceURL)
    }

    /// Rotates backups to keep only the most recent ones.
    private func rotateBackups() async throws {
        guard let iCloudURL = getiCloudDocumentsURL() else { return }

        let fileManager = FileManager.default

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: iCloudURL,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            // Filter to dated backup files (not latest.dueasy)
            let datedBackups = contents.filter {
                $0.lastPathComponent.hasPrefix("backup-") &&
                $0.pathExtension == "dueasy"
            }

            // Sort by date (newest first)
            let sortedBackups = datedBackups.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }

            // Delete old backups beyond retention limit
            if sortedBackups.count > maxBackupRetention {
                let toDelete = sortedBackups.dropFirst(maxBackupRetention)
                for url in toDelete {
                    try? fileManager.removeItem(at: url)
                    logger.info("Deleted old backup: \(url.lastPathComponent)")
                }
            }
        } catch {
            logger.warning("Failed to rotate backups: \(error.localizedDescription)")
            // Non-fatal, continue
        }
    }

    /// Lists available backups in iCloud.
    private func listBackups() async -> [BackupInfo] {
        guard let iCloudURL = getiCloudDocumentsURL() else { return [] }

        let fileManager = FileManager.default

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: iCloudURL,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .ubiquitousItemDownloadingStatusKey],
                options: [.skipsHiddenFiles]
            )

            let backupFiles = contents.filter { $0.pathExtension == "dueasy" }

            var backupInfos: [BackupInfo] = []
            for url in backupFiles {
                let resources = try url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let date = resources.creationDate ?? Date.distantPast
                let size = Int64(resources.fileSize ?? 0)
                let isLatest = url.lastPathComponent == "latest.dueasy"

                backupInfos.append(BackupInfo(
                    id: url.lastPathComponent,
                    date: date,
                    documentCount: 0, // Would need to read file to get this
                    fileSize: size,
                    source: .iCloudAutoBackup,
                    isLatest: isLatest
                ))
            }

            return backupInfos.sorted { $0.date > $1.date }
        } catch {
            logger.error("Failed to list iCloud backups: \(error.localizedDescription)")
            return []
        }
    }

    /// Ensures a file is downloaded from iCloud before reading.
    private func ensureFileDownloaded(at url: URL) async throws {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            throw BackupError.fileNotFound
        }

        let resources = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])

        if let status = resources.ubiquitousItemDownloadingStatus,
           status != .current {
            // File needs to be downloaded
            try fileManager.startDownloadingUbiquitousItem(at: url)

            // Wait for download (with timeout)
            let timeout: TimeInterval = 60
            let startTime = Date()

            while true {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                if Date().timeIntervalSince(startTime) > timeout {
                    throw BackupError.iCloudSyncInProgress
                }

                let updatedResources = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if updatedResources.ubiquitousItemDownloadingStatus == .current {
                    break
                }
            }
        }
    }

    // MARK: - Scheduling

    /// Schedules daily backup.
    private func scheduleDailyBackup() {
        dailyBackupTask?.cancel()

        dailyBackupTask = Task {
            while !Task.isCancelled {
                // Calculate time until next scheduled backup (e.g., 3 AM)
                let nextBackupTime = calculateNextBackupTime()
                let delay = nextBackupTime.timeIntervalSinceNow

                if delay > 0 {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        try await triggerBackup()
                    } catch is CancellationError {
                        break
                    } catch {
                        logger.error("Daily backup failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Calculates the next scheduled backup time (3 AM tomorrow).
    private func calculateNextBackupTime() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 3
        components.minute = 0
        components.second = 0

        var nextBackup = calendar.date(from: components) ?? Date()

        // If 3 AM today has passed, schedule for tomorrow
        if nextBackup <= Date() {
            nextBackup = calendar.date(byAdding: .day, value: 1, to: nextBackup) ?? Date()
        }

        return nextBackup
    }

    // MARK: - State Persistence

    private func loadState() {
        isEnabled = (try? keychain.loadBool(key: Self.enabledKey)) ?? false
        lastBackupDate = loadLastBackupDate()

        if isEnabled {
            scheduleDailyBackup()
            Task {
                await refreshBackupList()
            }
        }
    }

    private func loadLastBackupDate() -> Date? {
        guard let dateString = try? keychain.load(key: Self.lastBackupKey) else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }

    private func saveLastBackupDate(_ date: Date) throws {
        let formatter = ISO8601DateFormatter()
        try keychain.save(key: Self.lastBackupKey, value: formatter.string(from: date))
    }
}
