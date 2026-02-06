import Foundation
import Observation
import os.log

/// Single source of truth for app access state.
///
/// ## Architecture Role
///
/// `AccessManager` is the **single decision point** for all access-related questions:
/// - Can the user use cloud extraction? -> `makeAnalysisDecision(isOnline:)`
/// - Can the user export/import? -> `currentState.capabilities.canExportImport`
/// - What tier is the user on? -> `currentState.tier`
/// - What is the cloud quota? -> `currentState.quota`
///
/// ## Simplified Local-First Architecture
///
/// - ALL data stays local (no iCloud sync, no cloud backup)
/// - Backend is the single source of truth for cloud quota
/// - No client-side usage tracking (UsageTracker removed)
/// - Export/import requires Sign in with Apple
/// - Cloud analysis requires Sign in with Apple + backend quota
///
/// ## State Updates
///
/// AccessManager observes:
/// 1. `AuthBootstrapper` - for auth state changes (guest <-> apple)
/// 2. `SubscriptionServiceProtocol` - for subscription changes (free <-> pro)
/// 3. Backend quota responses - for cloud usage counts
///
/// When any input changes, `currentState` is recomputed and published.
///
/// ## Thread Safety
///
/// MainActor-isolated. All state mutations happen on the main thread.
@MainActor
@Observable
final class AccessManager {

    // MARK: - Published State

    /// Current app access state snapshot.
    /// Updated whenever auth, subscription, or quota changes.
    private(set) var currentState: AppAccessState = .unknown

    // MARK: - Dependencies

    private let authBootstrapper: AuthBootstrapper
    private let subscriptionService: SubscriptionServiceProtocol
    private let networkMonitor: NetworkMonitorProtocol
    private let settingsManager: SettingsManager
    private let logger = Logger(subsystem: "com.dueasy.app", category: "AccessManager")

    // MARK: - Internal State

    /// Cached subscription tier from last subscription check.
    private var cachedSubscriptionTier: SubscriptionTier = .free

    /// Latest cloud quota from backend.
    /// Updated when backend responds with quota info (after cloud analysis or explicit fetch).
    private var latestCloudQuota: CloudQuota = .unknown

