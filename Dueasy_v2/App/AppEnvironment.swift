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
/// Free tier: Local-only analysis, no cloud features.
/// Pro tier: Cloud AI analysis, cloud vault, enhanced accuracy.
enum AppTier: String, Sendable {
    case free
    case pro

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        }
    }

    /// Whether cloud features are available at this tier
    var hasCloudFeatures: Bool {
        self == .pro
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
@MainActor
@Observable
final class AppEnvironment {

    // MARK: - Model Context

    let modelContext: ModelContext

    // MARK: - App Tier

    /// Current application tier (free or pro)
    let appTier: AppTier

    // MARK: - Repositories

    let documentRepository: DocumentRepositoryProtocol

    // MARK: - Core Services

    let fileStorageService: FileStorageServiceProtocol
    let ocrService: OCRServiceProtocol
    let documentAnalysisService: DocumentAnalysisServiceProtocol
    let calendarService: CalendarServiceProtocol
    let notificationService: NotificationServiceProtocol
    let syncService: SyncServiceProtocol
    let cryptoService: CryptoServiceProtocol

    // MARK: - Learning Services

    let keywordLearningService: KeywordLearningService
    let learningDataService: LearningDataService
    let vendorProfileService: VendorProfileService
    let vendorMigrationService: VendorProfileMigrationService
    let vendorTemplateService: VendorTemplateService

    // MARK: - Recurring Payment Services

    let vendorFingerprintService: VendorFingerprintServiceProtocol
    let documentClassifierService: DocumentClassifierServiceProtocol
    let recurringTemplateService: RecurringTemplateServiceProtocol
    let recurringSchedulerService: RecurringSchedulerServiceProtocol
    let recurringMatcherService: RecurringMatcherServiceProtocol
    let recurringDetectionService: RecurringDetectionServiceProtocol

    // MARK: - Cloud Integration Services (Phase 1 Foundation)

    /// Authentication service for backend access.
    /// Free tier: NoOpAuthService (always unauthenticated)
    /// Pro tier: FirebaseAuthService (Iteration 2)
    let authService: AuthServiceProtocol

    /// Subscription and entitlement service.
    /// Free tier: NoOpSubscriptionService (always free)
    /// Pro tier: StoreKitSubscriptionService (Iteration 2)
    let subscriptionService: SubscriptionServiceProtocol

    /// Document analysis router for provider selection.
    /// Free tier: LocalOnlyAnalysisRouter (always local)
    /// Pro tier: HybridAnalysisRouter (Iteration 2)
    let analysisRouter: DocumentAnalysisRouterProtocol

    // MARK: - Settings

    let settingsManager: SettingsManager

    // MARK: - Configuration

    let globalKeywordConfig: GlobalKeywordConfig

    // MARK: - Initialization

    /// Initialize AppEnvironment with all dependencies.
    /// - Parameters:
    ///   - modelContext: SwiftData model context
    ///   - tier: Application tier (default: .free)
    init(modelContext: ModelContext, tier: AppTier = .free) {
        self.modelContext = modelContext
        self.appTier = tier

        // Initialize settings manager first (other services may depend on it)
        self.settingsManager = SettingsManager()

        // Load GlobalKeywordConfig (use the latest version)
        let configDescriptor = FetchDescriptor<GlobalKeywordConfig>(
            sortBy: [SortDescriptor(\.version, order: .reverse)]
        )
        do {
            let configs = try modelContext.fetch(configDescriptor)
            if let latestConfig = configs.first {
                self.globalKeywordConfig = latestConfig
            } else {
                // Fallback: create default v1 if none exists
                let defaultConfig = GlobalKeywordConfig.createDefaultV1()
                modelContext.insert(defaultConfig)
                try modelContext.save()
                self.globalKeywordConfig = defaultConfig
            }
        } catch {
            // Critical failure: create v1 without saving
            self.globalKeywordConfig = GlobalKeywordConfig.createDefaultV1()
        }

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

        // Initialize services with local implementations (Iteration 1)
        // In Iteration 2, these can be swapped with backend implementations
        self.fileStorageService = LocalFileStorageService(cryptoService: cryptoService)
        self.ocrService = AppleVisionOCRService()

        // Pass keyword learning service and global config to parsing service
        // Using LayoutFirstInvoiceParser for anchor-based extraction (A3 architecture)
        self.documentAnalysisService = LayoutFirstInvoiceParser(
            keywordLearningService: keywordLearningService,
            globalKeywordConfig: globalKeywordConfig
        )

        self.calendarService = EventKitCalendarService()
        self.notificationService = LocalNotificationService()
        self.syncService = NoOpSyncService() // No-op for Iteration 1

        // Initialize recurring payment services
        self.vendorFingerprintService = VendorFingerprintService()
        self.documentClassifierService = DocumentClassifierService()

        // Template service needs modelContext
        let templateService = RecurringTemplateService(modelContext: modelContext)
        self.recurringTemplateService = templateService

        // Scheduler service needs modelContext, notification service, calendar service, and settings
        let schedulerService = RecurringSchedulerService(
            modelContext: modelContext,
            notificationService: notificationService,
            calendarService: calendarService,
            settingsManager: settingsManager
        )
        self.recurringSchedulerService = schedulerService

        // Matcher service needs modelContext, template service, and scheduler service
        self.recurringMatcherService = RecurringMatcherService(
            modelContext: modelContext,
            templateService: templateService,
            schedulerService: schedulerService
        )

        // Detection service needs modelContext, template service, and classifier service
        self.recurringDetectionService = RecurringDetectionService(
            modelContext: modelContext,
            templateService: templateService,
            classifierService: documentClassifierService
        )

        // Initialize tier-specific services
        switch tier {
        case .pro:
            // Pro tier - Firebase + cloud features (Phase 3)
            #if canImport(FirebaseAuth) && canImport(FirebaseFunctions)
            // Firebase SDK available - use real implementations
            let firebaseAuth = FirebaseAuthService()
            self.authService = firebaseAuth
            self.subscriptionService = FirebaseSubscriptionService(authService: firebaseAuth)

            // Create cloud gateway for OpenAI analysis
            let cloudGateway = FirebaseCloudExtractionGateway(authService: firebaseAuth)

            // Use hybrid router for intelligent local/cloud routing
            self.analysisRouter = HybridAnalysisRouter(
                localService: documentAnalysisService,
                cloudGateway: cloudGateway,
                settingsManager: settingsManager,
                config: .default
            )
            PrivacyLogger.app.info("AppEnvironment initialized for tier: Pro (Firebase active)")
            #else
            // Firebase SDK not available - fall back to no-op (development/testing)
            self.authService = NoOpAuthService()
            self.subscriptionService = NoOpSubscriptionService()
            self.analysisRouter = LocalOnlyAnalysisRouter(
                localService: documentAnalysisService
            )
            PrivacyLogger.app.warning("AppEnvironment initialized for tier: Pro (Firebase SDK not available, using local-only)")
            #endif

        case .free:
            // Free tier - all local, no cloud features
            self.authService = NoOpAuthService()
            self.subscriptionService = NoOpSubscriptionService()
            self.analysisRouter = LocalOnlyAnalysisRouter(
                localService: documentAnalysisService
            )
            PrivacyLogger.app.info("AppEnvironment initialized for tier: Free")
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

    /// Creates a FinalizeInvoiceUseCase with injected dependencies
    func makeFinalizeInvoiceUseCase() -> FinalizeInvoiceUseCase {
        FinalizeInvoiceUseCase(
            repository: documentRepository,
            calendarService: calendarService,
            notificationService: notificationService,
            settingsManager: settingsManager,
            vendorFingerprintService: vendorFingerprintService,
            classifierService: documentClassifierService
        )
    }

    /// Creates a MarkAsPaidUseCase with injected dependencies
    func makeMarkAsPaidUseCase() -> MarkAsPaidUseCase {
        MarkAsPaidUseCase(
            repository: documentRepository,
            notificationService: notificationService
        )
    }

    /// Creates a DeleteDocumentUseCase with injected dependencies
    func makeDeleteDocumentUseCase() -> DeleteDocumentUseCase {
        DeleteDocumentUseCase(
            repository: documentRepository,
            fileStorageService: fileStorageService,
            calendarService: calendarService,
            notificationService: notificationService
        )
    }

    /// Creates an UpdateDocumentUseCase with injected dependencies
    func makeUpdateDocumentUseCase() -> UpdateDocumentUseCase {
        UpdateDocumentUseCase(
            repository: documentRepository,
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
            classifierService: documentClassifierService
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
            schedulerService: recurringSchedulerService
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
            notificationService: notificationService,
            calendarService: calendarService
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
            calendarService: calendarService
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
            appTier: appTier
        )
    }

    // MARK: - Versioning and Migration

    /// Run vendor profile migrations on app startup
    /// Call this after AppEnvironment is initialized
    func runStartupMigrations() async throws {
        try await vendorMigrationService.migrateVendorsIfNeeded(to: globalKeywordConfig)

        // Backfill vendorFingerprint and documentCategory for existing documents
        try await backfillVendorFingerprints()
    }

    /// Get migration statistics for monitoring
    func getMigrationStats() throws -> MigrationStats {
        return try vendorMigrationService.getMigrationStats()
    }

    // MARK: - Vendor Fingerprint Backfill

    /// Backfills vendorFingerprint and documentCategory for existing documents that don't have them.
    /// This is a one-time migration to fix documents created before fingerprint support was added.
    /// Safe to call multiple times - only updates documents with nil fingerprint.
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

        logger.info("Backfilling vendorFingerprint for \(documentsToBackfill.count) documents")

        var backfilledCount = 0
        for document in documentsToBackfill {
            // Skip documents without a title (empty drafts)
            guard !document.title.isEmpty else {
                logger.debug("Skipping document \(document.id) - no title")
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
            logger.debug("Backfilled document: fingerprint=\(fingerprint.prefix(16))..., category=\(classification.category.rawValue)")
        }

        // Save changes
        try modelContext.save()
        logger.info("Successfully backfilled \(backfilledCount) documents with vendor fingerprints")
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

    /// Check if cloud features are available
    var hasCloudFeatures: Bool {
        appTier.hasCloudFeatures
    }

    /// Check if cloud analysis is currently available
    /// Requires: Pro tier + signed in + network
    var isCloudAnalysisAvailable: Bool {
        get async {
            guard hasCloudFeatures else { return false }
            return await analysisRouter.isCloudAvailable
        }
    }

    /// Current analysis mode based on tier and settings
    var currentAnalysisMode: AnalysisMode {
        analysisRouter.analysisMode
    }
}
