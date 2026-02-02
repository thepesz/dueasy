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
        PrivacyLogger.logParsingMetrics(fieldsFound: fieldsFound, totalFields: 4, confidence: overallConfidence)

        // Build and return result
        return DocumentAnalysisResult(
            documentType: .invoice,
            vendorName: vendorExtraction.bestValue,
            vendorAddress: vendorAddressExtraction.bestValue,
            vendorNIP: nipExtraction.bestValue,
            vendorREGON: regon,
            amount: amount,
            currency: currency ?? "PLN",
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

        // Junk keywords to filter out (Polish and English)
        let junkKeywords = [
            // Polish
            "nabywca", "kupujący", "kupujacy", "data", "faktura", "nr", "konto", "regon", "krs",
            "termin", "płatności", "platnosci", "razem", "suma", "brutto", "netto",
            // English
            "buyer", "purchaser", "date", "invoice", "account", "bank", "payment",
            "total", "sum", "due", "tax", "vat"
        ]

        // Filter out junk lines
        let vendorLines = candidateLines.filter { line in
            let normalized = line.text.lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)

            // Reject if contains junk keywords
            if junkKeywords.contains(where: { normalized.contains($0) }) {
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
                    // First valid line above block is vendor name
                    let vendorName = cleanVendorName(startLine.text)
                    let confidenceBoost = FieldValidators.vendorNameConfidenceBoost(vendorName)

                    // Build address from block lines (up to 3 address components)
                    let addressLines = vendorBlock.prefix(3)
                    let addressText = addressLines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: ", ")

                    PrivacyLogger.parsing.debug("Vendor block captured: name + \(vendorBlock.count) address lines")

                    candidates.append(ExtractionCandidate(
                        value: vendorName,
                        confidence: min(1.0, 0.95 * vendorAnchor.confidence + confidenceBoost),
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
                    candidates.append(ExtractionCandidate(
                        value: value,
                        confidence: min(1.0, 0.9 * vendorAnchor.confidence + confidenceBoost),
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

        // Strategy 2: NIP-based fallback with block capture (find vendor name ABOVE NIP in same column)
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

                candidates.append(ExtractionCandidate(
                    value: vendorName,
                    confidence: min(1.0, 0.8 + confidenceBoost),
                    bbox: startLine.bbox,
                    method: .anchorBased,
                    source: "nip-fallback-block: above NIP",
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

        return FieldExtraction(candidates: candidates)
    }

    // MARK: - Vendor Address Extraction (New)

    private func extractVendorAddress(
        layout: LayoutAnalysis,
        vendorExtraction: FieldExtraction,
        nipLine: OCRLineData?,
        allLines: [OCRLineData]
    ) -> FieldExtraction {
        var candidates: [ExtractionCandidate] = []

        // Find vendor name line
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

        return FieldExtraction(candidates: candidates)
    }

    // MARK: - NIP Extraction

    private func extractNIP(
        layout: LayoutAnalysis,
        anchors: [AnchorType: DetectedAnchor],
        allLines: [OCRLineData]
    ) -> FieldExtraction {
        var candidates: [ExtractionCandidate] = []

        // NIP pattern: 10 digits, optionally with separators
        let nipPattern = #"(\d{3}[-\s]?\d{3}[-\s]?\d{2}[-\s]?\d{2}|\d{3}[-\s]?\d{2}[-\s]?\d{2}[-\s]?\d{3}|\d{10})"#

        // Strategy 1: Anchor-based extraction (NIP label)
        if let nipAnchor = anchors[.nipLabel] {
            PrivacyLogger.parsing.debug("Found NIP anchor")

            // Look for NIP value in same line or nearby
            let searchLines = [nipAnchor.line] + layout.linesToRight(of: nipAnchor.line, tolerance: 0.02) + layout.linesBelow(nipAnchor.line, maxDistance: 0.03)

            for line in searchLines {
                if let nip = extractNIPValue(from: line.text, pattern: nipPattern) {
                    // Validate NIP checksum
                    let isValid = FieldValidators.validateNIPChecksum(nip)

                    // Determine if this is vendor NIP based on context
                    let isVendorNIP = isInVendorSection(line: line, layout: layout, anchors: anchors)
                    let baseConfidence = isVendorNIP ? 0.95 : 0.7
                    let checksumBoost = isValid ? 0.05 : -0.1

                    candidates.append(ExtractionCandidate(
                        value: nip,
                        confidence: min(1.0, (baseConfidence + checksumBoost) * nipAnchor.confidence),
                        bbox: line.bbox,
                        method: .anchorBased,
                        source: "anchor: \(nipAnchor.matchedPattern)",
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
                    if let nip = extractNIPValue(from: line.text, pattern: nipPattern) {
                        let isValid = FieldValidators.validateNIPChecksum(nip)
                        let checksumBoost = isValid ? 0.05 : -0.1

                        candidates.append(ExtractionCandidate(
                            value: nip,
                            confidence: min(1.0, (0.7 + checksumBoost) * line.confidence),
                            bbox: line.bbox,
                            method: .regionHeuristic,
                            source: "region: \(region.rawValue)",
                            region: region.rawValue
                        ))
                    }
                }
            }
        }

        // Strategy 3: Pattern matching fallback
        for line in allLines {
            if let nip = extractNIPValue(from: line.text, pattern: nipPattern) {
                // Check if already found
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
        }

        return FieldExtraction(candidates: candidates)
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
        let amountPatterns = [
            #"(\d{1,3}(?:[\s\u{00A0}]?\d{3})*[,\.]\d{2})"#,  // 1 234,56 or 1234.56
            #"(\d+[,\.]\d{2})"#                               // Simple: 1234,56
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

        // Sort by confidence (highest first)
        var sorted = candidates.sorted { $0.confidence > $1.confidence }

        // Detailed logging for amount extraction
        PrivacyLogger.parsing.info("Amount extraction: found \(candidates.count) candidates")
        for (index, candidate) in sorted.prefix(5).enumerated() {
            PrivacyLogger.parsing.info("  Candidate \(index + 1): confidence=\(String(format: "%.3f", candidate.confidence)), y=\(String(format: "%.2f", candidate.bbox.y)), source=\(candidate.source)")
        }

        // Score gap analysis: if top two are close, return both as alternatives
        if sorted.count > 1 {
            let scoreGap = sorted[0].confidence - sorted[1].confidence
            PrivacyLogger.parsing.info("Score gap to 2nd place: \(String(format: "%.3f", scoreGap))")
            if scoreGap < 0.15 {
                PrivacyLogger.parsing.debug("Low score gap - returning multiple amount candidates")
                // Keep top 3 for user selection
                sorted = Array(sorted.prefix(3))
            } else {
                // High confidence gap - return single best with alternatives
                sorted = Array(sorted.prefix(5))
            }
        }

        if let best = sorted.first {
            PrivacyLogger.parsing.info("Selected amount: confidence=\(String(format: "%.3f", best.confidence)), source=\(best.source)")
        }

        // Secondary sort: among similar confidence levels, prefer larger amounts
        let finalSorted = sorted.sorted { lhs, rhs in
            // First by confidence (with threshold)
            if abs(lhs.confidence - rhs.confidence) > 0.08 {
                return lhs.confidence > rhs.confidence
            }
            // Then by amount value (larger = more likely total)
            let lhsValue = parseAmountValue(lhs.value) ?? 0
            let rhsValue = parseAmountValue(rhs.value) ?? 0
            return lhsValue > rhsValue
        }

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

        // Process all lines looking for dates
        for line in allLines {
            guard let dateResult = dateParser.parseDateWithPattern(from: line.text) else {
                continue
            }

            var score = 50.0  // Base score
            var reasons: [String] = []

            let normalized = line.text.lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)

            // STRONG preference for due date keywords
            if dueDateKeywords.contains(where: { normalized.contains($0) }) {
                score += 100
                reasons.append("due-date-keyword")
            }

            // PENALTY for issue date keywords
            if issueDateKeywords.contains(where: { normalized.contains($0) }) {
                score -= 50
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

            // Score by date value (prefer dates in reasonable future)
            let now = Date()
            let daysFromNow = dateResult.date.timeIntervalSince(now) / 86400

            if daysFromNow >= 7 && daysFromNow <= 90 {
                // Likely due date (7-90 days in future)
                score += 40
                reasons.append("future-7-90d")
            } else if daysFromNow > 90 {
                // Too far (unlikely due date)
                score -= 30
                reasons.append("too-far-future")
            } else if daysFromNow < 0 && daysFromNow >= -30 {
                // Recent past date (might be issue date or recently past due)
                score -= 10
                reasons.append("recent-past-date")
            } else if daysFromNow < -30 {
                // Old past date (likely issue date)
                score -= 40
                reasons.append("old-past-date-penalty")
            }

            // Check proximity to due date anchor (if exists)
            if let anchor = anchors[.dueDateLabel] {
                let distance = abs(line.bbox.y - anchor.line.bbox.y)
                if distance < 0.05 {  // Very close
                    score += 60
                    reasons.append("near-due-date-anchor")
                } else if distance < 0.1 {  // Nearby
                    score += 30
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

        // Sort by score (highest first)
        scoredCandidates.sort { $0.score > $1.score }

        // Log scoring results for debugging
        if !scoredCandidates.isEmpty {
            PrivacyLogger.parsing.debug("Date ranking: \(scoredCandidates.count) candidates, top score: \(String(format: "%.1f", scoredCandidates.first?.score ?? 0))")
        }

        // Convert to ExtractionCandidates
        // IMPROVED: Better confidence calibration (changed divisor from 200 to 150)
        // With score=70:  70/150 = 0.47 (was 0.35)
        // With score=100: 100/150 = 0.67 (was 0.50)
        // With score=180: 180/150 = 1.0 -> capped at 0.95
        let candidates: [ExtractionCandidate] = scoredCandidates.prefix(5).map { scored in
            let dateString = formatDateForOutput(scored.date)
            let rawConfidence = scored.score / 150.0  // Changed from 200 to 150 for better calibration
            let normalizedConfidence = min(0.95, max(0.15, rawConfidence))
            let reasonString = scored.reasons.joined(separator: ", ")

            return ExtractionCandidate(
                value: dateString,
                confidence: normalizedConfidence,
                bbox: scored.line.bbox,
                method: scored.reasons.contains("near-due-date-anchor") || scored.reasons.contains("close-to-anchor")
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

        return FieldExtraction(candidates: candidates)
    }

    // MARK: - Bank Account Extraction (Enhanced)

    private func extractBankAccount(
        layout: LayoutAnalysis,
        anchors: [AnchorType: DetectedAnchor],
        allLines: [OCRLineData],
        fullText: String
    ) -> FieldExtraction {
        var candidates: [ExtractionCandidate] = []

        // Bank account patterns
        let accountPatterns = [
            #"[A-Z]{2}\d{2}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}"#,  // IBAN
            #"\d{2}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}[\s]?\d{4}"#,          // Polish 26-digit
            #"\d{26}"#                                                                       // 26 digits no spaces
        ]

        // Strategy 1: Anchor-based extraction
        if let bankAnchor = anchors[.bankAccountLabel] {
            PrivacyLogger.parsing.debug("Found bank account anchor")

            // Check same line
            if let account = extractBankAccountFromLine(bankAnchor.line.text, patterns: accountPatterns) {
                let isValid = FieldValidators.validateIBAN(account)
                let validityBoost = isValid ? 0.05 : -0.1

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
                    let isValid = FieldValidators.validateIBAN(account)
                    let validityBoost = isValid ? 0.05 : -0.1

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
                    let isValid = FieldValidators.validateIBAN(account)
                    let validityBoost = isValid ? 0.05 : -0.1

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
                    let isValid = FieldValidators.validateIBAN(account)
                    let validityBoost = isValid ? 0.05 : -0.1

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
                    let isValid = FieldValidators.validateIBAN(account)
                    let validityBoost = isValid ? 0.05 : -0.1

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

        return FieldExtraction(candidates: candidates)
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

    private func extractAmountFromLine(_ text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(text.startIndex..., in: text)

            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if let valueRange = Range(match.range(at: 1), in: text) {
                    return String(text[valueRange])
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
        // Normalize amount string
        var normalized = string
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "") // Non-breaking space
            .replacingOccurrences(of: ",", with: ".")

        // Handle European format: 1.234,56 -> 1234.56
        if normalized.contains(".") && normalized.last == "6" {
            let parts = normalized.split(separator: ".")
            if parts.count > 2 {
                // Multiple dots - European thousands separator
                normalized = parts.dropLast().joined() + "." + String(parts.last!)
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
            // Polish
            "do zaplaty", "razem", "suma", "brutto", "naleznosc", "kwota", "ogolem", "lacznie",
            // English
            "total", "amount due", "gross", "payable", "balance due", "grand total", "sum",
            "total amount", "amount payable", "net payable"
        ]
        return keywords.contains { lowercased.contains($0) }
    }

    private func containsBruttoKeyword(_ text: String) -> Bool {
        let lowercased = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        // Polish and English keywords for gross/total amounts (not definitive "amount due")
        let keywords = [
            // Polish
            "brutto", "razem", "suma", "ogolem", "wartosc",
            // English
            "gross", "total", "subtotal", "sum"
        ]
        return keywords.contains { lowercased.contains($0) }
    }

    private func containsDueDateKeyword(_ text: String) -> Bool {
        let lowercased = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        // Polish and English keywords for due date
        let keywords = [
            // Polish
            "termin", "platnosci", "platne", "zaplaty", "do dnia", "wplaty",
            // English
            "due", "payable", "pay by", "due date", "payment due", "due by",
            "deadline", "expires", "maturity"
        ]
        return keywords.contains { lowercased.contains($0) }
    }

    private func isDefinitiveAmountAnchor(_ pattern: String) -> Bool {
        // Polish and English definitive amount labels (not just "total" or "brutto")
        let definitive = [
            // Polish
            "do zaplaty", "do zapłaty", "naleznosc", "należność", "kwota do zaplaty",
            "suma do zaplaty", "razem do zaplaty", "lacznie do zaplaty",
            // English
            "amount due", "payable", "total due", "balance due", "amount payable",
            "total payable", "net payable", "pay this amount"
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

    private func extractCurrency(from text: String) -> String? {
        let patterns = [
            #"\b(PLN|EUR|USD|GBP|CHF)\b"#,
            #"(zł|zl|złotych|zlotych)"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if let valueRange = Range(match.range(at: 1), in: text) {
                        let currency = String(text[valueRange]).uppercased()
                        if currency.contains("ZL") || currency.contains("ZŁ") {
                            return "PLN"
                        }
                        return currency
                    }
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

        // This is a degraded mode - use simple pattern matching
        // In production, this should rarely be reached as OCR should provide line data

        let currency = extractCurrency(from: text)
        let regon = extractREGON(from: text)

        // Simple NIP extraction
        let nipPattern = #"(?:NIP|nip)[:\s]*(\d{3}[-\s]?\d{3}[-\s]?\d{2}[-\s]?\d{2}|\d{10})"#
        var vendorNIP: String?
        if let regex = try? NSRegularExpression(pattern: nipPattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if let valueRange = Range(match.range(at: 1), in: text) {
                    vendorNIP = String(text[valueRange]).replacingOccurrences(of: "[-\\s]", with: "", options: .regularExpression)
                }
            }
        }

        return DocumentAnalysisResult(
            documentType: .invoice,
            vendorNIP: vendorNIP,
            vendorREGON: regon,
            currency: currency ?? "PLN",
            overallConfidence: 0.3, // Low confidence for text-only
            provider: providerIdentifier,
            version: analysisVersion,
            rawOCRText: text
        )
    }
}
