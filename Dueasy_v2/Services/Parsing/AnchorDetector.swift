import Foundation
import os.log

// MARK: - Anchor Type

/// Types of anchor labels that can be detected in documents.
/// Anchors are labels that indicate where specific values should be found.
enum AnchorType: String, Codable, Sendable, CaseIterable {
    /// Vendor/seller label: "Sprzedawca", "Seller", "Issuer", "Vendor", "From"
    case vendorLabel = "vendorLabel"

    /// Buyer/recipient label: "Nabywca", "Buyer", "Recipient", "Bill To"
    case buyerLabel = "buyerLabel"

    /// Due date label: "Termin platnosci", "Payment due", "Due date"
    case dueDateLabel = "dueDateLabel"

    /// Amount label: "Do zaplaty", "Amount due", "Total payable"
    case amountLabel = "amountLabel"

    /// Tax ID label: "NIP", "Tax ID", "VAT", "REGON", "KRS"
    case nipLabel = "nipLabel"

    /// Invoice number label: "Faktura nr", "Invoice No", "Invoice Number"
    case invoiceNumberLabel = "invoiceNumberLabel"

    /// General date label: "Data", "Date", "Data wystawienia"
    case dateLabel = "dateLabel"

    /// Bank account label: "Konto", "Account", "Bank Account", "IBAN"
    case bankAccountLabel = "bankAccountLabel"

    /// REGON label (Polish business registry)
    case regonLabel = "regonLabel"

    /// Payment terms label: "Forma platnosci", "Payment method"
    case paymentTermsLabel = "paymentTermsLabel"

    /// Typical document region where this anchor appears
    var typicalRegion: DocumentRegion {
        switch self {
        case .vendorLabel: return .topLeft
        case .buyerLabel: return .topRight
        case .dueDateLabel: return .topRight
        case .amountLabel: return .bottomRight
        case .nipLabel: return .middleLeft
        case .invoiceNumberLabel: return .topCenter
        case .dateLabel: return .topRight
        case .bankAccountLabel: return .bottomLeft
        case .regonLabel: return .middleLeft
        case .paymentTermsLabel: return .middleCenter
        }
    }
}

// MARK: - Detected Anchor

/// A detected anchor label in the document with its location and confidence.
struct DetectedAnchor: Sendable {
    /// Type of anchor detected
    let type: AnchorType

    /// The OCR line containing this anchor
    let line: OCRLineData

    /// Confidence score for this detection (0.0-1.0)
    let confidence: Double

    /// The pattern that matched this anchor
    let matchedPattern: String

    /// Position within the line where the anchor was found (character index)
    let positionInLine: Int

    /// Whether the anchor appears to be a label (e.g., followed by colon or whitespace)
    let isLabel: Bool

    /// Bounding box of the anchor (same as line bbox for now)
    var bbox: BoundingBox {
        line.bbox
    }
}

// MARK: - Anchor Patterns

/// Multilingual anchor pattern definitions.
/// Patterns are organized by anchor type with confidence weights.
enum AnchorPatterns {

    // MARK: - Vendor/Seller Patterns (Polish & English)

    static let vendorPatterns: [(pattern: String, confidence: Double)] = [
        // Polish patterns - highest confidence for explicit labels
        ("sprzedawca", 0.95),
        ("sprzedawcy", 0.90),       // Genitive form
        ("dane sprzedawcy", 0.95),  // "Seller data" - very explicit
        ("wystawca", 0.90),
        ("wystawca faktury", 0.95),
        ("dostawca", 0.85),
        ("uslugodawca", 0.85),
        ("usługodawca", 0.85),      // With diacritic
        ("od", 0.50),               // "From" - lower confidence
        ("podatnik", 0.70),         // "Taxpayer" - often seller
        ("nadawca", 0.80),          // "Sender"
        // English/US patterns
        ("seller", 0.90),
        ("vendor", 0.90),
        ("supplier", 0.85),
        ("provider", 0.80),
        ("from", 0.60),
        ("issued by", 0.85),
        ("billed by", 0.85),
        ("service provider", 0.80),
        ("merchant", 0.75),
        ("remit to", 0.90),         // US: payment remittance address
        ("pay to the order of", 0.90),
        ("pay to", 0.85),
        ("payee", 0.80),
        ("bill from", 0.85),
        ("company", 0.50),          // Very generic - low confidence
        ("contractor", 0.75),
    ]