    /// Task for subscription observation (retained to prevent cancellation).
    /// Using nonisolated(unsafe) to allow access from deinit.
    nonisolated(unsafe) private var subscriptionObservationTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        authBootstrapper: AuthBootstrapper,
        subscriptionService: SubscriptionServiceProtocol,
        networkMonitor: NetworkMonitorProtocol,
        settingsManager: SettingsManager
    ) {
        self.authBootstrapper = authBootstrapper
        self.subscriptionService = subscriptionService
        self.networkMonitor = networkMonitor
        self.settingsManager = settingsManager

        // Compute initial state
        recomputeState()

        // Start observing subscription changes
        startSubscriptionObservation()

        logger.info("AccessManager initialized with tier: \(self.currentState.tier.displayName)")
    }

    deinit {
        subscriptionObservationTask?.cancel()
    }

    // MARK: - State Recomputation

    /// Recomputes the full access state from current inputs.
    /// Called whenever any input (auth, subscription, quota) changes.
    func recomputeState() {
        let authState = deriveAuthState()
        let tier = deriveTier(authState: authState)
        let quota = deriveQuota(tier: tier)

        let newState = AppAccessState(
            authState: authState,
            tier: tier,
            quota: quota
        )

        if currentState != newState {
            let oldTier = currentState.tier
            currentState = newState

            if oldTier != newState.tier {
                logger.info("Access state changed: \(oldTier.displayName) -> \(newState.tier.displayName)")
            }
        }
    }

    // MARK: - Analysis Decision

    /// Makes the extraction routing decision.
    ///
    /// This is the **single decision point** for extraction routing.
    /// The result is passed directly to `HybridAnalysisRouter.analyzeDocument(decision:...)`.
    ///
    /// ## Decision Matrix
    ///
    /// | Condition                          | Decision                          |
    /// |-----------------------------------|-----------------------------------|
    /// | Cloud disabled in settings        | .localOnly(.disabledInSettings)   |
    /// | Offline                           | .localOnly(.offline)              |
    /// | Guest (not signed in)             | .localOnly(.notSignedIn)          |
    /// | Signed in, quota exhausted        | .localOnly(.quotaExhausted)       |
    /// | Signed in, quota remaining        | .cloudAllowed(remaining)          |
    ///
    /// ## Important: No Paywall Blocking
    ///
    /// The decision never blocks the user. Even when quota is exhausted,
    /// local extraction proceeds. The UI can show an upgrade banner based
    /// on the `.localOnly(.quotaExhausted)` reason.
    ///
    /// - Parameter isOnline: Current network connectivity status.
    ///   Defaults to the network monitor's current state.
    /// - Returns: Extraction routing decision for the router.
    func makeAnalysisDecision(isOnline: Bool? = nil) -> ExtractionModeDecision {
        // Refresh state before making decision
        recomputeState()

        let online = isOnline ?? networkMonitor.isOnline
        let state = currentState

        // Rule 1: Cloud disabled in settings
        if !settingsManager.cloudAnalysisEnabled {
            return .localOnly(reason: .disabledInSettings)
        }

        // Rule 2: Offline -> local only
        if !online {
            return .localOnly(reason: .offline)
        }

        // Rule 3: Guest -> local only (no cloud access)
        if state.tier.isGuest {
            return .localOnly(reason: .notSignedIn)
        }

        // Rule 4: Signed in but quota exhausted (backend-authoritative)
        if state.quota.isExhausted && state.quota != .unknown {
            return .localOnly(reason: .quotaExhausted)
        }

        // Rule 5: Signed in with remaining quota -> cloud allowed
        // If quota is unknown (not yet fetched), allow cloud - backend will enforce
        return .cloudAllowed(remaining: state.quota.remaining)
    }

    // MARK: - Backend Quota Updates

    /// Updates cloud quota from backend response.
    /// Call when backend reports quota (e.g., after cloud extraction response).
    /// - Parameter quota: The backend-reported cloud quota.
    func updateQuotaFromBackend(_ quota: CloudQuota) {
        latestCloudQuota = quota
        recomputeState()
        logger.info("Quota updated from backend: \(quota.used)/\(quota.limit) used, \(quota.remaining) remaining")
    }

    // MARK: - Convenience Accessors

    /// Current plan tier (shorthand for `currentState.tier`).
    var tier: PlanTier { currentState.tier }

    /// Current capabilities (shorthand for `currentState.capabilities`).
    var capabilities: Capabilities { currentState.capabilities }

    /// Current cloud quota (shorthand for `currentState.quota`).
    var quota: CloudQuota { currentState.quota }

    /// Whether the user can use cloud extraction right now.
    /// Combines capability check with quota check.
    var canUseCloudNow: Bool {
        currentState.capabilities.canUseCloud && !currentState.quota.isExhausted
    }

    /// Whether the user is signed in with Apple.
    var isSignedIn: Bool {
        currentState.authState.isSignedIn
    }

    // MARK: - Private Helpers

    /// Derives AuthState from AuthBootstrapper's current state.
    private func deriveAuthState() -> AuthState {
        if !authBootstrapper.hasBootstrapped {
            return .unknown
        }

        if authBootstrapper.isAppleLinked, let userId = authBootstrapper.currentUserId {
            return .apple(userId: userId)
        }

        return .guest
    }

    /// Derives PlanTier from AuthState and subscription status.
    private func deriveTier(authState: AuthState) -> PlanTier {
        switch authState {
        case .unknown, .guest:
            return .guestFree

        case .apple:
            return cachedSubscriptionTier == .pro ? .applePro : .appleFree
        }
    }

    /// Derives quota for the given tier.
    /// Guest gets zero quota. Signed-in users get the latest backend quota,
    /// or an optimistic default if backend hasn't been contacted yet.
    private func deriveQuota(tier: PlanTier) -> CloudQuota {
        switch tier {
        case .guestFree:
            return .guest

        case .appleFree, .applePro:
            // If we have backend quota, use it
            if latestCloudQuota != .unknown {
                return latestCloudQuota
            }
            // Not yet fetched from backend - use optimistic default
            // (allows first cloud attempt; backend will enforce actual limit)
            return CloudQuota(
                used: 0,
                limit: tier.cloudLimit,
                remaining: tier.cloudLimit,
                resetDate: nil
            )
        }
    }

    /// Starts observing subscription status changes.
    private func startSubscriptionObservation() {
        subscriptionObservationTask = Task { [weak self] in
            guard let self else { return }

            // Initial subscription check
            let initialStatus = await self.subscriptionService.subscriptionStatus
            await MainActor.run {
                self.cachedSubscriptionTier = initialStatus.tier
                self.recomputeState()
                self.logger.info("Initial subscription tier: \(initialStatus.tier.displayName)")
            }

            // Listen for ongoing status changes
            for await status in self.subscriptionService.statusChanges() {
                await MainActor.run {
                    if self.cachedSubscriptionTier != status.tier {
                        self.cachedSubscriptionTier = status.tier
                        self.recomputeState()
                        self.logger.info("Subscription changed to: \(status.tier.displayName)")
                    }
                }
            }
        }
    }
}

// MARK: - Auth State Change Handling

extension AccessManager {

    /// Call when auth state changes (sign-in, sign-out, bootstrap complete).
    /// Triggers a full state recomputation.
    func handleAuthStateChange() {
        logger.info("Auth state change detected, recomputing access state")

        // Reset quota when auth changes (new user = new quota)
        latestCloudQuota = .unknown

        recomputeState()
    }
}
