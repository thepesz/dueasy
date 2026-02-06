import Foundation
import os.log

// MARK: - Field Validators

/// Field-specific validation utilities for invoice parsing.
/// Provides filters and validation rules for each extracted field type.
enum FieldValidators {

    private static let logger = Logger(subsystem: "com.dueasy.app", category: "FieldValidators")

    // MARK: - Vendor Name Validation

    /// Rejected patterns for vendor name extraction
    private static let vendorRejectedPatterns: [String] = [
        "VAT INVOICE", "INVOICE", "FAKTURA VAT", "FAKTURA",
        "RECEIPT", "PARAGON", "RACHUNEK",
        "PROFORMA", "PRO FORMA",
        "KORYGUJĄCA", "KOREKTA", "CORRECTION",
        "DUPLIKAT", "DUPLICATE"
    ]

    /// Company type suffixes that validate a vendor name
    private static let companyTypeSuffixes: [String] = [
        // Polish
        "sp. z o.o.", "spółka z o.o.", "sp.z.o.o.", "sp.zo.o.",
        "s.a.", "spółka akcyjna",
        "s.c.", "spółka cywilna",
        "s.k.", "spółka komandytowa",
        "s.k.a.", "spółka komandytowo-akcyjna",
        "s.j.", "spółka jawna",
        // German
        "gmbh", "ag", "kg", "ohg", "gbr",
        // English/International
        "ltd", "ltd.", "limited",
        "llc", "l.l.c.",
        "inc", "inc.", "incorporated",
        "corp", "corp.", "corporation",
        "plc", "p.l.c.",
        "co.", "company",
        // French
        "sarl", "sas", "sa"
    ]

    /// Validate if text is a valid vendor name
    /// - Parameter text: Text to validate
    /// - Returns: True if text passes vendor name validation
    static func isValidVendorName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercased = trimmed.uppercased()
        let lowercased = trimmed.lowercased()

        // Minimum length check
        guard trimmed.count > 5 else {
            logger.debug("Vendor rejected: too short '\(trimmed)'")
            return false
        }

        // Must contain mostly letters (at least 60%)
        let letterCount = trimmed.filter { $0.isLetter }.count
        let letterRatio = Double(letterCount) / Double(trimmed.count)
        guard letterRatio > 0.5 else {
            logger.debug("Vendor rejected: not enough letters '\(trimmed)'")
            return false
        }

        // Reject document type headers
        for pattern in vendorRejectedPatterns {
            if uppercased.contains(pattern) {
                logger.debug("Vendor rejected: contains document type '\(trimmed)'")
                return false
            }
        }

        // Reject date patterns
        if looksLikeDate(trimmed) {
            logger.debug("Vendor rejected: looks like date '\(trimmed)'")
            return false
        }

        // Reject account numbers
        if looksLikeAccountNumber(trimmed) {
            // PRIVACY: Don't log actual value
            logger.debug("Vendor rejected: looks like account (length=\(trimmed.count))")
            return false
        }

        // Reject amounts
        if looksLikeAmount(trimmed) {
            // PRIVACY: Don't log actual value
            logger.debug("Vendor rejected: looks like amount (length=\(trimmed.count))")
            return false
        }

        // Reject NIP/REGON/KRS patterns
        if looksLikeNIP(trimmed) || looksLikeREGON(trimmed) || looksLikeKRS(trimmed) {
            // PRIVACY: Don't log actual value
            logger.debug("Vendor rejected: looks like tax ID (length=\(trimmed.count))")
            return false
        }

        // Reject pure numbers with punctuation
        let strippedPunctuation = trimmed.filter { $0.isLetter || $0.isNumber }
        if strippedPunctuation.allSatisfy({ $0.isNumber }) && strippedPunctuation.count > 0 {
            // PRIVACY: Don't log actual value
            logger.debug("Vendor rejected: all numbers (length=\(trimmed.count))")
            return false
        }

        // Bonus: Check for company type suffix (increases confidence but not required)
        let hasCompanySuffix = companyTypeSuffixes.contains { lowercased.contains($0) }
        if hasCompanySuffix {
            logger.debug("Vendor accepted with company suffix: '\(trimmed)'")
        }

