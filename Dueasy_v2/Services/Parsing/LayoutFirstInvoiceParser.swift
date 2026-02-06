import Foundation
import os

/// Layout-first invoice parser that uses document spatial structure for extraction.
/// Implements a three-tier extraction strategy:
/// 1. Anchor-based: Find labels (e.g., "NIP:", "Sprzedawca") and extract adjacent values
/// 2. Region heuristic: Use document layout (top-left = vendor, bottom-right = amount)
/// 3. Pattern matching: Fall back to regex patterns on full text
///
/// This approach is more robust than keyword-only parsing because it considers
/// where text appears on the document, not just what the text contains.
///
/// PRIVACY: Uses PrivacyLogger to ensure no PII is ever logged. Only metrics
/// (line counts, confidence scores, extraction methods) are logged.
final class LayoutFirstInvoiceParser: DocumentAnalysisServiceProtocol, @unchecked Sendable {

    private let layoutAnalyzer: LayoutAnalyzer
    private let anchorDetector: AnchorDetector
    private let dateParser: DateParser
    private let keywordLearningService: KeywordLearningService?
    private let globalKeywordConfig: GlobalKeywordConfig

    /// Optional vendor profile for vendor-specific keyword scoring
    var vendorProfile: VendorProfileV2?

    // MARK: - Initialization

    init(
        keywordLearningService: KeywordLearningService? = nil,
        globalKeywordConfig: GlobalKeywordConfig
    ) {
        self.layoutAnalyzer = LayoutAnalyzer()
        self.anchorDetector = AnchorDetector(useFuzzyMatching: true)
        self.dateParser = DateParser()
        self.keywordLearningService = keywordLearningService
        self.globalKeywordConfig = globalKeywordConfig

        PrivacyLogger.parsing.info("LayoutFirstInvoiceParser initialized")
    }

    // MARK: - DocumentAnalysisServiceProtocol

    var providerIdentifier: String { "local-layout" }
    var analysisVersion: Int { 2 }
    var supportsVisionAnalysis: Bool { false }

    func analyzeDocument(
        text: String,
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {
        guard !text.isEmpty else {
            PrivacyLogger.parsing.warning("Empty text provided for analysis")
            return .empty
        }

        // PRIVACY: Log metrics only, not actual content
        PrivacyLogger.logAnalysisStart(documentType: documentType.rawValue, textLength: text.count, lineCount: 0)

        // Without line data, fall back to text-only parsing
        // This is a degraded mode - layout analysis requires OCRLineData
        return parseInvoiceTextOnly(text: text)
    }

    func analyzeDocument(
        ocrResult: OCRResult,
        documentType: DocumentType
    ) async throws -> DocumentAnalysisResult {
        guard ocrResult.hasText else {
            PrivacyLogger.parsing.warning("Empty OCR result provided for analysis")
            return .empty
        }

        guard let lineData = ocrResult.lineData, !lineData.isEmpty else {
            PrivacyLogger.parsing.warning("No line data available, falling back to text-only parsing")
            return parseInvoiceTextOnly(text: ocrResult.text)
        }

        // PRIVACY: Log metrics only
        PrivacyLogger.logAnalysisStart(documentType: documentType.rawValue, textLength: ocrResult.text.count, lineCount: lineData.count)

        switch documentType {
        case .invoice:
            return parseInvoiceWithLayout(text: ocrResult.text, lineData: lineData)
        case .contract, .receipt:
            // Not implemented in MVP - return basic result
            return DocumentAnalysisResult(
                documentType: documentType,
                overallConfidence: 0.0,
                provider: providerIdentifier,
                version: analysisVersion
            )
        }
    }

    // MARK: - Layout-First Parsing

    private func parseInvoiceWithLayout(text: String, lineData: [OCRLineData]) -> DocumentAnalysisResult {
        // PRIVACY: Log only metrics, never actual content

        // Step 0: Detect document language for disambiguation
        let documentLanguage = detectDocumentLanguage(from: text)
        dateParser.languageHint = documentLanguage
        PrivacyLogger.parsing.info("Document language detected: \(documentLanguage.rawValue)")

        // Step 1: Analyze document layout
        let layout = layoutAnalyzer.analyzeLayout(lines: lineData)
        PrivacyLogger.parsing.debug("Layout analysis: \(layout.rows.count) rows, \(layout.columns.count) columns")

        // PRIVACY: Log block distribution metrics only
        for region in DocumentRegion.allCases {
            if let block = layout.block(for: region), !block.isEmpty {
                PrivacyLogger.parsing.debug("Block \(region.rawValue): \(block.lineCount) lines")
            }
        }

        // Step 2: Detect anchors
        let anchors = anchorDetector.detectAnchors(in: lineData)
        let anchorsByType = anchorDetector.bestAnchors(from: anchors)
        PrivacyLogger.parsing.debug("Detected \(anchors.count) anchors, \(anchorsByType.count) types")

        // Step 3: Extract NIP first (used as fallback anchor for vendor)
        let nipExtraction = extractNIP(layout: layout, anchors: anchorsByType, allLines: lineData)
        let nipLine = nipExtraction.hasValue ? lineData.first { $0.text.contains(nipExtraction.bestValue ?? "") } : nil

        // Step 4: Extract fields using layout-first strategy
        let vendorExtraction = extractVendor(layout: layout, anchors: anchorsByType, allLines: lineData, nipLine: nipLine)
        let vendorAddressExtraction = extractVendorAddress(layout: layout, vendorExtraction: vendorExtraction, nipLine: nipLine, allLines: lineData)
        let amountExtraction = extractAmount(layout: layout, anchors: anchorsByType, allLines: lineData, fullText: text)
        let dueDateExtraction = extractDueDate(layout: layout, anchors: anchorsByType, allLines: lineData, fullText: text)
        let invoiceNumberExtraction = extractInvoiceNumber(layout: layout, anchors: anchorsByType, allLines: lineData, fullText: text)
        let bankAccountExtraction = extractBankAccount(layout: layout, anchors: anchorsByType, allLines: lineData, fullText: text)

        // Step 5: Extract currency and REGON using pattern matching
        let currency = extractCurrency(from: text)
        let regon = extractREGON(from: text)

        // Step 6: Convert amount string to Decimal
        let amount: Decimal? = amountExtraction.bestValue.flatMap { parseAmountValue($0) }

        // Step 7: Convert date string to Date
        let dueDate: Date? = dueDateExtraction.bestValue.flatMap { dateParser.parseDate(from: $0) }

        // Step 8: Build suggested amounts from candidates
        let suggestedAmounts: [(Decimal, String)] = amountExtraction.candidates.compactMap { candidate in
            guard let value = parseAmountValue(candidate.value) else { return nil }
            return (value, candidate.source)
        }

        // Step 9: Build candidate arrays for all fields
        let vendorCandidatesList = buildVendorCandidates(from: vendorExtraction)
        let nipCandidatesList = buildNIPCandidates(from: nipExtraction)
        let amountCandidatesList = buildAmountCandidates(from: amountExtraction, lineData: lineData)
        let dateCandidatesList = buildDateCandidates(from: dueDateExtraction, lineData: lineData)
        let documentNumberCandidatesList = buildDocumentNumberCandidates(from: invoiceNumberExtraction)
        let bankAccountCandidatesList = buildBankAccountCandidates(from: bankAccountExtraction)

        // Log candidate counts for debugging alternatives UI
        PrivacyLogger.parsing.info("Built candidates: vendor=\(vendorCandidatesList.count), nip=\(nipCandidatesList.count), amount=\(amountCandidatesList.count), date=\(dateCandidatesList.count), docNum=\(documentNumberCandidatesList.count), bank=\(bankAccountCandidatesList.count)")

        // Step 10: Calculate confidence
        var fieldsFound = 0
        if vendorExtraction.hasValue { fieldsFound += 1 }
        if amount != nil { fieldsFound += 1 }
        if dueDate != nil { fieldsFound += 1 }
        if invoiceNumberExtraction.hasValue { fieldsFound += 1 }

        let overallConfidence = Double(fieldsFound) / 4.0

        // PRIVACY: Log extraction method metrics only, no actual values
        PrivacyLogger.logFieldExtractionMetrics(
            fieldType: "vendor",
            extractionMethod: vendorExtraction.method.rawValue,
            confidence: vendorExtraction.confidence,
            candidatesCount: vendorCandidatesList.count
        )

        // Detailed vendor candidate ranking log (metrics only, no PII)
        for (index, candidate) in vendorExtraction.candidates.prefix(3).enumerated() {
            PrivacyLogger.parsing.info("  Vendor candidate \(index + 1): confidence=\(String(format: "%.3f", candidate.confidence)), source=\(candidate.source), hasSuffix=\(FieldValidators.vendorNameConfidenceBoost(candidate.value) > 0)")
        }
        PrivacyLogger.logParsingMetrics(fieldsFound: fieldsFound, totalFields: 4, confidence: overallConfidence)

        // Build and return result
        return DocumentAnalysisResult(
            documentType: .invoice,
            vendorName: vendorExtraction.bestValue,
            vendorAddress: vendorAddressExtraction.bestValue,
            vendorNIP: nipExtraction.bestValue,
            vendorREGON: regon,
            amount: amount,
            currency: currency ?? defaultCurrency(for: documentLanguage),
            dueDate: dueDate,
            documentNumber: invoiceNumberExtraction.bestValue,
            bankAccountNumber: bankAccountExtraction.bestValue,
            suggestedAmounts: suggestedAmounts,
            amountCandidates: amountCandidatesList.isEmpty ? nil : amountCandidatesList,
            dateCandidates: dateCandidatesList.isEmpty ? nil : dateCandidatesList,
            vendorCandidates: vendorCandidatesList.isEmpty ? nil : vendorCandidatesList,
            nipCandidates: nipCandidatesList.isEmpty ? nil : nipCandidatesList,
            bankAccountCandidates: bankAccountCandidatesList.isEmpty ? nil : bankAccountCandidatesList,
            documentNumberCandidates: documentNumberCandidatesList.isEmpty ? nil : documentNumberCandidatesList,
            vendorEvidence: vendorExtraction.evidence,
            amountEvidence: amountExtraction.evidence,
            dueDateEvidence: dueDateExtraction.evidence,
            documentNumberEvidence: invoiceNumberExtraction.evidence,
            nipEvidence: nipExtraction.evidence,
            bankAccountEvidence: bankAccountExtraction.evidence,
            vendorExtractionMethod: vendorExtraction.method,
            amountExtractionMethod: amountExtraction.method,
            dueDateExtractionMethod: dueDateExtraction.method,
            nipExtractionMethod: nipExtraction.method,
            overallConfidence: overallConfidence,
            fieldConfidences: FieldConfidences(
                vendorName: vendorExtraction.confidence,
                amount: amountExtraction.confidence,
                dueDate: dueDateExtraction.confidence,
                documentNumber: invoiceNumberExtraction.confidence,
                nip: nipExtraction.confidence,
                bankAccount: bankAccountExtraction.confidence
            ),
            provider: providerIdentifier,
            version: analysisVersion,
            rawHints: nil,
            rawOCRText: text
        )
    }

    // MARK: - Vendor Block Capture (Enhanced)

    /// Extract a vendor block (3-6 lines) capturing vendor name and address components.
    /// Uses column alignment to find related lines below the starting line.
    /// - Parameters:
    ///   - startLine: The starting line (vendor name line)
    ///   - layout: Document layout analysis
    ///   - maxLines: Maximum number of lines to capture (default: 6)
    /// - Returns: Array of OCRLineData representing the vendor block
    private func extractVendorBlock(
        startLine: OCRLineData,
        layout: LayoutAnalysis,
        maxLines: Int = 6
    ) -> [OCRLineData] {
        // Find lines in same column as start line
        let tolerance = 0.08
        let xMin = startLine.bbox.x - tolerance
        let xMax = startLine.bbox.x + tolerance

        // Get lines below start line in same column
        let candidateLines = layout.allLines.filter { line in
            // Must be below start line
            guard line.bbox.y > startLine.bbox.y else { return false }

            // Must be in same column (vertically aligned)
            return line.bbox.x >= xMin && line.bbox.x <= xMax
        }
        .sorted { $0.bbox.y < $1.bbox.y }  // Top to bottom
        .prefix(maxLines)

        // Junk keywords to filter out (Polish and English).
        // These are section HEADERS that mark the start of a different section,
        // NOT words that might appear in an address line.
        // "nr" was removed because it appears in valid addresses (e.g., "ul. Kwiatowa nr 5").
        // "data" was removed because it could appear in business names.
        // NIP/REGON/KRS patterns are caught separately by FieldValidators.
        let junkKeywords = [
            // Polish section headers
            "nabywca", "kupujący", "kupujacy", "faktura", "konto", "konto bankowe",
            "termin", "płatności", "platnosci", "razem", "suma", "brutto", "netto",
            // English section headers
            "buyer", "purchaser", "invoice", "account", "bank account", "payment",
            "total", "sum", "due", "tax", "vat"
        ]

        // Filter out junk lines
        let vendorLines = candidateLines.filter { line in
            let normalized = line.text.lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)
            let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

            // Reject if the line STARTS with a junk keyword (section header).
            // Using startsWith instead of contains avoids rejecting valid address
            // lines that incidentally contain a keyword (e.g., "ul. Bankowa 5").
            if junkKeywords.contains(where: { trimmed.hasPrefix($0) }) {
                return false
            }

            // Also reject if the line IS EXACTLY a junk keyword (standalone label)
            if junkKeywords.contains(trimmed) {
                return false
            }

            // Reject if looks like date
            if FieldValidators.looksLikeDate(line.text) {
                return false
            }

            // Reject if looks like amount
            if FieldValidators.looksLikeAmount(line.text) {
                return false
            }

            // Reject if looks like account number
            if FieldValidators.looksLikeAccountNumber(line.text) {
                return false
            }

            // Reject if looks like NIP/REGON/KRS
            if FieldValidators.looksLikeNIP(line.text) ||
               FieldValidators.looksLikeREGON(line.text) ||
               FieldValidators.looksLikeKRS(line.text) {
                return false
            }

            return true
        }

        return Array(vendorLines)
    }

