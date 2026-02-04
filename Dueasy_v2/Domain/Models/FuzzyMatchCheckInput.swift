import Foundation

/// Data Transfer Object for fuzzy match checking.
/// Used instead of creating temporary FinanceDocument objects for fuzzy match checks.
///
/// This is a clean architectural pattern that:
/// 1. Avoids creating and discarding model objects
/// 2. Makes the intent clear - this is just for checking, not persistence
/// 3. Provides a minimal interface for the fuzzy match check operation
struct FuzzyMatchCheckInput: Sendable {
    /// The vendor name (required)
    let vendorName: String

    /// The vendor's NIP (Polish tax ID, optional)
    let nip: String?

    /// The document amount (required)
    let amount: Decimal

    /// Creates a FuzzyMatchCheckInput with the given values.
    /// - Parameters:
    ///   - vendorName: The vendor name from the document
    ///   - nip: Optional NIP (Polish tax ID)
    ///   - amount: The document amount
    init(vendorName: String, nip: String?, amount: Decimal) {
        self.vendorName = vendorName
        self.nip = nip
        self.amount = amount
    }
}