    // MARK: - Buyer Patterns (Polish & English)

    static let buyerPatterns: [(pattern: String, confidence: Double)] = [
        // Polish patterns
        ("nabywca", 0.95),
        ("nabywcy", 0.90),          // Genitive form
        ("kupujacy", 0.90),
        ("kupujący", 0.90),         // With diacritic
        ("odbiorca", 0.85),
        ("klient", 0.80),
        ("platnik", 0.80),
        ("płatnik", 0.80),          // With diacritic
        // English/US patterns
        ("buyer", 0.95),
        ("purchaser", 0.90),
        ("recipient", 0.85),
        ("customer", 0.80),
        ("bill to", 0.90),
        ("billed to", 0.90),
        ("sold to", 0.85),
        ("ship to", 0.75),          // Lower - could be different from buyer
        ("client", 0.80),
        ("customer no", 0.85),
        ("customer number", 0.85),
        ("account holder", 0.80),
        ("attention", 0.70),        // "Attention: John Doe"
        ("attn", 0.70),
        ("deliver to", 0.75),
        ("to", 0.40),               // Very low - too generic
    ]

    // MARK: - Due Date Patterns (Polish & English)

    static let dueDatePatterns: [(pattern: String, confidence: Double)] = [
        // Polish patterns (full forms)
        ("termin platnosci", 0.95),
        ("termin płatności", 0.95), // With diacritics
        ("termin zaplaty", 0.90),
        ("termin zapłaty", 0.90),   // With diacritics
        ("data platnosci", 0.85),
        ("data płatności", 0.85),   // With diacritics
        ("do zaplaty do", 0.85),
        ("do zapłaty do", 0.85),    // With diacritics
        ("platne do", 0.90),
        ("płatne do", 0.90),        // With diacritics
        ("platnosc do", 0.85),
        ("płatność do", 0.85),      // With diacritics
        // Polish patterns (abbreviated/OCR-friendly - common on scanned invoices)
        ("t. platnosci", 0.85),
        ("t. płatności", 0.85),
        ("termin plat", 0.80),      // Truncated by OCR
        ("termin płat", 0.80),
        ("wplaty do", 0.80),
        ("wpłaty do", 0.80),
        ("zaplata do", 0.80),
        ("zapłata do", 0.80),
        // English/US patterns
        ("payment due", 0.95),
        ("due date", 0.95),
        ("payable by", 0.90),
        ("pay by", 0.85),
        ("due by", 0.85),
        ("payment deadline", 0.90),
        ("due on", 0.80),
        ("payment due date", 0.98),
        ("please pay by", 0.90),
        ("must be paid by", 0.90),
        ("terms", 0.60),            // "Terms: Net 30" - generic
        ("net 30", 0.75),           // Common US payment terms
        ("net 15", 0.75),
        ("net 60", 0.75),
        ("net 90", 0.70),
        ("net", 0.55),              // "Net 30" etc - lower confidence
        ("upon receipt", 0.80),     // "Due upon receipt"
        ("due upon receipt", 0.90),
    ]

    // MARK: - Amount Patterns (Polish & English)