    // MARK: - Vendor Extraction (Enhanced with Block Capture)

    private func extractVendor(
        layout: LayoutAnalysis,
        anchors: [AnchorType: DetectedAnchor],
        allLines: [OCRLineData],
        nipLine: OCRLineData?
    ) -> FieldExtraction {
        var candidates: [ExtractionCandidate] = []

        // Strategy 1: Anchor-based extraction with block capture (vendor label)
        if let vendorAnchor = anchors[.vendorLabel] {
            PrivacyLogger.parsing.debug("Found vendor anchor at Y=\(String(format: "%.3f", vendorAnchor.line.bbox.centerY))")

            // Look for starting vendor line below anchor in the SAME COLUMN
            let belowLines = findLinesBelow(vendorAnchor.line, inSameColumn: true, layout: layout, maxLines: 3)
            if let startLine = belowLines.first(where: { FieldValidators.isValidVendorName(cleanVendorName($0.text)) }) {
                // Capture vendor block starting from this line
                let vendorBlock = extractVendorBlock(startLine: startLine, layout: layout)

                if !vendorBlock.isEmpty {
                    // First valid line below anchor is vendor name
                    let vendorName = cleanVendorName(startLine.text)
                    let confidenceBoost = FieldValidators.vendorNameConfidenceBoost(vendorName)

                    // Build address from block lines (up to 3 address components)
                    let addressLines = vendorBlock.prefix(3)
                    let addressText = addressLines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: ", ")

                    PrivacyLogger.parsing.debug("Vendor block captured: name + \(vendorBlock.count) address lines")

                    // CALIBRATION: Base confidence depends on whether the vendor name
                    // looks like a real company name (has suffix like "Sp. z o.o.", "LLC")
                    // vs a possible label or abbreviated identifier. Without a company
                    // suffix, the first line below "Sprzedawca" might be a sub-label
                    // or department name, not the actual legal entity name.
                    let baseConfidence = confidenceBoost > 0 ? 0.95 : 0.88
                    let hasAddressContext = !addressLines.isEmpty
                    let addressBoost = hasAddressContext ? 0.02 : 0.0

                    candidates.append(ExtractionCandidate(
                        value: vendorName,
                        confidence: min(1.0, baseConfidence * vendorAnchor.confidence + confidenceBoost + addressBoost),
                        bbox: startLine.bbox,
                        method: .anchorBased,
                        source: "vendor-block-capture: \(vendorAnchor.matchedPattern)",
                        anchorType: AnchorType.vendorLabel.rawValue,
                        additionalData: addressText.isEmpty ? nil : ["address": addressText]
                    ))
                } else {
                    // No block lines, just use the start line
                    let value = cleanVendorName(startLine.text)
                    let confidenceBoost = FieldValidators.vendorNameConfidenceBoost(value)
                    let baseConfidence = confidenceBoost > 0 ? 0.90 : 0.82
                    candidates.append(ExtractionCandidate(
                        value: value,
                        confidence: min(1.0, baseConfidence * vendorAnchor.confidence + confidenceBoost),
                        bbox: startLine.bbox,
                        method: .anchorBased,
                        source: "anchor-below-column: \(vendorAnchor.matchedPattern)",
                        anchorType: AnchorType.vendorLabel.rawValue
                    ))
                }
            }

            // Look for value to the right of anchor (same line) - fallback
            let rightLines = layout.linesToRight(of: vendorAnchor.line, tolerance: 0.02)
            if let rightLine = rightLines.first, !rightLine.text.trimmingCharacters(in: .whitespaces).isEmpty {
                let value = cleanVendorName(rightLine.text)
                if FieldValidators.isValidVendorName(value) {
                    let confidenceBoost = FieldValidators.vendorNameConfidenceBoost(value)
                    candidates.append(ExtractionCandidate(
                        value: value,
                        confidence: min(1.0, 0.85 * vendorAnchor.confidence + confidenceBoost),
                        bbox: rightLine.bbox,
                        method: .anchorBased,
                        source: "anchor-right: \(vendorAnchor.matchedPattern)",
                        anchorType: AnchorType.vendorLabel.rawValue
                    ))
                }
            }
        }

