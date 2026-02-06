import Foundation
import SwiftData

// MARK: - IBAN Verification Status

/// Verification status for a bank account (IBAN).
/// Tracks whether the account has been verified as legitimate.
enum IBANVerificationStatus: String, Codable, Sendable, CaseIterable {
    /// Account has not been verified yet
    case unverified

    /// Account has been verified as legitimate by the user
    case verified

    /// Account has been flagged as suspicious
    case suspicious

    /// Account has been confirmed as fraudulent
    case fraudulent

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .unverified: return "Unverified"
        case .verified: return "Verified"
        case .suspicious: return "Suspicious"
        case .fraudulent: return "Fraudulent"
        }
    }

    /// Whether this status indicates a potential problem
    var isProblem: Bool {
        switch self {
        case .unverified, .verified: return false
        case .suspicious, .fraudulent: return true
        }
    }
}

// MARK: - Vendor Bank Account History Model

/// Tracks the history of bank accounts (IBANs) used by vendors.
/// Enables detection of bank account changes which may indicate fraud.
///
/// Each record represents a unique combination of vendor fingerprint and IBAN.
/// When a vendor uses a new IBAN, a new record is created.
/// The system can then alert users when a known vendor suddenly uses a different account.
@Model
final class VendorBankAccountHistory {

    // MARK: - Primary Fields

    /// Unique identifier
    @Attribute(.unique)
    var id: UUID

    /// Vendor fingerprint for matching (same as used in documents and templates)
    @Attribute(.spotlight)
    var vendorFingerprint: String

    /// Normalized IBAN (spaces and dashes removed, uppercase)
    var iban: String

    /// Country code extracted from IBAN (first 2 characters)
    var ibanCountryCode: String

    // MARK: - Usage Tracking

    /// When this IBAN was first seen for this vendor
    var firstSeenAt: Date

    /// When this IBAN was last used by this vendor
    var lastSeenAt: Date

    /// Number of documents using this IBAN
    var documentCount: Int

    /// Whether this is the primary/most-used account for this vendor
    var isPrimary: Bool

    // MARK: - Verification Status

    /// Current verification status (stored as raw string)
    var verificationStatusRaw: String

    /// When the verification status was last updated
    var verificationUpdatedAt: Date?

    /// Notes about verification (e.g., "Confirmed via phone call to vendor")
    var verificationNotes: String?

    /// User who verified this account (for audit trail)
    var verifiedBy: String?

    // MARK: - Computed Properties

    /// Verification status enum
    var verificationStatus: IBANVerificationStatus {
        get { IBANVerificationStatus(rawValue: verificationStatusRaw) ?? .unverified }
        set {
            verificationStatusRaw = newValue.rawValue
            verificationUpdatedAt = Date()
        }
    }

    /// Whether this account is safe to use (verified or unverified but not flagged)
    var isSafeToUse: Bool {
        switch verificationStatus {
        case .verified, .unverified: return true
        case .suspicious, .fraudulent: return false
        }
    }

    /// Formatted IBAN for display (with spaces every 4 characters)
    var formattedIBAN: String {
        var result = ""
        for (index, char) in iban.enumerated() {
            if index > 0 && index % 4 == 0 {
                result += " "
            }
            result.append(char)
        }
        return result
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        vendorFingerprint: String,
        iban: String,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.vendorFingerprint = vendorFingerprint

        // Normalize the IBAN
        let normalized = Self.normalizeIBAN(iban)
        self.iban = normalized

        // Extract country code (first 2 characters of IBAN)
        self.ibanCountryCode = String(normalized.prefix(2))

        self.firstSeenAt = Date()
        self.lastSeenAt = Date()
        self.documentCount = 1
        self.isPrimary = isPrimary
        self.verificationStatusRaw = IBANVerificationStatus.unverified.rawValue
        self.verificationUpdatedAt = nil
        self.verificationNotes = nil
        self.verifiedBy = nil
    }

    // MARK: - Methods

    /// Records a usage of this bank account (updates lastSeenAt and documentCount).
    func recordUsage() {
        lastSeenAt = Date()
        documentCount += 1
    }

    /// Marks this account as verified by the user.
    /// - Parameters:
    ///   - notes: Optional notes about verification
    ///   - verifiedBy: Optional identifier of who verified
    func markAsVerified(notes: String? = nil, verifiedBy: String? = nil) {
        self.verificationStatus = .verified
        self.verificationNotes = notes
        self.verifiedBy = verifiedBy
    }

    /// Marks this account as suspicious.
    /// - Parameter notes: Optional notes about why it's suspicious
    func markAsSuspicious(notes: String? = nil) {
        self.verificationStatus = .suspicious
        self.verificationNotes = notes
    }

    /// Marks this account as fraudulent.
    /// - Parameter notes: Optional notes about the fraud
    func markAsFraudulent(notes: String? = nil) {
        self.verificationStatus = .fraudulent
        self.verificationNotes = notes
    }

    /// Resets verification status to unverified.
    func resetVerification() {
        self.verificationStatus = .unverified
        self.verificationNotes = nil
        self.verifiedBy = nil
    }

    // MARK: - Static Methods

    /// Normalizes an IBAN by removing spaces/dashes and converting to uppercase.
    /// - Parameter iban: The IBAN to normalize
    /// - Returns: Normalized IBAN string
    static func normalizeIBAN(_ iban: String) -> String {
        return iban
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
    }

    /// Validates an IBAN using the MOD-97 algorithm.
    /// - Parameter iban: The IBAN to validate
    /// - Returns: True if the IBAN is valid, false otherwise
    static func validateIBAN(_ iban: String) -> Bool {
        let normalized = normalizeIBAN(iban)

        // Basic length check (most IBANs are between 15-34 characters)
        guard normalized.count >= 15 && normalized.count <= 34 else {
            return false
        }

        // Check that first 2 characters are letters (country code)
        let countryCode = normalized.prefix(2)
        guard countryCode.allSatisfy({ $0.isLetter }) else {
            return false
        }

        // Check that characters 3-4 are digits (check digits)
        let checkDigits = normalized.dropFirst(2).prefix(2)
        guard checkDigits.allSatisfy({ $0.isNumber }) else {
            return false
        }

        // Rearrange: move first 4 characters to end
        let rearranged = String(normalized.dropFirst(4)) + String(normalized.prefix(4))

        // Convert letters to numbers (A=10, B=11, ..., Z=35)
        var numericString = ""
        for char in rearranged {
            if char.isLetter {
                let value = Int(char.asciiValue! - Character("A").asciiValue!) + 10
                numericString += String(value)
            } else {
                numericString += String(char)
            }
        }

        // Perform MOD 97 calculation
        // Process in chunks to handle large numbers
        var remainder = 0
        for char in numericString {
            guard let digit = Int(String(char)) else { return false }
            remainder = (remainder * 10 + digit) % 97
        }

        return remainder == 1
    }

    /// Extracts the country code from an IBAN.
    /// - Parameter iban: The IBAN to extract from
    /// - Returns: Two-letter country code, or nil if invalid
    static func extractCountryCode(_ iban: String) -> String? {
        let normalized = normalizeIBAN(iban)
        guard normalized.count >= 2 else { return nil }

        let countryCode = String(normalized.prefix(2))
        guard countryCode.allSatisfy({ $0.isLetter }) else { return nil }

        return countryCode
    }
}
