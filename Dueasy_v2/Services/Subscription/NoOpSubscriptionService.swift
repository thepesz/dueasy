import Foundation
import os

/// No-op subscription service for free tier.
/// Always returns free tier status with no Pro features.
///
/// Used when:
/// - User is on free tier
/// - Testing without StoreKit
/// - Offline mode
///
/// In Iteration 2, replace with StoreKitSubscriptionService for IAP.
final class NoOpSubscriptionService: SubscriptionServiceProtocol {

    // MARK: - Properties

    var hasProSubscription: Bool {
        get async { false }
    }

    var subscriptionStatus: SubscriptionStatus {
        get async { .free }
    }

    var availableProducts: [SubscriptionProduct] {
        get async { [] }
    }

    // MARK: - Methods

    func refreshStatus() async throws -> SubscriptionStatus {
        PrivacyLogger.app.debug("NoOpSubscriptionService: refreshStatus called - returning free tier")
        return .free
    }

    func purchase(productId: String) async throws -> SubscriptionStatus {
        PrivacyLogger.app.debug("NoOpSubscriptionService: purchase called - not available")
        throw SubscriptionError.notAvailable
    }

    func restorePurchases() async throws -> SubscriptionStatus {
        PrivacyLogger.app.debug("NoOpSubscriptionService: restorePurchases called - no purchases to restore")
        // In no-op mode, restore always returns free tier
        return .free
    }

    func statusChanges() -> AsyncStream<SubscriptionStatus> {
        // Return a stream that immediately emits free status
        AsyncStream { continuation in
            continuation.yield(.free)
            // Keep stream open but never emit again (no subscription changes in no-op)
        }
    }
}
