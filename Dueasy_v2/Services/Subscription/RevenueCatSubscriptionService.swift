import Foundation
import Combine
import os

#if canImport(RevenueCat)
import RevenueCat
#endif

/// Production subscription service using RevenueCat SDK.
///
/// ## Features
///
/// - Entitlement checking for Pro features
/// - In-app purchase handling via RevenueCat
/// - Restore purchases support
/// - Real-time subscription status updates
///
/// ## Configuration
///
/// Before using this service, ensure RevenueCat is configured:
/// 1. Replace API key in `RevenueCatConfiguration.swift`
/// 2. Configure products in App Store Connect
/// 3. Link products to "pro" entitlement in RevenueCat dashboard
///
/// ## Thread Safety
///
/// This service is marked @MainActor for SwiftUI compatibility.
/// All RevenueCat SDK calls are async and thread-safe.
@MainActor
final class RevenueCatSubscriptionService: SubscriptionServiceProtocol {

    // MARK: - Properties

    #if canImport(RevenueCat)
    private var customerInfoCancellable: AnyCancellable?
    private var lastCustomerInfo: CustomerInfo?
    #endif

    private let logger = Logger(subsystem: "com.dueasy.app", category: "RevenueCatSubscription")

    /// Current cached subscription status
    private var cachedStatus: SubscriptionStatus = .free

    /// Status update continuation for async stream
    private var statusContinuation: AsyncStream<SubscriptionStatus>.Continuation?

    // MARK: - Initialization

    init() {
        #if canImport(RevenueCat)
        // Listen for customer info updates
        setupCustomerInfoListener()
        #endif
    }

    deinit {
        statusContinuation?.finish()
    }

    // MARK: - Configuration

    /// Configure RevenueCat SDK. Call this once at app startup.
    /// - Parameter apiKey: RevenueCat public API key
    static func configure(apiKey: String? = nil) {
        #if canImport(RevenueCat)
        let key = apiKey ?? RevenueCatConfiguration.apiKey

        // Validate configuration
        RevenueCatConfiguration.validateConfiguration()

        guard RevenueCatConfiguration.isConfigured || apiKey != nil else {
            PrivacyLogger.app.warning("RevenueCat not configured - using placeholder API key")
            return
        }

        // Configure logging level
        if RevenueCatConfiguration.debugLoggingEnabled {
            Purchases.logLevel = .debug
        } else {
            Purchases.logLevel = .info
        }

        // Configure RevenueCat
        Purchases.configure(withAPIKey: key)

        PrivacyLogger.app.info("RevenueCat configured successfully")
        #else
        PrivacyLogger.app.warning("RevenueCat SDK not available - subscriptions disabled")
        #endif
    }

    // MARK: - SubscriptionServiceProtocol

    var hasProSubscription: Bool {
        get async {
            #if canImport(RevenueCat)
            do {
                let customerInfo = try await Purchases.shared.customerInfo()
                return customerInfo.entitlements[RevenueCatConfiguration.proEntitlementID]?.isActive == true
            } catch {
                logger.error("Failed to check Pro subscription: \(error.localizedDescription)")
                return false
            }
            #else
            return false
            #endif
        }
    }

    var subscriptionStatus: SubscriptionStatus {
        get async {
            #if canImport(RevenueCat)
            do {
                let customerInfo = try await Purchases.shared.customerInfo()
                return mapToSubscriptionStatus(customerInfo)
            } catch {
                logger.error("Failed to get subscription status: \(error.localizedDescription)")
                return .free
            }
            #else
            return .free
            #endif
        }
    }

    var availableProducts: [SubscriptionProduct] {
        get async {
            #if canImport(RevenueCat)
            do {
                let offerings = try await Purchases.shared.offerings()
                guard let current = offerings.current else {
                    logger.info("No current offering available")
                    return []
                }

                return current.availablePackages.compactMap { package in
                    mapToSubscriptionProduct(package)
                }
            } catch {
                logger.error("Failed to fetch offerings: \(error.localizedDescription)")
                return []
            }
            #else
            return []
            #endif
        }
    }

    func refreshStatus() async throws -> SubscriptionStatus {
        #if canImport(RevenueCat)
        do {
            // Force refresh from RevenueCat servers
            let customerInfo = try await Purchases.shared.customerInfo()
            let status = mapToSubscriptionStatus(customerInfo)
            cachedStatus = status

            // Notify listeners
            statusContinuation?.yield(status)

            logger.info("Subscription status refreshed: tier=\(status.tier.rawValue), active=\(status.isActive)")
            return status
        } catch {
            logger.error("Failed to refresh subscription status: \(error.localizedDescription)")
            throw SubscriptionError.networkError(error)
        }
        #else
        return .free
        #endif
    }

