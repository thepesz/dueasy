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
        CreateDocumentUseCase(repository: documentRepository)
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
            settingsManager: settingsManager
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
            notificationService: notificationService
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

    // MARK: - Versioning and Migration

    /// Run vendor profile migrations on app startup
    /// Call this after AppEnvironment is initialized
    func runStartupMigrations() async throws {
        try await vendorMigrationService.migrateVendorsIfNeeded(to: globalKeywordConfig)
    }

    /// Get migration statistics for monitoring
    func getMigrationStats() throws -> MigrationStats {
        return try vendorMigrationService.getMigrationStats()
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