    static let amountPatterns: [(pattern: String, confidence: Double)] = [
        // Polish patterns (definitive - "amount to pay")
        ("do zaplaty", 0.95),
        ("do zapłaty", 0.95),       // With diacritic
        ("razem do zaplaty", 0.98),
        ("razem do zapłaty", 0.98), // With diacritic
        ("suma do zaplaty", 0.95),
        ("suma do zapłaty", 0.95),  // With diacritic
        ("lacznie do zaplaty", 0.95),
        ("łącznie do zapłaty", 0.95), // With diacritics
        ("kwota do zaplaty", 0.95),
        ("kwota do zapłaty", 0.95), // With diacritic
        ("nalezy zaplacic", 0.90),  // "amount to be paid"
        ("należy zapłacić", 0.90),  // With diacritics
        ("naleznosc", 0.80),
        ("należność", 0.80),        // With diacritic
        // OCR-resilient Polish patterns (common OCR misreadings)
        ("do zap", 0.85),           // Truncated by OCR line break
        ("do zapl", 0.85),          // Truncated by OCR line break
        ("dozaplaty", 0.90),        // OCR merges words (no space)
        ("do zaptaty", 0.85),       // OCR misreads ł as t
        ("do zapiaty", 0.85),       // OCR misreads ł as i
        ("do zaplaly", 0.85),       // OCR misreads t as l
        ("razem do zapl", 0.90),    // Truncated compound form
        ("do zap aty", 0.85),       // OCR inserts extra space in ł
        ("do zaplacenia", 0.90),    // Alternative phrasing "to be paid"
        ("do zapiacenia", 0.85),    // OCR misread of above
        // Polish patterns (total/gross)
        ("razem", 0.70),            // "Total" - lower confidence
        ("suma", 0.65),             // "Sum" - lower confidence
        ("brutto", 0.75),           // Gross amount
        ("ogolna wartosc brutto", 0.85),
        ("ogólna wartość brutto", 0.85), // With diacritics
        ("wartosc brutto", 0.80),
        ("wartość brutto", 0.80),
        ("razem brutto", 0.80),
        // Polish patterns (OCR-friendly/abbreviated)
        ("kwota", 0.60),            // "Amount" - generic
        ("wartosc", 0.55),
        ("wartość", 0.55),
        // English/US patterns
        ("amount due", 0.95),
        ("total due", 0.95),
        ("total payable", 0.95),
        ("amount payable", 0.90),
        ("total amount", 0.85),
        ("balance due", 0.90),
        ("grand total", 0.85),
        ("invoice total", 0.90),
        ("total charges", 0.85),
        ("amount owed", 0.90),
        ("payment amount", 0.85),
        ("please pay", 0.85),
        ("pay this amount", 0.90),
        ("net amount", 0.80),
        ("net payable", 0.85),
        ("total", 0.70),            // Generic - lower confidence
        ("amount", 0.55),           // Very generic
        ("subtotal", 0.50),         // Usually not the final amount
    ]

    // MARK: - NIP/Tax ID Patterns

    static let nipPatterns: [(pattern: String, confidence: Double)] = [
        // Polish patterns
        ("nip", 0.95),
        ("nr nip", 0.95),
        ("numer nip", 0.95),
        ("nip sprzedawcy", 0.98),
        ("nip nabywcy", 0.98),
        // English/International patterns
        ("tax id", 0.90),
        ("tax identification", 0.90),
        ("tax identification number", 0.95),
        ("vat", 0.80),              // Could be VAT rate, not ID
        ("vat number", 0.90),
        ("vat no", 0.90),
        ("vat id", 0.90),
        ("tin", 0.85),              // Tax Identification Number
        ("tax number", 0.85),
        // US-specific patterns
        ("ein", 0.90),              // Employer Identification Number
        ("employer identification", 0.90),
        ("fein", 0.90),             // Federal Employer Identification Number
        ("federal id", 0.85),
        ("federal tax id", 0.90),
        ("tax id number", 0.90),
    ]

    // MARK: - REGON Patterns

    static let regonPatterns: [(pattern: String, confidence: Double)] = [
        ("regon", 0.95),
        ("nr regon", 0.95),
        ("numer regon", 0.95),
    ]

    // MARK: - Invoice Number Patterns (Polish & English)

