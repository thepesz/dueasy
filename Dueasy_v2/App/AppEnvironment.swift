import Foundation
import SwiftData
import Observation
import os

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

// MARK: - App Tier

/// Application tier determining available features.
///
/// ## Cloud Extraction Access
///
/// Both tiers have access to cloud extraction with backend-enforced limits:
/// - Free tier: 3 cloud extractions per month
/// - Pro tier: 100 cloud extractions per month
///
/// Backend is the single source of truth for usage limits.
/// No client-side enforcement.
enum AppTier: String, Sendable {
    case free
    case pro

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        }
    }

    /// Whether premium cloud features are available at this tier.
    /// Note: Basic cloud extraction is available to all tiers (within limits).
    /// This refers to premium features like cloud vault, priority processing, etc.
    var hasPremiumCloudFeatures: Bool {
        self == .pro
    }

    /// Monthly cloud extraction limit for this tier.
    /// Note: This is informational only. Backend enforces actual limits.
    var monthlyCloudExtractionLimit: Int {
        switch self {
        case .free: return 3
        case .pro: return 100
        }
    }
}

// MARK: - Lazy Service Box

/// Thread-safe lazy initialization wrapper for heavy services.
/// Uses @MainActor isolation for thread safety in SwiftUI context.
/// This avoids loading heavy services at app startup.
@MainActor
final class LazyService<T> {
    private var _value: T?
    private let factory: () -> T

    init(_ factory: @escaping () -> T) {
        self.factory = factory
    }

    var value: T {
        if let existing = _value {
            return existing
        }
        let newValue = factory()
        _value = newValue
        return newValue
    }

    /// Check if the service has been initialized without triggering initialization
    var isInitialized: Bool {
        _value != nil
    }
}

// MARK: - App Environment

/// Central dependency container for DuEasy.
/// All services are protocol-based to enable swapping implementations in Iteration 2 (backend/AI).
///
/// Architecture principle: ViewModels call Use Cases only. Use Cases depend on protocols injected here.
///
/// Tier Support:
/// - Free tier: Local-only analysis with NoOp auth/subscription services
/// - Pro tier: Cloud AI analysis via Firebase (Iteration 2)
///
/// Performance Optimization:
/// - Heavy services (LayoutFirstInvoiceParser) use lazy initialization
/// - Cloud services only initialized for Pro tier when first accessed
/// - Free tier users never load cloud analysis infrastructure
@MainActor
@Observable
final class AppEnvironment {

    // MARK: - Model Context

    let modelContext: ModelContext

    // MARK: - App Tier

    /// Base tier set at initialization (used when subscription service unavailable).
    /// In production with RevenueCat, use `currentTier` instead which queries subscription state.
    private let baseTier: AppTier

    /// Current application tier (free or pro).
    /// Dynamically determined from subscription service when available.
    /// Falls back to baseTier if subscription check fails.
    var appTier: AppTier {
        // For synchronous access, we use the cached tier from subscription changes
        // The actual tier is determined asynchronously by subscription service
        return _cachedTier ?? baseTier
    }

    /// Cached tier updated from subscription service status changes.
    /// This allows synchronous access to current tier while subscription is managed asynchronously.
    private var _cachedTier: AppTier?

    // MARK: - Repositories

    let documentRepository: DocumentRepositoryProtocol

    // MARK: - Core Services (Eagerly Initialized - Lightweight)

    let fileStorageService: FileStorageServiceProtocol
    let ocrService: OCRServiceProtocol
    let calendarService: CalendarServiceProtocol
    let notificationService: NotificationServiceProtocol
    let syncService: SyncServiceProtocol
    let cryptoService: CryptoServiceProtocol

    // MARK: - Core Services (Lazily Initialized - Heavy)

    /// Document analysis service - lazily initialized because LayoutFirstInvoiceParser
    /// loads multiple sub-parsers and regex patterns that are expensive at startup.
    private let _lazyDocumentAnalysisService: LazyService<DocumentAnalysisServiceProtocol>

    /// Public accessor that triggers lazy initialization on first access
    var documentAnalysisService: DocumentAnalysisServiceProtocol {
        _lazyDocumentAnalysisService.value
    }

    // MARK: - Learning Services

    let keywordLearningService: KeywordLearningService
    let learningDataService: LearningDataService
    let vendorProfileService: VendorProfileService
    let vendorMigrationService: VendorProfileMigrationService
    let vendorTemplateService: VendorTemplateService

    // MARK: - Recurring Payment Services

    let recurringDateService: RecurringDateServiceProtocol
    let vendorFingerprintService: VendorFingerprintServiceProtocol
    let documentClassifierService: DocumentClassifierServiceProtocol
    let recurringTemplateService: RecurringTemplateServiceProtocol
    let recurringSchedulerService: RecurringSchedulerServiceProtocol
    let recurringMatcherService: RecurringMatcherServiceProtocol
    let recurringDetectionService: RecurringDetectionServiceProtocol
    let recurringIntegrityService: RecurringIntegrityService
    let fingerprintMigrationService: FingerprintMigrationService

