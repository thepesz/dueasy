import Foundation

// MARK: - Auth State

/// Represents the user's authentication state.
///
/// ## State Transitions
///
/// ```
/// .unknown -> .guest (no credential)
/// .unknown -> .apple (existing Apple credential)
/// .guest -> .apple (user signs in with Apple)
/// .apple -> .guest (user signs out)
/// ```
///
/// ## Design Decision
///
/// AuthState is separate from Firebase's anonymous auth concept.
/// From the user's perspective, there are only two meaningful states:
/// - Not signed in (guest) - includes Firebase anonymous users
/// - Signed in with Apple - linked Apple credential
///
/// Firebase anonymous auth is an implementation detail handled by AuthBootstrapper.
enum AuthState: Equatable, Sendable {
    /// App startup - auth state not yet determined.
    /// Resolves to .guest or .apple once AuthBootstrapper completes.
    case unknown

    /// Not signed in with Apple.
    /// May still have a Firebase anonymous session (implementation detail).
    case guest

    /// Signed in with Apple. User has linked their Apple credential.
    /// - Parameter userId: The Firebase user ID (stable across sessions).
    case apple(userId: String)

    /// Whether the user is signed in with Apple.
    var isSignedIn: Bool {
        if case .apple = self { return true }
        return false
    }

    /// Whether auth state is still being determined.
    var isUnknown: Bool {
        self == .unknown
    }
}

// MARK: - Plan Tier

/// The user's plan tier, combining auth state and subscription status.
///
/// ## Tier Rules
///
/// | Auth State | Subscription | Tier         |
/// |-----------|-------------|-------------|
/// | Guest     | N/A         | guestFree   |
/// | Apple     | None        | appleFree   |
/// | Apple     | Pro         | applePro    |
///
/// ## Cloud Extraction Limits (Backend-Enforced)
///
/// - guestFree: 0 per month (cloud blocked entirely - must sign in)
/// - appleFree: 3 per month (backend-enforced)
/// - applePro: 100 per month (backend-enforced)
///
/// Backend is the single source of truth for usage counts.
/// These limits are informational for UI display only.
enum PlanTier: String, Equatable, Sendable, Codable {
    /// Not signed in. No cloud, no export/import.
    case guestFree

    /// Signed in with Apple, free tier. Limited cloud, export/import available.
    case appleFree

    /// Signed in with Apple, pro subscription. Full cloud, export/import available.
    case applePro

    /// Monthly cloud extraction limit (informational - backend enforces actual limit).
    var cloudLimit: Int {
        switch self {
        case .guestFree: return 0
        case .appleFree: return 3
        case .applePro: return 100
        }
    }

    /// Display name for UI badges and banners.
    var displayName: String {
        switch self {
        case .guestFree: return "Guest"
        case .appleFree: return "Free"
        case .applePro: return "Pro"
        }
    }

    /// Whether this tier has any cloud extraction access.
    var hasCloudAccess: Bool {
        cloudLimit > 0
    }

    /// Whether this tier requires a sign-in to unlock features.
    var isGuest: Bool {
        self == .guestFree
    }

    /// Whether this tier has a paid subscription.
    var isPro: Bool {
        self == .applePro
    }
}

// MARK: - Cloud Quota (Backend-Authoritative)

/// Cloud extraction quota as reported by the backend.
///
/// ## Source of Truth
///
/// The backend (Firebase Functions) is the single source of truth for usage counts.
/// The client does NOT track usage locally. When the client needs quota info,
/// it calls the backend which returns: { used, limit, remaining, resetDate }.
///
/// ## No Client-Side Failsafe
///
/// Previous architecture had a local failsafe counter in UserDefaults.
/// This has been removed. The backend enforces limits server-side.
struct CloudQuota: Equatable, Sendable {
    /// Number of cloud extractions used this period.
    let used: Int

    /// Maximum cloud extractions allowed this period.
    let limit: Int

    /// Remaining cloud extractions this period.
    let remaining: Int

    /// Date when the quota resets (start of next month).
    let resetDate: Date?

    /// Whether the user can use cloud extraction (has remaining quota).
    var canUseCloud: Bool { remaining > 0 }

    /// Whether the monthly limit has been reached.
    var isExhausted: Bool { remaining <= 0 }

    /// Usage as a percentage (0.0 to 1.0).
    var usagePercentage: Double {
        guard limit > 0 else { return 1.0 }
        return min(1.0, Double(used) / Double(limit))
    }

    /// Display string for UI: "2/3 used" or "45/100 used"
    var displayString: String {
        "\(used)/\(limit) used"
    }

    /// Unknown quota (before backend response).
    /// Assumes no quota available until backend confirms.
    static let unknown = CloudQuota(used: 0, limit: 0, remaining: 0, resetDate: nil)