    static let invoiceNumberPatterns: [(pattern: String, confidence: Double)] = [
        // Polish patterns
        ("faktura", 0.85),
        ("faktura nr", 0.95),
        ("faktura numer", 0.95),
        ("faktura vat", 0.90),
        ("faktura vat nr", 0.98),
        ("nr faktury", 0.95),
        ("numer faktury", 0.95),
        ("dokument nr", 0.80),
        ("numer dokumentu", 0.80),
        // English/US patterns
        ("invoice", 0.80),
        ("invoice no", 0.95),
        ("invoice number", 0.95),
        ("invoice #", 0.95),
        ("inv no", 0.90),
        ("inv #", 0.90),
        ("inv", 0.75),              // Short form
        ("invoice ref", 0.85),
        ("reference no", 0.80),
        ("reference number", 0.80),
        ("ref no", 0.80),
        ("ref #", 0.80),
        ("reference", 0.60),        // Generic - lower confidence
        ("document no", 0.80),
        ("doc no", 0.75),
        ("doc #", 0.75),
        // US-specific patterns
        ("bill no", 0.90),
        ("bill number", 0.90),
        ("bill #", 0.90),
        ("statement no", 0.85),
        ("statement number", 0.85),
        ("statement #", 0.85),
        ("order no", 0.75),         // Could be PO number
        ("order number", 0.75),
        ("order #", 0.75),
        ("po number", 0.70),        // Purchase order - lower, different from invoice
        ("po #", 0.70),
        ("purchase order", 0.70),
    ]

    // MARK: - Date Patterns (Polish & English)

    static let datePatterns: [(pattern: String, confidence: Double)] = [
        // Polish patterns
        ("data", 0.70),             // Generic "date"
        ("data wystawienia", 0.95),
        ("data sprzedazy", 0.85),
        ("data sprzedaży", 0.85),   // With diacritic
        ("data faktury", 0.90),
        ("wystawiono", 0.80),
        ("wystawiona", 0.80),
        // English/US patterns
        ("date", 0.70),
        ("invoice date", 0.95),
        ("issue date", 0.95),
        ("date of issue", 0.95),
        ("date of invoice", 0.90),
        ("billing date", 0.90),
        ("bill date", 0.90),
        ("statement date", 0.90),
        ("dated", 0.80),
        ("issued", 0.75),
        ("issued on", 0.85),
        ("created", 0.70),
        ("period", 0.60),           // "Billing period" - generic
        ("service date", 0.80),
        ("transaction date", 0.80),
    ]

    // MARK: - Bank Account Patterns (Polish & English)

    static let bankAccountPatterns: [(pattern: String, confidence: Double)] = [
        // Polish patterns
        ("konto", 0.85),
        ("nr konta", 0.95),
        ("numer konta", 0.95),
        ("rachunek", 0.85),
        ("nr rachunku", 0.95),
        ("numer rachunku", 0.95),
        ("rachunek bankowy", 0.95),
        ("konto bankowe", 0.95),
        ("przelew na konto", 0.90),
        // English/International patterns
        ("account", 0.80),
        ("bank account", 0.95),
        ("account no", 0.95),
        ("account number", 0.95),
        ("iban", 0.95),
        ("swift", 0.80),
        ("bic", 0.80),
        // US-specific banking patterns
        ("routing number", 0.90),
        ("routing no", 0.90),
        ("routing #", 0.90),
        ("aba number", 0.90),       // ABA routing transit number
        ("aba", 0.75),
        ("wire transfer", 0.85),
        ("wire instructions", 0.90),
        ("ach", 0.80),              // Automated Clearing House
        ("bank details", 0.90),
        ("banking details", 0.90),
        ("payment details", 0.85),
        ("remittance", 0.80),
        ("remittance info", 0.85),
    ]

    // MARK: - Payment Terms Patterns

    static let paymentTermsPatterns: [(pattern: String, confidence: Double)] = [
        // Polish patterns
        ("forma platnosci", 0.95),
        ("forma płatności", 0.95),  // With diacritics
        ("sposob platnosci", 0.90),
        ("sposób płatności", 0.90), // With diacritics
        ("metoda platnosci", 0.90),
        ("metoda płatności", 0.90), // With diacritics
        ("przelew", 0.80),
        ("gotowka", 0.80),
        ("gotówka", 0.80),          // With diacritic
        // English/US patterns
        ("payment method", 0.95),
        ("payment terms", 0.90),
        ("pay by", 0.75),
        ("payment type", 0.85),
        ("payment info", 0.85),
        ("payment information", 0.90),
        ("how to pay", 0.85),
        ("accepted payments", 0.80),
        ("wire transfer", 0.80),
        ("check", 0.65),            // Could be generic
        ("credit card", 0.75),
        ("bank transfer", 0.85),
    ]

