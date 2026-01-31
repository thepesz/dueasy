import Foundation
import SwiftData

/// Keyword learning statistics - tracks performance of keyword candidates
/// Separate entity for efficient querying and learning
@Model
final class KeywordStats {

    // MARK: - Identity

    @Attribute(.unique) var id: UUID

    /// Vendor key (e.g., "orange_pl", "pge_pl")
    /// Links to VendorProfile.vendorKey
    var vendorKey: String

    /// The phrase being tracked (e.g., "do zapłaty", "amount due")
    var phrase: String

    /// Field type this keyword is for
    var fieldTypeRaw: String

    // MARK: - Statistics

    /// Number of times this phrase was near the CORRECT value
    var hits: Int

    /// Number of times this phrase was near an INCORRECT value
    var misses: Int

    /// When this phrase was last seen in an invoice
    var lastSeenAt: Date

    /// Current learning state
    var stateRaw: String

    // MARK: - Computed Properties

    var fieldType: FieldType {
        get { FieldType(rawValue: fieldTypeRaw) ?? .amount }
        set { fieldTypeRaw = newValue.rawValue }
    }

    var state: KeywordStatState {
        get { KeywordStatState(rawValue: stateRaw) ?? .candidate }
        set { stateRaw = newValue.rawValue }
    }

    /// Should this keyword be promoted to the vendor's permanent keywords?
    /// Rule: hits >= 3 and misses == 0
    var shouldPromote: Bool {
        return hits >= 3 && misses == 0 && state == .candidate
    }

    /// Should this keyword be blocked (too many failures)?
    /// Rule: misses >= 2
    var shouldBlock: Bool {
        return misses >= 2 && state == .candidate
    }

    /// Confidence score (0.0-1.0)
    var confidence: Double {
        let total = hits + misses
        guard total > 0 else { return 0.0 }
        return Double(hits) / Double(total)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        vendorKey: String,
        phrase: String,
        fieldType: FieldType,
        hits: Int = 0,
        misses: Int = 0,
        state: KeywordStatState = .candidate
    ) {
        self.id = id
        self.vendorKey = vendorKey
        self.phrase = phrase
        self.fieldTypeRaw = fieldType.rawValue
        self.hits = hits
        self.misses = misses
        self.lastSeenAt = Date()
        self.stateRaw = state.rawValue
    }

    // MARK: - Mutation

    /// Record a hit (phrase was near correct value)
    func recordHit() {
        hits += 1
        lastSeenAt = Date()

        // Auto-promote if threshold reached
        if shouldPromote {
            state = .promoted
        }
    }

    /// Record a miss (phrase was near incorrect value)
    func recordMiss() {
        misses += 1
        lastSeenAt = Date()

        // Auto-block if threshold reached
        if shouldBlock {
            state = .blocked
        }
    }

    /// Reset statistics (useful after vendor profile update)
    func reset() {
        hits = 0
        misses = 0
        state = .candidate
        lastSeenAt = Date()
    }
}

// MARK: - Querying Helpers

extension KeywordStats {

    /// Predicate for finding stats by vendor
    static func byVendor(_ vendorKey: String) -> Predicate<KeywordStats> {
        #Predicate<KeywordStats> { stat in
            stat.vendorKey == vendorKey
        }
    }

    /// Predicate for finding promoted keywords
    static func promoted(for vendorKey: String) -> Predicate<KeywordStats> {
        #Predicate<KeywordStats> { stat in
            stat.vendorKey == vendorKey && stat.stateRaw == "promoted"
        }
    }

    /// Predicate for finding candidates ready for promotion
    static func readyForPromotion(for vendorKey: String) -> Predicate<KeywordStats> {
        #Predicate<KeywordStats> { stat in
            stat.vendorKey == vendorKey &&
            stat.stateRaw == "candidate" &&
            stat.hits >= 3 &&
            stat.misses == 0
        }
    }

    /// Predicate for finding blocked keywords
    static func blocked(for vendorKey: String) -> Predicate<KeywordStats> {
        #Predicate<KeywordStats> { stat in
            stat.vendorKey == vendorKey && stat.stateRaw == "blocked"
        }
    }
}