    // MARK: - Cloud Integration Services (Phase 1 Foundation)

    /// Authentication service for backend access.
    /// Free tier: NoOpAuthService (always unauthenticated)
    /// Pro tier: FirebaseAuthService (Iteration 2)
    let authService: AuthServiceProtocol

    /// Subscription and entitlement service.
    /// Free tier: NoOpSubscriptionService (always free)
    /// Pro tier: StoreKitSubscriptionService (Iteration 2)
    let subscriptionService: SubscriptionServiceProtocol

    /// Authentication bootstrapper for managing Firebase auth state.
    /// Guarantees a Firebase user exists (anonymous or linked) before any cloud extraction requests.
    /// Provides observable state for UI (isSignedIn, isAppleLinked, currentUserEmail).
    let authBootstrapper: AuthBootstrapper

    // MARK: - Network Services

    /// Network connectivity monitor for routing decisions.
    /// Tracks device online/offline state using NWPathMonitor.
    let networkMonitor: NetworkMonitor

    /// Document analysis router - lazily initialized.
    /// All tiers use HybridAnalysisRouter with cloud-first routing.
    /// Backend enforces monthly limits (Free: 3, Pro: 100).
    private let _lazyAnalysisRouter: LazyService<DocumentAnalysisRouterProtocol>

    /// Public accessor for analysis router
    var analysisRouter: DocumentAnalysisRouterProtocol {
        _lazyAnalysisRouter.value
    }

    // MARK: - Settings

    let settingsManager: SettingsManager

    // MARK: - Backup Services

    /// Local backup service for export/import functionality
    let backupService: BackupServiceProtocol

    /// iCloud auto-backup service for automatic encrypted backups
    let iCloudBackupService: iCloudBackupService

    // MARK: - Configuration

    let globalKeywordConfig: GlobalKeywordConfig

    // MARK: - Diagnostics

    /// Check which lazy services have been initialized (for debugging/testing)
    var lazyServiceStatus: (documentAnalysis: Bool, analysisRouter: Bool) {
        (_lazyDocumentAnalysisService.isInitialized, _lazyAnalysisRouter.isInitialized)
    }

    // MARK: - Initialization

