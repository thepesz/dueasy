import Foundation
import os

/// Local heuristic-based invoice parsing service.
/// Extracts dates, amounts, and vendor names from OCR text.
/// Supports Polish and English invoice formats with 90%+ detection accuracy.
/// Handles OCR misreads, diacritics variations, and regional formats.
/// Includes adaptive learning from user corrections.
///
/// ## Privacy and OCR Text Handling
///
/// This service processes OCR text transiently during analysis:
/// - OCR text is received, parsed, and results returned in `DocumentAnalysisResult`
/// - The `rawOCRText` field is passed through for keyword learning (NOT persisted)
/// - Only extracted field values are stored in `FinanceDocument`
/// - Only keyword patterns (not raw text) are saved in learning data
///
/// **PRIVACY**: Uses PrivacyLogger to ensure no PII (vendor names, amounts, dates,
/// addresses, NIP numbers) is ever logged. Only metrics are logged.
final class LocalInvoiceParsingService: DocumentAnalysisServiceProtocol, @unchecked Sendable {
    private let keywordLearningService: KeywordLearningService?
    private let globalKeywordConfig: GlobalKeywordConfig

    /// Optional vendor profile for vendor-specific keyword scoring
    /// Set this before calling analyzeDocument to use vendor keywords
    var vendorProfile: VendorProfileV2?

    // MARK: - Initialization

    init(keywordLearningService: KeywordLearningService? = nil, globalKeywordConfig: GlobalKeywordConfig) {
        self.keywordLearningService = keywordLearningService
        self.globalKeywordConfig = globalKeywordConfig
        if keywordLearningService != nil {
            PrivacyLogger.parsing.info("LocalInvoiceParsingService initialized with keyword learning enabled")
        }
    }

    // MARK: - DocumentAnalysisServiceProtocol

    var providerIdentifier: String { "local" }
    var analysisVersion: Int { 5 } // Bumped for 2-pass OCR confidence support
    var supportsVisionAnalysis: Bool { false }