    func purchase(productId: String) async throws -> SubscriptionStatus {
        #if canImport(RevenueCat)
        do {
            // Find the package for this product
            let offerings = try await Purchases.shared.offerings()
            guard let current = offerings.current else {
                throw SubscriptionError.productNotFound
            }

            // Find matching package
            guard let package = current.availablePackages.first(where: { $0.storeProduct.productIdentifier == productId }) else {
                throw SubscriptionError.productNotFound
            }

            // Attempt purchase
            let (_, customerInfo, userCancelled) = try await Purchases.shared.purchase(package: package)

            if userCancelled {
                throw SubscriptionError.purchaseCancelled
            }

            // Update cached status
            let status = mapToSubscriptionStatus(customerInfo)
            cachedStatus = status
            statusContinuation?.yield(status)

            logger.info("Purchase completed: productId=\(productId), tier=\(status.tier.rawValue)")
            return status

        } catch let error as SubscriptionError {
            throw error
        } catch let error as NSError {
            // Handle RevenueCat specific errors
            if let errorCode = RevenueCat.ErrorCode(rawValue: error.code) {
                switch errorCode {
                case .purchaseCancelledError:
                    throw SubscriptionError.purchaseCancelled
                case .purchaseNotAllowedError:
                    throw SubscriptionError.notAvailable
                case .purchaseInvalidError:
                    throw SubscriptionError.purchaseFailed("Invalid purchase")
                case .productAlreadyPurchasedError:
                    // Already purchased - refresh status
                    return try await refreshStatus()
                case .networkError:
                    throw SubscriptionError.networkError(error)
                case .receiptAlreadyInUseError:
                    throw SubscriptionError.purchaseFailed("Receipt already in use on another account")
                default:
                    throw SubscriptionError.storeKitError(error.localizedDescription)
                }
            }
            throw SubscriptionError.unknown(error.localizedDescription)
        }
        #else
        throw SubscriptionError.notAvailable
        #endif
    }

    func restorePurchases() async throws -> SubscriptionStatus {
        #if canImport(RevenueCat)
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            let status = mapToSubscriptionStatus(customerInfo)
            cachedStatus = status
            statusContinuation?.yield(status)

            logger.info("Purchases restored: tier=\(status.tier.rawValue), active=\(status.isActive)")
            return status
        } catch {
            logger.error("Failed to restore purchases: \(error.localizedDescription)")
            throw SubscriptionError.networkError(error)
        }
        #else
        return .free
        #endif
    }

    func statusChanges() -> AsyncStream<SubscriptionStatus> {
        AsyncStream { continuation in
            self.statusContinuation = continuation

            // Emit current cached status immediately
            continuation.yield(self.cachedStatus)

            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.statusContinuation = nil
                }
            }
        }
    }

    // MARK: - Private Helpers

    #if canImport(RevenueCat)
    private func setupCustomerInfoListener() {
        // RevenueCat 4.x uses Combine publisher for customer info updates
        customerInfoCancellable = Purchases.shared.customerInfoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] customerInfo in
                guard let self = self else { return }
                let status = self.mapToSubscriptionStatus(customerInfo)
                self.cachedStatus = status
                self.statusContinuation?.yield(status)
                self.logger.info("Customer info updated: tier=\(status.tier.rawValue)")
            }
    }

    private func mapToSubscriptionStatus(_ customerInfo: CustomerInfo) -> SubscriptionStatus {
        // Check for Pro entitlement
        guard let proEntitlement = customerInfo.entitlements[RevenueCatConfiguration.proEntitlementID],
              proEntitlement.isActive else {
            return .free
        }

        // Extract subscription details
        let expirationDate = proEntitlement.expirationDate
        let willRenew = proEntitlement.willRenew
        let productIdentifier = proEntitlement.productIdentifier
        let originalPurchaseDate = proEntitlement.originalPurchaseDate
        let isInTrial = proEntitlement.periodType == .trial
        let isInGrace = proEntitlement.periodType == .grace

        return SubscriptionStatus(
            isActive: true,
            tier: .pro,
            expirationDate: expirationDate,
            willAutoRenew: willRenew,
            productId: productIdentifier,
            originalPurchaseDate: originalPurchaseDate,
            isTrialPeriod: isInTrial,
            isInGracePeriod: isInGrace
        )
    }

    private func mapToSubscriptionProduct(_ package: Package) -> SubscriptionProduct? {
        let product = package.storeProduct

        // Determine subscription period
        let period: SubscriptionPeriod
        switch package.packageType {
        case .weekly:
            period = .weekly
        case .monthly:
            period = .monthly
        case .annual:
            period = .yearly
        default:
            // Default to monthly for unknown types
            period = .monthly
        }

        // Extract introductory offer if available
        var introOffer: IntroductoryOffer?
        if let intro = product.introductoryDiscount {
            let offerPeriod: SubscriptionPeriod
            switch intro.subscriptionPeriod.unit {
            case .day, .week:
                offerPeriod = .weekly
            case .month:
                offerPeriod = .monthly
            case .year:
                offerPeriod = .yearly
            @unknown default:
                offerPeriod = .monthly
            }

            let offerType: IntroductoryOffer.OfferType
            switch intro.type {
            case .introductory:
                if intro.price == 0 {
                    offerType = .freeTrial
                } else {
                    offerType = .payAsYouGo
                }
            case .promotional:
                offerType = .payAsYouGo
            @unknown default:
                offerType = .payAsYouGo
            }

            introOffer = IntroductoryOffer(
                displayPrice: intro.localizedPriceString,
                period: offerPeriod,
                numberOfPeriods: intro.subscriptionPeriod.value,
                type: offerType
            )
        }

        return SubscriptionProduct(
            id: product.productIdentifier,
            displayName: product.localizedTitle,
            description: product.localizedDescription,
            displayPrice: product.localizedPriceString,
            priceValue: product.price,
            currencyCode: product.currencyCode ?? "USD",
            subscriptionPeriod: period,
            introductoryOffer: introOffer
        )
    }
    #endif
}

// MARK: - RevenueCat Delegate Extension

#if canImport(RevenueCat)
extension RevenueCatSubscriptionService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            let status = mapToSubscriptionStatus(customerInfo)
            cachedStatus = status
            statusContinuation?.yield(status)
            logger.info("Received customer info update from delegate: tier=\(status.tier.rawValue)")
        }
    }
}
#endif