    /// Initialize AppEnvironment with all dependencies.
    /// Heavy services use lazy initialization to reduce startup time.
    /// - Parameters:
    ///   - modelContext: SwiftData model context
    ///   - tier: Application tier (default: .free)
    init(modelContext: ModelContext, tier: AppTier = .free) {
        self.modelContext = modelContext
        self.baseTier = tier
        self._cachedTier = nil // Will be set from subscription service

        // Initialize settings manager first (other services may depend on it)
        self.settingsManager = SettingsManager()

        // Load GlobalKeywordConfig (use the latest version)
        let configDescriptor = FetchDescriptor<GlobalKeywordConfig>(
            sortBy: [SortDescriptor(\.version, order: .reverse)]
        )
        let loadedConfig: GlobalKeywordConfig
        do {
            let configs = try modelContext.fetch(configDescriptor)
            if let latestConfig = configs.first {
                loadedConfig = latestConfig
            } else {
                // Fallback: create default v1 if none exists
                let defaultConfig = GlobalKeywordConfig.createDefaultV1()
                modelContext.insert(defaultConfig)
                try modelContext.save()
                loadedConfig = defaultConfig
            }
        } catch {
            // Critical failure: create v1 without saving
            loadedConfig = GlobalKeywordConfig.createDefaultV1()
        }
        self.globalKeywordConfig = loadedConfig

        // Initialize keyword learning service
        self.keywordLearningService = KeywordLearningService()

        // Initialize learning data service for capturing user corrections
        self.learningDataService = LearningDataService(modelContext: modelContext)

        // Initialize vendor profile service for intelligent parsing per vendor
        self.vendorProfileService = VendorProfileService(modelContext: modelContext)

        // Initialize vendor migration service for version upgrades
        self.vendorMigrationService = VendorProfileMigrationService(modelContext: modelContext)

        // Initialize vendor template service for local learning
        self.vendorTemplateService = VendorTemplateService(modelContext: modelContext)

        // Initialize repositories
        self.documentRepository = SwiftDataDocumentRepository(modelContext: modelContext)

        // Initialize crypto service first (needed by file storage)
        self.cryptoService = IOSDataProtectionCryptoService() // iOS file protection wrapper

        // Initialize lightweight services eagerly
        self.fileStorageService = LocalFileStorageService(cryptoService: cryptoService)
        self.ocrService = AppleVisionOCRService()
        self.calendarService = EventKitCalendarService()
        self.notificationService = LocalNotificationService()
        self.syncService = NoOpSyncService() // No-op for Iteration 1

        // Initialize recurring payment services (lightweight)
        // MVVM Pure: RecurringDateService extracts date logic from RecurringInstance model
        self.recurringDateService = RecurringDateService()
        self.vendorFingerprintService = VendorFingerprintService()
        self.documentClassifierService = DocumentClassifierService()

        // Template service needs modelContext
        let templateService = RecurringTemplateService(modelContext: modelContext)
        self.recurringTemplateService = templateService

        // Scheduler service needs modelContext, notification service, calendar service, settings, and date service
        let schedulerService = RecurringSchedulerService(
            modelContext: modelContext,
            notificationService: notificationService,
            calendarService: calendarService,
            settingsManager: settingsManager,
            dateService: recurringDateService
        )
        self.recurringSchedulerService = schedulerService

        // Matcher service needs modelContext, template service, scheduler service, and date service
        self.recurringMatcherService = RecurringMatcherService(
            modelContext: modelContext,
            templateService: templateService,
            schedulerService: schedulerService,
            dateService: recurringDateService
        )

        // Detection service needs modelContext, template service, and classifier service
        self.recurringDetectionService = RecurringDetectionService(
            modelContext: modelContext,
            templateService: templateService,
            classifierService: documentClassifierService
        )

        // CRITICAL FIX: Integrity service for cleaning up orphaned references
        self.recurringIntegrityService = RecurringIntegrityService(
            modelContext: modelContext,
            calendarService: calendarService,
            notificationService: notificationService
        )

        // Fingerprint migration service for handling amount-bucketed fingerprints
        self.fingerprintMigrationService = FingerprintMigrationService(
            modelContext: modelContext,
            fingerprintService: self.vendorFingerprintService,
            templateService: templateService
        )

        // LAZY INITIALIZATION: LayoutFirstInvoiceParser
        // This is a heavy service with multiple sub-parsers and regex patterns.
        // Defer initialization until first document scan to reduce app startup time.
        let capturedKeywordService = self.keywordLearningService
        let capturedConfig = loadedConfig
        self._lazyDocumentAnalysisService = LazyService {
            PrivacyLogger.app.info("Lazy init: LayoutFirstInvoiceParser")
            return LayoutFirstInvoiceParser(
                keywordLearningService: capturedKeywordService,
                globalKeywordConfig: capturedConfig
            )
        }

        // Initialize auth service (always Firebase when available, for cloud extraction)
        #if canImport(FirebaseAuth) && canImport(FirebaseFunctions)
        let firebaseAuth = FirebaseAuthService()
        self.authService = firebaseAuth
        #else
        self.authService = NoOpAuthService()
        #endif

        // Initialize subscription service based on environment
        // Production: Use RevenueCat for real subscription management
        // Debug/Testing: Use NoOp or Firebase for testing different tiers
        #if canImport(RevenueCat)
        // Production: RevenueCat handles all subscription management
        // Tier is determined by entitlement state, NOT hard-coded
        self.subscriptionService = RevenueCatSubscriptionService()
        PrivacyLogger.app.info("Using RevenueCat subscription service")
        #elseif canImport(FirebaseAuth) && canImport(FirebaseFunctions)
        // Fallback: Firebase-based subscription service
        self.subscriptionService = FirebaseSubscriptionService(authService: firebaseAuth)
        PrivacyLogger.app.info("Using Firebase subscription service (RevenueCat unavailable)")
        #else
        // No subscription SDK available - free tier only
        self.subscriptionService = NoOpSubscriptionService()
        PrivacyLogger.app.warning("No subscription SDK available - free tier only")
        #endif

        // Initialize auth bootstrapper with the auth service
        self.authBootstrapper = AuthBootstrapper(authService: authService)

        // Initialize network monitor
        // Start monitoring immediately so network status is available for first extraction
        self.networkMonitor = NetworkMonitor()
        self.networkMonitor.startMonitoring()
        PrivacyLogger.app.info("Network monitor started")

        // LAZY INITIALIZATION: Analysis Router
        // All tiers use HybridAnalysisRouter with cloud-first routing.
        // Backend enforces monthly limits (Free: 3, Pro: 100).
        // NO client-side tier-based routing - backend is source of truth.
        let capturedAuthService = self.authService
        let capturedSettingsManager = self.settingsManager
        let capturedNetworkMonitor: NetworkMonitorProtocol = self.networkMonitor
        let lazyDocAnalysis = self._lazyDocumentAnalysisService

        self._lazyAnalysisRouter = LazyService {
            #if canImport(FirebaseAuth) && canImport(FirebaseFunctions)
            PrivacyLogger.app.info("Lazy init: HybridAnalysisRouter (cloud-first routing for all tiers)")
            let cloudGateway = FirebaseCloudExtractionGateway(authService: capturedAuthService)
            return HybridAnalysisRouter(
                localService: lazyDocAnalysis.value,
                cloudGateway: cloudGateway,
                networkMonitor: capturedNetworkMonitor,
                settingsManager: capturedSettingsManager,
                config: .default
            )
            #else
            PrivacyLogger.app.warning("Lazy init: LocalOnlyAnalysisRouter (Firebase SDK unavailable)")
            return LocalOnlyAnalysisRouter(localService: lazyDocAnalysis.value)
            #endif
        }

        // Initialize backup services
        let localBackupService = LocalBackupService(modelContainer: modelContext.container)
        self.backupService = localBackupService
        self.iCloudBackupService = Dueasy_v2.iCloudBackupService(
            backupService: localBackupService,
            keychain: KeychainService()
        )
        PrivacyLogger.app.info("Backup services initialized")

        // Start observing subscription status changes
        // This updates _cachedTier whenever subscription state changes
        startSubscriptionObservation()

        PrivacyLogger.app.info("AppEnvironment initialized for tier: \(tier.displayName) (heavy services deferred)")
    }

