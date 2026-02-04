import Foundation
import CryptoKit
import os.log

// MARK: - Amount Bucket Configuration

/// Configuration for amount bucketing in fingerprint generation.
/// Amount buckets allow grouping similar amounts together while separating significantly different ones.
///
/// **Bucketing Strategy:**
/// - Amounts within a tolerance percentage of each other are considered the same bucket
/// - Default tolerance is 10% (e.g., 500 PLN and 550 PLN are in the same bucket)
/// - Bucket boundaries are determined by the amount's magnitude
///
/// **Example Buckets (with 10% tolerance):**
/// - 500 PLN -> bucket "450-550" (10% range around 500)
/// - 1200 PLN -> bucket "1080-1320" (10% range around 1200)
/// - 45.50 PLN -> bucket "41-50" (10% range around 45.50)
enum AmountBucketStrategy: Sendable {
    /// Use amount buckets in fingerprint (separates different payment types from same vendor)
    case enabled(tolerancePercent: Double)

    /// Do not use amount in fingerprint (legacy behavior)
    case disabled

    /// Default strategy: 15% tolerance to handle minor price changes
    static let `default`: AmountBucketStrategy = .enabled(tolerancePercent: 15.0)
}

// MARK: - Fingerprint Result

/// Result of fingerprint generation including metadata about certainty and components.
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

    /// The amount bucket identifier used (nil if amount bucketing disabled)
    let amountBucket: String?

    /// The vendor-only fingerprint (without amount bucket) for finding related templates
    let vendorOnlyFingerprint: String

    /// Components used to generate the fingerprint (for debugging/logging)
    var components: String {
        var parts = [normalizedName]
        if let nip = normalizedNIP {
            parts.append("nip:\(nip)")
        }
        if let bucket = amountBucket {
            parts.append("amount:\(bucket)")
        }
        return parts.joined(separator: "|")
    }
}

/// Service for generating consistent vendor fingerprints for matching recurring payments.
/// Uses SHA256 hash of normalized vendor name + NIP + amount bucket for stable identification.
///
/// **Fingerprint Components (v2):**
/// 1. Normalized vendor name (required)
/// 2. NIP - Polish tax ID (optional, increases confidence)
/// 3. Amount bucket (optional, separates different services from same vendor)
///
/// **Amount Bucketing:**
/// Addresses the case where one vendor has multiple recurring payments:
/// - Santander Credit Card: 500 PLN on day 15
/// - Santander Loan: 1200 PLN on day 5
///
/// Without amount bucketing, both would match the same template.
/// With amount bucketing, they get separate fingerprints.
///
/// **Normalization rules:**
/// - Lowercase all text
/// - Remove Polish diacritical marks
/// - Remove common business suffixes (sp. z o.o., s.a., etc.)
/// - Remove punctuation and extra whitespace
/// - Remove common prefixes (firma, przedsiebiorstwo, etc.)
///
/// **The fingerprint is stable across:**
/// - OCR variations in capitalization
/// - Minor spelling differences
/// - Different formatting of the same vendor
/// - Small amount variations (within tolerance)
protocol VendorFingerprintServiceProtocol: Sendable {
    /// Generates a fingerprint from vendor name, optional NIP, and optional amount.
    ///
    /// The fingerprint is a SHA256 hash of the normalized inputs, providing a stable
    /// identifier for recurring payment matching.
    ///
    /// - Parameters:
    ///   - vendorName: Raw vendor name from document. Will be normalized (lowercase,
    ///     diacritics removed, business suffixes stripped).
    ///   - nip: Optional NIP (Polish tax ID). If provided, increases fingerprint uniqueness.
    ///   - amount: Optional amount for bucket-based differentiation. Amounts are grouped
    ///     into buckets to separate different services from the same vendor.
    /// - Returns: A 64-character hexadecimal SHA256 fingerprint string.
    func generateFingerprint(vendorName: String, nip: String?, amount: Decimal?) -> String

    /// Generates a fingerprint from vendor name and optional NIP (legacy, no amount).
    ///
    /// Use this method when amount bucketing is not needed or when migrating from
    /// legacy fingerprints.
    ///
    /// - Parameters:
    ///   - vendorName: Raw vendor name from document.
    ///   - nip: Optional NIP (Polish tax ID).
    /// - Returns: A 64-character hexadecimal SHA256 fingerprint string.
    func generateFingerprint(vendorName: String, nip: String?) -> String