    /// Get patterns for a specific anchor type
    static func patterns(for type: AnchorType) -> [(pattern: String, confidence: Double)] {
        switch type {
        case .vendorLabel: return vendorPatterns
        case .buyerLabel: return buyerPatterns
        case .dueDateLabel: return dueDatePatterns
        case .amountLabel: return amountPatterns
        case .nipLabel: return nipPatterns
        case .regonLabel: return regonPatterns
        case .invoiceNumberLabel: return invoiceNumberPatterns
        case .dateLabel: return datePatterns
        case .bankAccountLabel: return bankAccountPatterns
        case .paymentTermsLabel: return paymentTermsPatterns
        }
    }
}

// MARK: - Anchor Detector

/// Detects anchor labels in OCR text that indicate where values should be found.
/// Uses multilingual pattern matching with fuzzy tolerance.
final class AnchorDetector: Sendable {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "AnchorDetector")

    /// Minimum confidence threshold for anchor detection
    static let minimumConfidence: Double = 0.5

    /// Whether to use fuzzy matching (diacritic-insensitive)
    let useFuzzyMatching: Bool

    init(useFuzzyMatching: Bool = true) {
        self.useFuzzyMatching = useFuzzyMatching
    }

    // MARK: - Main Detection

    /// Detect all anchors in the given OCR lines.
    /// - Parameter lines: OCR line data to analyze
    /// - Returns: Array of detected anchors, sorted by confidence
    func detectAnchors(in lines: [OCRLineData]) -> [DetectedAnchor] {
        var allAnchors: [DetectedAnchor] = []

        for line in lines {
            let anchorsInLine = detectAnchorsInLine(line)
            allAnchors.append(contentsOf: anchorsInLine)
        }

        // Sort by confidence descending
        let sorted = allAnchors.sorted { $0.confidence > $1.confidence }

        logger.info("Detected \(sorted.count) anchors in \(lines.count) lines")

        // Log top anchors for debugging
        for anchor in sorted.prefix(5) {
            logger.debug("Anchor: \(anchor.type.rawValue) conf=\(String(format: "%.2f", anchor.confidence)) pattern='\(anchor.matchedPattern)'")
        }

        return sorted
    }

    /// Find anchors of a specific type in the given lines.
    /// - Parameters:
    ///   - type: Type of anchor to find
    ///   - lines: OCR lines to search
    /// - Returns: Matching anchor, or nil if not found
    func findAnchor(type: AnchorType, in lines: [OCRLineData]) -> DetectedAnchor? {
        let patterns = AnchorPatterns.patterns(for: type)

        for line in lines {
            if let anchor = matchPatterns(patterns, in: line, anchorType: type) {
                if anchor.confidence >= Self.minimumConfidence {
                    return anchor
                }
            }
        }

        return nil
    }

    /// Find all anchors of a specific type in the given lines.
    /// - Parameters:
    ///   - type: Type of anchor to find
    ///   - lines: OCR lines to search
    /// - Returns: Array of matching anchors, sorted by confidence
    func findAllAnchors(type: AnchorType, in lines: [OCRLineData]) -> [DetectedAnchor] {
        let patterns = AnchorPatterns.patterns(for: type)
        var anchors: [DetectedAnchor] = []

        for line in lines {
            if let anchor = matchPatterns(patterns, in: line, anchorType: type) {
                if anchor.confidence >= Self.minimumConfidence {
                    anchors.append(anchor)
                }
            }
        }

        return anchors.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Internal Detection

    private func detectAnchorsInLine(_ line: OCRLineData) -> [DetectedAnchor] {
        var anchors: [DetectedAnchor] = []

        for anchorType in AnchorType.allCases {
            let patterns = AnchorPatterns.patterns(for: anchorType)
            if let anchor = matchPatterns(patterns, in: line, anchorType: anchorType) {
                if anchor.confidence >= Self.minimumConfidence {
                    anchors.append(anchor)
                }
            }
        }

        return anchors
    }

    private func matchPatterns(
        _ patterns: [(pattern: String, confidence: Double)],
        in line: OCRLineData,
        anchorType: AnchorType
    ) -> DetectedAnchor? {
        let normalizedText = normalizeText(line.text)

        var bestMatch: (pattern: String, confidence: Double, position: Int)?

        for (pattern, baseConfidence) in patterns {
            let normalizedPattern = normalizeText(pattern)

            // Try exact match first
            if let range = normalizedText.range(of: normalizedPattern) {
                let position = normalizedText.distance(from: normalizedText.startIndex, to: range.lowerBound)

                // Boost confidence based on position (anchors at start are more reliable)
                let positionBoost = position == 0 ? 0.05 : 0.0

                // Check if it looks like a label (followed by colon, whitespace, or at end)
                let isLabel = checkIfLabel(normalizedText, patternRange: range)
                let labelBoost = isLabel ? 0.05 : 0.0

                let totalConfidence = min(1.0, baseConfidence + positionBoost + labelBoost)

                if bestMatch == nil || totalConfidence > bestMatch!.confidence {
                    bestMatch = (pattern, totalConfidence, position)
                }
            }
        }

        guard let match = bestMatch else { return nil }

        // Determine if the matched text appears to be a label
        let normalizedPattern = normalizeText(match.pattern)
        let isLabel: Bool
        if let range = normalizedText.range(of: normalizedPattern) {
            isLabel = checkIfLabel(normalizedText, patternRange: range)
        } else {
            isLabel = false
        }

        return DetectedAnchor(
            type: anchorType,
            line: line,
            confidence: match.confidence,
            matchedPattern: match.pattern,
            positionInLine: match.position,
            isLabel: isLabel
        )
    }

    // MARK: - Text Normalization

    /// Normalize text for pattern matching.
    /// - Lowercase
    /// - Remove diacritics (Polish characters)
    /// - Normalize whitespace
    private func normalizeText(_ text: String) -> String {
        var normalized = text.lowercased()

        if useFuzzyMatching {
            // Remove Polish diacritics
            normalized = normalized.folding(options: .diacriticInsensitive, locale: .current)
        }

        // Normalize whitespace
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: .whitespaces)

        return normalized
    }

    /// Check if a pattern match looks like a label.
    /// Labels are typically followed by colon, significant whitespace, or are at line end.
    private func checkIfLabel(_ text: String, patternRange: Range<String.Index>) -> Bool {
        // If pattern is at the end of the text
        if patternRange.upperBound == text.endIndex {
            return true
        }

        // Get character after the pattern
        let afterPattern = text[patternRange.upperBound...]
        let trimmed = afterPattern.trimmingCharacters(in: .whitespaces)

        // Check for colon
        if trimmed.hasPrefix(":") {
            return true
        }

        // Check for significant content after (suggests this is a label)
        if trimmed.count > 0 {
            return true
        }

        return false
    }
}