    // MARK: - Subscription Observation

    /// Start observing subscription status changes to keep cached tier in sync.
    /// Called during initialization and whenever subscription service is ready.
    private func startSubscriptionObservation() {
        Task { [weak self] in
            guard let self = self else { return }

            // Initial subscription check
            let initialStatus = await self.subscriptionService.subscriptionStatus
            await MainActor.run {
                self._cachedTier = initialStatus.tier == .pro ? .pro : .free
                PrivacyLogger.app.info("Initial subscription tier: \(self._cachedTier?.displayName ?? "unknown")")
            }

            // Listen for ongoing status changes
            for await status in self.subscriptionService.statusChanges() {
                await MainActor.run {
                    let newTier: AppTier = status.tier == .pro ? .pro : .free
                    if self._cachedTier != newTier {
                        self._cachedTier = newTier
                        PrivacyLogger.app.info("Subscription tier changed to: \(newTier.displayName)")
                    }
                }
            }
        }
    }

    // MARK: - Use Case Factory Methods

    /// Creates a CreateDocumentUseCase with injected dependencies
    func makeCreateDocumentUseCase() -> CreateDocumentUseCase {
        CreateDocumentUseCase(
            repository: documentRepository,
            vendorFingerprintService: vendorFingerprintService,
            classifierService: documentClassifierService
        )
    }

    /// Creates a ScanAndAttachFileUseCase with injected dependencies
    func makeScanAndAttachFileUseCase() -> ScanAndAttachFileUseCase {
        ScanAndAttachFileUseCase(
            fileStorageService: fileStorageService,
            repository: documentRepository
        )
    }

    /// Creates an ExtractAndSuggestFieldsUseCase with injected dependencies
    func makeExtractAndSuggestFieldsUseCase() -> ExtractAndSuggestFieldsUseCase {
        ExtractAndSuggestFieldsUseCase(
            ocrService: ocrService,
            analysisRouter: analysisRouter
        )
    }

    /// Creates a FinalizeInvoiceUseCase with injected dependencies.
    /// CRITICAL FIX: Now includes recurring services for automatic matching of new documents
    /// to existing recurring instances. This ensures that when a user scans a new invoice
    /// for a vendor that already has a recurring template, the document is automatically
    /// linked to the appropriate recurring instance instead of creating a duplicate.
    func makeFinalizeInvoiceUseCase() -> FinalizeInvoiceUseCase {
        FinalizeInvoiceUseCase(
            repository: documentRepository,
            calendarService: calendarService,
            notificationService: notificationService,
            settingsManager: settingsManager,
            vendorFingerprintService: vendorFingerprintService,
            classifierService: documentClassifierService,
            recurringMatcherService: recurringMatcherService,
            recurringTemplateService: recurringTemplateService,
            recurringSchedulerService: recurringSchedulerService
        )
    }

    /// Creates a MarkAsPaidUseCase with injected dependencies.
    /// CRITICAL FIX: Now includes modelContext for recurring instance sync.
    func makeMarkAsPaidUseCase() -> MarkAsPaidUseCase {
        MarkAsPaidUseCase(
            repository: documentRepository,
            notificationService: notificationService,
            modelContext: modelContext
        )
    }

    /// Creates a DeleteDocumentUseCase with injected dependencies.
    /// CRITICAL FIX: Now includes recurring services to handle linkage cleanup before deletion.
    func makeDeleteDocumentUseCase() -> DeleteDocumentUseCase {
        DeleteDocumentUseCase(
            repository: documentRepository,
            fileStorageService: fileStorageService,
            calendarService: calendarService,
            notificationService: notificationService,
            modelContext: modelContext,
            recurringSchedulerService: recurringSchedulerService,
            recurringTemplateService: recurringTemplateService
        )
    }

    /// Creates an UpdateDocumentUseCase with injected dependencies
    func makeUpdateDocumentUseCase() -> UpdateDocumentUseCase {
        UpdateDocumentUseCase(
            repository: documentRepository,
            modelContext: modelContext,
            calendarService: calendarService,
            notificationService: notificationService,
            vendorFingerprintService: vendorFingerprintService,
            classifierService: documentClassifierService
        )
    }

    /// Creates a CheckPermissionsUseCase with injected dependencies
    func makeCheckPermissionsUseCase() -> CheckPermissionsUseCase {
        CheckPermissionsUseCase(
            calendarService: calendarService,
            notificationService: notificationService
        )
    }