    /// Generates a fingerprint with metadata about certainty and components.
    ///
    /// Use this method when you need to inspect the fingerprint generation process,
    /// such as checking if the fingerprint is a "fallback" (generated without NIP).
    ///
    /// - Parameters:
    ///   - vendorName: Raw vendor name from document.
    ///   - nip: Optional NIP (Polish tax ID).
    ///   - amount: Optional amount for bucket-based differentiation.
    /// - Returns: A `FingerprintResult` containing the fingerprint hash and metadata
    ///   about which components were used.
    func generateFingerprintWithMetadata(vendorName: String, nip: String?, amount: Decimal?) -> FingerprintResult

    /// Generates a fingerprint with metadata (legacy, no amount).
    ///
    /// - Parameters:
    ///   - vendorName: Raw vendor name from document.
    ///   - nip: Optional NIP (Polish tax ID).
    /// - Returns: A `FingerprintResult` containing the fingerprint hash and metadata.
    func generateFingerprintWithMetadata(vendorName: String, nip: String?) -> FingerprintResult

    /// Normalizes a vendor name for comparison and fingerprinting.
    ///
    /// Normalization includes:
    /// - Converting to lowercase
    /// - Removing Polish diacritical marks (e.g., "Spolka" -> "spolka")
    /// - Removing business suffixes (e.g., "Sp. z o.o.", "S.A.")
    /// - Removing common prefixes (e.g., "Firma", "Przedsiebiorstwo")
    /// - Removing punctuation and collapsing whitespace
    ///
    /// - Parameter vendorName: Raw vendor name string.
    /// - Returns: Normalized vendor name suitable for hashing.
    func normalizeVendorName(_ vendorName: String) -> String

    /// Normalizes a NIP for comparison.
    ///
    /// Removes all non-digit characters. Polish NIP should be 10 digits.
    ///
    /// - Parameter nip: Raw NIP string (may contain dashes, spaces).
    /// - Returns: Normalized NIP containing only digits.
    func normalizeNIP(_ nip: String) -> String

    /// Calculates the amount bucket identifier for a given amount.
    ///
    /// Amounts are bucketed based on magnitude:
    /// - Under 100: rounded to nearest 10 (e.g., 45 -> "bucket_50")
    /// - 100-1000: rounded to nearest 50 (e.g., 175 -> "bucket_150")
    /// - 1000-10000: rounded to nearest 100 (e.g., 1234 -> "bucket_1200")
    /// - Over 10000: rounded to nearest 500 (e.g., 12345 -> "bucket_12500")
    ///
    /// - Parameter amount: The amount to bucket.
    /// - Returns: Bucket identifier string (e.g., "bucket_500").
    func calculateAmountBucket(_ amount: Decimal) -> String

    /// Checks if two amounts would fall into the same bucket.
    ///
    /// This is useful for determining if two documents are likely from the same
    /// recurring payment series.
    ///
    /// - Parameters:
    ///   - amount1: First amount.
    ///   - amount2: Second amount.
    /// - Returns: `true` if both amounts resolve to the same bucket identifier.
    func areAmountsInSameBucket(_ amount1: Decimal, _ amount2: Decimal) -> Bool

    /// Generates a vendor-only fingerprint (without amount bucket).
    ///
    /// Useful for finding all templates from the same vendor, regardless of amount.
    /// This enables the fuzzy matching feature that detects when a vendor has
    /// multiple recurring payments at different amounts.
    ///
    /// - Parameters:
    ///   - vendorName: Raw vendor name from document.
    ///   - nip: Optional NIP (Polish tax ID).
    /// - Returns: A 64-character hexadecimal SHA256 fingerprint string (vendor + NIP only).
    func generateVendorOnlyFingerprint(vendorName: String, nip: String?) -> String
}