// MARK: - Anchor Detector Extensions

extension AnchorDetector {

    /// Group detected anchors by type.
    /// - Parameter anchors: Anchors to group
    /// - Returns: Dictionary mapping anchor types to arrays of anchors
    func groupByType(_ anchors: [DetectedAnchor]) -> [AnchorType: [DetectedAnchor]] {
        var grouped: [AnchorType: [DetectedAnchor]] = [:]

        for anchor in anchors {
            grouped[anchor.type, default: []].append(anchor)
        }

        // Sort each group by confidence
        for (type, anchorsOfType) in grouped {
            grouped[type] = anchorsOfType.sorted { $0.confidence > $1.confidence }
        }

        return grouped
    }

    /// Get the best anchor for each type.
    /// - Parameter anchors: Anchors to analyze
    /// - Returns: Dictionary mapping anchor types to the best anchor of that type
    func bestAnchors(from anchors: [DetectedAnchor]) -> [AnchorType: DetectedAnchor] {
        var best: [AnchorType: DetectedAnchor] = [:]

        for anchor in anchors {
            if let existing = best[anchor.type] {
                if anchor.confidence > existing.confidence {
                    best[anchor.type] = anchor
                }
            } else {
                best[anchor.type] = anchor
            }
        }

        return best
    }
}