    /// Creates a FetchDocumentsUseCase with injected dependencies
    func makeFetchDocumentsUseCase() -> FetchDocumentsUseCase {
        FetchDocumentsUseCase(repository: documentRepository)
    }

    /// Creates a CountDocumentsByStatusUseCase with injected dependencies
    func makeCountDocumentsByStatusUseCase() -> CountDocumentsByStatusUseCase {
        CountDocumentsByStatusUseCase(repository: documentRepository)
    }

    /// Creates a FetchDocumentsForCalendarUseCase with injected dependencies
    func makeFetchDocumentsForCalendarUseCase() -> FetchDocumentsForCalendarUseCase {
        FetchDocumentsForCalendarUseCase(repository: documentRepository)
    }

    /// Creates a FetchRecurringInstancesForMonthUseCase with injected dependencies
    func makeFetchRecurringInstancesForMonthUseCase() -> FetchRecurringInstancesForMonthUseCase {
        FetchRecurringInstancesForMonthUseCase(modelContext: modelContext)
    }

    /// Creates an ImportFromPDFUseCase with injected dependencies
    func makeImportFromPDFUseCase() -> ImportFromPDFUseCase {
        ImportFromPDFUseCase(
            fileStorageService: fileStorageService,
            repository: documentRepository
        )
    }

    /// Creates an ImportFromPhotoUseCase with injected dependencies
    func makeImportFromPhotoUseCase() -> ImportFromPhotoUseCase {
        ImportFromPhotoUseCase(
            fileStorageService: fileStorageService,
            repository: documentRepository
        )
    }

    // MARK: - Recurring Payment Use Case Factory Methods

    /// Creates a CreateRecurringTemplateFromDocumentUseCase with injected dependencies
    func makeCreateRecurringTemplateFromDocumentUseCase() -> CreateRecurringTemplateFromDocumentUseCase {
        CreateRecurringTemplateFromDocumentUseCase(
            templateService: recurringTemplateService,
            schedulerService: recurringSchedulerService,
            matcherService: recurringMatcherService,
            fingerprintService: vendorFingerprintService,
            classifierService: documentClassifierService,
            dateService: recurringDateService
        )
    }

    /// Creates a DetectRecurringCandidatesUseCase with injected dependencies
    func makeDetectRecurringCandidatesUseCase() -> DetectRecurringCandidatesUseCase {
        DetectRecurringCandidatesUseCase(
            detectionService: recurringDetectionService,
            templateService: recurringTemplateService
        )
    }

    /// Creates a LinkExistingDocumentsUseCase with injected dependencies
    func makeLinkExistingDocumentsUseCase() -> LinkExistingDocumentsUseCase {
        LinkExistingDocumentsUseCase(
            documentRepository: SwiftDataDocumentRepository(modelContext: modelContext),
            schedulerService: recurringSchedulerService,
            dateService: recurringDateService
        )
    }

    /// Creates a ManuallyLinkDocumentsUseCase for retroactive linking
    func makeManuallyLinkDocumentsUseCase() -> ManuallyLinkDocumentsUseCase {
        ManuallyLinkDocumentsUseCase(
            documentRepository: SwiftDataDocumentRepository(modelContext: modelContext),
            schedulerService: recurringSchedulerService,
            templateService: recurringTemplateService
        )
    }

    /// Creates a MatchDocumentToRecurringUseCase with injected dependencies
    func makeMatchDocumentToRecurringUseCase() -> MatchDocumentToRecurringUseCase {
        MatchDocumentToRecurringUseCase(
            matcherService: recurringMatcherService,
            fingerprintService: vendorFingerprintService,
            classifierService: documentClassifierService,
            detectionService: recurringDetectionService
        )
    }

    /// Creates an UnlinkDocumentFromRecurringUseCase with injected dependencies
    func makeUnlinkDocumentFromRecurringUseCase() -> UnlinkDocumentFromRecurringUseCase {
        UnlinkDocumentFromRecurringUseCase(
            modelContext: modelContext,
            schedulerService: recurringSchedulerService,
            templateService: recurringTemplateService,
            notificationService: notificationService
        )
    }

    /// Creates a DeactivateRecurringTemplateUseCase with injected dependencies
    func makeDeactivateRecurringTemplateUseCase() -> DeactivateRecurringTemplateUseCase {
        DeactivateRecurringTemplateUseCase(
            modelContext: modelContext,
            templateService: recurringTemplateService,
            schedulerService: recurringSchedulerService,
            notificationService: notificationService,
            calendarService: calendarService,
            settingsManager: settingsManager
        )
    }

    /// Creates a DeleteRecurringInstanceUseCase with injected dependencies
    func makeDeleteRecurringInstanceUseCase() -> DeleteRecurringInstanceUseCase {
        DeleteRecurringInstanceUseCase(
            modelContext: modelContext,
            notificationService: notificationService,
            calendarService: calendarService
        )
    }

