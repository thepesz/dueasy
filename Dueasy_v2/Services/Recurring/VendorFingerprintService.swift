import Foundation
import CryptoKit
import os.log

/// Result of fingerprint generation including metadata about certainty.
struct FingerprintResult: Sendable {
    /// The SHA256 fingerprint hash
    let fingerprint: String

    /// Whether the fingerprint was generated without NIP (fallback mode).
    /// Fallback fingerprints have lower certainty as they rely only on normalized vendor name.
    let isFallback: Bool

    /// The normalized vendor name used for generation
    let normalizedName: String

    /// The normalized NIP used (nil if fallback)
    let normalizedNIP: String?
}

/// Service for generating consistent vendor fingerprints for matching recurring payments.
/// Uses SHA256 hash of normalized vendor name + NIP for stable identification.
///
/// Normalization rules:
/// - Lowercase all text
/// - Remove Polish diacritical marks
/// - Remove common business suffixes (sp. z o.o., s.a., etc.)
/// - Remove punctuation and extra whitespace
/// - Remove common prefixes (firma, przedsiebiorstwo, etc.)
///
/// The fingerprint is stable across:
/// - OCR variations in capitalization
/// - Minor spelling differences
/// - Different formatting of the same vendor
protocol VendorFingerprintServiceProtocol: Sendable {
    /// Generates a fingerprint from vendor name and optional NIP.
    /// - Parameters:
    ///   - vendorName: Raw vendor name from document
    ///   - nip: Optional NIP (Polish tax ID)
    /// - Returns: SHA256 fingerprint string
    func generateFingerprint(vendorName: String, nip: String?) -> String

    /// Generates a fingerprint with metadata about certainty.
    /// - Parameters:
    ///   - vendorName: Raw vendor name from document
    ///   - nip: Optional NIP (Polish tax ID)
    /// - Returns: FingerprintResult containing fingerprint and metadata
    func generateFingerprintWithMetadata(vendorName: String, nip: String?) -> FingerprintResult

    /// Normalizes a vendor name for comparison and fingerprinting.
    /// - Parameter vendorName: Raw vendor name
    /// - Returns: Normalized vendor name
    func normalizeVendorName(_ vendorName: String) -> String

    /// Normalizes a NIP for comparison.
    /// - Parameter nip: Raw NIP string
    /// - Returns: Normalized NIP (digits only)
    func normalizeNIP(_ nip: String) -> String
}

/// Default implementation of VendorFingerprintService
final class VendorFingerprintService: VendorFingerprintServiceProtocol, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "VendorFingerprint")

    // MARK: - Polish Diacritical Mapping

    private static let polishDiacriticsMap: [Character: Character] = [
        "ą": "a", "Ą": "A",
        "ć": "c", "Ć": "C",
        "ę": "e", "Ę": "E",
        "ł": "l", "Ł": "L",
        "ń": "n", "Ń": "N",
        "ó": "o", "Ó": "O",
        "ś": "s", "Ś": "S",
        "ź": "z", "Ź": "Z",
        "ż": "z", "Ż": "Z"
    ]

    // MARK: - Business Suffix Patterns

    /// Common Polish and international business suffixes to remove
    private static let businessSuffixes: [String] = [
        // Polish
        "sp. z o.o.", "sp.z o.o.", "spzoo", "sp z o o", "spolka z ograniczona odpowiedzialnoscia",
        "sp. z o. o.", "sp.z.o.o.", "sp. z.o.o",
        "s.a.", "sa", "spolka akcyjna",
        "sp.j.", "spj", "spolka jawna",
        "sp.k.", "spk", "spolka komandytowa",
        "sp.p.", "spp", "spolka partnerska",
        "s.c.", "sc", "spolka cywilna",
        "psp", "phu", "pphu", "fhu", "phup",
        // International
        "ltd", "ltd.", "limited",
        "llc", "l.l.c.",
        "inc", "inc.", "incorporated",
        "corp", "corp.", "corporation",
        "gmbh", "ag",
        "bv", "nv",
        "srl", "sarl"
    ]

    /// Common prefixes to remove
    private static let businessPrefixes: [String] = [
        "firma", "przedsiebiorstwo", "zaklad", "biuro", "kancelaria",
        "centrum", "grupa", "holding", "polski", "polskie",
        "company", "the"
    ]

    /// Common words to remove (not meaningful for identification)
    private static let stopWords: [String] = [
        "i", "oraz", "lub", "and", "or", "of", "the", "a", "an"
    ]

    // MARK: - VendorFingerprintServiceProtocol

    func generateFingerprint(vendorName: String, nip: String?) -> String {
        return generateFingerprintWithMetadata(vendorName: vendorName, nip: nip).fingerprint
    }

    func generateFingerprintWithMetadata(vendorName: String, nip: String?) -> FingerprintResult {
        let normalizedName = normalizeVendorName(vendorName)
        let normalizedNIP = nip.map { normalizeNIP($0) }

        // Combine name and NIP for fingerprint
        // NIP takes precedence when available (more stable identifier)
        let combined: String
        let isFallback: Bool

        if let normalizedNIP = normalizedNIP, !normalizedNIP.isEmpty {
            combined = "\(normalizedName)|\(normalizedNIP)"
            isFallback = false
            logger.debug("Generating fingerprint with NIP for vendor: \(vendorName.prefix(30))...")
        } else {
            // Fallback: use normalized name only
            // Mark as lower certainty - this handles:
            // - OCR failures to extract NIP
            // - Foreign invoices without Polish NIP
            combined = normalizedName
            isFallback = true
            logger.warning("Generating FALLBACK fingerprint (no NIP) for vendor: \(vendorName.prefix(30))... - lower certainty")
        }

        // Generate SHA256 hash
        let data = Data(combined.utf8)
        let hash = SHA256.hash(data: data)
        let fingerprint = hash.compactMap { String(format: "%02x", $0) }.joined()

        return FingerprintResult(
            fingerprint: fingerprint,
            isFallback: isFallback,
            normalizedName: normalizedName,
            normalizedNIP: isFallback ? nil : normalizedNIP
        )
    }

    func normalizeVendorName(_ vendorName: String) -> String {
        var result = vendorName

        // Step 1: Lowercase
        result = result.lowercased()

        // Step 2: Remove Polish diacritics
        result = String(result.map { Self.polishDiacriticsMap[$0] ?? $0 })

        // Step 3: Remove business suffixes
        for suffix in Self.businessSuffixes {
            if result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
            }
            // Also check with period variations
            result = result.replacingOccurrences(of: " \(suffix)", with: "")
            result = result.replacingOccurrences(of: "\(suffix)", with: "")
        }

        // Step 4: Remove business prefixes
        for prefix in Self.businessPrefixes {
            if result.hasPrefix("\(prefix) ") {
                result = String(result.dropFirst(prefix.count + 1))
            }
        }

        // Step 5: Remove punctuation (keep alphanumeric and spaces)
        result = result.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0) }
            .map { String($0) }
            .joined()

        // Step 6: Remove stop words
        let words = result.split(separator: " ").map(String.init)
        let filteredWords = words.filter { !Self.stopWords.contains($0) && !$0.isEmpty }
        result = filteredWords.joined(separator: " ")

        // Step 7: Collapse multiple spaces and trim
        result = result.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return result
    }

    func normalizeNIP(_ nip: String) -> String {
        // Remove all non-digit characters
        let digitsOnly = nip.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
            .map { String($0) }
            .joined()

        // Polish NIP should be 10 digits
        // Return as-is for flexibility (might be international tax IDs)
        return digitsOnly
    }
}