/// Default implementation of VendorFingerprintService
final class VendorFingerprintService: VendorFingerprintServiceProtocol, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "VendorFingerprint")

    /// Amount bucketing strategy
    private let bucketStrategy: AmountBucketStrategy

    /// Tolerance percentage for amount bucketing (extracted from strategy)
    private var tolerancePercent: Double {
        switch bucketStrategy {
        case .enabled(let tolerance):
            return tolerance
        case .disabled:
            return 0
        }
    }

    // MARK: - Initialization

    init(bucketStrategy: AmountBucketStrategy = .default) {
        self.bucketStrategy = bucketStrategy
    }

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

    func generateFingerprint(vendorName: String, nip: String?, amount: Decimal?) -> String {
        return generateFingerprintWithMetadata(vendorName: vendorName, nip: nip, amount: amount).fingerprint
    }

    func generateFingerprint(vendorName: String, nip: String?) -> String {
        // Legacy method - no amount bucketing
        return generateFingerprintWithMetadata(vendorName: vendorName, nip: nip, amount: nil).fingerprint
    }

    func generateFingerprintWithMetadata(vendorName: String, nip: String?) -> FingerprintResult {
        // Legacy method - no amount bucketing
        return generateFingerprintWithMetadata(vendorName: vendorName, nip: nip, amount: nil)
    }

    func generateFingerprintWithMetadata(vendorName: String, nip: String?, amount: Decimal?) -> FingerprintResult {
        let normalizedName = normalizeVendorName(vendorName)
        let normalizedNIP = nip.map { normalizeNIP($0) }

        // Generate vendor-only fingerprint first (always needed for finding related templates)
        let vendorOnlyFingerprint = generateVendorOnlyFingerprint(vendorName: vendorName, nip: nip)

        // Calculate amount bucket if enabled and amount provided
        let amountBucket: String?
        switch bucketStrategy {
        case .enabled:
            if let amount = amount {
                amountBucket = calculateAmountBucket(amount)
            } else {
                amountBucket = nil
            }
        case .disabled:
            amountBucket = nil
        }

        // Combine components for fingerprint
        // Format: name|nip|amount_bucket (each component optional except name)
        var components: [String] = [normalizedName]
        var isFallback = true

        if let normalizedNIP = normalizedNIP, !normalizedNIP.isEmpty {
            components.append(normalizedNIP)
            isFallback = false
        }

        if let bucket = amountBucket {
            components.append(bucket)
            // Amount bucket without NIP is still considered fallback
            // but has higher confidence than name-only
        }

        let combined = components.joined(separator: "|")

        // Log fingerprint generation details
        if isFallback {
            if amountBucket != nil {
                logger.debug("Generating fingerprint: name+amount (no NIP) - nameLength=\(vendorName.count), bucket=\(amountBucket ?? "none")")
            } else {
                logger.debug("Generating FALLBACK fingerprint (no NIP, no amount) - nameLength=\(vendorName.count)")
            }
        } else {
            if amountBucket != nil {
                logger.debug("Generating fingerprint: name+NIP+amount - nameLength=\(vendorName.count), bucket=\(amountBucket ?? "none")")
            } else {
                logger.debug("Generating fingerprint: name+NIP - nameLength=\(vendorName.count)")
            }
        }

        // Generate SHA256 hash
        let data = Data(combined.utf8)
        let hash = SHA256.hash(data: data)
        let fingerprint = hash.compactMap { String(format: "%02x", $0) }.joined()

        return FingerprintResult(
            fingerprint: fingerprint,
            isFallback: isFallback,
            normalizedName: normalizedName,
            normalizedNIP: isFallback ? nil : normalizedNIP,
            amountBucket: amountBucket,
            vendorOnlyFingerprint: vendorOnlyFingerprint
        )
    }

    func generateVendorOnlyFingerprint(vendorName: String, nip: String?) -> String {
        let normalizedName = normalizeVendorName(vendorName)
        let normalizedNIP = nip.map { normalizeNIP($0) }

        let combined: String
        if let normalizedNIP = normalizedNIP, !normalizedNIP.isEmpty {
            combined = "\(normalizedName)|\(normalizedNIP)"
        } else {
            combined = normalizedName
        }

        let data = Data(combined.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Amount Bucketing

    func calculateAmountBucket(_ amount: Decimal) -> String {
        // Convert to Double for easier math
        let amountDouble = NSDecimalNumber(decimal: amount).doubleValue

        // Handle edge cases
        guard amountDouble > 0 else {
            return "bucket_0"
        }

        // Calculate bucket center using logarithmic scaling
        // This creates buckets that grow proportionally with amount size
        //
        // Strategy: Round to nearest "nice" number based on magnitude
        // - Under 100: round to nearest 10 (e.g., 45 -> bucket_50)
        // - 100-1000: round to nearest 50 (e.g., 175 -> bucket_150, 525 -> bucket_500)
        // - 1000-10000: round to nearest 100 (e.g., 1234 -> bucket_1200)
        // - Over 10000: round to nearest 500 (e.g., 12345 -> bucket_12500)

        let bucketCenter: Int
        switch amountDouble {
        case ..<100:
            // Round to nearest 10
            bucketCenter = Int((amountDouble / 10).rounded()) * 10
        case 100..<1000:
            // Round to nearest 50
            bucketCenter = Int((amountDouble / 50).rounded()) * 50
        case 1000..<10000:
            // Round to nearest 100
            bucketCenter = Int((amountDouble / 100).rounded()) * 100
        default:
            // Round to nearest 500
            bucketCenter = Int((amountDouble / 500).rounded()) * 500
        }

        // Ensure minimum bucket of 10
        let finalBucket = max(bucketCenter, 10)

        return "bucket_\(finalBucket)"
    }

    func areAmountsInSameBucket(_ amount1: Decimal, _ amount2: Decimal) -> Bool {
        return calculateAmountBucket(amount1) == calculateAmountBucket(amount2)
    }

    // MARK: - Vendor Name Normalization

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
