import Foundation
import Network
import Combine
import os.log

// MARK: - NetworkMonitorProtocol

/// Protocol for network connectivity monitoring.
/// Allows swapping implementations for testing and different platforms.
protocol NetworkMonitorProtocol: Sendable {
    /// Whether the device currently has network connectivity.
    /// This is a snapshot of the current state.
    var isOnline: Bool { get }

    /// Publisher that emits network connectivity changes.
    /// Emits `true` when network becomes available, `false` when lost.
    var statusPublisher: AnyPublisher<Bool, Never> { get }

    /// Start monitoring network changes.
    /// Call this once when the app launches.
    func startMonitoring()

    /// Stop monitoring network changes.
    /// Call this when monitoring is no longer needed.
    func stopMonitoring()
}

// MARK: - NetworkMonitor Implementation

/// Production network monitor using NWPathMonitor.
/// Provides real-time network connectivity status for the app.
///
/// ## Thread Safety
/// NWPathMonitor callbacks are dispatched on a background queue.
/// Status updates are marshalled to MainActor for UI safety.
///
/// ## Usage
/// ```swift
/// let monitor = NetworkMonitor()
/// monitor.startMonitoring()
///
/// // Check current status
/// if monitor.isOnline {
///     // Make network request
/// }
///
/// // React to changes
/// monitor.statusPublisher
///     .sink { isOnline in
///         // Update UI
///     }
/// ```
@MainActor
final class NetworkMonitor: ObservableObject, NetworkMonitorProtocol {

    // MARK: - Published State

    /// Current network connectivity status.
    /// Published to allow SwiftUI views to react to changes.
    @Published private(set) var isOnline: Bool = true

    // MARK: - NetworkMonitorProtocol

    nonisolated var statusPublisher: AnyPublisher<Bool, Never> {
        // Access MainActor-isolated property from nonisolated context
        // by creating a publisher that will emit on main
        return MainActor.assumeIsolated {
            $isOnline.eraseToAnyPublisher()
        }
    }

    // MARK: - Private Properties

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.dueasy.networkmonitor", qos: .utility)
    private let logger = Logger(subsystem: "com.dueasy.app", category: "NetworkMonitor")
    private var isMonitoring = false

    // MARK: - Initialization

    init() {
        // Initial state assumes online until proven otherwise
        // This prevents blocking the first request while waiting for monitor
    }

    // MARK: - Public Methods

    func startMonitoring() {
        guard !isMonitoring else {
            logger.debug("Network monitoring already active")
            return
        }

        isMonitoring = true
        logger.info("Starting network monitoring")

        monitor.pathUpdateHandler = { [weak self] path in
            let newStatus = path.status == .satisfied

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Only log and update if status changed
                if self.isOnline != newStatus {
                    self.logger.info("Network status changed: \(newStatus ? "online" : "offline")")
                    self.isOnline = newStatus
                }
            }
        }

        monitor.start(queue: monitorQueue)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        logger.info("Stopping network monitoring")
        monitor.cancel()
        isMonitoring = false
    }

    deinit {
        // Note: deinit cannot be async, so we cancel synchronously
        // The monitor is already thread-safe
        monitor.cancel()
    }
}

// MARK: - Sendable Conformance

extension NetworkMonitor: @unchecked Sendable {
    // NetworkMonitor is MainActor-isolated, making it safe to send across actors
    // NWPathMonitor is internally thread-safe
}

// MARK: - Mock Implementation for Testing

/// Mock network monitor for unit testing.
/// Allows tests to simulate online/offline states.
final class MockNetworkMonitor: NetworkMonitorProtocol, @unchecked Sendable {

    private let _isOnline: CurrentValueSubject<Bool, Never>
    private var _statusPublisher: AnyPublisher<Bool, Never>

    var isOnline: Bool {
        _isOnline.value
    }

    var statusPublisher: AnyPublisher<Bool, Never> {
        _statusPublisher
    }

    init(isOnline: Bool = true) {
        _isOnline = CurrentValueSubject<Bool, Never>(isOnline)
        _statusPublisher = _isOnline.eraseToAnyPublisher()
    }

    func startMonitoring() {
        // No-op for mock
    }

    func stopMonitoring() {
        // No-op for mock
    }

    /// Simulate network status change for testing
    func setOnline(_ online: Bool) {
        _isOnline.send(online)
    }
}