        return true
    }

    /// Calculate vendor name confidence boost based on company suffix presence
    static func vendorNameConfidenceBoost(_ text: String) -> Double {
        let lowercased = text.lowercased()
        if companyTypeSuffixes.contains(where: { lowercased.contains($0) }) {
            return 0.1
        }
        return 0.0
    }

    // MARK: - Address Validation

    /// Postal code patterns (Polish & International)
    private static let postalCodePatterns = [
        #"\d{2}-\d{3}"#,           // Polish: NN-NNN (e.g., 02-675)
        #"\d{5}"#,                  // US ZIP: NNNNN (e.g., 10001)
        #"\d{5}-\d{4}"#,           // US ZIP+4: NNNNN-NNNN (e.g., 10001-1234)
        #"[A-Z]{1,2}\d{1,2}[A-Z]?\s*\d[A-Z]{2}"#,  // UK: AA9A 9AA, A9A 9AA, etc.
        #"\d{4}\s?[A-Z]{2}"#       // Netherlands: NNNN AA
    ]

    /// Street prefixes (Polish & English)
    private static let streetPrefixes = [
        // Polish
        "ul.", "al.", "pl.", "os.", "lok.", "m.", "ul ", "al ", "pl ",
        // English
        "street", "st.", "st ", "avenue", "ave.", "ave ", "road", "rd.", "rd ",
        "lane", "ln.", "ln ", "drive", "dr.", "dr ", "boulevard", "blvd.", "blvd ",
        "court", "ct.", "ct ", "place", "pl.", "way", "circle", "cir.",
        "highway", "hwy.", "parkway", "pkwy.", "terrace", "ter."
    ]

    /// Validate if text is a valid address component
    static func isValidAddressComponent(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        guard trimmed.count > 3 else { return false }

        // Check for postal codes (Polish and international)
        for pattern in postalCodePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if regex.firstMatch(in: trimmed, range: range) != nil {
                    return true
                }
            }
        }

        // Check for street prefixes (Polish and English)
        for prefix in streetPrefixes {
            if lowercased.contains(prefix) {
                return true
            }
        }

        // Check for street number patterns (letters followed by digits)
        let streetNumberPattern = #"\d+[a-zA-Z]?(?:/\d+)?"#
        if let regex = try? NSRegularExpression(pattern: streetNumberPattern) {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if regex.firstMatch(in: trimmed, range: range) != nil {
                // Must also have some letters (street name)
                if trimmed.contains(where: { $0.isLetter }) {
                    return true
                }
            }
        }

        // City name heuristic: mostly letters (addresses like "Krakow" or "krakow" from OCR)
        let letterSpaceCount = trimmed.filter { $0.isLetter || $0.isWhitespace || $0 == "-" }.count
        let letterRatio = Double(letterSpaceCount) / Double(trimmed.count)
        if letterRatio > 0.7 && trimmed.count >= 3 {
            // Reject if it looks like a section header keyword
            let lowerTrimmed = trimmed.lowercased()
            let sectionHeaders = ["nabywca", "sprzedawca", "faktura", "buyer", "seller", "invoice", "total", "payment"]
            if !sectionHeaders.contains(where: { lowerTrimmed.hasPrefix($0) }) {
                return true
            }
        }

        return false
    }

    // MARK: - Invoice Number Validation

    /// Allowed characters in invoice numbers
    private static let invoiceNumberAllowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/-._#"))

    /// Validate if text is a valid invoice number
    static func validateInvoiceNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Length check
        guard trimmed.count >= 3 && trimmed.count <= 30 else {
            return false
        }

        // Check for disallowed characters
        if trimmed.unicodeScalars.contains(where: { !invoiceNumberAllowedChars.contains($0) && !$0.properties.isWhitespace }) {
            return false
        }

        // Reject if looks like date
        if looksLikeDate(trimmed) {
            // But allow dates with prefixes like "FV-" or "INV/"
            let prefixPattern = #"^[A-Za-z]{2,4}[-/]"#
            if let regex = try? NSRegularExpression(pattern: prefixPattern) {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if regex.firstMatch(in: trimmed, range: range) == nil {
                    return false
                }
            } else {
                return false
            }
        }

        // Reject if purely numeric and long (likely account number)
        if trimmed.allSatisfy({ $0.isNumber }) && trimmed.count > 15 {
            return false
        }

        // Should have at least one digit (invoice numbers typically have numbers)
        guard trimmed.contains(where: { $0.isNumber }) else {
            return false
        }

        return true
    }

    // MARK: - IBAN Validation

    /// Validate Polish IBAN (28 characters: PL + 26 digits)
    static func validateIBAN(_ iban: String) -> Bool {
        let clean = iban.replacingOccurrences(of: " ", with: "").uppercased()

        // Polish IBAN: PL + 2 check digits + 24 digits = 28 chars
        guard clean.count == 28 else {
            // Also accept 26-digit Polish account without PL prefix
            if clean.count == 26 && clean.allSatisfy({ $0.isNumber }) {
                return validatePolishAccountChecksum(clean)
            }
            return false
        }

        guard clean.hasPrefix("PL") else { return false }

        // Check that remaining characters are digits
        let digits = clean.dropFirst(2)
        guard digits.allSatisfy({ $0.isNumber }) else { return false }

        // Mod 97 checksum validation (ISO 13616)
        return validateIBANChecksum(clean)
    }

    /// Validate IBAN checksum using mod 97 algorithm
    private static func validateIBANChecksum(_ iban: String) -> Bool {
        // Move first 4 chars to end
        let rearranged = String(iban.dropFirst(4)) + String(iban.prefix(4))

        // Convert letters to numbers (A=10, B=11, ..., Z=35)
        var numericString = ""
        for char in rearranged {
            if let digit = char.wholeNumberValue {
                numericString += String(digit)
            } else if let asciiValue = char.asciiValue, char.isLetter {
                let value = Int(asciiValue) - 55 // A=65, so A-55=10
                numericString += String(value)
            } else {
                return false
            }
        }

        // Calculate mod 97 using chunks (number is too large for Int)
        var remainder = 0
        for chunk in numericString.chunked(into: 9) {
            let combined = String(remainder) + chunk
            if let value = Int(combined) {
                remainder = value % 97
            } else {
                return false
            }
        }

        return remainder == 1
    }

    /// Validate Polish 26-digit account number checksum
    private static func validatePolishAccountChecksum(_ account: String) -> Bool {
        guard account.count == 26 && account.allSatisfy({ $0.isNumber }) else {
            return false
        }

        // Polish accounts use IBAN validation with "PL" prefix
        return validateIBANChecksum("PL" + account)
    }

    // MARK: - Pattern Detection Helpers

    /// Check if text looks like a date
    static func looksLikeDate(_ text: String) -> Bool {
        let patterns = [
            #"^\d{2}[-./]\d{2}[-./]\d{4}$"#,    // DD-MM-YYYY, DD.MM.YYYY, DD/MM/YYYY
            #"^\d{4}[-./]\d{2}[-./]\d{2}$"#,    // YYYY-MM-DD
            #"^\d{1,2}\s+\w+\s+\d{4}$"#,        // 15 January 2024
            #"\d{2}[-./]\d{2}[-./]\d{4}"#,      // Contains date pattern
            #"\d{4}[-./]\d{2}[-./]\d{2}"#       // Contains ISO date pattern
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, range: range) != nil {
                    return true
                }
            }
        }

        return false
    }

    /// Check if text looks like an account number (26-30 digits)
    static func looksLikeAccountNumber(_ text: String) -> Bool {
        let digitsOnly = text.filter { $0.isNumber }
        return digitsOnly.count >= 26 && digitsOnly.count <= 30
    }

    /// Check if text looks like a monetary amount
    static func looksLikeAmount(_ text: String) -> Bool {
        let patterns = [
            #"^\d{1,3}(?:[\s\u{00A0}]?\d{3})*[,\.]\d{2}$"#,  // 1 234,56 or 1234.56
            #"^\d+[,\.]\d{2}\s*(?:PLN|EUR|USD|zł|zl|€|\$)?$"#,  // Amount with currency
            #"^(?:PLN|EUR|USD|zł|zl|€|\$)\s*\d"#                // Currency prefix
        ]

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if regex.firstMatch(in: trimmed, range: range) != nil {
                    return true
                }
            }
        }

        return false
    }

    /// Check if text looks like a NIP (Polish Tax ID: 10 digits)
    static func looksLikeNIP(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        // Check if labeled as NIP
        if lowercased.contains("nip") {
            return true
        }

        // Check for 10-digit pattern with optional separators
        let pattern = #"^\d{3}[-\s]?\d{3}[-\s]?\d{2}[-\s]?\d{2}$|^\d{10}$"#
        let digitsOnly = text.filter { $0.isNumber }

        if digitsOnly.count == 10 {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                return regex.firstMatch(in: trimmed, range: range) != nil
            }
        }

        return false
    }

    /// Check if text looks like a REGON (Polish business registry: 9 or 14 digits)
    static func looksLikeREGON(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        if lowercased.contains("regon") {
            return true
        }

        let digitsOnly = text.filter { $0.isNumber }
        return digitsOnly.count == 9 || digitsOnly.count == 14
    }

    /// Check if text looks like a KRS (Polish court registry: 10 digits)
    static func looksLikeKRS(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        if lowercased.contains("krs") {
            return true
        }

        return false
    }

    // MARK: - Amount Validation

    /// Validate if text contains a valid amount pattern
    static func isValidAmount(_ text: String) -> Bool {
        let patterns = [
            #"\d{1,3}(?:[\s\u{00A0}]?\d{3})*[,\.]\d{2}"#,  // 1 234,56 or 1234.56
            #"\d+[,\.]\d{2}"#                               // Simple: 1234,56
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, range: range) != nil {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Deduction Detection

    /// Keywords indicating deductions/discounts/corrections (Polish & English)
    private static let deductionKeywords = [
        // Polish
        "rabat", "zniżka", "znizka", "korekta", "odliczenie", "potrącenie", "potracenie",
        "upust", "bonifikata", "storno", "anulowane", "anulowano",
        // English
        "discount", "deduction", "correction", "credit", "adjustment",
        "rebate", "refund", "credit note", "cancelled", "canceled", "void",
        "allowance", "markdown", "reduction"
    ]

    /// Check if text contains deduction-related keywords
    static func containsDeductionKeywords(_ text: String) -> Bool {
        let normalized = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        return deductionKeywords.contains { normalized.contains($0) }
    }

    // MARK: - NIP Checksum Validation

    /// Validate NIP checksum (weighted sum mod 11)
    static func validateNIPChecksum(_ nip: String) -> Bool {
        let digitsOnly = nip.filter { $0.isNumber }
        guard digitsOnly.count == 10 else { return false }

        let digits = digitsOnly.compactMap { $0.wholeNumberValue }
        guard digits.count == 10 else { return false }

        // NIP weights: 6, 5, 7, 2, 3, 4, 5, 6, 7
        let weights = [6, 5, 7, 2, 3, 4, 5, 6, 7]
        var sum = 0

        for i in 0..<9 {
            sum += digits[i] * weights[i]
        }

        let checkDigit = sum % 11

        // Check digit must not be 10 (invalid NIP if so)
        if checkDigit == 10 {
            return false
        }

        return checkDigit == digits[9]
    }

    // MARK: - US EIN Validation

    /// Validate US EIN (Employer Identification Number) format.
    /// Format: XX-XXXXXXX (2 digits, dash, 7 digits)
    /// The first two digits (prefix) must be a valid IRS campus/service center code.
    static func validateEIN(_ ein: String) -> Bool {
        let digitsOnly = ein.filter { $0.isNumber }
        guard digitsOnly.count == 9 else { return false }

        // Valid EIN prefixes (IRS campus/service center codes)
        // https://www.irs.gov/businesses/small-businesses-self-employed/how-eins-are-assigned-and-valid-ein-prefixes
        let validPrefixes: Set<String> = [
            "01", "02", "03", "04", "05", "06",
            "10", "11", "12", "13", "14", "15", "16",
            "20", "21", "22", "23", "24", "25", "26", "27",
            "30", "31", "32", "33", "34", "35", "36", "37", "38", "39",
            "40", "41", "42", "43", "44", "45", "46", "47", "48",
            "50", "51", "52", "53", "54", "55", "56", "57", "58", "59",
            "60", "61", "62", "63", "64", "65", "66", "67", "68",
            "71", "72", "73", "74", "75", "76", "77",
            "80", "81", "82", "83", "84", "85", "86", "87", "88",
            "90", "91", "92", "93", "94", "95", "98", "99"
        ]

        let prefix = String(digitsOnly.prefix(2))
        return validPrefixes.contains(prefix)
    }

    /// Check if text looks like a US EIN (XX-XXXXXXX format)
    static func looksLikeEIN(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        // Check if labeled as EIN
        if lowercased.contains("ein") || lowercased.contains("employer identification") ||
           lowercased.contains("fein") || lowercased.contains("federal id") {
            return true
        }

        // Check for XX-XXXXXXX pattern
        let pattern = #"\d{2}-\d{7}"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            return regex.firstMatch(in: trimmed, range: range) != nil
        }

        return false
    }

    // MARK: - US Routing Number Validation

    /// Validate US ABA routing transit number using checksum algorithm.
    /// Format: 9 digits. Checksum: 3*d1 + 7*d2 + d3 + 3*d4 + 7*d5 + d6 + 3*d7 + 7*d8 + d9 = multiple of 10
    static func validateUSRoutingNumber(_ routing: String) -> Bool {
        let digitsOnly = routing.filter { $0.isNumber }
        guard digitsOnly.count == 9 else { return false }

        let digits = digitsOnly.compactMap { $0.wholeNumberValue }
        guard digits.count == 9 else { return false }

        // ABA routing number checksum weights: 3, 7, 1, 3, 7, 1, 3, 7, 1
        let weights = [3, 7, 1, 3, 7, 1, 3, 7, 1]
        var sum = 0

        for i in 0..<9 {
            sum += digits[i] * weights[i]
        }

        return sum % 10 == 0
    }
}

// MARK: - String Extension for Chunking

private extension String {
    /// Split string into chunks of specified size
    func chunked(into size: Int) -> [String] {
        var chunks: [String] = []
        var currentIndex = startIndex

        while currentIndex < endIndex {
            let endIndex = index(currentIndex, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[currentIndex..<endIndex]))
            currentIndex = endIndex
        }

        return chunks
    }
}