    func analyzeDocument(
        text: String,
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {
        guard !text.isEmpty else {
            PrivacyLogger.parsing.warning("Empty text provided for analysis")
            return .empty
        }

        // PRIVACY: Log metrics only, not actual text content
        PrivacyLogger.logAnalysisStart(documentType: documentType.rawValue, textLength: text.count, lineCount: 0)

        switch documentType {
        case .invoice:
            return parseInvoice(text: text, lineData: nil)
        case .contract, .receipt:
            // Not implemented in MVP
            return DocumentAnalysisResult(
                documentType: documentType,
                overallConfidence: 0.0,
                provider: providerIdentifier,
                version: analysisVersion
            )
        }
    }

    /// Analyze document using OCRResult with line data for confidence-weighted scoring.
    /// This method uses per-line OCR confidence to improve extraction accuracy.
    func analyzeDocument(
        ocrResult: OCRResult,
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {
        guard ocrResult.hasText else {
            PrivacyLogger.parsing.warning("Empty OCR result provided for analysis")
            return .empty
        }

        let lineData = ocrResult.lineData ?? []
        let hasLineData = !lineData.isEmpty

        // PRIVACY: Log metrics only, not actual content
        PrivacyLogger.logAnalysisStart(documentType: documentType.rawValue, textLength: ocrResult.text.count, lineCount: lineData.count)

        if hasLineData {
            // PRIVACY: Log source and confidence distribution metrics only
            let standardCount = lineData.filter { $0.source == .standard }.count
            let sensitiveCount = lineData.filter { $0.source == .sensitive }.count
            let mergedCount = lineData.filter { $0.source == .merged }.count
            PrivacyLogger.parsing.debug("Line sources: standard=\(standardCount), sensitive=\(sensitiveCount), merged=\(mergedCount)")

            let highConf = lineData.filter { $0.hasHighConfidence }.count
            let medConf = lineData.filter { $0.hasMediumConfidence }.count
            let lowConf = lineData.filter { $0.hasLowConfidence }.count
            PrivacyLogger.parsing.debug("Confidence distribution: high=\(highConf), medium=\(medConf), low=\(lowConf)")
        }

        switch documentType {
        case .invoice:
            return parseInvoice(text: ocrResult.text, lineData: hasLineData ? lineData : nil)
        case .contract, .receipt:
            return DocumentAnalysisResult(
                documentType: documentType,
                overallConfidence: 0.0,
                provider: providerIdentifier,
                version: analysisVersion
            )
        }
    }

    // MARK: - Invoice Parsing

    /// Parse invoice from text with optional OCR line data for confidence-weighted scoring.
    /// - Parameters:
    ///   - text: Full OCR text
    ///   - lineData: Optional array of OCRLineData with per-line confidence
    /// - Returns: Structured analysis result with extracted fields
    private func parseInvoice(text: String, lineData: [OCRLineData]?) -> DocumentAnalysisResult {
        let lines = text.components(separatedBy: .newlines)
        let normalizedText = text.lowercased()

        // PRIVACY: Log metrics only, never log actual text content
        PrivacyLogger.parsing.debug("Parsing invoice with \(lines.count) lines, lineData: \(lineData?.count ?? 0) entries")

        // Store raw text for keyword learning (not persisted, used only during session)
        let rawOCRText = text

        // Extract fields
        let vendorName = extractVendorName(from: lines, fullText: text)
        let vendorAddress = extractVendorAddress(from: lines, fullText: text)
        let vendorNIP = extractNIP(from: text)
        let vendorREGON = extractREGON(from: text)

        // Extract amounts with OCR confidence if lineData available
        let allAmounts: [InternalAmountCandidate]
        if let lineData = lineData, !lineData.isEmpty {
            allAmounts = extractAllAmounts(from: text, lineData: lineData)
            PrivacyLogger.parsing.info("Amount extraction used \(lineData.count) OCR line entries for confidence scoring")
        } else {
            allAmounts = extractAllAmounts(from: text)
        }
        let amount = allAmounts.first?.value

        let currency = extractCurrency(from: text)
        let dueDate = extractDueDate(from: text, normalizedText: normalizedText)
        let invoiceNumber = extractInvoiceNumber(from: text)
        let bankAccountNumber = extractBankAccountNumber(from: text)

        // Convert amount candidates to suggested amounts for UI
        let suggestedAmounts: [(Decimal, String)] = allAmounts.map { candidate in
            // Create a user-friendly description
            let shortContext = candidate.context.count > 50
                ? String(candidate.context.prefix(50)) + "..."
                : candidate.context
            return (candidate.value, shortContext)
        }

        // Convert internal candidates to learning format
        let amountCandidatesForLearning: [AmountCandidate] = allAmounts.map { candidate in
            return AmountCandidate(
                value: candidate.value,
                currencyHint: currency,
                lineText: candidate.context,
                lineBBox: BoundingBox(x: 0, y: 0, width: 0, height: 0), // Placeholder
                nearbyKeywords: candidate.matchedKeywords,
                matchedPattern: candidate.description,
                confidence: Double(candidate.score) / 100.0, // Use score for learning
                context: candidate.context
            )
        }

        // Calculate confidence based on what was found
        var fieldsFound = 0

        // PRIVACY: Count fields without logging actual values
        if vendorName != nil { fieldsFound += 1 }
        if amount != nil { fieldsFound += 1 }
        if dueDate != nil { fieldsFound += 1 }
        if invoiceNumber != nil { fieldsFound += 1 }

        let confidence = Double(fieldsFound) / 4.0

        // PRIVACY: Log only metrics - field count, confidence, candidate counts
        PrivacyLogger.logParsingMetrics(fieldsFound: fieldsFound, totalFields: 4, confidence: confidence)
        PrivacyLogger.parsing.debug("Candidates: amounts=\(allAmounts.count), vendor=\(vendorName != nil ? 1 : 0), nip=\(vendorNIP != nil ? 1 : 0)")

        return DocumentAnalysisResult(
            documentType: .invoice,
            vendorName: vendorName,
            vendorAddress: vendorAddress,
            vendorNIP: vendorNIP,
            vendorREGON: vendorREGON,
            amount: amount,
            currency: currency ?? "PLN",
            dueDate: dueDate,
            documentNumber: invoiceNumber,
            bankAccountNumber: bankAccountNumber,
            suggestedAmounts: suggestedAmounts,
            amountCandidates: amountCandidatesForLearning,
            dateCandidates: nil, // TODO: Extract date candidates
            vendorCandidates: nil, // TODO: Extract vendor candidates
            overallConfidence: confidence,
            fieldConfidences: FieldConfidences(
                vendorName: vendorName != nil ? 0.7 : nil,
                amount: amount != nil ? 0.8 : nil,
                dueDate: dueDate != nil ? 0.7 : nil,
                documentNumber: invoiceNumber != nil ? 0.8 : nil
            ),
            provider: providerIdentifier,
            version: analysisVersion,
            rawHints: nil,
            rawOCRText: rawOCRText // Provide raw text for keyword learning
        )
    }

    // MARK: - Vendor Name Extraction

    private func extractVendorName(from lines: [String], fullText: String) -> String? {
        let normalizedText = fullText.lowercased()

        // CRITICAL: Isolate the vendor section to avoid picking up buyer information
        // Polish invoices have "Sprzedawca" (seller/vendor) and "Nabywca/Kupujący" (buyer)
        // We must only search in the Sprzedawca section
        let vendorSectionText = extractVendorSection(from: fullText)
        let searchText = vendorSectionText ?? fullText
        // PRIVACY: Log only metrics (character count), never actual text
        PrivacyLogger.parsing.debug("Vendor extraction: search text \(searchText.count) chars, isolated=\(vendorSectionText != nil)")

        // Strategy 1: Look for labeled vendor information (Polish and English) - HIGHEST PRIORITY
        // These are explicit labels that definitively identify the vendor
        // EXPANDED: Added kontrahent, podatnik, nazwa, wystawca faktury, etc.
        let vendorLabelPatterns: [(pattern: String, captureGroup: Int, description: String)] = [
            // Polish patterns - seller/issuer labels (these identify the VENDOR)
            (#"sprzedawca[:\s]+([A-Za-ząćęłńóśźżĄĆĘŁŃÓŚŹŻ0-9\s\-\.\,]+?)(?:\n|NIP|nip|Adres|adres|ul\.|$)"#, 1, "Sprzedawca label"),
            (#"wystawca(?:\s*faktury)?[:\s]+([A-Za-ząćęłńóśźżĄĆĘŁŃÓŚŹŻ0-9\s\-\.\,]+?)(?:\n|NIP|nip|Adres|adres|ul\.|$)"#, 1, "Wystawca label"),
            (#"dostawca[:\s]+([A-Za-ząćęłńóśźżĄĆĘŁŃÓŚŹŻ0-9\s\-\.\,]+?)(?:\n|NIP|nip|Adres|adres|ul\.|$)"#, 1, "Dostawca label"),
            (#"us[lł]ugodawca[:\s]+([A-Za-ząćęłńóśźżĄĆĘŁŃÓŚŹŻ0-9\s\-\.\,]+?)(?:\n|NIP|nip|Adres|adres|ul\.|$)"#, 1, "Uslugodawca label"),
            // kontrahent can be either party - check context
            (#"kontrahent[:\s]+([A-Za-ząćęłńóśźżĄĆĘŁŃÓŚŹŻ0-9\s\-\.\,]+?)(?:\n|NIP|nip|Adres|adres|ul\.|$)"#, 1, "Kontrahent label"),
            // Nazwa firmy patterns
            (#"nazwa\s*(?:firmy|sprzedawcy|dostawcy|wystawcy)[:\s]+([^\n]{3,60})"#, 1, "Nazwa firmy label"),
            (#"nazwa[:\s]+([A-Za-ząćęłńóśźżĄĆĘŁŃÓŚŹŻ][^\n]{3,60})"#, 1, "Nazwa label"),
            // Podatnik (taxpayer) - often the seller
            (#"podatnik[:\s]+([A-Za-ząćęłńóśźżĄĆĘŁŃÓŚŹŻ0-9\s\-\.\,]+?)(?:\n|NIP|nip|Adres|adres|ul\.|$)"#, 1, "Podatnik label"),
            // English patterns
            (#"(?:vendor|seller|supplier|provider)[:\s]+([^\n]{3,60})"#, 1, "Vendor/Seller label"),
            (#"(?:billed\s*by|from|issued\s*by)[:\s]+([^\n]{3,60})"#, 1, "Billed by label"),
            (#"(?:service\s*provider|merchant)[:\s]+([^\n]{3,60})"#, 1, "Service provider label"),
        ]

        for (pattern, captureGroup, description) in vendorLabelPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(searchText.startIndex..., in: searchText)
                if let match = regex.firstMatch(in: searchText, options: [], range: range) {
                    if let valueRange = Range(match.range(at: captureGroup), in: searchText) {
                        let value = String(searchText[valueRange])
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                            .trimmingCharacters(in: .whitespaces)
                        // PRIVACY: Don't log actual vendor name (PII)
                        PrivacyLogger.parsing.debug("Checking labeled vendor candidate (\(description)): length=\(value.count)")

                        // CRITICAL FIX: If captured value is too short or invalid, look at next lines
                        // This handles OCR fragments like "ine" before "ORLEN S.A."
                        // But still allows legitimate short names like "O2", "ING", "PKO"
                        if isValidVendorName(value) && !isBankName(value) {
                            // PRIVACY: Don't log vendor name
                            PrivacyLogger.parsing.info("SELECTED VENDOR via \(description) (name hidden for privacy)")
                            return cleanVendorName(value)
                        } else if value.count < 5 || !isValidVendorName(value) {
                            // Short or invalid - try next few lines after the label
                            PrivacyLogger.parsing.debug("Vendor too short/invalid (length=\(value.count)), checking next lines...")
                            if let vendorFromNextLines = findVendorInNextLines(after: match.range, in: searchText, lines: lines) {
                                // PRIVACY: Don't log vendor name
                                PrivacyLogger.parsing.info("SELECTED VENDOR from next line after \(description) (name hidden for privacy)")
                                return vendorFromNextLines
                            }
                        }
                    }
                }
            }
        }

        // Strategy 2: Look for company name patterns (Sp. z o.o., S.A., Ltd, etc.)
        // EXPANDED: Added sp z oo, sp zoo, s.k.a., P.P.H., F.H.U., etc.
        let companyPatterns = [
            // Polish company types - with and without dots/spaces
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]+(?:Sp\.\s*z\s*o\.?\s*o\.?|SP\.\s*Z\s*O\.?\s*O\.?))"#, "Sp. z o.o."),
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]+(?:sp\s*z\s*oo|sp\s*zoo|spzoo))"#, "sp z oo/sp zoo"),
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]+(?:S\.A\.|s\.a\.|SA))"#, "S.A."),
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]+(?:s\.k\.a\.|S\.K\.A\.|ska))"#, "s.k.a."),
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]+(?:sp\.\s*j\.|Sp\.\s*j\.|spj))"#, "sp. j."),
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]+(?:sp\.\s*k\.|Sp\.\s*k\.|spk))"#, "sp. k."),
            // Polish business abbreviations
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]*(?:P\.P\.H\.|PPH|P\.H\.U\.|PHU))"#, "P.P.H./P.H.U."),
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]*(?:F\.H\.U\.|FHU|F\.H\.|FH))"#, "F.H.U./F.H."),
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]*(?:P\.P\.U\.H\.|PPUH|P\.U\.H\.|PUH))"#, "P.P.U.H./P.U.H."),
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]*(?:Z\.P\.H\.|ZPH))"#, "Z.P.H."),
            // Spolka variations (with/without diacritics)
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s]+(?:SPÓŁKA|spółka|SPOLKA|spolka))"#, "SPOLKA"),
            // International company types
            (#"([A-Z][A-Za-z\s\-\.]+(?:Ltd\.?|LLC|Inc\.?|GmbH|Corp\.?|Co\.?))"#, "Ltd/LLC/Inc/GmbH"),
            (#"([A-Z][A-Za-z\s\-\.]+(?:Limited|Incorporated|Corporation))"#, "Limited/Incorporated"),
        ]

        for (pattern, description) in companyPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(searchText.startIndex..., in: searchText)
                if let match = regex.firstMatch(in: searchText, options: [], range: range) {
                    if let valueRange = Range(match.range(at: 1), in: searchText) {
                        let value = String(searchText[valueRange]).trimmingCharacters(in: .whitespaces)
                        // PRIVACY: Don't log actual vendor name
                        PrivacyLogger.parsing.debug("Checking company pattern candidate (\(description)): length=\(value.count)")
                        // CRITICAL: Skip bank names
                        if isValidVendorName(value) && !isBankName(value) {
                            PrivacyLogger.parsing.info("SELECTED VENDOR via company pattern (\(description)) (name hidden for privacy)")
                            return cleanVendorName(value)
                        } else {
                            PrivacyLogger.parsing.debug("Rejected: isValidVendorName=\(self.isValidVendorName(value)), isBankName=\(self.isBankName(value))")
                        }
                    }
                }
            }
        }

        // Strategy 3: Look for NIP (Polish tax ID) and get the line before or after
        if let nipRange = normalizedText.range(of: #"nip[:\s]*\d"#, options: .regularExpression) {
            let nipIndex = normalizedText.distance(from: normalizedText.startIndex, to: nipRange.lowerBound)
            // Find which line contains NIP
            var currentIndex = 0
            for (index, line) in lines.enumerated() {
                if currentIndex <= nipIndex && currentIndex + line.count >= nipIndex {
                    // Check line before NIP line
                    if index > 0 {
                        let prevLine = lines[index - 1].trimmingCharacters(in: .whitespaces)
                        // PRIVACY: Don't log actual line content
                        PrivacyLogger.parsing.debug("Checking line before NIP: length=\(prevLine.count)")
                        if isValidVendorName(prevLine) && !prevLine.lowercased().contains("nip") && !isBankName(prevLine) {
                            PrivacyLogger.parsing.info("SELECTED VENDOR before NIP line (name hidden for privacy)")
                            return cleanVendorName(prevLine)
                        }
                    }
                    break
                }
                currentIndex += line.count + 1 // +1 for newline
            }
        }

        // Strategy 4: Heuristic - First reasonable-looking company name in top portion
        for line in lines.prefix(15) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            guard !trimmed.isEmpty else { continue }

            // Skip common header words
            let lowercased = trimmed.lowercased()
            let skipWords = ["faktura", "invoice", "rachunek", "receipt", "paragon",
                            "data", "date", "nip", "regon", "krs", "konto", "bank",
                            "nr", "no.", "numer", "number", "sprzedawca", "nabywca",
                            "buyer", "seller", "adres", "address", "tel", "email",
                            "www", "http", "vat", "brutto", "netto", "suma", "total",
                            "odbiorca", "płatnik", "platnik", "kontrahent"]

            if skipWords.contains(where: { lowercased.hasPrefix($0) }) { continue }

            // Skip lines that are dates, amounts, or too short
            if looksLikeDate(trimmed) || looksLikeAmount(trimmed) { continue }
            if trimmed.count < 4 { continue }

            // Skip lines that are mostly numbers
            let digitCount = trimmed.filter { $0.isNumber }.count
            if Double(digitCount) / Double(trimmed.count) > 0.5 { continue }

            // This might be a vendor name
            if isValidVendorName(trimmed) && !isBankName(trimmed) {
                // PRIVACY: Don't log actual vendor name
                PrivacyLogger.parsing.info("SELECTED VENDOR via heuristic (name hidden for privacy)")
                return cleanVendorName(trimmed)
            }
        }

        PrivacyLogger.parsing.warning("=== NO VENDOR FOUND ===")
        return nil
    }

    /// Check if the name is a bank name (should be excluded from vendor detection)
    /// EXPANDED: More comprehensive bank list for Polish market
    private func isBankName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        let bankKeywords = [
            // Major Polish banks
            "bank", "pko", "pekao", "santander", "ing", "mbank", "bnp paribas",
            "credit agricole", "alior", "millennium", "getin", "nest", "citi",
            "bph", "bgk", "bos", "bre bank", "eurobank", "raiffeisen", "toyota bank",
            "plus bank", "idea bank", "nest bank", "t-mobile uslugi bankowe",
            // International banks
            "deutsche", "hsbc", "barclays", "revolut", "n26", "wise", "transferwise",
            "paypal", "payoneer", "stripe",
            // Credit unions
            "skok", "kasa", "spoldzielcz"
        ]
        return bankKeywords.contains { lowercased.contains($0) }
    }

    /// Extracts only the vendor/seller section from the invoice text
    /// This prevents mixing up vendor data with buyer data
    private func extractVendorSection(from text: String) -> String? {
        let lowercased = text.lowercased()

        // Find buyer section start (Nabywca, Kupujący, Buyer, Customer, etc.)
        let buyerPatterns = [
            "nabywca", "kupuj", "odbiorca", "klient",
            "buyer", "customer", "purchaser", "client", "bill to", "sold to"
        ]

        var buyerStartIndex: String.Index?
        for pattern in buyerPatterns {
            if let range = lowercased.range(of: pattern) {
                if buyerStartIndex == nil || range.lowerBound < buyerStartIndex! {
                    buyerStartIndex = range.lowerBound
                }
            }
        }

        // Find seller section start (Sprzedawca, Wystawca, Dostawca, Vendor, Seller, etc.)
        let sellerPatterns = [
            "sprzedawca", "wystawca", "dostawca", "us[lł]ugodawca",
            "vendor", "seller", "supplier", "provider", "from:", "billed by"
        ]

        var sellerStartIndex: String.Index?
        for pattern in sellerPatterns {
            if let range = lowercased.range(of: pattern, options: .regularExpression) {
                if sellerStartIndex == nil || range.lowerBound < sellerStartIndex! {
                    sellerStartIndex = range.lowerBound
                }
            }
        }

        // Determine the vendor section boundaries
        if let sellerStart = sellerStartIndex {
            // Found seller label
            if let buyerStart = buyerStartIndex, buyerStart > sellerStart {
                // Seller comes before buyer - extract text between them
                let vendorSection = String(text[sellerStart..<buyerStart])
                PrivacyLogger.parsing.debug("Extracted vendor section between seller and buyer labels (\(vendorSection.count) chars)")
                return vendorSection
            } else {
                // No buyer or buyer comes before seller - take from seller to end (or first 1000 chars)
                let endIndex = text.index(sellerStart, offsetBy: min(1000, text.distance(from: sellerStart, to: text.endIndex)))
                let vendorSection = String(text[sellerStart..<endIndex])
                PrivacyLogger.parsing.debug("Extracted vendor section from seller label (\(vendorSection.count) chars)")
                return vendorSection
            }
        } else if let buyerStart = buyerStartIndex {
            // No seller label found, but buyer label exists
            // Take everything before buyer section (this is likely the vendor area)
            let vendorSection = String(text[..<buyerStart])
            PrivacyLogger.parsing.debug("Extracted vendor section before buyer label (\(vendorSection.count) chars)")
            return vendorSection
        }

        // No section markers found - return nil to search full text
        PrivacyLogger.parsing.debug("No vendor/buyer section markers found")
        return nil
    }

    /// Helper to find vendor in the next few lines after a label match
    /// Used when the immediate match is too short or invalid (OCR fragments)
    private func findVendorInNextLines(after matchRange: NSRange, in text: String, lines: [String]) -> String? {
        // Find which line the match ends on
        let matchEnd = matchRange.location + matchRange.length
        var currentPos = 0
        var matchLineIndex = 0

        for (index, line) in lines.enumerated() {
            currentPos += line.count + 1 // +1 for newline
            if currentPos > matchEnd {
                matchLineIndex = index
                break
            }
        }

        // Check next 3 lines after the match
        let startLine = matchLineIndex + 1
        let endLine = min(startLine + 3, lines.count)

        for lineIndex in startLine..<endLine {
            let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)

            // Skip very short lines (likely fragments)
            guard line.count >= 3 else { continue }

            // Skip lines that look like addresses, NIPs, etc.
            let lowercased = line.lowercased()
            if lowercased.hasPrefix("nip") || lowercased.hasPrefix("ul.") ||
               lowercased.hasPrefix("adres") || lowercased.contains("@") {
                continue
            }

            // Check if this line is a valid vendor name
            if isValidVendorName(line) && !isBankName(line) {
                return cleanVendorName(line)
            }
        }

        return nil
    }

    private func isValidVendorName(_ name: String) -> Bool {
        // NOTE: Minimum is 3 to allow short legitimate names like "O2", "ING", "PKO"
        // We handle OCR fragments via findVendorInNextLines instead
        // Must be between 3 and 100 characters
        guard name.count >= 3 && name.count <= 100 else { return false }

        // Must contain at least one letter
        guard name.contains(where: { $0.isLetter }) else { return false }

        // Should not be pure numbers
        let letterCount = name.filter { $0.isLetter }.count
        guard Double(letterCount) / Double(name.count) > 0.3 else { return false }

        // Should not contain certain patterns that indicate non-vendor text
        let invalidPatterns = ["faktura vat", "invoice", "paragon", "rachunek", "nota"]
        let lowercased = name.lowercased()
        for pattern in invalidPatterns {
            if lowercased == pattern { return false }
        }

        return true
    }

    private func cleanVendorName(_ name: String) -> String {
        var cleaned = name
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":-"))
            .trimmingCharacters(in: .whitespaces)

        // Remove common prefixes
        let prefixes = ["sprzedawca", "wystawca", "dostawca", "vendor", "seller", "from",
                       "nazwa", "firma", "kontrahent", "podatnik", "uslugodawca"]
        for prefix in prefixes {
            if cleaned.lowercased().hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ":-"))
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        return cleaned
    }

    // MARK: - Amount Extraction

    /// Extracted amount with context and scoring for intelligent selection
    struct InternalAmountCandidate: Sendable {
        let value: Decimal
        let confidence: Int          // Original pattern-based confidence
        let score: Int                // Semantic score based on keywords (includes OCR confidence adjustment)
        let context: String           // Surrounding text
        let description: String       // Pattern that matched
        let lineIndex: Int           // Position in document (for tie-breaking)
        let matchedKeywords: [String] // Keywords found in context (for learning)
        let ocrConfidence: Double    // OCR confidence for this line (0.0-1.0)

        /// Initialize with default OCR confidence (for text-only parsing)
        init(value: Decimal, confidence: Int, score: Int, context: String, description: String, lineIndex: Int, matchedKeywords: [String], ocrConfidence: Double = 1.0) {
            self.value = value
            self.confidence = confidence
            self.score = score
            self.context = context
            self.description = description
            self.lineIndex = lineIndex
            self.matchedKeywords = matchedKeywords
            self.ocrConfidence = ocrConfidence
        }
    }

    // MARK: - OCR Confidence Scoring

    /// Apply OCR confidence adjustment to a score.
    /// - High confidence (>0.9): +20 bonus
    /// - Medium confidence (0.7-0.9): no change
    /// - Low confidence (<0.7): -30 penalty
    private func applyOCRConfidenceAdjustment(baseScore: Int, ocrConfidence: Double) -> Int {
        if ocrConfidence > 0.9 {
            // High confidence: boost score
            return baseScore + 20
        } else if ocrConfidence >= 0.7 {
            // Medium confidence: neutral
            return baseScore
        } else {
            // Low confidence: penalize score
            return baseScore - 30
        }
    }

    /// Find the OCR line data that contains the given match position.
    /// Returns the OCRLineData and its confidence, or nil if not found.
    private func findMatchingLineData(
        for matchRange: NSRange,
        in text: String,
        lineData: [OCRLineData]
    ) -> OCRLineData? {
        // Convert match position to a rough line index
        let lines = text.components(separatedBy: .newlines)
        var currentPos = 0
        var matchLineIndex = 0

        for (index, line) in lines.enumerated() {
            let lineLength = line.count + 1 // +1 for newline
            if currentPos <= matchRange.location && currentPos + lineLength > matchRange.location {
                matchLineIndex = index
                break
            }
            currentPos += lineLength
        }

        // Find the OCRLineData for this line index
        // LineData is sorted by position, so we look for matching Y position
        // Since Vision uses bottom-left origin, higher Y = higher on page
        let targetY = 1.0 - (Double(matchLineIndex) / Double(max(1, lines.count)))

        // Find closest matching line by Y position (within 5% tolerance)
        return lineData.first { lineItem in
            abs(lineItem.bbox.centerY - targetY) < 0.05
        }
    }

    /// Extract all amounts from text, returning them sorted by confidence
    /// First element is the recommended amount
    /// EXPANDED: Comprehensive Polish invoice keywords for 90%+ accuracy
    /// ADAPTIVE: Uses learned keywords from user corrections
    func extractAllAmounts(from text: String) -> [InternalAmountCandidate] {
        PrivacyLogger.parsing.info("=== AMOUNT EXTRACTION START ===")
        PrivacyLogger.parsing.debug("Text length: \(text.count) chars")

        let lines = text.components(separatedBy: .newlines)

        // Load learned keywords from keyword learning service
        var learnedAmountKeywords: [String] = []
        if let learningService = keywordLearningService {
            let learned = learningService.getLearnedKeywords(for: .amount)
            learnedAmountKeywords = learned.map { $0.keyword }
            if !learned.isEmpty {
                PrivacyLogger.parsing.info("Using \(learned.count) learned amount keywords")
            }
        }

        // ========================================
        // DEFINITIVE PAYMENT KEYWORDS - HIGHEST PRIORITY (300-400 confidence boost)
        // These are the final amounts that should be paid
        // ========================================
        let definitivePaymentKeywords = [
            // English - telecom/utility invoices (CRITICAL - user feedback)
            "current account amount payable",
            "amount payable",
            "total amount payable",
            "amount due",
            "total due",
            "balance due",
            "pay this amount",
            "payment amount",
            "outstanding balance",
            "total to pay",
            // Polish - definitive payment terms
            "kwota do zapłaty na rachunek bieżący",
            "kwota do zapłaty na rachunek",
            "saldo do zapłaty",
            "rachunek bieżący",
            "kwota do zapłaty",
            "do zapłaty",
            "do zapłacenia",        // Alternative form
            "do zaplaty",           // Without diacritics
            "do zapłacenia",
            "do zaplecenia",        // OCR misread
            "należność do zapłaty",
            "naleznosc do zaplaty",
            "należność ogółem",     // Total amount due
            "naleznosc ogolem",
            "końcowa kwota",        // Final amount
            "koncowa kwota",
            "w tym do zapłaty",     // Including to pay
        ]

        // ========================================
        // POLISH TOTAL KEYWORDS - HIGH PRIORITY (100-200 confidence boost)
        // ========================================
        let polishTotalKeywords = [
            // Payment-related
            "do zapłaty", "do zaplaty", "do zapłaty:",
            "do zapłacenia", "do zaplecenia",
            "płatne", "platne",                     // Payable
            "należność płatna", "naleznosc platna",
            // Totals and sums
            "razem do zapłaty", "razem do zaplaty",
            "suma do zapłaty", "suma do zaplaty",
            "wartość brutto", "wartosc brutto",
            "kwota brutto", "kwota do zapłaty",
            "razem brutto", "ogółem brutto", "ogolem brutto",
            "należność", "naleznosc",
            "suma", "razem", "total", "ogółem", "ogolem",
            "brutto", "gross",
            // Invoice value
            "wartość faktury", "wartosc faktury",   // Invoice value
            "fakturowana kwota",                    // Invoiced amount
            // Telecom/utility specific
            "opłata", "oplata",                     // Fee/charge
            "abonament",                            // Subscription
            "rachunek za",                          // Bill for
            "należność za", "naleznosc za",         // Amount due for
            // VAT related
            "kwota vat", "podatek vat",
            "wartość z vat", "wartosc z vat",
        ]

        // ========================================
        // OCR MISREAD VARIATIONS
        // Same confidence as correct spellings
        // ========================================
        let ocrMisreadKeywords = [
            // Cyrillic lookalikes (common OCR confusion)
            "dо zapłaty",   // Cyrillic 'о' instead of 'o'
            "dо zарłaty",   // Cyrillic 'о' and 'р'
            // Missing diacritics
            "zaplaty", "naleznosc", "platnosc",
            // OCR l→i confusion
            "zaplaiy", "nalezinosc", "pilatnosc",
            // OCR ł→l confusion (very common)
            "zaplaty", "platne", "ogolem",
            // OCR ą→a, ę→e confusion
            "razem do zapłaty", "naleznosc platna",
        ]

        // Simple amount pattern that matches most formats: 0,98 or 1234,56 or 1 234,56
        // This is the core pattern used throughout
        // CRITICAL FIX: Using \xA0 instead of \u{00A0} - NSRegularExpression doesn't support \u{} syntax
        let amountPattern = #"(\d+(?:[\s\xA0]?\d{3})*[,\.]\d{2})"#

        // Pattern for amount on the next line after keyword (handles line breaks)
        // Matches: "keyword\n0,98" or "keyword: \n 0,98" with optional whitespace
        let amountNextLinePattern = #"[\s\n]*(\d+(?:[\s\xA0]?\d{3})*[,\.]\d{2})"#

        // ========================================
        // REGEX PATTERNS - Ordered by specificity (highest confidence first)
        // ========================================
        let patterns: [(pattern: String, description: String, bonusConfidence: Int)] = [
            // ==========================================
            // TIER 1: DEFINITIVE PAYMENT KEYWORDS (350-400)
            // These are the most reliable indicators
            // ==========================================

            // English definitive patterns
            (#"(?:current\s*account\s*)?amount\s*payable[:\s\.]*(?:by\s*\d{1,2}[.\-/]\d{1,2}[.\-/]\d{2,4}[.\s]*)?"# + amountPattern, "current account amount payable", 400),
            (amountPattern + #"\s*(?:amount\s*payable)"#, "amount before payable", 400),
            (#"(?:total\s*)?amount\s*due[:\s]*"# + amountPattern, "amount due", 380),
            (#"(?:balance|total)\s*due[:\s]*"# + amountPattern, "balance/total due", 370),
            (#"pay\s*this\s*amount[:\s]*"# + amountPattern, "pay this amount", 360),
            (#"outstanding\s*balance[:\s]*"# + amountPattern, "outstanding balance", 350),

            // Polish definitive patterns
            // CRITICAL: Handle grammatical cases - "rachunku" (genitive) and "rachunek" (nominative)
            // CRITICAL: Handle OCR misreads - "kwota" can be "kwor", "kwot", "kwo", etc.
            (#"(?:kwo[rt]?[a!]?\s*do\s*zap[lł]aty\s*na\s*)?rachunek\s*bie[zż][aą]cy[:\s]*"# + amountPattern, "rachunek biezacy", 400),
            (#"kwo[rt]?[a!]?\s*bie[zż][aą]cego\s*rachunku[:\s]*(?:p[lł]atna\s*(?:do\s*\d{1,2}[.\-/]\d{1,2}[.\-/]\d{2,4}[.\s]*)?)?"# + amountPattern, "kwota biezacego rachunku (OCR tolerant)", 400),
            (#"saldo\s*do\s*zap[lł]aty[:\s]*"# + amountPattern, "saldo do zaplaty", 390),
            (#"nale[zż]no[sś][cć]\s*og[oó][lł]em[:\s]*"# + amountPattern, "naleznosc ogolem", 380),
            (#"ko[nń]cowa\s*kwota[:\s]*"# + amountPattern, "koncowa kwota", 370),
            (#"w\s*tym\s*do\s*zap[lł]aty[:\s]*"# + amountPattern, "w tym do zaplaty", 360),

            // ==========================================
            // TIER 2: PRIMARY PAYMENT KEYWORDS (280-350)
            // ==========================================

            // Polish "kwota" patterns - CRITICAL for simple invoices
            // CRITICAL: OCR-tolerant - "kwota" can be misread as "kwor", "kwot", "kwo", etc.
            (#"kwo[rt]?[a!]?\s*do\s*zap[lł]aty[:\s!]*"# + amountPattern, "kwota do zaplaty (OCR tolerant)", 350),
            (#"kwo[rt]?[a!]?\s*do\s*zap[lł]acenia[:\s!]*"# + amountPattern, "kwota do zaplacenia (OCR tolerant)", 340),
            (#"kwo[rt]?[a!]?[:\s!]*"# + amountPattern, "kwota (OCR tolerant)", 300),

            // Polish "należność płatna" (payable amount)
            (#"nale[zż]no[sś][cć]\s*p[lł]atna[:\s]*(?:do\s*\d{1,2}[.\-/]\d{1,2}[.\-/]\d{2,4}[.\s]*)?"# + amountPattern, "naleznosc platna", 340),
            (amountPattern + #"\s*nale[zż]no[sś][cć]\s*p[lł]atna"#, "amount naleznosc platna", 340),

            // Polish "do zapłaty" patterns (the amount to pay)
            (#"do\s*zap[lł]aty[:\s]*"# + amountPattern, "do zaplaty + amount", 320),
            (amountPattern + #"\s*(?:do\s*zap[lł]aty)"#, "amount + do zaplaty", 320),
            (#"do\s*zap[lł]acenia[:\s]*"# + amountPattern, "do zaplacenia", 310),
            (#"p[lł]atne[:\s]*"# + amountPattern, "platne", 300),

            // ==========================================
            // TIER 3: TELECOM/UTILITY KEYWORDS (250-280)
            // ==========================================

            (#"op[lł]ata[:\s]*"# + amountPattern, "oplata (fee)", 280),
            (#"op[lł]ata\s*(?:za|miesi[eę]czna|sta[lł]a)[:\s]*"# + amountPattern, "oplata za/miesieczna", 270),
            (#"abonament[:\s]*"# + amountPattern, "abonament", 270),
            (#"abonament\s*(?:miesi[eę]czny|za)[:\s]*"# + amountPattern, "abonament miesieczny", 260),
            (#"rachunek\s*za[:\s]*[^\d]*"# + amountPattern, "rachunek za", 260),
            (#"fakturowana\s*kwota[:\s]*"# + amountPattern, "fakturowana kwota", 250),

            // ==========================================
            // TIER 4: TOTAL/SUM KEYWORDS (180-250)
            // ==========================================

            (#"(?:razem\s*do\s*zap[lł]aty|suma\s*do\s*zap[lł]aty)[:\s]*"# + amountPattern, "razem/suma do zaplaty", 250),
            (#"nale[zż]no[sś][cć]\s*(?:za|do)[:\s]*"# + amountPattern, "naleznosc za", 230),

            // CRITICAL FIX: Handle amount on next line after "wartość brutto"
            (#"(?:warto[sś][cć]\s*brutto|kwota\s*brutto)[:\s]*"# + amountPattern, "wartosc/kwota brutto", 220),
            (#"(?:warto[sś][cć]\s*brutto|kwota\s*brutto)\s*pln"# + amountNextLinePattern, "wartosc brutto PLN + nextline", 220),

            (#"warto[sś][cć]\s*faktury[:\s]*"# + amountPattern, "wartosc faktury", 210),
            (#"(?:razem\s*brutto|og[oó][lł]em\s*brutto)[:\s]*"# + amountPattern, "razem/ogolem brutto", 200),
            (#"(?:nale[zż]no[sś][cć])[:\s]*"# + amountPattern, "naleznosc", 190),

            // ==========================================
            // TIER 5: GENERIC TOTAL KEYWORDS (120-180)
            // ==========================================

            (#"(?:suma|razem|total|og[oó][lł]em)[:\s]*"# + amountPattern, "suma/razem/total", 160),
            (amountPattern + #"\s*(?:suma|razem|brutto|og[oó][lł]em)"#, "amount before keyword", 150),
            (#"(?:warto[sś][cć]|value)[:\s]*"# + amountPattern, "wartosc/value", 140),

            // CRITICAL FIX: Standalone amounts near "PLN" keyword (very common)
            (#"PLN"# + amountNextLinePattern, "PLN + amount on next line", 135),
            (amountPattern + #"\s*PLN"#, "amount + PLN", 135),

            (#"ca[lł]kowita[:\s]*"# + amountPattern, "calkowita (total)", 130),

            // ==========================================
            // TIER 6: CURRENCY-ATTACHED AMOUNTS (80-120)
            // ==========================================

            (amountPattern + #"\s*(PLN|z[lł]|ZŁ|z[lł]otych)"#, "PLN with suffix", 120),
            (amountPattern + #"\s*(EUR|€|euro)"#, "EUR with suffix", 120),
            (amountPattern + #"\s*(USD|\$|dolar)"#, "USD with suffix", 120),
            (amountPattern + #"\s*(GBP|£|funt)"#, "GBP with suffix", 120),
            (#"[€$£]\s*"# + amountPattern, "Currency prefix", 110),
            (#"(?:PLN|EUR|USD|GBP|CHF)\s*"# + amountPattern, "Currency code prefix", 100),

            // ==========================================
            // TIER 7: VAT-RELATED KEYWORDS (60-80)
            // ==========================================

            (#"brutto[:\s]*"# + amountPattern, "brutto keyword", 80),
            (#"gross[:\s]*"# + amountPattern, "gross keyword", 80),
            (#"(?:kwota\s*)?vat[:\s]*"# + amountPattern, "VAT keyword", 70),
            (#"podatek[:\s]*"# + amountPattern, "podatek (tax)", 60),

            // ==========================================
            // TIER 8: GENERIC FALLBACK (10-50)
            // ==========================================

            // Try to find amounts with common nearby words
            (#"(?:z[lł]|z[lł]otych)"# + amountNextLinePattern, "zl + amount nextline", 50),
            (#"(?:groszy|grosze)"# + amountNextLinePattern, "groszy + amount nextline", 40),

            (amountPattern, "Generic decimal", 10),
        ]

        var amounts: [InternalAmountCandidate] = []
        var seenValues: Set<Decimal> = [] // Deduplicate amounts with same value

        // DEBUG: Test basic amount pattern directly (metrics only, no actual amounts logged)
        // NOTE: Using \xA0 for non-breaking space instead of \u{00A0} which doesn't work in NSRegularExpression
        let testAmountPattern = #"(\d+(?:[\s\xA0]?\d{3})*[,\.]\d{2})"#
        if let testRegex = try? NSRegularExpression(pattern: testAmountPattern, options: []) {
            let testMatches = testRegex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            // PRIVACY: Only log count, not actual amounts
            PrivacyLogger.parsing.debug("Basic amount regex test: found \(testMatches.count) matches")
        }

        // DEBUG: Log pattern match counts (metrics only)
        PrivacyLogger.parsing.debug("Testing top 10 amount patterns...")
        for (index, (pattern, description, _)) in patterns.prefix(10).enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: range)
                // PRIVACY: Only log pattern name and count, not actual values
                PrivacyLogger.parsing.debug("  Pattern #\(index) (\(description)): \(matches.count) match(es)")
            }
        }

        for (pattern, description, bonusConfidence) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: range)

                for match in matches {
                    // Try to get the amount from group 1
                    if let amountRange = Range(match.range(at: 1), in: text) {
                        let amountString = String(text[amountRange])
                        if let amount = parseAmountString(amountString) {
                            // Skip if we already have this value
                            if seenValues.contains(amount) { continue }

                            // Get extended context: current line + 1 line above + 1 line below
                            let (extendedContext, lineIndex) = extractExtendedContext(
                                for: match.range,
                                in: text,
                                lines: lines
                            )

                            // Calculate semantic score based on keywords in context
                            let (semanticScore, matchedKeywords) = calculateAmountScore(context: extendedContext)

                            // Base confidence from pattern
                            let baseConfidence = bonusConfidence

                            // Final score = pattern confidence + semantic score
                            let finalScore = baseConfidence + semanticScore

                            // Short context for UI display
                            let displayContext = extendedContext.count > 80
                                ? String(extendedContext.prefix(80)) + "..."
                                : extendedContext

                            seenValues.insert(amount)
                            amounts.append(InternalAmountCandidate(
                                value: amount,
                                confidence: baseConfidence,
                                score: finalScore,
                                context: displayContext,
                                description: description,
                                lineIndex: lineIndex,
                                matchedKeywords: matchedKeywords
                            ))
                            // PRIVACY: Don't log actual amount value
                            PrivacyLogger.parsing.debug("Amount candidate found via '\(description)' score=\(finalScore) (base: \(baseConfidence) + semantic: \(semanticScore)) keywords=\(matchedKeywords.count)")
                        }
                    }
                }
            }
        }

        // Sort by SCORE (not value!), with tie-breakers
        // Rule: Choose amount with highest score, NOT highest value
        let sortedAmounts = amounts.sorted { lhs, rhs in
            // Primary: Sort by score
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }

            // Tie-breaker 1: Position in document (lower = closer to bottom = better)
            // Higher lineIndex means further down in the document
            if lhs.lineIndex != rhs.lineIndex {
                return lhs.lineIndex > rhs.lineIndex
            }

            // Tie-breaker 2: Currency preference (PLN/zł preferred)
            let lhsHasPLN = lhs.context.lowercased().contains("pln") || lhs.context.lowercased().contains("zł")
            let rhsHasPLN = rhs.context.lowercased().contains("pln") || rhs.context.lowercased().contains("zł")
            if lhsHasPLN != rhsHasPLN {
                return lhsHasPLN
            }

            // Tie-breaker 3: Prefer smaller amounts when all else equal
            // (Large amounts might be totals for multiple items)
            return lhs.value < rhs.value
        }

        PrivacyLogger.parsing.info("Found \(sortedAmounts.count) unique amounts")

        // Log top candidates sorted by score (sanitized amounts)
        for (index, candidate) in sortedAmounts.prefix(5).enumerated() {
            PrivacyLogger.parsing.info("  #\(index + 1): \(PrivacyLogger.sanitizeAmount(candidate.value)) - score=\(candidate.score) (base:\(candidate.confidence)) line:\(candidate.lineIndex) ocrConf:\(String(format: "%.2f", candidate.ocrConfidence)) keywords:\(candidate.matchedKeywords.joined(separator: ","))")
        }

        return sortedAmounts
    }

    /// Extract all amounts using OCR line data for confidence-weighted scoring.
    /// This version uses per-line OCR confidence to boost/penalize candidates.
    /// - Parameters:
    ///   - text: Full OCR text
    ///   - lineData: Array of OCRLineData with per-line confidence
    /// - Returns: Sorted array of amount candidates with OCR confidence applied
    func extractAllAmounts(from text: String, lineData: [OCRLineData]) -> [InternalAmountCandidate] {
        // First, get base candidates using text-only extraction
        var baseCandidates = extractAllAmounts(from: text)

        // If no lineData, return as-is
        guard !lineData.isEmpty else {
            return baseCandidates
        }

        PrivacyLogger.parsing.info("Applying OCR confidence to \(baseCandidates.count) amount candidates using \(lineData.count) line entries")

        // Apply OCR confidence adjustments
        var adjustedCandidates: [InternalAmountCandidate] = []

        for candidate in baseCandidates {
            // Find the OCRLineData that contains this amount
            let matchingLine = findBestMatchingLine(for: candidate, in: lineData)
            let ocrConfidence = matchingLine?.confidence ?? 1.0

            // Apply OCR confidence adjustment to the score
            let adjustedScore = applyOCRConfidenceAdjustment(baseScore: candidate.score, ocrConfidence: ocrConfidence)

            adjustedCandidates.append(InternalAmountCandidate(
                value: candidate.value,
                confidence: candidate.confidence,
                score: adjustedScore,
                context: candidate.context,
                description: candidate.description,
                lineIndex: candidate.lineIndex,
                matchedKeywords: candidate.matchedKeywords,
                ocrConfidence: ocrConfidence
            ))

            if ocrConfidence != 1.0 {
                let adjustment = adjustedScore - candidate.score
                PrivacyLogger.parsing.debug("OCR confidence adjustment for \(PrivacyLogger.sanitizeAmount(candidate.value)): \(candidate.score) -> \(adjustedScore) (ocrConf: \(String(format: "%.3f", ocrConfidence)), adj: \(adjustment >= 0 ? "+" : "")\(adjustment))")
            }
        }

        // Re-sort by adjusted score
        let sortedAdjusted = adjustedCandidates.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.lineIndex != rhs.lineIndex {
                return lhs.lineIndex > rhs.lineIndex
            }
            let lhsHasPLN = lhs.context.lowercased().contains("pln") || lhs.context.lowercased().contains("zl")
            let rhsHasPLN = rhs.context.lowercased().contains("pln") || rhs.context.lowercased().contains("zl")
            if lhsHasPLN != rhsHasPLN {
                return lhsHasPLN
            }
            return lhs.value < rhs.value
        }

        return sortedAdjusted
    }

    /// Find the best matching OCRLineData for a given amount candidate.
    /// Matches by text containment.
    private func findBestMatchingLine(for candidate: InternalAmountCandidate, in lineData: [OCRLineData]) -> OCRLineData? {
        // Format the amount value as string for matching
        let amountStr = "\(candidate.value)"
        let amountComponents = amountStr.components(separatedBy: ".")

        // Try to find a line that contains this amount
        for line in lineData {
            let lineText = line.text.replacingOccurrences(of: " ", with: "")

            // Check if line contains the amount (with comma or dot separator)
            if amountComponents.count == 2 {
                let withComma = amountComponents[0] + "," + amountComponents[1]
                let withDot = amountComponents[0] + "." + amountComponents[1]

                if lineText.contains(withComma) || lineText.contains(withDot) {
                    return line
                }
            }
        }

        return nil
    }

    private func extractAmount(from text: String) -> Decimal? {
        let allAmounts = extractAllAmounts(from: text)

        // Return the highest confidence amount
        if let best = allAmounts.first {
            PrivacyLogger.parsing.info("=== SELECTED AMOUNT: \(PrivacyLogger.sanitizeAmount(best.value)) (confidence: \(best.confidence)) via '\(best.description)' ===")
            return best.value
        }

        // Last resort: find any large number that could be an amount
        if let fallback = findLargestReasonableAmount(in: text) {
            PrivacyLogger.parsing.warning("=== USING FALLBACK AMOUNT: \(PrivacyLogger.sanitizeAmount(fallback)) (no keyword matches) ===")
            return fallback
        }

        PrivacyLogger.parsing.error("=== NO AMOUNT FOUND ===")
        return nil
    }

    private func findLargestReasonableAmount(in text: String) -> Decimal? {
        // Look for any number with comma/dot that could be an amount
        let pattern = #"(\d+)[,\.](\d{2})(?!\d)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        var amounts: [Decimal] = []
        for match in matches {
            if let intPartRange = Range(match.range(at: 1), in: text),
               let decPartRange = Range(match.range(at: 2), in: text) {
                let intPart = String(text[intPartRange]).replacingOccurrences(of: " ", with: "")
                let decPart = String(text[decPartRange])
                if let amount = Decimal(string: "\(intPart).\(decPart)") {
                    amounts.append(amount)
                }
            }
        }

        // Filter to reasonable invoice amounts (0.01 - 1,000,000)
        let reasonable = amounts.filter { $0 >= 0.01 && $0 <= 1_000_000 }
        return reasonable.max()
    }

    private func parseAmountString(_ string: String) -> Decimal? {
        // Normalize the amount string
        var normalized = string
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "") // non-breaking space

        PrivacyLogger.parsing.debug("Parsing amount string (length: \(string.count)) -> normalized (length: \(normalized.count))")

        // Handle European format (1.234,56 -> 1234.56) vs US format (1,234.56)
        if normalized.contains(",") && normalized.contains(".") {
            // Determine which is the decimal separator
            if let commaIndex = normalized.lastIndex(of: ","),
               let dotIndex = normalized.lastIndex(of: ".") {
                if commaIndex > dotIndex {
                    // European format: 1.234,56
                    normalized = normalized.replacingOccurrences(of: ".", with: "")
                    normalized = normalized.replacingOccurrences(of: ",", with: ".")
                } else {
                    // US format: 1,234.56
                    normalized = normalized.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if normalized.contains(",") {
            // Only comma - likely European decimal separator
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        }

        return Decimal(string: normalized)
    }

    // MARK: - Currency Extraction

    private func extractCurrency(from text: String) -> String? {
        let currencyPatterns: [(String, String)] = [
            (#"PLN|zł|ZŁ|złotych|złote|zlotych|zlote"#, "PLN"),
            (#"EUR|€|euro"#, "EUR"),
            (#"USD|\$|dolar"#, "USD"),
            (#"GBP|£|funt"#, "GBP"),
            (#"CHF|frank"#, "CHF"),
            (#"CZK|Kč|korun"#, "CZK"),
            (#"SEK|krona"#, "SEK"),
            (#"NOK|krone"#, "NOK"),
            (#"DKK"#, "DKK"),
        ]

        for (pattern, currency) in currencyPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    PrivacyLogger.parsing.debug("Found currency: \(currency)")
                    return currency
                }
            }
        }

        return nil
    }

    // MARK: - Due Date Extraction

    /// EXPANDED: Comprehensive due date keyword support for 90%+ Polish invoice accuracy
    private func extractDueDate(from text: String, normalizedText: String) -> Date? {
        PrivacyLogger.parsing.info("=== DUE DATE EXTRACTION START ===")

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Max date filter: reject dates more than 2 years in the future
        guard let maxValidDate = calendar.date(byAdding: .year, value: 2, to: today) else {
            PrivacyLogger.parsing.error("Failed to calculate max valid date")
            return nil
        }

        // Min date filter: reject dates more than 1 year in the past (very old invoices)
        guard let minValidDate = calendar.date(byAdding: .year, value: -1, to: today) else {
            PrivacyLogger.parsing.error("Failed to calculate min valid date")
            return nil
        }

        PrivacyLogger.parsing.info("Valid date range configured for extraction")

        // ========================================
        // KEYWORDS THAT SUGGEST DUE DATE (Polish and English)
        // EXPANDED: More comprehensive coverage
        // ========================================
        let dueDateKeywords = [
            // Polish - high priority (definitive due date indicators)
            "termin płatności", "termin platnosci", "termin platności",
            "data płatności", "data platnosci",
            "płatność do", "platnosc do", "płatne do", "platne do",
            "zapłata do", "zaplata do", "zapłać do", "zaplac do",
            "termin zapłaty", "termin zaplaty",
            "do zapłaty do", "do zaplaty do",
            "termin", "data realizacji", "płatność", "platnosc",
            // Additional Polish patterns
            "do dnia",                              // By date
            "ostateczny termin", "ostateczny termin płatności",  // Final deadline
            "data zapłaty", "data zaplaty",         // Payment date
            "zapłać do", "zaplac do",               // Pay by
            "termin wykonania",                     // Execution deadline
            "płatne w terminie", "platne w terminie", // Payable by term
            "upływa", "upłynie",                    // Expires
            "ważne do", "wazne do",                 // Valid until
            "data ważności", "data waznosci",       // Validity date
            // OCR misread variations
            "termin piatnosci", "termin plaтności", // OCR l→i, Cyrillic т
            "platności", "płainości",               // OCR variations
            // English
            "due date", "payment due", "pay by", "payment deadline",
            "due by", "payable by", "payment date", "due",
            "deadline", "expires", "valid until", "maturity date",
        ]

        // ========================================
        // KEYWORDS THAT SUGGEST INVOICE/ISSUE DATE (we want to AVOID these)
        // ========================================
        let issueDateKeywords = [
            // Polish issue date keywords
            "data wystawienia", "data sprzedaży", "data sprzedazy",
            "data faktury", "wystawiono", "wystawienia",
            "data dostawy", "data wykonania usługi", "data wykonania uslugi",
            "data zakupu", "data transakcji",
            "sporządzono", "sporzadzono",
            // English issue date keywords
            "issue date", "invoice date", "date of issue", "issued",
            "date of invoice", "billing date", "transaction date",
            "purchase date", "order date",
        ]

        // Date patterns
        let datePatterns: [(pattern: String, format: String)] = [
            (#"(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{4})"#, "dd.mm.yyyy"),
            (#"(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})"#, "yyyy-mm-dd"),
            (#"(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{2})(?!\d)"#, "dd.mm.yy"),
        ]

        var candidates: [(date: Date, score: Int, context: String, reason: String)] = []

        for (pattern, format) in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: range)

                for match in matches {
                    if let date = parseDate(from: match, in: text, format: format) {

                        // CRITICAL: Reject dates outside valid range
                        if date > maxValidDate {
                            PrivacyLogger.parsing.warning("REJECTED date - more than 2 years in future")
                            continue
                        }
                        if date < minValidDate {
                            PrivacyLogger.parsing.warning("REJECTED date - more than 1 year in past")
                            continue
                        }

                        let matchPosition = match.range.location

                        // Check context around this date (look before, as keywords usually precede the date)
                        let contextStart = max(0, matchPosition - 80)
                        let contextEnd = min(text.count, matchPosition + match.range.length + 30)

                        let startIdx = text.index(text.startIndex, offsetBy: contextStart)
                        let endIdx = text.index(text.startIndex, offsetBy: contextEnd)
                        let context = String(text[startIdx..<endIdx]).lowercased()
                        let contextClean = context.replacingOccurrences(of: "\n", with: " ")

                        // Calculate score with reasons
                        var score = 0
                        var reasons: [String] = []

                        // High score for due date keywords nearby
                        for keyword in dueDateKeywords {
                            if context.contains(keyword) {
                                score += 100
                                reasons.append("+100 due keyword '\(keyword)'")
                                break // Only count one keyword match
                            }
                        }

                        // Strong negative score for issue date keywords
                        for keyword in issueDateKeywords {
                            if context.contains(keyword) {
                                score -= 80
                                reasons.append("-80 issue keyword '\(keyword)'")
                                break
                            }
                        }

                        // Score based on how reasonable the date is
                        let daysFromNow = calendar.dateComponents([.day], from: today, to: date).day ?? 0

                        if daysFromNow >= 7 && daysFromNow <= 90 {
                            // IDEAL: 7-90 days in future (typical invoice terms)
                            score += 50
                            reasons.append("+50 ideal range (7-90 days)")
                        } else if daysFromNow >= 1 && daysFromNow <= 180 {
                            // GOOD: 1-180 days in future
                            score += 30
                            reasons.append("+30 good range (1-180 days)")
                        } else if daysFromNow >= 0 {
                            // OK: Today or future
                            score += 15
                            reasons.append("+15 future date")
                        } else if daysFromNow >= -30 {
                            // ACCEPTABLE: Up to 30 days in past (might be overdue)
                            score += 5
                            reasons.append("+5 recent past (-30 days)")
                        } else {
                            // POOR: Older past dates
                            score -= 20
                            reasons.append("-20 old past date")
                        }

                        let reasonString = reasons.joined(separator: ", ")
                        candidates.append((date, score, contextClean, reasonString))
                        PrivacyLogger.parsing.info("DATE CANDIDATE: score=\(score), reasons=[\(reasonString)]")
                    }
                }
            }
        }

        PrivacyLogger.parsing.info("Found \(candidates.count) valid date candidates")

        // Sort by score descending
        let sortedCandidates = candidates.sorted { $0.score > $1.score }

        // Log top candidates (sanitized)
        for (index, candidate) in sortedCandidates.prefix(5).enumerated() {
            PrivacyLogger.parsing.info("  Top #\(index + 1): score=\(candidate.score), reason=\(candidate.reason)")
        }

        // Return the best candidate with positive score
        if let best = sortedCandidates.first, best.score > 0 {
            PrivacyLogger.parsing.info("=== SELECTED DUE DATE (score: \(best.score)) ===")
            return best.date
        }

        // Fallback: prefer dates in the ideal range (7-90 days future) even without keywords
        let idealRangeCandidates = candidates.filter { candidate in
            let days = calendar.dateComponents([.day], from: today, to: candidate.date).day ?? 0
            return days >= 7 && days <= 90
        }.sorted { $0.date < $1.date } // Prefer earlier dates

        if let ideal = idealRangeCandidates.first {
            PrivacyLogger.parsing.info("=== SELECTED DUE DATE (ideal range fallback) ===")
            return ideal.date
        }

        // Second fallback: any future date
        let futureCandidates = candidates.filter { $0.date >= today }.sorted { $0.date < $1.date }
        if let future = futureCandidates.first {
            PrivacyLogger.parsing.info("=== SELECTED DUE DATE (future fallback) ===")
            return future.date
        }

        // Last resort: most recent past date (might be overdue)
        let sortedByDate = candidates.sorted { $0.date > $1.date }
        if let latest = sortedByDate.first {
            PrivacyLogger.parsing.warning("=== SELECTED DUE DATE (past date last resort) ===")
            return latest.date
        }

        PrivacyLogger.parsing.error("=== NO VALID DUE DATE FOUND ===")
        return nil
    }

    private func parseDate(from match: NSTextCheckingResult, in text: String, format: String) -> Date? {
        let calendar = Calendar.current

        switch format {
        case "dd.mm.yyyy":
            guard let dayRange = Range(match.range(at: 1), in: text),
                  let monthRange = Range(match.range(at: 2), in: text),
                  let yearRange = Range(match.range(at: 3), in: text),
                  let day = Int(text[dayRange]),
                  let month = Int(text[monthRange]),
                  let year = Int(text[yearRange]) else {
                return nil
            }

            // Validate date components
            guard day >= 1 && day <= 31 && month >= 1 && month <= 12 else {
                return nil
            }

            var components = DateComponents()
            components.day = day
            components.month = month
            components.year = year

            return calendar.date(from: components)

        case "yyyy-mm-dd":
            guard let yearRange = Range(match.range(at: 1), in: text),
                  let monthRange = Range(match.range(at: 2), in: text),
                  let dayRange = Range(match.range(at: 3), in: text),
                  let year = Int(text[yearRange]),
                  let month = Int(text[monthRange]),
                  let day = Int(text[dayRange]) else {
                return nil
            }

            guard day >= 1 && day <= 31 && month >= 1 && month <= 12 else {
                return nil
            }

            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day

            return calendar.date(from: components)

        case "dd.mm.yy":
            guard let dayRange = Range(match.range(at: 1), in: text),
                  let monthRange = Range(match.range(at: 2), in: text),
                  let yearRange = Range(match.range(at: 3), in: text),
                  let day = Int(text[dayRange]),
                  let month = Int(text[monthRange]),
                  var year = Int(text[yearRange]) else {
                return nil
            }

            guard day >= 1 && day <= 31 && month >= 1 && month <= 12 else {
                return nil
            }

            // Convert 2-digit year to 4-digit
            if year < 100 {
                year = year >= 50 ? 1900 + year : 2000 + year
            }

            var components = DateComponents()
            components.day = day
            components.month = month
            components.year = year

            return calendar.date(from: components)

        default:
            return nil
        }
    }

    // MARK: - Invoice Number Extraction

    /// EXPANDED: Comprehensive invoice number patterns for Polish invoices
    private func extractInvoiceNumber(from text: String) -> String? {
        // Patterns for invoice numbers - EXPANDED with all common Polish formats
        let patterns = [
            // Polish invoice number patterns with labels - FIXED: Handle complex formats like "F 916/4556/26"
            (#"(?:faktura|fv|fak)\s*(?:vat\s*)?(?:nr|no\.?|numer)?[:\s#]*([A-Za-z]\s*\d+[/\-]\d+[/\-]\d+)"#, "Letter + multi-part (F 916/4556/26)"),
            (#"(?:faktura|fv|fak)\s*(?:vat\s*)?(?:nr|no\.?|numer)?[:\s#]*([A-Za-z0-9\-/\s]+\d+[A-Za-z0-9\-/]*)"#, "faktura/FV prefix"),
            (#"(?:nr|no|numer|number)[:\s.]*(?:faktury|fv|fak)?[:\s.]*([A-Za-z]\s*\d+[/\-]\d+[/\-]\d+)"#, "nr + Letter multi-part"),
            (#"(?:nr|no|numer|number)[:\s.]*(?:faktury|fv|fak)?[:\s.]*([A-Za-z0-9\-/\s]+\d+[A-Za-z0-9\-/]*)"#, "nr/numer prefix"),
            (#"(?:nr\s*dok\.?|numer\s*dokumentu)[:\s]*([A-Za-z0-9\-/\s]+\d+[A-Za-z0-9\-/]*)"#, "nr dok./numer dokumentu"),
            // Common Polish invoice number formats
            (#"(FV[/\-]\d{4}[/\-]\d+)"#, "FV/2024/001 format"),
            (#"(FV[/\-]\d+[/\-]\d{4})"#, "FV/001/2024 format"),
            (#"(FS[/\-]\d{4}[/\-]\d+)"#, "FS (faktura sprzedazy) format"),
            (#"(FS[/\-]\d+[/\-]\d{4})"#, "FS/001/2024 format"),
            (#"(FP[/\-]\d{4}[/\-]\d+)"#, "FP (faktura proforma) format"),
            (#"(FP[/\-]\d+[/\-]\d{4})"#, "FP/001/2024 format"),
            (#"(FK[/\-]\d{4}[/\-]\d+)"#, "FK (faktura korygująca) format"),
            (#"(R[/\-]\d{4}[/\-]\d+)"#, "R (rachunek) format"),
            // Generic formats with letters and slashes
            (#"([A-Z]\s+\d+[/\-]\d+[/\-]\d+)"#, "F 916/4556/26 format"),
            (#"([A-Z]{1,3}\s*\d+[/\-]\d+[/\-]\d+)"#, "Letter(s) + numbers with slashes"),
            (#"([A-Z]{2,3}[/\-]\d{4}[/\-]\d+)"#, "XX/2024/001 format"),
            (#"([A-Z]{2,3}[/\-]\d+[/\-]\d{4})"#, "XX/001/2024 format"),
            (#"(\d{1,4}[/\-]\d{4})"#, "001/2024 format"),
            // English patterns
            (#"(?:invoice)[:\s#]*([A-Za-z0-9\-/\s]+)"#, "invoice prefix"),
            (#"(?:inv|ref)[:\s#\.]*([A-Za-z0-9\-/\s]+)"#, "inv/ref prefix"),
            // Abbreviated patterns
            (#"(?:nr\s*fak\.?)[:\s]*([A-Za-z0-9\-/\s]+)"#, "nr fak. prefix"),
        ]

        for (pattern, description) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if let numberRange = Range(match.range(at: 1), in: text) {
                        // CRITICAL FIX: Split on newline to avoid capturing "2511160751855\nData wystawienia..."
                        let number = String(text[numberRange])
                            .components(separatedBy: "\n").first ?? ""
                            .trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: "  ", with: " ") // Normalize multiple spaces
                        if !number.isEmpty && number.count >= 3 {
                            PrivacyLogger.parsing.debug("Found invoice number via '\(description)' (length: \(number.count))")
                            return number
                        }
                    }
                }
            }
        }

        PrivacyLogger.parsing.warning("No invoice number found in text")
        return nil
    }

    // MARK: - Vendor Address Extraction

    private func extractVendorAddress(from lines: [String], fullText: String) -> String? {
        PrivacyLogger.parsing.debug("Extracting vendor address")

        // CRITICAL: Isolate vendor section to avoid picking up buyer address
        let vendorSectionText = extractVendorSection(from: fullText)
        let searchText = vendorSectionText ?? fullText

        // Strategy 1: Look for labeled address (Polish and English)
        let addressLabelPatterns: [(pattern: String, captureGroup: Int)] = [
            // Polish patterns
            (#"(?:adres|siedziba)[:\s]+([^\n]{10,100})"#, 1),
            (#"(?:ul\.|ulica)[:\s]*([A-Za-ząćęłńóśźżĄĆĘŁŃÓŚŹŻ0-9\s\-\.\/]+\d+[A-Za-z]?(?:[\/\-]\d+)?)"#, 1),
            // English patterns
            (#"(?:address)[:\s]+([^\n]{10,100})"#, 1),
        ]

        for (pattern, captureGroup) in addressLabelPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(searchText.startIndex..., in: searchText)
                if let match = regex.firstMatch(in: searchText, options: [], range: range) {
                    if let valueRange = Range(match.range(at: captureGroup), in: searchText) {
                        let value = String(searchText[valueRange]).trimmingCharacters(in: .whitespaces)
                        if isValidAddress(value) {
                            PrivacyLogger.parsing.debug("Found address via label pattern (length: \(value.count))")
                            return cleanAddress(value)
                        }
                    }
                }
            }
        }

        // Strategy 2: Look for street + postal code pattern
        // Polish format: ul. Street Name 123, 00-000 City
        let streetPostalPattern = #"(ul\.[^\n,]+\d+[A-Za-z]?(?:[\/\-]\d+)?)[,\s]*(\d{2}-\d{3})[,\s]*([A-Za-ząćęłńóśźżĄĆĘŁŃÓŚŹŻ\s\-]+)"#
        if let regex = try? NSRegularExpression(pattern: streetPostalPattern, options: [.caseInsensitive]) {
            let range = NSRange(searchText.startIndex..., in: searchText)
            if let match = regex.firstMatch(in: searchText, options: [], range: range) {
                var addressParts: [String] = []
                if let streetRange = Range(match.range(at: 1), in: searchText) {
                    addressParts.append(String(searchText[streetRange]).trimmingCharacters(in: .whitespaces))
                }
                if let postalRange = Range(match.range(at: 2), in: searchText) {
                    addressParts.append(String(searchText[postalRange]))
                }
                if let cityRange = Range(match.range(at: 3), in: searchText) {
                    // CRITICAL FIX: Split on newline to avoid capturing "WARSZAWA\nNIP"
                    let city = String(searchText[cityRange]).trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: "\n").first ?? ""
                    if !city.isEmpty && city.count < 50 {
                        addressParts.append(city)
                    }
                }
                if !addressParts.isEmpty {
                    let address = addressParts.joined(separator: ", ")
                    PrivacyLogger.parsing.debug("Found address via street+postal pattern (length: \(address.count))")
                    return address
                }
            }
        }

        // Strategy 3: Look for postal code and grab surrounding context
        let postalPattern = #"(\d{2}-\d{3})\s+([A-Za-ząćęłńóśźżĄĆĘŁŃÓŚŹŻ\s\-]+)"#
        if let regex = try? NSRegularExpression(pattern: postalPattern, options: []) {
            let range = NSRange(searchText.startIndex..., in: searchText)
            if let match = regex.firstMatch(in: searchText, options: [], range: range) {
                if let postalRange = Range(match.range(at: 1), in: searchText),
                   let cityRange = Range(match.range(at: 2), in: searchText) {
                    let postal = String(searchText[postalRange])
                    let city = String(searchText[cityRange]).trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: "\n").first ?? ""
                    if !city.isEmpty && city.count < 50 {
                        let address = "\(postal) \(city)"
                        PrivacyLogger.parsing.debug("Found address via postal code (length: \(address.count))")
                        return address
                    }
                }
            }
        }

        return nil
    }

    private func isValidAddress(_ address: String) -> Bool {
        // Must be between 10 and 200 characters
        guard address.count >= 10 && address.count <= 200 else { return false }

        // Must contain at least some letters
        guard address.contains(where: { $0.isLetter }) else { return false }

        // Should contain a number (street number or postal code)
        guard address.contains(where: { $0.isNumber }) else { return false }

        return true
    }

    private func cleanAddress(_ address: String) -> String {
        // Split into lines and stop when we hit invoice metadata
        let lines = address.components(separatedBy: "\n")
        var cleanedLines: [String] = []

        let stopPatterns = [
            "nip", "regon", "krs", "faktura", "invoice", "fv", "f vat",
            "data wystawienia", "date", "termin płatności", "należność",
            "rachunek", "bank account", "konto", "iban", "nr rachunku"
        ]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Stop if we hit invoice metadata
            let lowercased = trimmed.lowercased()
            if stopPatterns.contains(where: { lowercased.contains($0) }) {
                break
            }

            cleanedLines.append(trimmed)

            // Limit to 3 address lines max
            if cleanedLines.count >= 3 {
                break
            }
        }

        return cleanedLines.joined(separator: "\n")
            .replacingOccurrences(of: "  ", with: " ")
    }

    // MARK: - Bank Account Number Extraction

    /// EXPANDED: Comprehensive bank account patterns for Polish invoices
    private func extractBankAccountNumber(from text: String) -> String? {
        PrivacyLogger.parsing.debug("Extracting bank account number")

        // Polish IBAN format: PL + 26 digits (can have spaces)
        // Example: PL 61 1090 1014 0000 0712 1981 2874
        // EXPANDED: More keyword patterns
        let ibanPatterns = [
            // IBAN with explicit label
            (#"(?:IBAN|iban)[:\s]*(?:PL\s*)?(\d{2}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4})"#, "IBAN with label"),
            (#"PL[\s]?(\d{2}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4})"#, "PL prefix"),
            // Polish bank account keywords - EXPANDED
            (#"(?:rachunek\s*bankowy|konto\s*bankowe|nr\s*konta|bank\s*account|numer\s*rachunku)[:\s]*(?:PL[\s]?)?(\d{2}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4})"#, "account label"),
            (#"(?:nr\s*rachunku|numer\s*rachunku)[:\s]*(?:PL[\s]?)?(\d{2}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4})"#, "nr rachunku"),
            (#"(?:rachunek\s*bankowy\s*odbiorcy)[:\s]*(?:PL[\s]?)?(\d{2}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4})"#, "rachunek bankowy odbiorcy"),
            (#"(?:przelew\s*na\s*konto|wpłata\s*na\s*rachunek|wplata\s*na\s*rachunek)[:\s]*(?:PL[\s]?)?(\d{2}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4})"#, "przelew/wplata"),
            (#"(?:rachunek\s*VAT)[:\s]*(?:PL[\s]?)?(\d{2}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4})"#, "rachunek VAT"),
            // Generic 26-digit Polish account number (lower priority)
            (#"(\d{2}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4})"#, "26-digit number"),
        ]

        for (pattern, description) in ibanPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if let accountRange = Range(match.range(at: 1), in: text) {
                        var accountNumber = String(text[accountRange])
                            .trimmingCharacters(in: .whitespaces)

                        // Normalize: remove internal spaces, verify length
                        let digitsOnly = accountNumber.filter { $0.isNumber }
                        if digitsOnly.count == 26 {
                            // Format nicely: XX XXXX XXXX XXXX XXXX XXXX XXXX
                            accountNumber = formatBankAccount(digitsOnly)
                            PrivacyLogger.parsing.debug("Found bank account via '\(description)' (26 digits)")
                            return accountNumber
                        }
                    }
                }
            }
        }

        return nil
    }

    private func formatBankAccount(_ digits: String) -> String {
        guard digits.count == 26 else { return digits }

        var formatted = ""
        for (index, char) in digits.enumerated() {
            if index > 0 && index % 4 == 2 {
                formatted += " "
            }
            formatted += String(char)
        }
        return formatted
    }

    // MARK: - Helpers

    /// Extract keywords from context text (for learning)
    private func extractNearbyKeywords(from context: String) -> [String] {
        let normalized = context.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        // Common invoice keywords
        let keywords = [
            "suma", "total", "razem", "wartość", "wartosc", "kwota",
            "brutto", "netto", "vat", "do zapłaty", "do zaplaty",
            "należność", "naleznosc", "płatność", "platnosc",
            "rachunek bieżący", "rachunek biezacy", "konto", "pln", "zł"
        ]

        return keywords.filter { normalized.contains($0) }
    }

    // MARK: - Amount Scoring System

    /// Calculate semantic score for an amount based on surrounding context
    /// Rule: Choose amount with highest score, NOT highest value
    /// Uses vendor-specific keywords if vendorProfile is set, otherwise uses global keywords
    private func calculateAmountScore(context: String) -> (score: Int, matchedKeywords: [String]) {
        // Use new KeywordRule-based scoring system
        let result: (score: Int, matchedRules: [KeywordRule])

        if let vendor = vendorProfile {
            // Use vendor-specific keywords + global fallback
            result = vendor.calculateScore(for: .amount, context: context, globalConfig: globalKeywordConfig)
            // PRIVACY: Log score only, not actual keywords or vendor name
            PrivacyLogger.parsing.debug("Amount score: \(result.score) using vendor keywords (matched: \(result.matchedRules.count) rules)")
        } else {
            // Use global keywords only
            result = globalKeywordConfig.calculateScore(for: .amount, context: context)
            // PRIVACY: Log score only, not actual keywords
            PrivacyLogger.parsing.debug("Amount score: \(result.score) using global keywords (matched: \(result.matchedRules.count) rules)")
        }

        // Convert KeywordRule matches to strings for backward compatibility
        let matchedKeywords = result.matchedRules.map { rule in
            rule.weight < 0 ? "-\(rule.phrase)" : rule.phrase
        }

        return (result.score, matchedKeywords)
    }

    /// Extract extended context: current line + 1 line above + 1 line below
    private func extractExtendedContext(for matchRange: NSRange, in text: String, lines: [String]) -> (context: String, lineIndex: Int) {
        // Find which line contains this match
        let matchLocation = matchRange.location
        var currentPosition = 0
        var lineIndex = 0

        for (index, line) in lines.enumerated() {
            let lineLength = line.count + 1 // +1 for newline
            if currentPosition <= matchLocation && currentPosition + lineLength > matchLocation {
                lineIndex = index
                break
            }
            currentPosition += lineLength
        }

        // Gather context: line above + current + line below
        var contextLines: [String] = []
        if lineIndex > 0 {
            contextLines.append(lines[lineIndex - 1])
        }
        if lineIndex < lines.count {
            contextLines.append(lines[lineIndex])
        }
        if lineIndex + 1 < lines.count {
            contextLines.append(lines[lineIndex + 1])
        }

        let context = contextLines.joined(separator: " ")
        return (context, lineIndex)
    }

    private func looksLikeDate(_ string: String) -> Bool {
        let datePattern = #"^\d{1,4}[.\-/]\d{1,2}[.\-/]\d{2,4}$"#
        return string.range(of: datePattern, options: .regularExpression) != nil
    }

    private func looksLikeAmount(_ string: String) -> Bool {
        let amountPattern = #"^[\d\s,\.]+\s*(PLN|zł|EUR|USD|€|\$|GBP|£)?$"#
        return string.range(of: amountPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - NIP/REGON Extraction (for Vendor Matching)

    /// Extract NIP (Polish Tax ID) from text
    /// Format: NIP: 123-456-78-90 or NIP 1234567890 (10 digits)
    func extractNIP(from text: String) -> String? {
        let nipPattern = #"NIP[:\s]*(\d{3}[\s\-]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}|\d{10})"#

        guard let regex = try? NSRegularExpression(pattern: nipPattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let nipRange = Range(match.range(at: 1), in: text) {
            let nip = String(text[nipRange])
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
            if nip.count == 10 {
                // PRIVACY: Don't log the actual NIP value
                PrivacyLogger.parsing.debug("Found valid NIP (10 digits)")
                return nip
            }
        }

        return nil
    }

    /// Extract REGON (Polish Business Registry Number) from text
    /// Format: REGON: 123456789 (9 digits) or 12345678901234 (14 digits)
    func extractREGON(from text: String) -> String? {
        let regonPattern = #"REGON[:\s]*(\d{9}|\d{14})"#

        guard let regex = try? NSRegularExpression(pattern: regonPattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let regonRange = Range(match.range(at: 1), in: text) {
            let regon = String(text[regonRange])
            if regon.count == 9 || regon.count == 14 {
                // PRIVACY: Don't log the actual REGON value
                PrivacyLogger.parsing.debug("Found valid REGON (\(regon.count) digits)")
                return regon
            }
        }

        return nil
    }
}
