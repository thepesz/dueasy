import Foundation
import SwiftData

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

/// Firebase-based subscription management service
@MainActor
final class FirebaseSubscriptionService: SubscriptionServiceProtocol {

    // MARK: - Properties

    private let authService: AuthServiceProtocol

    #if canImport(FirebaseFunctions)
    private let functions: Functions
    #endif

    // MARK: - Initialization

    init(authService: AuthServiceProtocol) {
        self.authService = authService
        #if canImport(FirebaseFunctions)
        self.functions = Functions.functions()
        #endif
    }

    // MARK: - SubscriptionServiceProtocol

    var hasProSubscription: Bool {
        get async {
            let status = await subscriptionStatus
            return status.isActive && status.tier == .pro
        }
    }

    var subscriptionStatus: SubscriptionStatus {
        get async {
            #if canImport(FirebaseFunctions)
            do {
                return try await refreshStatus()
            } catch {
                return .free
            }
            #else
            return .free
            #endif
        }
    }

    var availableProducts: [SubscriptionProduct] {
        get async {
            #if canImport(FirebaseFunctions)
            // This would fetch from StoreKit in production
            return []
            #else
            return []
            #endif
        }
    }

    func refreshStatus() async throws -> SubscriptionStatus {
        #if canImport(FirebaseFunctions)
        guard await authService.isSignedIn else {
            return .free
        }

        let result = try await functions.httpsCallable("getSubscriptionStatus").call()

        guard let data = result.data as? [String: Any],
              let statusStr = data["status"] as? String else {
            throw AppError.parsingFailed("Invalid subscription response")
        }

        switch statusStr {
        case "pro":
            let expiresAt = (data["expiresAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            let willAutoRenew = data["willAutoRenew"] as? Bool ?? false
            let productId = data["productId"] as? String
            let originalPurchaseDate = (data["originalPurchaseDate"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            let isTrialPeriod = data["isTrialPeriod"] as? Bool ?? false
            let isInGracePeriod = data["isInGracePeriod"] as? Bool ?? false

            return SubscriptionStatus(
                isActive: true,
                tier: .pro,
                expirationDate: expiresAt,
                willAutoRenew: willAutoRenew,
                productId: productId,
                originalPurchaseDate: originalPurchaseDate,
                isTrialPeriod: isTrialPeriod,
                isInGracePeriod: isInGracePeriod
            )

        default:
            return .free
        }
        #else
        return .free
        #endif
    }

    func purchase(productId: String) async throws -> SubscriptionStatus {
        #if canImport(FirebaseFunctions)
        guard await authService.isSignedIn else {
            throw AppError.authenticationRequired
        }

        // This would integrate with StoreKit for actual purchases
        // For now, just call the backend to record the intent
        let payload = ["productId": productId]
        _ = try await functions.httpsCallable("initiatePurchase").call(payload)

        // Refresh status after purchase
        return try await refreshStatus()
        #else
        throw AppError.featureUnavailable("Firebase SDK not available")
        #endif
    }

    func restorePurchases() async throws -> SubscriptionStatus {
        #if canImport(FirebaseFunctions)
        guard await authService.isSignedIn else {
            throw AppError.authenticationRequired
        }

        _ = try await functions.httpsCallable("restorePurchases").call()
        return try await refreshStatus()
        #else
        throw AppError.featureUnavailable("Firebase SDK not available")
        #endif
    }

    func statusChanges() -> AsyncStream<SubscriptionStatus> {
        #if canImport(FirebaseFunctions)
        return AsyncStream { continuation in
            let task = Task {
                for await (isSignedIn, _) in authService.authStateChanges() {
                    if isSignedIn {
                        if let status = try? await self.refreshStatus() {
                            continuation.yield(status)
                        }
                    } else {
                        continuation.yield(.free)
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
        #else
        return AsyncStream { continuation in
            continuation.yield(.free)
            continuation.finish()
        }
        #endif
    }
}