        // Strategy 2: NIP-based extraction with block capture (find vendor name ABOVE NIP in same column)
        // NIP is the MOST RELIABLE anchor on Polish invoices. The vendor name is almost always
        // directly above the NIP line in the same column. This strategy should be treated as
        // a primary extraction method (not a "fallback"), with confidence comparable to or
        // higher than anchor-based extraction when a company suffix is found.
        if let nipLine = nipLine {
            let aboveLines = findLinesAbove(nipLine, inSameColumn: true, layout: layout, maxLines: 5)
            // Find the topmost valid vendor name line
            var vendorStartLine: OCRLineData?
            for line in aboveLines.reversed() { // Start from top
                let value = cleanVendorName(line.text)
                if FieldValidators.isValidVendorName(value) {
                    vendorStartLine = line
                    break // Take topmost valid vendor name
                }
            }

            if let startLine = vendorStartLine {
                // Capture lines between vendor name and NIP as address
                let betweenLines = aboveLines.filter { line in
                    line.bbox.y > startLine.bbox.y && line.bbox.y < nipLine.bbox.y
                }.filter { FieldValidators.isValidAddressComponent($0.text) }

                let vendorName = cleanVendorName(startLine.text)
                let confidenceBoost = FieldValidators.vendorNameConfidenceBoost(vendorName)
                let addressText = betweenLines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: ", ")

                // NIP-anchored extraction is highly reliable:
                // - Base 0.90 (up from 0.80) because NIP proximity is a strong signal
                // - Company suffix boost (+0.10) can push it above anchor-based candidates
                // - Address lines between vendor and NIP further validate the block
                let hasAddressContext = !betweenLines.isEmpty
                let addressBoost = hasAddressContext ? 0.03 : 0.0

                // Also check if vendor is in the same section as the NIP anchor
                let isVendorSection = isInVendorSection(line: startLine, layout: layout, anchors: anchors)
                let sectionBoost = isVendorSection ? 0.02 : 0.0

                let nipConfidence = min(1.0, 0.90 + confidenceBoost + addressBoost + sectionBoost)

                PrivacyLogger.parsing.debug("NIP-based vendor: confidence=\(String(format: "%.3f", nipConfidence)), suffix=\(confidenceBoost > 0), address=\(hasAddressContext), vendorSection=\(isVendorSection)")

                candidates.append(ExtractionCandidate(
                    value: vendorName,
                    confidence: nipConfidence,
                    bbox: startLine.bbox,
                    method: .anchorBased,
                    source: "nip-block: above NIP",
                    anchorType: AnchorType.nipLabel.rawValue,
                    additionalData: addressText.isEmpty ? nil : ["address": addressText]
                ))
            }
        }

        // Strategy 3: Region heuristic with block capture (top-left block)
        if let topLeftBlock = layout.block(for: .topLeft), !topLeftBlock.isEmpty {
            // Find first valid vendor name in top-left
            let sortedLines = topLeftBlock.lines.sorted(by: { $0.bbox.y < $1.bbox.y })
            if let startLine = sortedLines.first(where: { FieldValidators.isValidVendorName(cleanVendorName($0.text)) }) {
                let vendorBlock = extractVendorBlock(startLine: startLine, layout: layout)
                let vendorName = cleanVendorName(startLine.text)
                let confidenceBoost = FieldValidators.vendorNameConfidenceBoost(vendorName)
                let confidence = min(1.0, 0.7 * startLine.confidence + confidenceBoost)

                let addressLines = vendorBlock.prefix(3)
                let addressText = addressLines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: ", ")

                candidates.append(ExtractionCandidate(
                    value: vendorName,
                    confidence: confidence,
                    bbox: startLine.bbox,
                    method: .regionHeuristic,
                    source: "region-block: topLeft",
                    region: DocumentRegion.topLeft.rawValue,
                    additionalData: addressText.isEmpty ? nil : ["address": addressText]
                ))
            }
        }

        // Strategy 4: Middle-left block (vendor section often continues here)
        if let middleLeftBlock = layout.block(for: .middleLeft), !middleLeftBlock.isEmpty {
            for line in middleLeftBlock.lines.sorted(by: { $0.bbox.y < $1.bbox.y }) {
                let value = cleanVendorName(line.text)
                if FieldValidators.isValidVendorName(value) && !containsNIP(line.text) {
                    let confidenceBoost = FieldValidators.vendorNameConfidenceBoost(value)
                    let confidence = min(1.0, 0.6 * line.confidence + confidenceBoost)
                    candidates.append(ExtractionCandidate(
                        value: value,
                        confidence: confidence,
                        bbox: line.bbox,
                        method: .regionHeuristic,
                        source: "region: middleLeft",
                        region: DocumentRegion.middleLeft.rawValue
                    ))
                    break
                }
            }
        }

        // Cross-validation: If multiple independent strategies found the SAME vendor name,
        // boost that candidate's confidence. Agreement between anchor-based and NIP-based
        // extraction is a very strong signal that the name is correct.
        let crossValidatedCandidates = crossValidateVendorCandidates(candidates)

        // Deduplicate vendor candidates by name, keeping highest confidence
        let deduplicatedVendors = deduplicateCandidatesByValue(crossValidatedCandidates)
        return FieldExtraction(candidates: deduplicatedVendors)
    }

    /// Cross-validate vendor candidates: if multiple independent strategies found the same
    /// vendor name, boost that candidate's confidence. This rewards agreement between
    /// anchor-based extraction and NIP-based extraction, which is a very strong signal.
    private func crossValidateVendorCandidates(_ candidates: [ExtractionCandidate]) -> [ExtractionCandidate] {
        guard candidates.count >= 2 else { return candidates }

        // Group by normalized value
        var valueGroups: [String: [Int]] = [:]
        for (index, candidate) in candidates.enumerated() {
            let key = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            valueGroups[key, default: []].append(index)
        }

        var boosted = candidates
        for (_, indices) in valueGroups {
            guard indices.count >= 2 else { continue }

            // Check if the strategies are truly independent (different source categories)
            let sources = indices.map { candidates[$0].source }
            let hasAnchorBased = sources.contains { $0.contains("vendor-block-capture") || $0.contains("anchor-below") || $0.contains("anchor-right") }
            let hasNIPBased = sources.contains { $0.contains("nip-block") || $0.contains("nip-fallback") }
            let hasRegionBased = sources.contains { $0.contains("region") }

            let independentStrategyCount = [hasAnchorBased, hasNIPBased, hasRegionBased].filter { $0 }.count

            if independentStrategyCount >= 2 {
                // Multiple independent strategies agree -- boost the highest-confidence entry
                let crossValidationBoost = 0.05
                let bestIndex = indices.max(by: { boosted[$0].confidence < boosted[$1].confidence })!
                let original = boosted[bestIndex]
                boosted[bestIndex] = ExtractionCandidate(
                    value: original.value,
                    confidence: min(1.0, original.confidence + crossValidationBoost),
                    bbox: original.bbox,
                    method: original.method,
                    source: original.source + " [cross-validated]",
                    anchorType: original.anchorType,
                    region: original.region,
                    additionalData: original.additionalData
                )
                PrivacyLogger.parsing.info("Cross-validated vendor candidate: \(independentStrategyCount) strategies agree, boost=\(crossValidationBoost)")
            }
        }

        return boosted
    }

    // MARK: - Vendor Address Extraction (Enhanced)

    private func extractVendorAddress(
        layout: LayoutAnalysis,
        vendorExtraction: FieldExtraction,
        nipLine: OCRLineData?,
        allLines: [OCRLineData]
    ) -> FieldExtraction {
        var candidates: [ExtractionCandidate] = []

        // Strategy 1: Use address data already captured in the winning vendor candidate's
        // additionalData. Both anchor-based and NIP-based strategies capture address lines
        // during vendor block extraction, so this data is already available.
        if let bestCandidate = vendorExtraction.candidates.first,
           let addressData = bestCandidate.additionalData?["address"],
           !addressData.isEmpty {
            candidates.append(ExtractionCandidate(
                value: addressData,
                confidence: min(0.95, bestCandidate.confidence),
                bbox: bestCandidate.bbox,
                method: bestCandidate.method,
                source: "vendor-block-address: \(bestCandidate.source)",
                anchorType: bestCandidate.anchorType
            ))
        }

        // Strategy 2: Also check non-winning candidates for address data (may have
        // better address coverage from a different strategy)
        for candidate in vendorExtraction.candidates.dropFirst() {
            if let addressData = candidate.additionalData?["address"],
               !addressData.isEmpty,
               !candidates.contains(where: { $0.value == addressData }) {
                candidates.append(ExtractionCandidate(
                    value: addressData,
                    confidence: min(0.90, candidate.confidence),
                    bbox: candidate.bbox,
                    method: candidate.method,
                    source: "vendor-block-address: \(candidate.source)",
                    anchorType: candidate.anchorType
                ))
            }
        }

        // Strategy 3: Fallback -- find lines between vendor name and NIP directly
        if candidates.isEmpty {
            guard let vendorEvidence = vendorExtraction.evidence else {
                return FieldExtraction(candidates: [])
            }

            let vendorLine = allLines.first { $0.bbox == vendorEvidence }

            guard let vendorLine = vendorLine else {
                return FieldExtraction(candidates: [])
            }

            // Find lines between vendor name and NIP (or next field)
            let candidateLines = findLinesBetween(
                start: vendorLine,
                end: nipLine,
                layout: layout,
                maxLines: 3
            ).filter { FieldValidators.isValidAddressComponent($0.text) }

            if !candidateLines.isEmpty {
                let addressParts = candidateLines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                let address = addressParts.joined(separator: ", ")

                // Use bounding box of first address line as evidence
                candidates.append(ExtractionCandidate(
                    value: address,
                    confidence: 0.85,
                    bbox: candidateLines[0].bbox,
                    method: .anchorBased,
                    source: "between vendor and NIP",
                    anchorType: nil
                ))
            }
        }

        return FieldExtraction(candidates: candidates)
    }

    // MARK: - NIP/Tax ID Extraction (Polish NIP + US EIN)

    private func extractNIP(
        layout: LayoutAnalysis,
        anchors: [AnchorType: DetectedAnchor],
        allLines: [OCRLineData]
    ) -> FieldExtraction {
        var candidates: [ExtractionCandidate] = []

        // NIP pattern: 10 digits, optionally with various separators
        // Handles: 123-456-78-90, 123 456 78 90, 1234567890, 123-45-67-890
        let nipPattern = #"(\d{3}[-\s]?\d{3}[-\s]?\d{2}[-\s]?\d{2}|\d{3}[-\s]?\d{2}[-\s]?\d{2}[-\s]?\d{3}|\d{10}|\d{3}[-\s]\d{3}[-\s]\d{4})"#

        // US EIN pattern: XX-XXXXXXX (2 digits, dash, 7 digits)
        let einPattern = #"(\d{2}-\d{7})"#

        // Strategy 1: Anchor-based extraction (NIP/Tax ID label)
        if let nipAnchor = anchors[.nipLabel] {
            PrivacyLogger.parsing.debug("Found NIP/Tax ID anchor")

            // Look for NIP/EIN value in same line or nearby
            let searchLines = [nipAnchor.line] + layout.linesToRight(of: nipAnchor.line, tolerance: 0.02) + layout.linesBelow(nipAnchor.line, maxDistance: 0.03)

            for line in searchLines {
                // Try NIP first (Polish 10-digit)
                if let nip = extractNIPValue(from: line.text, pattern: nipPattern) {
                    let isValid = FieldValidators.validateNIPChecksum(nip)
                    let isVendorNIP = isInVendorSection(line: line, layout: layout, anchors: anchors)
                    let baseConfidence = isVendorNIP ? 0.95 : 0.7
                    let checksumBoost = isValid ? 0.05 : -0.1

                    candidates.append(ExtractionCandidate(
                        value: nip,
                        confidence: min(1.0, (baseConfidence + checksumBoost) * nipAnchor.confidence),
                        bbox: line.bbox,
                        method: .anchorBased,
                        source: "anchor-NIP: \(nipAnchor.matchedPattern)",
                        anchorType: AnchorType.nipLabel.rawValue
                    ))
                }

                // Try EIN (US 9-digit: XX-XXXXXXX)
                if let ein = extractTaxIDValue(from: line.text, pattern: einPattern) {
                    let isValid = FieldValidators.validateEIN(ein)
                    let isVendorEIN = isInVendorSection(line: line, layout: layout, anchors: anchors)
                    let baseConfidence = isVendorEIN ? 0.95 : 0.7
                    let checksumBoost = isValid ? 0.05 : -0.1

                    candidates.append(ExtractionCandidate(
                        value: ein,
                        confidence: min(1.0, (baseConfidence + checksumBoost) * nipAnchor.confidence),
                        bbox: line.bbox,
                        method: .anchorBased,
                        source: "anchor-EIN: \(nipAnchor.matchedPattern)",
                        anchorType: AnchorType.nipLabel.rawValue
                    ))
                }
            }
        }

        // Strategy 2: Region heuristic - search vendor regions
        let vendorRegions: [DocumentRegion] = [.topLeft, .middleLeft]
        for region in vendorRegions {
            if let block = layout.block(for: region) {
                for line in block.lines {
                    // Try NIP
                    if let nip = extractNIPValue(from: line.text, pattern: nipPattern) {
                        let isValid = FieldValidators.validateNIPChecksum(nip)
                        let checksumBoost = isValid ? 0.05 : -0.1

                        candidates.append(ExtractionCandidate(
                            value: nip,
                            confidence: min(1.0, (0.7 + checksumBoost) * line.confidence),
                            bbox: line.bbox,
                            method: .regionHeuristic,
                            source: "region-NIP: \(region.rawValue)",
                            region: region.rawValue
                        ))
                    }

                    // Try EIN (only if line has EIN-related context)
                    let normalizedLine = line.text.lowercased()
                    if normalizedLine.contains("ein") || normalizedLine.contains("tax id") ||
                       normalizedLine.contains("federal") || normalizedLine.contains("employer") {
                        if let ein = extractTaxIDValue(from: line.text, pattern: einPattern) {
                            let isValid = FieldValidators.validateEIN(ein)
                            let checksumBoost = isValid ? 0.05 : -0.1

                            candidates.append(ExtractionCandidate(
                                value: ein,
                                confidence: min(1.0, (0.7 + checksumBoost) * line.confidence),
                                bbox: line.bbox,
                                method: .regionHeuristic,
                                source: "region-EIN: \(region.rawValue)",
                                region: region.rawValue
                            ))
                        }
                    }
                }
            }
        }

        // Strategy 3: Pattern matching fallback
        for line in allLines {
            // NIP fallback
            if let nip = extractNIPValue(from: line.text, pattern: nipPattern) {
                if !candidates.contains(where: { $0.value == nip }) {
                    let isValid = FieldValidators.validateNIPChecksum(nip)
                    let checksumBoost = isValid ? 0.05 : -0.1

                    candidates.append(ExtractionCandidate(
                        value: nip,
                        confidence: min(1.0, (0.5 + checksumBoost) * line.confidence),
                        bbox: line.bbox,
                        method: .patternMatching,
                        source: "pattern: NIP"
                    ))
                }
            }

            // EIN fallback (only with label context to avoid false positives)
            let normalizedLine = line.text.lowercased()
            if normalizedLine.contains("ein") || normalizedLine.contains("tax id") ||
               normalizedLine.contains("federal") || normalizedLine.contains("employer") {
                if let ein = extractTaxIDValue(from: line.text, pattern: einPattern) {
                    if !candidates.contains(where: { $0.value == ein }) {
                        let isValid = FieldValidators.validateEIN(ein)
                        let checksumBoost = isValid ? 0.05 : -0.1

                        candidates.append(ExtractionCandidate(
                            value: ein,
                            confidence: min(1.0, (0.5 + checksumBoost) * line.confidence),
                            bbox: line.bbox,
                            method: .patternMatching,
                            source: "pattern: EIN"
                        ))
                    }
                }
            }
        }

        // Deduplicate NIP candidates by value, keeping highest confidence per unique NIP
        let deduplicatedNIP = deduplicateCandidatesByValue(candidates)
        return FieldExtraction(candidates: deduplicatedNIP)
    }

    // MARK: - Amount Extraction (Enhanced with Massive "Do Zaplaty" Boost)

    private func extractAmount(
        layout: LayoutAnalysis,
        anchors: [AnchorType: DetectedAnchor],
        allLines: [OCRLineData],
        fullText: String
    ) -> FieldExtraction {
        var candidates: [ExtractionCandidate] = []

        // Amount patterns (supports comma and period as decimal separators)
        // Ordered from most specific to least specific
        let amountPatterns = [
            #"(\d{1,3}(?:\.\d{3})+,\d{2})"#,                  // European: 1.234,56 or 1.234.567,89
            #"(\d{1,3}(?:[\s\u{00A0}]\d{3})+[,]\d{2})"#,     // Polish space-separated: 1 234,56
            #"(\d{1,3}(?:,\d{3})+\.\d{2})"#,                  // US/UK: 1,234.56
            #"(\d{1,3}(?:[\s\u{00A0}]\d{3})+[\.]\d{2})"#,    // Space-separated with dot: 1 234.56
            #"(\d{1,3}(?:[\s\u{00A0}]?\d{3})*[,\.]\d{2})"#,  // General: 1234,56 or 1234.56
            #"(\d+[,\.]\d{2})"#                                // Simple fallback: 1234,56
        ]

        // Check for deduction keywords in document
        let hasDeductions = FieldValidators.containsDeductionKeywords(fullText)

        // Strategy 1: Anchor-based extraction (amount labels)
        if let amountAnchor = anchors[.amountLabel] {
            PrivacyLogger.parsing.debug("Found amount anchor")

            // Check if anchor is "do zaplaty" / "amount due" (definitive) vs "brutto" (gross)
            let isDefinitiveAnchor = isDefinitiveAmountAnchor(amountAnchor.matchedPattern)

            // Check same line for amount
            if let amount = extractAmountFromLine(amountAnchor.line.text, patterns: amountPatterns) {
                // MASSIVE boost for definitive anchors like "do zaplaty"
                let baseConfidence = isDefinitiveAnchor ? 0.98 : 0.85
                let sourceTag = isDefinitiveAnchor ? "do-zaplaty" : "anchor-sameline"
                candidates.append(ExtractionCandidate(
                    value: amount,
                    confidence: baseConfidence * amountAnchor.confidence,
                    bbox: amountAnchor.line.bbox,
                    method: .anchorBased,
                    source: "\(sourceTag): \(amountAnchor.matchedPattern)",
                    anchorType: AnchorType.amountLabel.rawValue
                ))
            }

            // Check next line in same column
            let belowLines = findLinesBelow(amountAnchor.line, inSameColumn: true, layout: layout, maxLines: 1)
            for line in belowLines {
                if let amount = extractAmountFromLine(line.text, patterns: amountPatterns) {
                    let baseConfidence = isDefinitiveAnchor ? 0.96 : 0.80
                    let sourceTag = isDefinitiveAnchor ? "do-zaplaty" : "anchor-below-column"
                    candidates.append(ExtractionCandidate(
                        value: amount,
                        confidence: baseConfidence * amountAnchor.confidence,
                        bbox: line.bbox,
                        method: .anchorBased,
                        source: "\(sourceTag): \(amountAnchor.matchedPattern)",
                        anchorType: AnchorType.amountLabel.rawValue
                    ))
                }
            }

            // Check to the right
            let rightLines = layout.linesToRight(of: amountAnchor.line, tolerance: 0.02)
            for line in rightLines.prefix(2) {
                if let amount = extractAmountFromLine(line.text, patterns: amountPatterns) {
                    let baseConfidence = isDefinitiveAnchor ? 0.96 : 0.80
                    let sourceTag = isDefinitiveAnchor ? "do-zaplaty" : "anchor-right"
                    candidates.append(ExtractionCandidate(
                        value: amount,
                        confidence: baseConfidence * amountAnchor.confidence,
                        bbox: line.bbox,
                        method: .anchorBased,
                        source: "\(sourceTag): \(amountAnchor.matchedPattern)",
                        anchorType: AnchorType.amountLabel.rawValue
                    ))
                }
            }
        }

        // Strategy 1.5: Direct line-scan for "do zaplaty" keywords (OCR-resilient)
        // Runs independently of anchor detector to catch cases where anchor matching
        // fails due to OCR variations. Scans all lines for definitive amount keywords
        // and extracts amounts from the same line or adjacent lines.
        let definitiveKeywords = [
            "do zaplaty", "do zapłaty", "dozaplaty", "do zapl", "do zap",
            "nalezy zaplacic", "należy zapłacić", "do zaplacenia",
            "kwota do zaplaty", "kwota do zapłaty",
            "razem do zaplaty", "razem do zapłaty",
            "suma do zaplaty", "suma do zapłaty",
            "amount due", "total due", "balance due", "total payable"
        ]
        for (lineIndex, line) in allLines.enumerated() {
            let normalizedLine = line.text.lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)

            guard definitiveKeywords.contains(where: { normalizedLine.contains($0) }) else {
                continue
            }

            // Found a definitive keyword on this line
            PrivacyLogger.parsing.info("Direct line-scan found definitive amount keyword at line \(lineIndex), y=\(String(format: "%.3f", line.bbox.y))")

            // Try to extract amount from same line
            if let amount = extractAmountFromLine(line.text, patterns: amountPatterns) {
                if !candidates.contains(where: { $0.value == amount && $0.bbox == line.bbox }) {
                    candidates.append(ExtractionCandidate(
                        value: amount,
                        confidence: 0.96 * line.confidence,
                        bbox: line.bbox,
                        method: .anchorBased,
                        source: "direct-scan-do-zaplaty: same-line",
                        anchorType: AnchorType.amountLabel.rawValue
                    ))
                }
            }

            // Try adjacent lines (1 line below and to the right) for the amount value
            let belowLines = findLinesBelow(line, inSameColumn: false, layout: layout, maxLines: 2)
            for belowLine in belowLines {
                if let amount = extractAmountFromLine(belowLine.text, patterns: amountPatterns) {
                    if !candidates.contains(where: { $0.value == amount && $0.bbox == belowLine.bbox }) {
                        candidates.append(ExtractionCandidate(
                            value: amount,
                            confidence: 0.94 * belowLine.confidence,
                            bbox: belowLine.bbox,
                            method: .anchorBased,
                            source: "direct-scan-do-zaplaty: below-line",
                            anchorType: AnchorType.amountLabel.rawValue
                        ))
                    }
                }
            }

            let rightLines = layout.linesToRight(of: line, tolerance: 0.02)
            for rightLine in rightLines.prefix(2) {
                if let amount = extractAmountFromLine(rightLine.text, patterns: amountPatterns) {
                    if !candidates.contains(where: { $0.value == amount && $0.bbox == rightLine.bbox }) {
                        candidates.append(ExtractionCandidate(
                            value: amount,
                            confidence: 0.94 * rightLine.confidence,
                            bbox: rightLine.bbox,
                            method: .anchorBased,
                            source: "direct-scan-do-zaplaty: right-line",
                            anchorType: AnchorType.amountLabel.rawValue
                        ))
                    }
                }
            }
        }

        // Strategy 2: Region heuristic (bottom-right = totals area)
        if let bottomRightBlock = layout.block(for: .bottomRight) {
            for line in bottomRightBlock.lines {
                if let amount = extractAmountFromLine(line.text, patterns: amountPatterns) {
                    // Check for definitive vs generic keywords
                    let isDefinitive = isDefinitiveAmountAnchor(line.text)
                    let hasBruttoKeyword = containsBruttoKeyword(line.text)
                    let hasGenericTotalKeyword = containsTotalKeyword(line.text) && !isDefinitive

                    var confidence: Double
                    var sourceTag: String

                    if isDefinitive {
                        confidence = 0.92  // High for "do zaplaty" in region
                        sourceTag = "region-do-zaplaty"
                    } else if hasBruttoKeyword {
                        confidence = 0.60  // Lower for brutto/razem
                        sourceTag = "region-brutto"
                    } else if hasGenericTotalKeyword {
                        confidence = 0.55  // Even lower for generic totals
                        sourceTag = "region-total"
                    } else {
                        confidence = 0.45  // Lowest for no keyword
                        sourceTag = "region"
                    }

                    // Apply stronger deduction penalty to non-definitive amounts
                    if hasDeductions && !isDefinitive && (hasBruttoKeyword || hasGenericTotalKeyword) {
                        confidence -= 0.25
                        PrivacyLogger.parsing.debug("Applied deduction penalty to non-definitive amount")
                    }

                    // Position scoring: prefer amounts in bottom 20% of document
                    if line.bbox.y > 0.80 {
                        confidence += 0.08  // Boost for bottom section
                    } else if line.bbox.y < 0.40 {
                        confidence -= 0.10  // Penalty for top section
                    }

                    candidates.append(ExtractionCandidate(
                        value: amount,
                        confidence: max(0.1, min(0.99, confidence * line.confidence)),
                        bbox: line.bbox,
                        method: .regionHeuristic,
                        source: "\(sourceTag): bottomRight",
                        region: DocumentRegion.bottomRight.rawValue
                    ))
                }
            }
        }

        // Strategy 3: Pattern matching with keyword boost
        for line in allLines {
            if let amount = extractAmountFromLine(line.text, patterns: amountPatterns) {
                // Check if already found
                if !candidates.contains(where: { $0.value == amount && $0.bbox == line.bbox }) {
                    let isDefinitive = isDefinitiveAmountAnchor(line.text)
                    let hasBruttoKeyword = containsBruttoKeyword(line.text)
                    let hasKeyword = containsTotalKeyword(line.text)

                    var confidence: Double
                    var sourceTag: String

                    if isDefinitive {
                        confidence = 0.88
                        sourceTag = "pattern-do-zaplaty"
                    } else if hasBruttoKeyword {
                        confidence = 0.50
                        sourceTag = "pattern-brutto"
                    } else if hasKeyword {
                        confidence = 0.45
                        sourceTag = "pattern-total"
                    } else {
                        confidence = 0.35
                        sourceTag = "pattern"
                    }

                    // Apply deduction penalty to non-definitive amounts
                    if hasDeductions && !isDefinitive && (hasBruttoKeyword || hasKeyword) {
                        confidence -= 0.20
                    }

                    // Position scoring
                    if line.bbox.y > 0.80 {
                        confidence += 0.06
                    } else if line.bbox.y < 0.40 {
                        confidence -= 0.08
                    }

                    candidates.append(ExtractionCandidate(
                        value: amount,
                        confidence: max(0.1, min(0.99, confidence * line.confidence)),
                        bbox: line.bbox,
                        method: .patternMatching,
                        source: "\(sourceTag): amount"
                    ))
                }
            }
        }

        // STEP A: Deduplicate candidates by parsed amount VALUE.
        // Multiple strategies often find the same amount on the same line (e.g., anchor-based
        // and direct-scan both find "do zaplaty: 1234,56"). Keep only the highest-confidence
        // candidate for each unique numeric value to avoid showing identical amounts to the user.
        let deduplicatedCandidates: [ExtractionCandidate] = {
            var bestByValue: [String: ExtractionCandidate] = [:]
            for candidate in candidates {
                // Normalize the amount value for dedup (strip formatting differences)
                let normalizedKey: String
                if let decimal = parseAmountValue(candidate.value) {
                    normalizedKey = "\(decimal)"
                } else {
                    normalizedKey = candidate.value
                }

                if let existing = bestByValue[normalizedKey] {
                    if candidate.confidence > existing.confidence {
                        bestByValue[normalizedKey] = candidate
                    }
                } else {
                    bestByValue[normalizedKey] = candidate
                }
            }
            return Array(bestByValue.values)
        }()

        // Sort by confidence (highest first)
        let sorted = deduplicatedCandidates.sorted { $0.confidence > $1.confidence }

        // Detailed logging for amount extraction
        PrivacyLogger.parsing.info("Amount extraction: found \(candidates.count) raw candidates, \(sorted.count) after dedup")
        for (index, candidate) in sorted.prefix(5).enumerated() {
            PrivacyLogger.parsing.info("  Candidate \(index + 1): confidence=\(String(format: "%.3f", candidate.confidence)), y=\(String(format: "%.2f", candidate.bbox.y)), source=\(candidate.source)")
        }

        // Score gap analysis
        if sorted.count > 1 {
            let scoreGap = sorted[0].confidence - sorted[1].confidence
            PrivacyLogger.parsing.info("Score gap to 2nd place: \(String(format: "%.3f", scoreGap))")
            if scoreGap < 0.15 {
                PrivacyLogger.parsing.debug("Low score gap - returning multiple amount candidates for user selection")
            }
        }

        if let best = sorted.first {
            PrivacyLogger.parsing.info("Selected amount: confidence=\(String(format: "%.3f", best.confidence)), source=\(best.source)")
        }

        // STEP B: Secondary sort -- among similar confidence levels, prefer:
        // 1. "do zaplaty" / "amount due" tagged candidates (definitive total)
        // 2. Larger amounts (more likely to be total than subtotal)
        let finalSorted = sorted.sorted { lhs, rhs in
            // If confidence difference is significant, use confidence alone
            if abs(lhs.confidence - rhs.confidence) > 0.08 {
                return lhs.confidence > rhs.confidence
            }
            // Prefer definitive source tags ("do-zaplaty", "amount due", "total due", "balance due")
            let lhsDefinitive = lhs.source.contains("do-zaplaty") || lhs.source.contains("amount-due") || lhs.source.contains("total-due") || lhs.source.contains("balance-due")
            let rhsDefinitive = rhs.source.contains("do-zaplaty") || rhs.source.contains("amount-due") || rhs.source.contains("total-due") || rhs.source.contains("balance-due")
            if lhsDefinitive != rhsDefinitive {
                return lhsDefinitive
            }
            // Then by amount value (larger = more likely total)
            let lhsValue = parseAmountValue(lhs.value) ?? 0
            let rhsValue = parseAmountValue(rhs.value) ?? 0
            return lhsValue > rhsValue
        }

        // Return up to 5 UNIQUE amount candidates for user selection
        return FieldExtraction(candidates: Array(finalSorted.prefix(5)))
    }

    // MARK: - Due Date Extraction (Enhanced with Ranking)

    /// Internal struct for scoring date candidates before conversion to ExtractionCandidate
    private struct ScoredDateCandidate {
        let date: Date
        let line: OCRLineData
        let score: Double
        let reasons: [String]
        let pattern: String
    }

    private func extractDueDate(
        layout: LayoutAnalysis,
        anchors: [AnchorType: DetectedAnchor],
        allLines: [OCRLineData],
        fullText: String
    ) -> FieldExtraction {
        // Extract all dates from document and score them
        var scoredCandidates: [ScoredDateCandidate] = []

        // Due date keywords (STRONG preference)
        let dueDateKeywords = [
            // Polish
            "termin płatności", "termin platnosci", "termin zapłaty", "termin zaplaty",
            "płatne do", "platne do", "do dnia", "wplaty", "wpłaty",
            // English
            "payment due", "due date", "payable by", "pay by", "due by",
            "deadline", "expires", "maturity", "due on"
        ]

        // Issue date keywords (PENALTY)
        let issueDateKeywords = [
            // Polish
            "data wystawienia", "data sprzedaży", "data sprzedazy", "wystawiono",
            // English
            "invoice date", "issue date", "date of issue", "dated", "issued on"
        ]

        // PRE-SCAN: Build a set of line indices that are ADJACENT to a due date keyword line.
        // This catches the common case where "Termin platnosci:" is on one OCR line and the
        // actual date "15.03.2026" is on the next line below it.
        var lineIndicesNearDueDateKeyword: Set<Int> = []
        for (lineIndex, line) in allLines.enumerated() {
            let normalized = line.text.lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)
            if dueDateKeywords.contains(where: { normalized.contains($0) }) {
                // Mark this line and 1-2 lines below/right as "near due date keyword"
                lineIndicesNearDueDateKeyword.insert(lineIndex)
                // Find nearby lines spatially (below or to the right)
                for (otherIndex, otherLine) in allLines.enumerated() {
                    if otherIndex == lineIndex { continue }
                    let yDistance = otherLine.bbox.y - line.bbox.maxY
                    let isBelow = yDistance > -0.01 && yDistance < 0.06
                    let isRight = otherLine.bbox.x > line.bbox.maxX && abs(otherLine.bbox.centerY - line.bbox.centerY) < 0.03
                    if isBelow || isRight {
                        lineIndicesNearDueDateKeyword.insert(otherIndex)
                    }
                }
            }
        }

        // Process all lines looking for dates
        for (lineIndex, line) in allLines.enumerated() {
            guard let dateResult = dateParser.parseDateWithPattern(from: line.text) else {
                continue
            }

            var score = 50.0  // Base score
            var reasons: [String] = []

            let normalized = line.text.lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)

            // STRONG preference for due date keywords ON SAME LINE
            if dueDateKeywords.contains(where: { normalized.contains($0) }) {
                score += 100
                reasons.append("due-date-keyword")
            }
            // STRONG preference for dates on lines ADJACENT to a due date keyword line
            else if lineIndicesNearDueDateKeyword.contains(lineIndex) {
                score += 80
                reasons.append("adjacent-to-due-date-keyword")
            }

            // PENALTY for issue date keywords
            if issueDateKeywords.contains(where: { normalized.contains($0) }) {
                score -= 60
                reasons.append("issue-date-keyword-penalty")
            }

            // Score by position (prefer bottom section for due dates)
            if line.bbox.y > 0.6 {  // Bottom 40%
                score += 30
                reasons.append("bottom-section")
            } else if line.bbox.y < 0.3 {  // Top 30%
                score -= 20
                reasons.append("top-section-penalty")
            }

            // Score by date value (prefer dates in reasonable future, but don't penalize
            // recent past dates -- they are likely overdue invoices, not issue dates)
            let now = Date()
            let daysFromNow = dateResult.date.timeIntervalSince(now) / 86400

            if daysFromNow >= 7 && daysFromNow <= 90 {
                // Likely due date (7-90 days in future)
                score += 40
                reasons.append("future-7-90d")
            } else if daysFromNow >= 0 && daysFromNow < 7 {
                // Very near future (imminent due date)
                score += 30
                reasons.append("imminent-due-date")
            } else if daysFromNow > 90 {
                // Too far (unlikely due date)
                score -= 30
                reasons.append("too-far-future")
            } else if daysFromNow < 0 && daysFromNow >= -60 {
                // Recent past date: likely an overdue due date, not an issue date.
                // No penalty -- overdue invoices are the primary use case for Dueasy.
                score += 10
                reasons.append("recent-past-date")
            } else if daysFromNow < -60 {
                // Old past date (likely issue date, not due date)
                score -= 40
                reasons.append("old-past-date-penalty")
            }

            // Check proximity to due date anchor (if exists)
            if let anchor = anchors[.dueDateLabel] {
                let distance = abs(line.bbox.y - anchor.line.bbox.y)
                if distance < 0.05 {  // Very close
                    score += 70
                    reasons.append("near-due-date-anchor")
                } else if distance < 0.1 {  // Nearby
                    score += 40
                    reasons.append("close-to-anchor")
                }
            }

            // Check for payment-related context in same line
            let paymentContext = ["zaplaty", "zapłaty", "platnosci", "płatności", "payment", "pay"]
            if paymentContext.contains(where: { normalized.contains($0) }) {
                score += 25
                reasons.append("payment-context")
            }

            scoredCandidates.append(ScoredDateCandidate(
                date: dateResult.date,
                line: line,
                score: score,
                reasons: reasons,
                pattern: dateResult.pattern
            ))
        }

        // Deduplicate by date value: keep the highest-scored candidate for each unique date
        var bestByDate: [String: ScoredDateCandidate] = [:]
        for candidate in scoredCandidates {
            let dateKey = formatDateForOutput(candidate.date)
            if let existing = bestByDate[dateKey] {
                if candidate.score > existing.score {
                    bestByDate[dateKey] = candidate
                }
            } else {
                bestByDate[dateKey] = candidate
            }
        }
        scoredCandidates = Array(bestByDate.values)

        // Sort by score (highest first)
        scoredCandidates.sort { $0.score > $1.score }

        // Log scoring results for debugging
        if !scoredCandidates.isEmpty {
            PrivacyLogger.parsing.debug("Date ranking: \(scoredCandidates.count) candidates (deduped), top score: \(String(format: "%.1f", scoredCandidates.first?.score ?? 0))")
        }

        // Convert to ExtractionCandidates with improved confidence calibration.
        //
        // Calibration table (score -> confidence):
        //   score=40  (issue date, top section):    40/100 = 0.40
        //   score=50  (bare date, no context):      50/100 = 0.50
        //   score=80  (date in bottom section):     80/100 = 0.80
        //   score=90  (overdue date, bottom):       90/100 = 0.90
        //   score=120 (adjacent keyword + future):  120/100 = capped 0.95
        //   score=180 (keyword + anchor + future):  180/100 = capped 0.95
        let candidates: [ExtractionCandidate] = scoredCandidates.prefix(5).map { scored in
            let dateString = formatDateForOutput(scored.date)
            let rawConfidence = scored.score / 100.0
            let normalizedConfidence = min(0.95, max(0.15, rawConfidence))
            let reasonString = scored.reasons.joined(separator: ", ")

            return ExtractionCandidate(
                value: dateString,
                confidence: normalizedConfidence,
                bbox: scored.line.bbox,
                method: scored.reasons.contains("near-due-date-anchor") || scored.reasons.contains("close-to-anchor") || scored.reasons.contains("adjacent-to-due-date-keyword")
                    ? .anchorBased : .patternMatching,
                source: "date-ranking: \(reasonString) [\(scored.pattern)]"
            )
        }

        // Log date extraction results
        PrivacyLogger.parsing.info("Date extraction: found \(candidates.count) candidates")
        for (index, candidate) in candidates.enumerated() {
            PrivacyLogger.parsing.info("  Date candidate \(index + 1): confidence=\(String(format: "%.2f", candidate.confidence)), source=\(candidate.source)")
        }

        return FieldExtraction(candidates: candidates)
    }

    // MARK: - Invoice Number Extraction (Enhanced with More Patterns)

    private func extractInvoiceNumber(
        layout: LayoutAnalysis,
        anchors: [AnchorType: DetectedAnchor],
        allLines: [OCRLineData],
        fullText: String
    ) -> FieldExtraction {
        var candidates: [ExtractionCandidate] = []

        // Invoice number patterns (alphanumeric with separators)
        // Enhanced with more Polish and international formats
        let invoicePatterns = [
            // Existing patterns
            #"(?:FV|FA|FAK|INV|FVS)?[-/]?\d{1,4}[-/]\d{1,4}[-/]?\d{0,4}"#,  // FV-123/2024, 001/2024
            #"\d{1,4}[-/]\d{4}"#,                                             // 123/2024
            #"[A-Z]{2,4}[-/]?\d{4,}"#,                                        // FV1234567

            // NEW: Polish format with month and suffix (e.g., 3620/01/2026/SP)
            #"\d{3,5}/\d{1,2}/\d{4}/[A-Z]+"#,
            #"\d{3,5}/\d{4}/\d{1,2}/[A-Z]+"#,                                 // 3620/2026/01/SP

            // NEW: More flexible number/slash combinations
            #"\d+/\d+/\d{4}"#,                                                // number/number/year
            #"\d+/\d{4}/\d+"#,                                                // number/year/number

            // NEW: Invoice with prefix and long number
            #"(?:FV|FA|INV)[-\s]?\d{4,8}"#,                                   // FV-12345678

            // NEW: European formats with dashes
            #"\d{4,6}-\d{2,4}-\d{2,4}"#,                                      // 123456-12-34

            // NEW: Alphanumeric mixed formats
            #"[A-Z]{1,3}\d{4,}/\d{2,4}"#,                                     // F1234/2024
            #"\d{1,4}/[A-Z]+/\d{4}"#                                          // 123/FV/2024
        ]

        // Strategy 1: Anchor-based extraction
        if let invoiceAnchor = anchors[.invoiceNumberLabel] {
            PrivacyLogger.parsing.debug("Found invoice number anchor")

            // Check same line
            if let invoiceNum = extractInvoiceNumberFromLine(invoiceAnchor.line.text, patterns: invoicePatterns) {
                if FieldValidators.validateInvoiceNumber(invoiceNum) {
                    candidates.append(ExtractionCandidate(
                        value: invoiceNum,
                        confidence: 0.95 * invoiceAnchor.confidence,
                        bbox: invoiceAnchor.line.bbox,
                        method: .anchorBased,
                        source: "anchor-sameline: \(invoiceAnchor.matchedPattern)",
                        anchorType: AnchorType.invoiceNumberLabel.rawValue
                    ))
                }
            }

            // Check below and right
            let searchLines = layout.linesToRight(of: invoiceAnchor.line, tolerance: 0.02) +
                              layout.linesBelow(invoiceAnchor.line, maxDistance: 0.03)

            for line in searchLines {
                if let invoiceNum = extractInvoiceNumberFromLine(line.text, patterns: invoicePatterns) {
                    if FieldValidators.validateInvoiceNumber(invoiceNum) {
                        candidates.append(ExtractionCandidate(
                            value: invoiceNum,
                            confidence: 0.90 * invoiceAnchor.confidence,
                            bbox: line.bbox,
                            method: .anchorBased,
                            source: "anchor: \(invoiceAnchor.matchedPattern)",
                            anchorType: AnchorType.invoiceNumberLabel.rawValue
                        ))
                    }
                }
            }
        }

        // Strategy 2: Region heuristic (top-center and top-right)
        for region in [DocumentRegion.topCenter, DocumentRegion.topRight] {
            if let block = layout.block(for: region) {
                for line in block.lines {
                    if let invoiceNum = extractInvoiceNumberFromLine(line.text, patterns: invoicePatterns) {
                        if FieldValidators.validateInvoiceNumber(invoiceNum) {
                            let confidence = 0.7 * line.confidence

                            candidates.append(ExtractionCandidate(
                                value: invoiceNum,
                                confidence: confidence,
                                bbox: line.bbox,
                                method: .regionHeuristic,
                                source: "region: \(region.rawValue)",
                                region: region.rawValue
                            ))
                        }
                    }
                }
            }
        }

        // Deduplicate invoice number candidates by value
        let deduplicatedInvoiceNums = deduplicateCandidatesByValue(candidates)
        return FieldExtraction(candidates: deduplicatedInvoiceNums)
    }

    // MARK: - Bank Account Extraction (Enhanced)

    private func extractBankAccount(
        layout: LayoutAnalysis,
        anchors: [AnchorType: DetectedAnchor],
        allLines: [OCRLineData],
        fullText: String
    ) -> FieldExtraction {
        var candidates: [ExtractionCandidate] = []

        // Bank account patterns (supports IBAN, Polish, and US formats)
        let accountPatterns = [
            // Full IBAN with country code: PL 12 3456 7890 1234 5678 9012 3456
            #"[A-Z]{2}[\s]?\d{2}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}"#,
            // Polish format with 2-digit prefix: 12 3456 7890 1234 5678 9012 3456
            #"\d{2}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}"#,
            // Compact 26-digit (no spaces)
            #"\d{26}"#,
            // Hyphenated format: 12-3456-7890-1234-5678-9012-3456
            #"\d{2}[-]?\d{4}[-]?\d{4}[-]?\d{4}[-]?\d{4}[-]?\d{4}[-]?\d{4}"#,
            // US routing number (9 digits) -- often labeled
            #"(?:routing|aba|rtn)[:\s#]*(\d{9})"#,
            // US account number (6-17 digits) -- often labeled
            #"(?:account\s*(?:no|number|#)?)[:\s]*(\d{6,17})"#
        ]

        // Strategy 1: Anchor-based extraction
        if let bankAnchor = anchors[.bankAccountLabel] {
            PrivacyLogger.parsing.debug("Found bank account anchor")

            // Check same line
            if let account = extractBankAccountFromLine(bankAnchor.line.text, patterns: accountPatterns) {
                let validityBoost = bankAccountValidityBoost(account)

                candidates.append(ExtractionCandidate(
                    value: account,
                    confidence: min(1.0, (0.95 + validityBoost) * bankAnchor.confidence),
                    bbox: bankAnchor.line.bbox,
                    method: .anchorBased,
                    source: "anchor-sameline: \(bankAnchor.matchedPattern)",
                    anchorType: AnchorType.bankAccountLabel.rawValue
                ))
            }

            // Check below
            let belowLines = layout.linesBelow(bankAnchor.line, maxDistance: 0.05)
            for line in belowLines.prefix(2) {
                if let account = extractBankAccountFromLine(line.text, patterns: accountPatterns) {
                    let validityBoost = bankAccountValidityBoost(account)

                    candidates.append(ExtractionCandidate(
                        value: account,
                        confidence: min(1.0, (0.90 + validityBoost) * bankAnchor.confidence),
                        bbox: line.bbox,
                        method: .anchorBased,
                        source: "anchor-below: \(bankAnchor.matchedPattern)",
                        anchorType: AnchorType.bankAccountLabel.rawValue
                    ))
                }
            }

            // Check right
            let rightLines = layout.linesToRight(of: bankAnchor.line, tolerance: 0.02)
            for line in rightLines.prefix(2) {
                if let account = extractBankAccountFromLine(line.text, patterns: accountPatterns) {
                    let validityBoost = bankAccountValidityBoost(account)

                    candidates.append(ExtractionCandidate(
                        value: account,
                        confidence: min(1.0, (0.90 + validityBoost) * bankAnchor.confidence),
                        bbox: line.bbox,
                        method: .anchorBased,
                        source: "anchor-right: \(bankAnchor.matchedPattern)",
                        anchorType: AnchorType.bankAccountLabel.rawValue
                    ))
                }
            }
        }

        // Strategy 2: Region heuristic (bottom-left = payment info)
        if let bottomLeftBlock = layout.block(for: .bottomLeft) {
            for line in bottomLeftBlock.lines {
                if let account = extractBankAccountFromLine(line.text, patterns: accountPatterns) {
                    let validityBoost = bankAccountValidityBoost(account)

                    candidates.append(ExtractionCandidate(
                        value: account,
                        confidence: min(1.0, (0.75 + validityBoost) * line.confidence),
                        bbox: line.bbox,
                        method: .regionHeuristic,
                        source: "region: bottomLeft",
                        region: DocumentRegion.bottomLeft.rawValue
                    ))
                }
            }
        }

        // Strategy 3: Pattern matching fallback
        for line in allLines {
            if let account = extractBankAccountFromLine(line.text, patterns: accountPatterns) {
                if !candidates.contains(where: { $0.value == account }) {
                    let validityBoost = bankAccountValidityBoost(account)

                    candidates.append(ExtractionCandidate(
                        value: account,
                        confidence: min(1.0, (0.5 + validityBoost) * line.confidence),
                        bbox: line.bbox,
                        method: .patternMatching,
                        source: "pattern: bank account"
                    ))
                }
            }
        }

        // Deduplicate bank account candidates by value
        let deduplicatedBankAccounts = deduplicateCandidatesByValue(candidates)
        return FieldExtraction(candidates: deduplicatedBankAccounts)
    }

    /// Calculate validity boost for bank account numbers.
    /// IBAN accounts get a boost for valid checksums and a penalty for invalid ones.
    /// US routing/account numbers are not penalized for failing IBAN validation.
    private func bankAccountValidityBoost(_ account: String) -> Double {
        let digitsOnly = account.filter { $0.isNumber }

        // IBAN-length accounts (26+ digits, or starts with country code): validate IBAN
        if digitsOnly.count >= 26 || (account.count >= 2 && account.prefix(2).allSatisfy({ $0.isUppercase && $0.isLetter })) {
            let isValid = FieldValidators.validateIBAN(account)
            return isValid ? 0.05 : -0.1
        }

        // US routing number (9 digits): validate checksum
        if digitsOnly.count == 9 {
            let isValid = FieldValidators.validateUSRoutingNumber(digitsOnly)
            return isValid ? 0.05 : -0.05
        }

        // US account number (6-17 digits): no checksum to validate, neutral
        if digitsOnly.count >= 6 && digitsOnly.count <= 17 {
            return 0.0
        }

        return -0.05  // Unknown format, slight penalty
    }

    // MARK: - Column-Based Line Finding

    /// Find lines below a reference line, optionally constrained to same column
    private func findLinesBelow(
        _ line: OCRLineData,
        inSameColumn: Bool,
        layout: LayoutAnalysis,
        maxLines: Int = 5
    ) -> [OCRLineData] {
        let allBelow = layout.linesBelow(line, maxDistance: 0.15)

        if inSameColumn {
            return allBelow
                .filter { $0.bbox.isOnSameColumn(as: line.bbox, tolerance: 0.08) }
                .prefix(maxLines)
                .map { $0 }
        }

        return Array(allBelow.prefix(maxLines))
    }

    /// Find lines above a reference line, optionally constrained to same column
    private func findLinesAbove(
        _ line: OCRLineData,
        inSameColumn: Bool,
        layout: LayoutAnalysis,
        maxLines: Int = 5
    ) -> [OCRLineData] {
        let allAbove = layout.allLines.filter { other in
            let yDistance = line.bbox.y - other.bbox.maxY
            return yDistance > 0 && yDistance < 0.15
        }.sorted { $0.bbox.y > $1.bbox.y } // Sort by Y descending (closest first)

        if inSameColumn {
            return allAbove
                .filter { $0.bbox.isOnSameColumn(as: line.bbox, tolerance: 0.08) }
                .prefix(maxLines)
                .map { $0 }
        }

        return Array(allAbove.prefix(maxLines))
    }

    /// Find lines between two reference lines (exclusive)
    private func findLinesBetween(
        start: OCRLineData,
        end: OCRLineData?,
        layout: LayoutAnalysis,
        maxLines: Int = 5
    ) -> [OCRLineData] {
        let startY = start.bbox.maxY
        let endY = end?.bbox.y ?? (startY + 0.2)

        return layout.allLines.filter { line in
            let lineY = line.bbox.y
            return lineY > startY && lineY < endY
        }
        .sorted { $0.bbox.y < $1.bbox.y }
        .prefix(maxLines)
        .map { $0 }
    }

    // MARK: - Candidate Deduplication

    /// Deduplicate extraction candidates by value, keeping only the highest-confidence
    /// candidate for each unique value. This prevents showing the same NIP/amount/date
    /// multiple times in the UI when multiple extraction strategies find the same value.
    private func deduplicateCandidatesByValue(_ candidates: [ExtractionCandidate]) -> [ExtractionCandidate] {
        var bestByValue: [String: ExtractionCandidate] = [:]
        for candidate in candidates {
            let key = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = bestByValue[key] {
                if candidate.confidence > existing.confidence {
                    bestByValue[key] = candidate
                }
            } else {
                bestByValue[key] = candidate
            }
        }
        return Array(bestByValue.values).sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Helper Methods

    private func extractNIPValue(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)

        if let match = regex.firstMatch(in: text, options: [], range: range) {
            if let valueRange = Range(match.range(at: 1), in: text) {
                let nip = String(text[valueRange]).replacingOccurrences(of: "[-\\s]", with: "", options: .regularExpression)
                // Validate NIP (10 digits)
                if nip.count == 10 && nip.allSatisfy({ $0.isNumber }) {
                    return nip
                }
            }
        }
        return nil
    }

    /// Extract US EIN (XX-XXXXXXX) or similar tax ID from text
    private func extractTaxIDValue(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)

        if let match = regex.firstMatch(in: text, options: [], range: range) {
            if let valueRange = Range(match.range(at: 1), in: text) {
                let taxId = String(text[valueRange])
                // Validate format: XX-XXXXXXX (with dash) or 9 digits
                let digitsOnly = taxId.filter { $0.isNumber }
                if digitsOnly.count == 9 {
                    return taxId  // Return with dash preserved for display
                }
            }
        }
        return nil
    }

    private func extractAmountFromLine(_ text: String, patterns: [String]) -> String? {
        // Try each pattern from most specific to least specific
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(text.startIndex..., in: text)

            // Find ALL matches in the line (there may be multiple amounts)
            let matches = regex.matches(in: text, options: [], range: range)
            for match in matches {
                if let valueRange = Range(match.range(at: 1), in: text) {
                    let candidate = String(text[valueRange])
                    // Validate the amount is non-trivial (not just "0,00" or "0.00")
                    if let amount = parseAmountValue(candidate), amount > 0 {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    private func extractInvoiceNumberFromLine(_ text: String, patterns: [String]) -> String? {
        // First, try to extract the value part after common prefixes
        let prefixPatterns = [
            #"(?:faktura\s*(?:vat\s*)?)(?:nr\.?|numer)?[:\s]*([A-Za-z0-9\-/\.#]+)"#,
            #"(?:invoice\s*)(?:no\.?|number|#)?[:\s]*([A-Za-z0-9\-/\.#]+)"#,
            #"(?:nr\.?|numer)[:\s]*([A-Za-z0-9\-/\.#]+)"#
        ]

        for pattern in prefixPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   let valueRange = Range(match.range(at: 1), in: text) {
                    let value = String(text[valueRange]).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty && value.count >= 3 {
                        return value
                    }
                }
            }
        }

        // Fallback to pattern matching
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)

            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if let valueRange = Range(match.range, in: text) {
                    let value = String(text[valueRange]).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty && value.count >= 3 {
                        return value
                    }
                }
            }
        }
        return nil
    }

    private func extractBankAccountFromLine(_ text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(text.startIndex..., in: text)

            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if let valueRange = Range(match.range, in: text) {
                    let value = String(text[valueRange])
                        .replacingOccurrences(of: " ", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    return value
                }
            }
        }
        return nil
    }

    private func parseAmountValue(_ string: String) -> Decimal? {
        // Strip whitespace and non-breaking spaces (Polish thousands separator)
        var normalized = string
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "") // Non-breaking space
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove currency symbols/text that may be attached
        let currencyPatterns = ["PLN", "EUR", "USD", "GBP", "CHF", "zł", "zl", "€", "$", "£"]
        for currency in currencyPatterns {
            normalized = normalized.replacingOccurrences(of: currency, with: "", options: .caseInsensitive)
        }
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        // Determine format: European (1.234,56) vs Standard (1,234.56)
        // Heuristic: if the last separator is a comma with exactly 2 digits after,
        // it's a decimal comma (European). If the last separator is a dot with
        // exactly 2 digits after, it's a decimal point (Standard).
        let lastCommaIndex = normalized.lastIndex(of: ",")
        let lastDotIndex = normalized.lastIndex(of: ".")

        if let commaIdx = lastCommaIndex, let dotIdx = lastDotIndex {
            if commaIdx > dotIdx {
                // Format: 1.234,56 (European - dot is thousands, comma is decimal)
                normalized = normalized.replacingOccurrences(of: ".", with: "")
                normalized = normalized.replacingOccurrences(of: ",", with: ".")
            } else {
                // Format: 1,234.56 (Standard - comma is thousands, dot is decimal)
                normalized = normalized.replacingOccurrences(of: ",", with: "")
            }
        } else if let commaIdx = lastCommaIndex {
            // Only commas present
            let afterComma = normalized[normalized.index(after: commaIdx)...]
            if afterComma.count == 2 && afterComma.allSatisfy({ $0.isNumber }) {
                // Single comma with 2 decimal digits: 1234,56 -> 1234.56
                normalized = normalized.replacingOccurrences(of: ",", with: ".")
            } else if afterComma.count == 3 && afterComma.allSatisfy({ $0.isNumber }) {
                // Comma as thousands separator: 1,234 -> 1234
                normalized = normalized.replacingOccurrences(of: ",", with: "")
            } else {
                // Ambiguous - treat as decimal separator (most common in Polish invoices)
                normalized = normalized.replacingOccurrences(of: ",", with: ".")
            }
        } else if lastDotIndex != nil {
            // Only dots present
            let parts = normalized.split(separator: ".")
            if parts.count > 2 {
                // Multiple dots: 1.234.567 - dots are thousands separators
                normalized = parts.joined()
            } else if parts.count == 2 {
                let afterDot = parts[1]
                if afterDot.count == 2 {
                    // Single dot with 2 decimal digits: 1234.56 (already correct)
                } else if afterDot.count == 3 {
                    // Single dot with 3 digits: 1.234 - dot is thousands separator
                    normalized = parts.joined()
                }
                // else keep as-is
            }
        }

        return Decimal(string: normalized)
    }

    private func formatDateForOutput(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private func cleanVendorName(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func containsNIP(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        // Polish and English tax ID labels
        let taxIdKeywords = [
            // Polish
            "nip", "regon", "krs",
            // English
            "tax id", "tax number", "vat no", "vat number", "tin", "tax identification"
        ]
        return taxIdKeywords.contains { lowercased.contains($0) }
    }

    private func containsTotalKeyword(_ text: String) -> Bool {
        let lowercased = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        // Polish and English keywords for total/amount
        let keywords = [
            // Polish (standard and OCR-resilient)
            "do zaplaty", "dozaplaty", "do zapl", "do zap",
            "razem", "suma", "brutto", "naleznosc", "kwota", "ogolem", "lacznie",
            "nalezy zaplacic", "do zaplacenia",
            // English/US
            "total", "amount due", "gross", "payable", "balance due", "grand total", "sum",
            "total amount", "amount payable", "net payable", "invoice total",
            "total charges", "amount owed", "payment amount", "please pay"
        ]
        return keywords.contains { lowercased.contains($0) }
    }

    private func containsBruttoKeyword(_ text: String) -> Bool {
        let lowercased = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        // Polish and English keywords for gross/total amounts (not definitive "amount due")
        let keywords = [
            // Polish
            "brutto", "razem", "suma", "ogolem", "wartosc",
            // English/US
            "gross", "total", "subtotal", "sum", "charges", "net amount"
        ]
        return keywords.contains { lowercased.contains($0) }
    }

    private func containsDueDateKeyword(_ text: String) -> Bool {
        let lowercased = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        // Polish and English keywords for due date
        let keywords = [
            // Polish
            "termin", "platnosci", "platne", "zaplaty", "do dnia", "wplaty",
            // English/US
            "due", "payable", "pay by", "due date", "payment due", "due by",
            "deadline", "expires", "maturity", "upon receipt", "net 30", "net 15",
            "net 60", "please pay by", "must be paid"
        ]
        return keywords.contains { lowercased.contains($0) }
    }

    private func isDefinitiveAmountAnchor(_ pattern: String) -> Bool {
        // Polish and English definitive amount labels (not just "total" or "brutto")
        let definitive = [
            // Polish (standard forms)
            "do zaplaty", "do zapłaty", "naleznosc", "należność", "kwota do zaplaty",
            "suma do zaplaty", "razem do zaplaty", "lacznie do zaplaty",
            "nalezy zaplacic", "należy zapłacić", "do zaplacenia",
            // Polish (OCR-resilient forms)
            "dozaplaty", "do zaptaty", "do zapiaty", "do zaplaly",
            "do zap aty", "do zapiacenia",
            // English/US
            "amount due", "payable", "total due", "balance due", "amount payable",
            "total payable", "net payable", "pay this amount", "amount owed",
            "invoice total", "please pay", "payment amount"
        ]
        let lowercased = pattern.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        return definitive.contains { lowercased.contains($0) }
    }

    private func isInVendorSection(line: OCRLineData, layout: LayoutAnalysis, anchors: [AnchorType: DetectedAnchor]) -> Bool {
        // Check if line is near vendor anchor
        if let vendorAnchor = anchors[.vendorLabel] {
            let yDistance = abs(line.bbox.centerY - vendorAnchor.line.bbox.centerY)
            if yDistance < 0.1 {
                return true
            }
        }

        // Check if line is in vendor region
        let region = layout.region(for: line)
        return region == .topLeft || region == .middleLeft
    }

    // MARK: - Document Language Detection

    /// Detect the document's language based on keyword frequency.
    /// Returns a language hint used for date disambiguation and currency defaults.
    ///
    /// Strategy: Count occurrences of strong Polish vs English keywords.
    /// Strong indicators avoid false positives from shared words (e.g., "data" is Polish for "date").
    private func detectDocumentLanguage(from text: String) -> DocumentLanguageHint {
        let normalized = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)

        // Strong Polish indicators (unique to Polish invoices)
        let polishKeywords = [
            "faktura", "sprzedawca", "nabywca", "do zaplaty", "brutto", "netto",
            "termin platnosci", "nip", "regon", "krs", "zlotych", "zl ",
            "razem", "kwota", "przelew", "rachunek", "konto bankowe",
            "platnosci", "wystawienia", "wystawiono"
        ]

        // Strong English/US indicators (unique to English invoices)
        let englishKeywords = [
            "invoice", "amount due", "total due", "balance due", "payment due",
            "bill to", "remit to", "due date", "subtotal", "grand total",
            "purchase order", "po number", "ein", "tax id",
            "routing number", "account number", "wire transfer",
            "net 30", "net 60", "upon receipt"
        ]

        var polishScore = 0
        var englishScore = 0

        for keyword in polishKeywords {
            if normalized.contains(keyword) {
                polishScore += 1
            }
        }

        for keyword in englishKeywords {
            if normalized.contains(keyword) {
                englishScore += 1
            }
        }

        PrivacyLogger.parsing.debug("Language detection: polish=\(polishScore), english=\(englishScore)")

        // Require a meaningful difference to declare a language
        if polishScore >= 3 && polishScore > englishScore * 2 {
            return .polish
        } else if englishScore >= 3 && englishScore > polishScore * 2 {
            return .english
        } else if polishScore > englishScore {
            return .polish
        } else if englishScore > polishScore {
            return .english
        }

        return .unknown
    }

    /// Determine the default currency based on detected language and explicit currency symbols.
    private func defaultCurrency(for language: DocumentLanguageHint) -> String {
        switch language {
        case .polish:
            return "PLN"
        case .english:
            return "USD"
        case .unknown:
            return "USD" // Safe default for international use
        }
    }

    // MARK: - Currency Extraction

    private func extractCurrency(from text: String) -> String? {
        // Pattern 1: Explicit currency codes (highest confidence)
        let codePattern = #"\b(PLN|EUR|USD|GBP|CHF|CAD|AUD|JPY|SEK|NOK|DKK|CZK|HUF)\b"#
        if let regex = try? NSRegularExpression(pattern: codePattern, options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if let valueRange = Range(match.range(at: 1), in: text) {
                    return String(text[valueRange]).uppercased()
                }
            }
        }

        // Pattern 2: Polish currency words
        let polishPattern = #"(zł|zl|złotych|zlotych|złoty|zloty)"#
        if let regex = try? NSRegularExpression(pattern: polishPattern, options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                return "PLN"
            }
        }

        // Pattern 3: Currency symbols (mapped to codes)
        // Check for $ symbol with surrounding context to avoid false positives
        let symbolPatterns: [(pattern: String, currency: String)] = [
            (#"\$\s*\d"#, "USD"),                       // $123 or $ 123
            (#"\d[.,]\d{2}\s*\$"#, "USD"),              // 123.45$ or 123,45 $
            (#"€\s*\d"#, "EUR"),                        // Euro prefix
            (#"\d[.,]\d{2}\s*€"#, "EUR"),               // Euro suffix
            (#"£\s*\d"#, "GBP"),                        // Pound prefix
            (#"\d[.,]\d{2}\s*£"#, "GBP"),               // Pound suffix
        ]

        for (pattern, currency) in symbolPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    return currency
                }
            }
        }

        return nil
    }

    private func extractREGON(from text: String) -> String? {
        // REGON: 9 or 14 digits
        let pattern = #"(?:REGON|regon)[:\s]*(\d{9}|\d{14})"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if let valueRange = Range(match.range(at: 1), in: text) {
                    return String(text[valueRange])
                }
            }
        }
        return nil
    }

    // MARK: - Candidate Builder Methods

    /// Build VendorCandidate array from extraction result
    private func buildVendorCandidates(from extraction: FieldExtraction) -> [VendorCandidate] {
        extraction.candidates.prefix(3).map { candidate in
            VendorCandidate(
                name: candidate.value,
                lineText: candidate.value,  // Best approximation
                lineBBox: candidate.bbox,
                matchedPattern: candidate.source,
                confidence: candidate.confidence,
                extractionMethod: candidate.method,
                extractionSource: candidate.source
            )
        }
    }

    /// Build NIPCandidate array from extraction result
    private func buildNIPCandidates(from extraction: FieldExtraction) -> [NIPCandidate] {
        extraction.candidates.prefix(3).map { candidate in
            NIPCandidate(
                value: candidate.value,
                lineText: candidate.value,
                lineBBox: candidate.bbox,
                isVendorNIP: candidate.source.contains("vendor") || candidate.region == DocumentRegion.topLeft.rawValue,
                confidence: candidate.confidence,
                extractionMethod: candidate.method,
                extractionSource: candidate.source
            )
        }
    }

    /// Build AmountCandidate array from extraction result
    private func buildAmountCandidates(from extraction: FieldExtraction, lineData: [OCRLineData]) -> [AmountCandidate] {
        extraction.candidates.prefix(5).compactMap { candidate -> AmountCandidate? in
            guard let value = parseAmountValue(candidate.value) else { return nil }

            // Find matching line for context
            let matchingLine = lineData.first { $0.bbox == candidate.bbox }
            let lineText = matchingLine?.text ?? candidate.value

            // Extract nearby keywords
            var nearbyKeywords: [String] = []
            if candidate.source.contains("do zaplaty") || candidate.source.contains("amount due") {
                nearbyKeywords.append("do zaplaty")
            }
            if candidate.source.contains("brutto") || candidate.source.contains("gross") {
                nearbyKeywords.append("brutto")
            }
            if candidate.source.contains("razem") || candidate.source.contains("total") {
                nearbyKeywords.append("razem")
            }

            return AmountCandidate(
                value: value,
                currencyHint: nil,
                lineText: lineText,
                lineBBox: candidate.bbox,
                nearbyKeywords: nearbyKeywords,
                matchedPattern: candidate.source,
                confidence: candidate.confidence,
                context: candidate.source,
                extractionMethod: candidate.method,
                extractionSource: candidate.source
            )
        }
    }

    /// Build DateCandidate array from extraction result
    private func buildDateCandidates(from extraction: FieldExtraction, lineData: [OCRLineData]) -> [DateCandidate] {
        extraction.candidates.prefix(5).compactMap { candidate -> DateCandidate? in
            guard let date = dateParser.parseDate(from: candidate.value) else { return nil }

            // Find matching line for context
            let matchingLine = lineData.first { $0.bbox == candidate.bbox }
            let lineText = matchingLine?.text ?? candidate.value

            // Extract nearby keywords from source
            var nearbyKeywords: [String] = []
            if candidate.source.contains("due-date-keyword") || candidate.source.contains("termin") {
                nearbyKeywords.append("termin platnosci")
            }
            if candidate.source.contains("payment") {
                nearbyKeywords.append("payment")
            }

            // Calculate score from confidence (scale 0-200)
            let score = Int(candidate.confidence * 200)

            return DateCandidate(
                date: date,
                lineText: lineText,
                lineBBox: candidate.bbox,
                nearbyKeywords: nearbyKeywords,
                matchedPattern: candidate.source,
                score: score,
                scoreReason: candidate.source,
                context: candidate.source,
                extractionMethod: candidate.method,
                extractionSource: candidate.source
            )
        }
    }

    /// Build DocumentNumberCandidate array from extraction result (as ExtractionCandidate)
    private func buildDocumentNumberCandidates(from extraction: FieldExtraction) -> [ExtractionCandidate] {
        Array(extraction.candidates.prefix(3))
    }

    /// Build BankAccountCandidate array from extraction result
    private func buildBankAccountCandidates(from extraction: FieldExtraction) -> [BankAccountCandidate] {
        extraction.candidates.prefix(3).map { candidate in
            let isIBAN = candidate.value.hasPrefix("PL") || candidate.value.hasPrefix("DE") ||
                         candidate.value.hasPrefix("GB") || candidate.value.count == 28

            return BankAccountCandidate(
                value: candidate.value,
                lineText: candidate.value,
                lineBBox: candidate.bbox,
                isIBAN: isIBAN,
                confidence: candidate.confidence,
                extractionMethod: candidate.method,
                extractionSource: candidate.source
            )
        }
    }

    // MARK: - Text-Only Fallback

    private func parseInvoiceTextOnly(text: String) -> DocumentAnalysisResult {
        PrivacyLogger.parsing.warning("Using text-only fallback (no layout data)")

        // Text-only fallback: extract fields using regex on full text.
        // Less accurate than layout-based parsing but still provides value.

        // Detect language for disambiguation and defaults
        let documentLanguage = detectDocumentLanguage(from: text)
        dateParser.languageHint = documentLanguage

        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        let currency = extractCurrency(from: text)
        let regon = extractREGON(from: text)

        // -- NIP/Tax ID extraction --
        // Polish NIP: 10 digits with optional separators
        let nipPattern = #"(?:NIP|nip|EIN|ein|Tax\s*ID|tax\s*id)[:\s]*(\d{2,3}[-\s]?\d{2,3}[-\s]?\d{2,4}[-\s]?\d{2,4}|\d{9,10})"#
        var vendorNIP: String?
        if let regex = try? NSRegularExpression(pattern: nipPattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if let valueRange = Range(match.range(at: 1), in: text) {
                    vendorNIP = String(text[valueRange]).replacingOccurrences(of: "[-\\s]", with: "", options: .regularExpression)
                }
            }
        }

        // -- Amount extraction (text-only) --
        // Look for "do zaplaty" / "amount due" patterns first (highest confidence)
        var bestAmount: Decimal?
        var amountConfidence = 0.0
        let amountPatterns = [
            // Definitive amount labels (Polish & English)
            #"(?:do\s+zap[łl]aty|razem\s+do\s+zap[łl]aty|nale[żz]no[śs][ćc]|amount\s+due|total\s+due|balance\s+due|amount\s+owed|invoice\s+total|pay\s+this\s+amount)[:\s]*(\d[\d\s\u{00A0}]*[.,]\d{2})"#,
            // Total/gross labels (Polish & English)
            #"(?:brutto|gross|razem|total|suma|sum|grand\s+total|total\s+charges|net\s+payable|total\s+amount)[:\s]*(\d[\d\s\u{00A0}]*[.,]\d{2})"#,
            // Currency-prefixed amounts (US style: $1,234.56)
            #"\$\s*(\d{1,3}(?:,\d{3})*\.\d{2})"#,
            // Raw amount with optional currency suffix
            #"(\d{1,3}(?:[\s\u{00A0},]?\d{3})*[.,]\d{2})\s*(?:PLN|zł|zl|EUR|USD|\$)?"#
        ]

        for (index, pattern) in amountPatterns.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: range)

                for match in matches {
                    if let valueRange = Range(match.range(at: 1), in: text) {
                        let amountStr = String(text[valueRange])
                        if let amount = parseAmountValue(amountStr) {
                            // Assign confidence based on pattern specificity
                            let conf: Double
                            switch index {
                            case 0: conf = 0.85  // "do zaplaty" / "amount due" pattern
                            case 1: conf = 0.65  // "brutto/total" pattern
                            case 2: conf = 0.75  // Dollar-prefixed (US style)
                            default: conf = 0.45 // Raw amount pattern
                            }
                            if conf > amountConfidence {
                                bestAmount = amount
                                amountConfidence = conf
                            }
                        }
                    }
                }
            }
        }

        // -- Date extraction (text-only) --
        var bestDueDate: Date?
        var dateConfidence = 0.0

        let dueDateKeywords = [
            // Polish
            "termin platnosci", "termin płatności", "termin zaplaty", "termin zapłaty",
            "platne do", "płatne do",
            // English/US
            "payment due", "due date", "payable by", "pay by", "due by",
            "payment deadline", "due on", "please pay by", "must be paid by"
        ]

        for line in lines {
            guard let dateResult = dateParser.parseDateWithPattern(from: line) else { continue }

            let normalizedLine = line.lowercased().folding(options: .diacriticInsensitive, locale: nil)

            // Check for due date keyword in same line
            if dueDateKeywords.contains(where: { normalizedLine.contains($0) }) {
                if dateConfidence < 0.85 {
                    bestDueDate = dateResult.date
                    dateConfidence = 0.85
                }
            } else if dateConfidence < 0.50 {
                // Use any future date as a weaker candidate
                let daysFromNow = dateResult.date.timeIntervalSince(Date()) / 86400
                if daysFromNow >= 0 && daysFromNow <= 90 {
                    bestDueDate = dateResult.date
                    dateConfidence = 0.50
                }
            }
        }

        // -- Vendor name extraction (text-only) --
        // Look for text near vendor/seller labels (Polish & English)
        var vendorName: String?
        var vendorConfidence = 0.0

        let vendorLabels = [
            // Polish
            "sprzedawca", "wystawca",
            // English/US
            "seller", "vendor", "supplier", "issued by", "billed by",
            "remit to", "pay to", "bill from", "from"
        ]
        for (i, line) in lines.enumerated() {
            let normalizedLine = line.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            if vendorLabels.contains(where: { normalizedLine.contains($0) }) {
                // Take the next non-empty line as vendor name
                for j in (i + 1)..<min(i + 4, lines.count) {
                    let candidate = cleanVendorName(lines[j])
                    if FieldValidators.isValidVendorName(candidate) {
                        vendorName = candidate
                        vendorConfidence = 0.70
                        break
                    }
                }
                if vendorName != nil { break }
            }
        }

        // -- Invoice number extraction (text-only) --
        var documentNumber: String?
        let invoiceNumPatterns = [
            // Polish: Faktura (VAT) Nr/Numer
            #"(?:faktura\s*(?:vat\s*)?|invoice\s*|bill\s*|statement\s*)(?:nr\.?|no\.?|numer|number|#)?[:\s]*([A-Za-z0-9\-/\.#]+(?:/[A-Za-z0-9\-/\.#]+)*)"#
        ]
        for pattern in invoiceNumPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   let valueRange = Range(match.range(at: 1), in: text) {
                    let value = String(text[valueRange]).trimmingCharacters(in: .whitespaces)
                    if FieldValidators.validateInvoiceNumber(value) {
                        documentNumber = value
                        break
                    }
                }
            }
        }

        // -- Bank account extraction (text-only) --
        var bankAccount: String?
        let bankPatterns = [
            // Polish/IBAN accounts with label
            #"(?:konto|rachunek|account|iban|nr\s+konta|nr\s+rachunku|bank\s+account)[:\s]*([A-Z]{0,2}\d[\d\s]{24,30})"#,
            // Polish IBAN with PL prefix
            #"(PL\s?\d{2}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4})"#,
            // 26-digit Polish account
            #"(\d{2}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4})"#,
            // US routing number (9 digits) with label
            #"(?:routing\s*(?:number|no|#)?|aba)[:\s]*(\d{9})"#,
            // US account number with label
            #"(?:account\s*(?:number|no|#))[:\s]*(\d{6,17})"#
        ]
        for pattern in bankPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   let valueRange = Range(match.range(at: 1), in: text) {
                    let value = String(text[valueRange]).replacingOccurrences(of: " ", with: "")
                    let digitCount = value.filter({ $0.isNumber }).count
                    // Accept: IBAN (26+ digits), US routing (9), US account (6-17)
                    if digitCount >= 6 {
                        bankAccount = value
                        break
                    }
                }
            }
        }

        // Calculate overall confidence
        var fieldsFound = 0
        if vendorName != nil { fieldsFound += 1 }
        if bestAmount != nil { fieldsFound += 1 }
        if bestDueDate != nil { fieldsFound += 1 }
        if documentNumber != nil { fieldsFound += 1 }
        let overallConfidence = Double(fieldsFound) / 4.0

        PrivacyLogger.parsing.info("Text-only fallback (\(documentLanguage.rawValue)): vendor=\(vendorName != nil), amount=\(bestAmount != nil), date=\(bestDueDate != nil), docNum=\(documentNumber != nil), nip=\(vendorNIP != nil)")

        return DocumentAnalysisResult(
            documentType: .invoice,
            vendorName: vendorName,
            vendorNIP: vendorNIP,
            vendorREGON: regon,
            amount: bestAmount,
            currency: currency ?? defaultCurrency(for: documentLanguage),
            dueDate: bestDueDate,
            documentNumber: documentNumber,
            bankAccountNumber: bankAccount,
            overallConfidence: overallConfidence,
            fieldConfidences: FieldConfidences(
                vendorName: vendorConfidence,
                amount: amountConfidence,
                dueDate: dateConfidence,
                documentNumber: documentNumber != nil ? 0.7 : 0.0,
                nip: vendorNIP != nil ? 0.8 : 0.0,
                bankAccount: bankAccount != nil ? 0.7 : 0.0
            ),
            provider: providerIdentifier,
            version: analysisVersion,
            rawOCRText: text
        )
    }
}
