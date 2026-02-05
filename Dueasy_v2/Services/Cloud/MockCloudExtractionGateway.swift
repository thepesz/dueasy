import Foundation
import os

/// Mock cloud gateway for testing and development.
/// Simulates cloud analysis with realistic delays and high-confidence results.
///
/// Use cases:
/// - Unit and integration testing
/// - Development without Firebase credentials
/// - UI previews
///
/// Behavior:
/// - Simulates network delay (configurable)
/// - Returns mock results with high confidence
/// - Can be configured to simulate errors
final class MockCloudExtractionGateway: CloudExtractionGatewayProtocol {

    // MARK: - Configuration

    /// Simulated network delay for text analysis
    var textAnalysisDelay: Duration = .seconds(1)

    /// Whether to simulate being available
    var simulateAvailable: Bool = true

    /// Error to throw (if any) - for testing error handling
    var simulatedError: CloudExtractionError?

    /// Confidence level for mock results
    var mockConfidence: Double = 0.95

    // MARK: - Protocol Properties

    var isAvailable: Bool {
        get async { simulateAvailable }
    }

    var providerIdentifier: String { "mock-cloud" }

    // MARK: - Analysis Methods

    func analyzeText(
        ocrText: String,
        documentType: DocumentType,
        languageHints: [String],
        currencyHints: [String]
    ) async throws -> DocumentAnalysisResult {

        PrivacyLogger.parsing.info("MockCloudExtractionGateway: Analyzing text (\(ocrText.count) chars)")

        // Check for simulated error
        if let error = simulatedError {
            PrivacyLogger.parsing.warning("MockCloudExtractionGateway: Simulating error")
            throw error
        }

        // Simulate network delay
        try await Task.sleep(for: textAnalysisDelay)

        // Generate mock result
        return createMockResult(
            documentType: documentType,
            currency: currencyHints.first ?? "PLN"
        )
    }

    // MARK: - Mock Result Generation

    private func createMockResult(
        documentType: DocumentType,
        currency: String,
        confidenceBoost: Double = 0.0
    ) -> DocumentAnalysisResult {

        let baseConfidence = min(mockConfidence + confidenceBoost, 1.0)

        // Generate realistic mock data based on document type
        let (vendorName, amount, documentNumber) = mockDataForType(documentType)

        // Due date 30 days from now
        let dueDate = Calendar.current.date(
            byAdding: .day,
            value: 30,
            to: Date()
        )

        return DocumentAnalysisResult(
            documentType: documentType,
            vendorName: vendorName,
            vendorAddress: "ul. Testowa 123\n00-001 Warszawa",
            vendorNIP: "1234567890",
            vendorREGON: "123456789",
            amount: amount,
            currency: currency,
            dueDate: dueDate,
            documentNumber: documentNumber,
            bankAccountNumber: "PL61109010140000071219812874",
            suggestedAmounts: [(amount, "Total amount")],
            amountCandidates: nil,
            dateCandidates: nil,
            vendorCandidates: nil,
            nipCandidates: nil,
            bankAccountCandidates: nil,
            documentNumberCandidates: nil,
            vendorEvidence: nil,
            amountEvidence: nil,
            dueDateEvidence: nil,
            documentNumberEvidence: nil,
            nipEvidence: nil,
            bankAccountEvidence: nil,
            vendorExtractionMethod: .cloudAI,
            amountExtractionMethod: .cloudAI,
            dueDateExtractionMethod: .cloudAI,
            nipExtractionMethod: .cloudAI,
            overallConfidence: baseConfidence,
            fieldConfidences: FieldConfidences(
                vendorName: baseConfidence,
                amount: baseConfidence,
                dueDate: baseConfidence,
                documentNumber: baseConfidence,
                nip: baseConfidence,
                bankAccount: baseConfidence
            ),
            provider: providerIdentifier,
            version: 1,
            rawHints: nil,
            rawOCRText: nil
        )
    }

    private func mockDataForType(_ documentType: DocumentType) -> (vendor: String, amount: Decimal, docNumber: String) {
        switch documentType {
        case .invoice:
            return ("Mock Vendor Sp. z o.o.", Decimal(1234.56), "FV/2024/MOCK-001")
        case .contract:
            return ("Mock Contract Partner", Decimal(5000.00), "UMOWA/2024/001")
        case .receipt:
            return ("Mock Store", Decimal(99.99), "PAR/2024/001")
        }
    }
}