    /// Creates a DeleteFutureRecurringInstancesUseCase with injected dependencies
    func makeDeleteFutureRecurringInstancesUseCase() -> DeleteFutureRecurringInstancesUseCase {
        DeleteFutureRecurringInstancesUseCase(
            modelContext: modelContext,
            templateService: recurringTemplateService,
            notificationService: notificationService,
            calendarService: calendarService,
            dateService: recurringDateService
        )
    }

    /// Creates a RecurringDeletionViewModel with all injected dependencies
    func makeRecurringDeletionViewModel() -> RecurringDeletionViewModel {
        RecurringDeletionViewModel(
            unlinkDocumentUseCase: makeUnlinkDocumentFromRecurringUseCase(),
            deactivateTemplateUseCase: makeDeactivateRecurringTemplateUseCase(),
            deleteInstanceUseCase: makeDeleteRecurringInstanceUseCase(),
            deleteFutureInstancesUseCase: makeDeleteFutureRecurringInstancesUseCase(),
            deleteDocumentUseCase: makeDeleteDocumentUseCase(),
            templateService: recurringTemplateService
        )
    }

    // MARK: - Home Screen Use Case Factory Methods

    /// Creates a FetchHomeMetricsUseCase with injected dependencies
    func makeFetchHomeMetricsUseCase() -> FetchHomeMetricsUseCase {
        FetchHomeMetricsUseCase(
            documentRepository: documentRepository,
            recurringTemplateService: recurringTemplateService,
            recurringSchedulerService: recurringSchedulerService,
            recurringDateService: recurringDateService,
            appTier: appTier
        )
    }

    // MARK: - Versioning and Migration

    private let migrationLogger = Logger(subsystem: "com.dueasy.app", category: "StartupMigrations")

    /// Run vendor profile migrations on app startup
    /// Call this after AppEnvironment is initialized
    func runStartupMigrations() async throws {
        migrationLogger.info("=== APP STARTUP MIGRATIONS START ===")

        // Existing migrations
        migrationLogger.info("Running vendor profile migrations...")
        try await vendorMigrationService.migrateVendorsIfNeeded(to: globalKeywordConfig)

        // Backfill vendorFingerprint and documentCategory for existing documents
        migrationLogger.info("Running vendor fingerprint backfill...")
        try await backfillVendorFingerprints()

        // CRITICAL FIX: Migrate absolute file paths to relative paths
        // iOS container paths change with app updates, breaking absolute path references.
        // This migration extracts relative paths from any existing absolute paths.
        migrationLogger.info("Running file path migration (absolute to relative)...")
        do {
            try await migrateFilePathsToRelative()
        } catch {
            migrationLogger.error("File path migration failed: \(error.localizedDescription)")
            // Continue app startup - migration failure is not fatal
        }

        // CRITICAL FIX: Run recurring payment integrity checks
        // This cleans up orphaned references that can occur when templates/instances are deleted
        migrationLogger.info("Running recurring payment integrity checks...")
        do {
            let result = try await recurringIntegrityService.runIntegrityChecks()
            migrationLogger.info("Integrity checks complete: \(result.totalIssuesFixed) issues found and resolved")
            if result.hasIssues {
                migrationLogger.info("  - Orphaned instances removed: \(result.orphanedInstancesRemoved)")
                migrationLogger.info("  - Orphaned document refs cleared: \(result.orphanedDocumentReferencesCleared)")
                migrationLogger.info("  - Orphaned candidates removed: \(result.orphanedCandidatesRemoved)")
                migrationLogger.info("  - Amounts migrated: \(result.amountPrecisionMigrations)")
            }
        } catch {
            migrationLogger.error("Integrity checks failed: \(error.localizedDescription)")
            // Continue app startup even if integrity checks fail - don't rethrow
        }

        // FINGERPRINT MIGRATION: Backfill vendor-only fingerprints for existing templates
        // This enables the "related templates from same vendor" feature and amount-based matching
        migrationLogger.info("Running fingerprint migration (vendor-only fingerprints)...")
        do {
            let backfilledCount = try await fingerprintMigrationService.backfillVendorOnlyFingerprints()
            if backfilledCount > 0 {
                migrationLogger.info("Backfilled vendor-only fingerprints for \(backfilledCount) templates")
            } else {
                migrationLogger.info("No templates needed vendor-only fingerprint backfill")
            }
        } catch {
            migrationLogger.error("Fingerprint migration failed: \(error.localizedDescription)")
            // Continue app startup - migration failure is not fatal
        }

        migrationLogger.info("=== APP STARTUP MIGRATIONS COMPLETE ===")
    }

    /// Get migration statistics for monitoring
    func getMigrationStats() throws -> MigrationStats {
        return try vendorMigrationService.getMigrationStats()
    }

    // MARK: - Vendor Fingerprint Backfill

    /// Batch size for fingerprint backfill to prevent UI freezes.
    /// Processing documents in smaller batches allows the main thread to handle UI updates.
    private static let backfillBatchSize = 50

