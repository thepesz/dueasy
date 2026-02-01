import Foundation
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

/// Firebase Cloud Functions gateway for OpenAI-powered document analysis
final class FirebaseCloudExtractionGateway: CloudExtractionGatewayProtocol {

    // MARK: - Properties

    #if canImport(FirebaseFunctions)
    private let functions: Functions
    #endif

    private let authService: AuthServiceProtocol

    // MARK: - Initialization

    init(authService: AuthServiceProtocol) {
        self.authService = authService
        #if canImport(FirebaseFunctions)
        self.functions = Functions.functions()
        // Use Europe region for GDPR compliance
        // self.functions.useEmulator(withHost: "localhost", port: 5001) // Development only
        #endif
    }

    // MARK: - CloudExtractionGatewayProtocol

    var providerIdentifier: String {
        return "openai-firebase"
    }

    var isAvailable: Bool {
        get async {
            #if canImport(FirebaseFunctions)
            return await authService.isSignedIn
            #else
            return false
            #endif
        }
    }

    func analyzeText(
        ocrText: String,
        documentType: DocumentType,
        languageHints: [String],
        currencyHints: [String]
    ) async throws -> DocumentAnalysisResult {
        #if canImport(FirebaseFunctions)
        guard await authService.isSignedIn else {
            throw CloudExtractionError.authenticationRequired
        }

        let payload: [String: Any] = [
            "ocrText": ocrText,
            "documentType": documentType.rawValue,
            "languageHints": languageHints,
            "currencyHints": currencyHints,
            "mode": "textOnly"
        ]

        let result = try await functions.httpsCallable("analyzeDocument").call(payload)
        return try parseAnalysisResult(from: result.data)
        #else
        throw AppError.featureUnavailable("Firebase SDK not available")
        #endif
    }

    func analyzeWithImages(
        ocrText: String?,
        croppedImages: [Data],
        documentType: DocumentType,
        languageHints: [String]
    ) async throws -> DocumentAnalysisResult {
        #if canImport(FirebaseFunctions)
        guard await authService.isSignedIn else {
            throw CloudExtractionError.authenticationRequired
        }

        // Convert images to base64
        let base64Images = croppedImages.map { $0.base64EncodedString() }

        let payload: [String: Any] = [
            "ocrText": ocrText as Any,
            "images": base64Images,
            "documentType": documentType.rawValue,
            "languageHints": languageHints,
            "mode": "withImages"
        ]

        let result = try await functions.httpsCallable("analyzeDocumentWithImages").call(payload)
        return try parseAnalysisResult(from: result.data)
        #else
        throw AppError.featureUnavailable("Firebase SDK not available")
        #endif
    }

    // MARK: - Private Helpers

    #if canImport(FirebaseFunctions)
    private func parseAnalysisResult(from data: Any) throws -> DocumentAnalysisResult {
        guard let dict = data as? [String: Any] else {
            throw CloudExtractionError.invalidResponse
        }

        // Extract main fields
        let vendorName = dict["vendorName"] as? String
        let vendorAddress = dict["vendorAddress"] as? String
        let vendorNIP = dict["vendorNIP"] as? String
        let documentNumber = dict["documentNumber"] as? String
        let bankAccount = dict["bankAccount"] as? String

        // Parse amount
        var amount: Decimal?
        if let amountStr = dict["amount"] as? String {
            amount = Decimal(string: amountStr)
        } else if let amountDouble = dict["amount"] as? Double {
            amount = Decimal(amountDouble)
        }

        // Parse dates
        var issueDate: Date?
        var dueDate: Date?
        if let issueDateStr = dict["issueDate"] as? String {
            issueDate = ISO8601DateFormatter().date(from: issueDateStr)
        }
        if let dueDateStr = dict["dueDate"] as? String {
            dueDate = ISO8601DateFormatter().date(from: dueDateStr)
        }

        // Parse candidates (alternatives)
        let vendorCandidates = parseCandidates(from: dict["vendorCandidates"])
        let nipCandidates = parseCandidates(from: dict["nipCandidates"])
        let amountCandidates = parseCandidates(from: dict["amountCandidates"])
        let dateCandidates = parseCandidates(from: dict["dateCandidates"])
        let documentNumberCandidates = parseCandidates(from: dict["documentNumberCandidates"])
        let bankAccountCandidates = parseCandidates(from: dict["bankAccountCandidates"])

        return DocumentAnalysisResult(
            vendorName: vendorName,
            vendorAddress: vendorAddress,
            vendorNIP: vendorNIP,
            amount: amount,
            issueDate: issueDate,
            dueDate: dueDate,
            documentNumber: documentNumber,
            bankAccount: bankAccount,
            vendorCandidates: vendorCandidates,
            nipCandidates: nipCandidates,
            amountCandidates: amountCandidates,
            dateCandidates: dateCandidates,
            documentNumberCandidates: documentNumberCandidates,
            bankAccountCandidates: bankAccountCandidates
        )
    }

    private func parseCandidates(from value: Any?) -> [CandidateData] {
        guard let array = value as? [[String: Any]] else { return [] }

        return array.compactMap { dict in
            guard let displayValue = dict["displayValue"] as? String,
                  let confidence = dict["confidence"] as? Double else {
                return nil
            }

            let extractionMethod = (dict["extractionMethod"] as? String).flatMap { CandidateData.ExtractionMethod(rawValue: $0) } ?? .cloudAI

            // Parse evidence bounding box if present
            var evidenceBBox: BoundingBox?
            if let bboxDict = dict["evidenceBBox"] as? [String: Double],
               let x = bboxDict["x"],
               let y = bboxDict["y"],
               let width = bboxDict["width"],
               let height = bboxDict["height"] {
                evidenceBBox = BoundingBox(x: x, y: y, width: width, height: height)
            }

            return CandidateData(
                displayValue: displayValue,
                confidence: confidence,
                extractionMethod: extractionMethod,
                evidenceBBox: evidenceBBox
            )
        }
    }
    #endif
}
