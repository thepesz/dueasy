import Foundation
import SwiftData
import os

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
        // Use Europe region for GDPR compliance - functions deployed to europe-west1
        self.functions = Functions.functions(region: "europe-west1")
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
        let vendorREGON = dict["vendorREGON"] as? String
        let documentNumber = dict["documentNumber"] as? String
        let bankAccountNumber = dict["bankAccount"] as? String
        let currency = dict["currency"] as? String ?? "PLN"

        // Log what OpenAI returned for vendor
        PrivacyLogger.app.info("🏢 OpenAI vendor: name=\(vendorName ?? "nil", privacy: .public), address=\(vendorAddress ?? "nil", privacy: .public), NIP=\(vendorNIP ?? "nil", privacy: .public)")

        // Extract document type
        let documentTypeStr = dict["documentType"] as? String ?? "invoice"
        let documentType = DocumentType(rawValue: documentTypeStr) ?? .invoice

        // Parse amount
        var amount: Decimal?
        if let amountStr = dict["amount"] as? String {
            amount = Decimal(string: amountStr)
        } else if let amountDouble = dict["amount"] as? Double {
            amount = Decimal(amountDouble)
        }

        // Parse issue date (ISO 8601 format: YYYY-MM-DD)
        var issueDate: Date?
        if let issueDateStr = dict["issueDate"] as? String, !issueDateStr.isEmpty {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            issueDate = isoFormatter.date(from: issueDateStr)
        }

        // Parse due date (ISO 8601 format: YYYY-MM-DD)
        var dueDate: Date?
        if let dueDateStr = dict["dueDate"] as? String, !dueDateStr.isEmpty {
            PrivacyLogger.app.info("📅 OpenAI returned dueDate: \(dueDateStr, privacy: .public)")

            // Try ISO 8601 format first (YYYY-MM-DD)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            if let parsed = isoFormatter.date(from: dueDateStr) {
                dueDate = parsed
                PrivacyLogger.app.info("✅ Parsed dueDate successfully: \(parsed, privacy: .public)")
            } else {
                // Fallback: try standard date formatter with multiple formats
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")

                for format in ["yyyy-MM-dd", "dd-MM-yyyy", "dd.MM.yyyy", "yyyy/MM/dd"] {
                    dateFormatter.dateFormat = format
                    if let parsed = dateFormatter.date(from: dueDateStr) {
                        dueDate = parsed
                        PrivacyLogger.app.info("✅ Parsed dueDate with format \(format, privacy: .public): \(parsed, privacy: .public)")
                        break
                    }
                }

                if dueDate == nil {
                    PrivacyLogger.app.warning("⚠️ Failed to parse dueDate: \(dueDateStr, privacy: .public)")
                }
            }
        } else {
            PrivacyLogger.app.info("📅 OpenAI returned null/empty dueDate")
            // Fallback: If no due date, use issue date (invoice might be already paid)
            if let issueDate = issueDate {
                dueDate = issueDate
                PrivacyLogger.app.info("📅 Using issue date as due date fallback")
            }
        }

        // Extract candidate arrays from OpenAI
        let amountCandidatesArray = dict["amountCandidates"] as? [[String: Any]] ?? []
        let dateCandidatesArray = dict["dateCandidates"] as? [[String: Any]] ?? []
        let vendorCandidatesArray = dict["vendorCandidates"] as? [[String: Any]] ?? []
        let nipCandidatesArray = dict["nipCandidates"] as? [[String: Any]] ?? []

        // Build suggestedAmounts from OpenAI amount candidates (without provider text)
        var suggestedAmounts: [(Decimal, String)] = []
        for candidate in amountCandidatesArray {
            if let displayValue = candidate["displayValue"] as? String,
               let amount = Decimal(string: displayValue) {
                // Just use empty context - no provider/confidence text needed
                suggestedAmounts.append((amount, ""))
            }
        }

        // If no candidates but we have a main amount, add it
        if suggestedAmounts.isEmpty, let amount = amount {
            suggestedAmounts.append((amount, ""))
        }

        // Calculate field confidences from candidates
        let vendorConfidence = vendorCandidatesArray.first?["confidence"] as? Double ?? (vendorName != nil ? 0.95 : 0.0)
        let amountConfidence = amountCandidatesArray.first?["confidence"] as? Double ?? (amount != nil ? 0.95 : 0.0)
        let dateConfidence = dateCandidatesArray.first?["confidence"] as? Double ?? (dueDate != nil ? 0.95 : 0.0)
        let nipConfidence = nipCandidatesArray.first?["confidence"] as? Double ?? (vendorNIP != nil ? 0.95 : 0.0)

        let fieldConfidences = FieldConfidences(
            vendorName: vendorConfidence,
            amount: amountConfidence,
            dueDate: dateConfidence,
            documentNumber: documentNumber != nil ? 0.90 : 0.0,
            nip: nipConfidence,
            bankAccount: bankAccountNumber != nil ? 0.85 : 0.0
        )

        // Calculate overall confidence as average of non-zero field confidences
        let allConfidences = [vendorConfidence, amountConfidence, dateConfidence, nipConfidence]
            .filter { $0 > 0.0 }
        let overallConfidence = allConfidences.isEmpty ? 0.0 : allConfidences.reduce(0.0, +) / Double(allConfidences.count)

        return DocumentAnalysisResult(
            documentType: documentType,
            vendorName: vendorName,
            vendorAddress: vendorAddress,
            vendorNIP: vendorNIP,
            vendorREGON: vendorREGON,
            amount: amount,
            currency: currency,
            dueDate: dueDate,
            documentNumber: documentNumber,
            bankAccountNumber: bankAccountNumber,
            suggestedAmounts: suggestedAmounts,
            amountCandidates: nil, // Cloud AI doesn't provide full candidate structures
            dateCandidates: nil,
            vendorCandidates: nil,
            nipCandidates: nil,
            bankAccountCandidates: nil,
            documentNumberCandidates: nil,
            vendorEvidence: nil, // No bounding boxes from cloud AI
            amountEvidence: nil,
            dueDateEvidence: nil,
            documentNumberEvidence: nil,
            nipEvidence: nil,
            bankAccountEvidence: nil,
            vendorExtractionMethod: .cloudAI,
            amountExtractionMethod: .cloudAI,
            dueDateExtractionMethod: .cloudAI,
            nipExtractionMethod: .cloudAI,
            overallConfidence: overallConfidence,
            fieldConfidences: fieldConfidences,
            provider: "openai-gpt4o",
            version: 1,
            rawOCRText: nil
        )
    }
    #endif
}