    /// Backfills vendorFingerprint and documentCategory for existing documents that don't have them.
    /// This is a one-time migration to fix documents created before fingerprint support was added.
    /// Safe to call multiple times - only updates documents with nil fingerprint.
    ///
    /// PERFORMANCE: Uses batch processing with Task.yield() to prevent UI freezes
    /// when processing hundreds of documents. Documents are processed in batches of 50,
    /// with explicit yielding between batches to allow UI thread responsiveness.
    func backfillVendorFingerprints() async throws {
        let logger = Logger(subsystem: "com.dueasy.app", category: "FingerprintBackfill")

        // Fetch all documents without vendorFingerprint
        let descriptor = FetchDescriptor<FinanceDocument>(
            predicate: #Predicate<FinanceDocument> { $0.vendorFingerprint == nil }
        )

        let documentsToBackfill = try modelContext.fetch(descriptor)

        if documentsToBackfill.isEmpty {
            logger.info("No documents need fingerprint backfill")
            return
        }

        let totalCount = documentsToBackfill.count
        let batchSize = Self.backfillBatchSize

        // PRIVACY: Log only counts, not document contents
        logger.info("Backfilling vendorFingerprint for \(totalCount) documents in batches of \(batchSize)")

        var backfilledCount = 0
        var skippedCount = 0
        var batchNumber = 0

        // Process in batches to avoid UI freeze
        for batchStart in stride(from: 0, to: totalCount, by: batchSize) {
            batchNumber += 1
            let batchEnd = min(batchStart + batchSize, totalCount)
            let batch = documentsToBackfill[batchStart..<batchEnd]

            // Process this batch
            for document in batch {
                // Skip documents without a title (empty drafts)
                guard !document.title.isEmpty else {
                    skippedCount += 1
                    continue
                }

                // Generate fingerprint
                let fingerprint = vendorFingerprintService.generateFingerprint(
                    vendorName: document.title,
                    nip: document.vendorNIP
                )
                document.vendorFingerprint = fingerprint

                // Classify document category
                let classification = documentClassifierService.classify(
                    vendorName: document.title,
                    ocrText: nil,
                    amount: document.amount
                )
                document.documentCategoryRaw = classification.category.rawValue

                backfilledCount += 1
            }

            // CRITICAL: Yield to allow UI updates between batches
            // This prevents the main thread from being blocked when processing
            // hundreds of documents, avoiding UI freeze and watchdog termination.
            await Task.yield()

            // Log batch progress (privacy-safe: only counts)
            let progress = Double(batchEnd) / Double(totalCount) * 100
            logger.info("Batch \(batchNumber) complete: \(batchEnd)/\(totalCount) (\(Int(progress))%)")
        }

        // Save all changes after processing
        try modelContext.save()

        // Final summary (privacy-safe logging)
        logger.info("Fingerprint backfill complete: \(backfilledCount) updated, \(skippedCount) skipped (empty drafts)")
    }

    // MARK: - File Path Migration

    /// Batch size for file path migration to prevent UI freezes.
    private static let filePathMigrationBatchSize = 50