    /// Guest quota (cloud blocked entirely).
    static let guest = CloudQuota(used: 0, limit: 0, remaining: 0, resetDate: nil)

    /// Creates a quota from backend response values.
    static func fromBackend(used: Int, limit: Int, remaining: Int, resetDate: Date?) -> CloudQuota {
        CloudQuota(used: used, limit: limit, remaining: remaining, resetDate: resetDate)
    }
}

// MARK: - Capabilities

/// Derived capabilities based on the user's plan tier.
///
/// ## Design Principle
///
/// Capabilities are computed from PlanTier, never set independently.
/// This ensures a single source of truth: change the tier, and all
/// capability gates automatically update.
///
/// ## Simplified Architecture
///
/// - ALL data stays local (no iCloud sync, no cloud backup)
/// - Export/import requires Sign in with Apple
/// - Cloud analysis requires Sign in with Apple + quota
struct Capabilities: Equatable, Sendable {
    /// Whether cloud extraction is available for this tier.
    /// Note: Even if true, the user may have exhausted their quota.
    let canUseCloud: Bool

    /// Whether data export/import functionality is available.
    /// Requires Sign in with Apple.
    let canExportImport: Bool

    /// Guest capabilities: no cloud, no export.
    static let guest = Capabilities(
        canUseCloud: false,
        canExportImport: false
    )

    /// Signed-in free tier: limited cloud, export available.
    static let appleFree = Capabilities(
        canUseCloud: true,
        canExportImport: true
    )

    /// Signed-in pro tier: full cloud, export available.
    static let applePro = Capabilities(
        canUseCloud: true,
        canExportImport: true
    )
}

// MARK: - Extraction Mode Decision

/// The single decision point for how document extraction should be routed.
///
/// ## Decision Authority
///
/// Only `AccessManager.makeAnalysisDecision(isOnline:)` produces this value.
/// No other code should attempt to compute extraction routing decisions.
///
/// ## Decision Flow
///
/// ```
/// AccessManager.makeAnalysisDecision(isOnline:)
///   -> ExtractionModeDecision
///     -> passed to HybridAnalysisRouter.analyzeDocument(decision:...)
/// ```
///
/// The router simply executes the decision; it does not second-guess it.
enum ExtractionModeDecision: Equatable, Sendable {
    /// Use local OCR and parsing only. Cloud is not attempted.
    /// Includes the reason for local-only routing (for UI messaging).
    case localOnly(reason: LocalOnlyReason)

    /// Cloud extraction is allowed. Includes remaining quota for UI display.
    case cloudAllowed(remaining: Int)
}

/// Reasons why extraction is limited to local-only mode.
enum LocalOnlyReason: String, Equatable, Sendable {
    /// Device is offline. Cloud is unavailable regardless of tier.
    case offline

    /// User is not signed in with Apple. Cloud requires sign-in.
    case notSignedIn

    /// User's monthly cloud quota is exhausted.
    case quotaExhausted

    /// Cloud service is unavailable (backend down, auth failed, etc.).
    case cloudUnavailable

    /// Cloud analysis is disabled in user settings.
    case disabledInSettings
}

// MARK: - App Access State

/// Complete snapshot of the user's access state at a point in time.
///
/// ## Single Source of Truth
///
/// This struct is produced exclusively by `AccessManager` and captures
/// everything the UI and services need to make access decisions:
///
/// - Auth state: Who is the user?
/// - Tier: What plan are they on?
/// - Quota: How much have they used? (from backend)
/// - Capabilities: What can they do?
///
/// ## Thread Safety
///
/// This is a value type (struct). It is safe to pass across isolation boundaries.
/// The `AccessManager` publishes new snapshots on state changes.
struct AppAccessState: Equatable, Sendable {
    /// Current authentication state.
    let authState: AuthState

    /// Current plan tier (derived from auth + subscription).
    let tier: PlanTier

    /// Current cloud quota (from backend, or unknown if not yet fetched).
    let quota: CloudQuota

    /// Derived capabilities for this tier.
    let capabilities: Capabilities

    init(authState: AuthState, tier: PlanTier, quota: CloudQuota) {
        self.authState = authState
        self.tier = tier
        self.quota = quota

        // Derive capabilities from tier - never set independently
        switch tier {
        case .guestFree:
            self.capabilities = .guest
        case .appleFree:
            self.capabilities = .appleFree
        case .applePro:
            self.capabilities = .applePro
        }
    }

    /// Default state used during app startup before auth is determined.
    static let unknown = AppAccessState(
        authState: .unknown,
        tier: .guestFree,
        quota: .unknown
    )
}