    /// Migrates documents with absolute file paths to relative paths.
    ///
    /// iOS container paths (e.g., `/var/mobile/Containers/Data/Application/{UUID}/Documents/...`)
    /// change with app updates. Storing absolute paths breaks file access after updates.
    ///
    /// This migration:
    /// 1. Finds documents where `sourceFileURL` contains an absolute path (starts with `/`)
    /// 2. Extracts the relative path (portion after `/Documents/`)
    /// 3. Updates the stored path to use only the relative portion
    ///
    /// **Safe to run multiple times** - only processes documents with absolute paths.
    /// **Non-destructive** - if path extraction fails, the original path is preserved.
    ///
    /// **Privacy:** Logs only counts and migration status, never file paths or document content.
    func migrateFilePathsToRelative() async throws {
        let logger = Logger(subsystem: "com.dueasy.app", category: "FilePathMigration")

        // Fetch ALL documents (we need to check sourceFileURL in memory since
        // SwiftData predicates can't easily check for string prefix on optionals)
        let allDescriptor = FetchDescriptor<FinanceDocument>()
        let allDocuments = try modelContext.fetch(allDescriptor)

        // Filter to documents with absolute paths (start with /)
        // The computed property getter now returns the resolved path,
        // but we need to check if the STORED value is absolute.
        // We do this by checking if reassigning the same value changes it
        // (if it's absolute, the setter will convert to relative)
        var documentsNeedingMigration: [FinanceDocument] = []

        for document in allDocuments {
            guard let currentPath = document.sourceFileURL else { continue }

            // Check if path looks like an absolute iOS container path
            // These contain patterns like "/var/mobile/Containers" or "/Users/.../CoreSimulator"
            if currentPath.hasPrefix("/") && currentPath.contains("/Documents/") {
                documentsNeedingMigration.append(document)
            }
        }

        if documentsNeedingMigration.isEmpty {
            logger.info("No documents need file path migration - all paths are already relative")
            return
        }

        let totalCount = documentsNeedingMigration.count
        let batchSize = Self.filePathMigrationBatchSize

        // PRIVACY: Log only counts, not paths or document details
        logger.info("Migrating \(totalCount) documents from absolute to relative file paths")

        var migratedCount = 0
        var skippedCount = 0
        var batchNumber = 0

        // Process in batches to prevent UI freeze
        for batchStart in stride(from: 0, to: totalCount, by: batchSize) {
            batchNumber += 1
            let batchEnd = min(batchStart + batchSize, totalCount)
            let batch = documentsNeedingMigration[batchStart..<batchEnd]

            for document in batch {
                guard let absolutePath = document.sourceFileURL else {
                    skippedCount += 1
                    continue
                }

                // Extract relative path from absolute path
                // Look for "/Documents/" marker and take everything after it
                if let range = absolutePath.range(of: "/Documents/") {
                    let relativePath = String(absolutePath[range.upperBound...])

                    // Verify the relative path is non-empty and looks reasonable
                    if !relativePath.isEmpty && !relativePath.hasPrefix("/") {
                        // The setter will normalize and store the relative path
                        // We set it directly to avoid going through the getter which builds full path
                        document.sourceFileURL = relativePath
                        document.markUpdated()
                        migratedCount += 1
                    } else {
                        logger.warning("Skipped migration: extracted path was invalid")
                        skippedCount += 1
                    }
                } else {
                    // Path is absolute but doesn't contain /Documents/ - unusual case
                    // Try to extract just the last path components as a fallback
                    let url = URL(fileURLWithPath: absolutePath)
                    let filename = url.lastPathComponent

                    // Check if it's in a subdirectory we recognize
                    let parentDir = url.deletingLastPathComponent().lastPathComponent
                    if parentDir == "ScannedDocuments" || parentDir.count == 36 { // UUID length
                        // Looks like ScannedDocuments/UUID or just a UUID directory
                        let relativePath = parentDir == "ScannedDocuments"
                            ? "ScannedDocuments/\(filename)"
                            : "ScannedDocuments/\(parentDir)/\(filename)"
                        document.sourceFileURL = relativePath
                        document.markUpdated()
                        migratedCount += 1
                    } else {
                        logger.warning("Skipped migration: could not determine relative path structure")
                        skippedCount += 1
                    }
                }
            }

            // Yield to allow UI updates
            await Task.yield()

            // Log batch progress (privacy-safe)
            let progress = Double(batchEnd) / Double(totalCount) * 100
            logger.info("File path migration batch \(batchNumber): \(batchEnd)/\(totalCount) (\(Int(progress))%)")
        }

        // Save all changes
        try modelContext.save()

        // Final summary (privacy-safe)
        logger.info("File path migration complete: \(migratedCount) migrated, \(skippedCount) skipped")
    }

    // MARK: - Keyword Learning Integration

    /// Learn from user correction (call after document finalization with corrected fields)
    /// - Parameters:
    ///   - vendorName: Vendor name from document
    ///   - nip: Vendor NIP (if available)
    ///   - regon: Vendor REGON (if available)
    ///   - correctedField: Which field was corrected (amount, dueDate, etc.)
    ///   - correctContext: Text context around the CORRECT value
    ///   - incorrectContexts: Text contexts around INCORRECT suggested values
    func learnFromUserCorrection(
        vendorName: String,
        nip: String?,
        regon: String?,
        correctedField: FieldType,
        correctContext: String,
        incorrectContexts: [String]
    ) async throws {
        // Get or create vendor profile
        let vendorProfile = try await vendorProfileService.getOrCreateVendorProfile(
            vendorName: vendorName,
            nip: nip,
            regon: regon,
            baseGlobalVersion: globalKeywordConfig.version
        )

        // Learn from correction
        try await vendorProfileService.learnFromCorrection(
            vendorProfile: vendorProfile,
            correctedField: correctedField,
            correctContext: correctContext,
            incorrectContexts: incorrectContexts
        )
    }

    // MARK: - Tier Convenience Methods

    /// Check if premium cloud features are available (cloud vault, priority, etc.)
    /// Note: Basic cloud extraction is available to all tiers.
    var hasPremiumCloudFeatures: Bool {
        appTier.hasPremiumCloudFeatures
    }

    /// Check if cloud analysis is currently available.
    /// Requires: signed in + network (available to all tiers within limits)
    var isCloudAnalysisAvailable: Bool {
        get async {
            return await analysisRouter.isCloudAvailable
        }
    }

    /// Current analysis mode based on settings
    var currentAnalysisMode: AnalysisMode {
        analysisRouter.analysisMode
    }

    /// Monthly cloud extraction limit for current tier (informational only).
    /// Backend enforces actual limits.
    var monthlyCloudExtractionLimit: Int {
        appTier.monthlyCloudExtractionLimit
    }
}
