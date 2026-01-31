import Foundation

/// Result of document analysis (OCR + parsing).
/// This is the stable contract for both local parsing (Iteration 1) and AI analysis (Iteration 2).
/// JSON-serializable for backend communication.
struct DocumentAnalysisResult: Codable, Equatable, Sendable {

    // MARK: - Extracted Fields

    /// Detected document type
    let documentType: DocumentType?

    /// Vendor or seller name
    let vendorName: String?

    /// Vendor address (street, city, postal code)
    let vendorAddress: String?

    /// Polish Tax ID (NIP) for vendor matching
    let vendorNIP: String?

    /// Polish Business Registry Number (REGON) for vendor matching
    let vendorREGON: String?

    /// Total amount (highest confidence selection)
    let amount: Decimal?

    /// Currency code (e.g., "PLN", "EUR", "USD")
    let currency: String?

    /// Payment due date
    let dueDate: Date?

    /// Invoice/document number
    let documentNumber: String?

    /// Bank account number for payment (IBAN or Polish 26-digit)
    let bankAccountNumber: String?

    /// All detected amounts with context for user selection
    /// Each tuple: (amount value, context description)
    let suggestedAmounts: [(Decimal, String)]

    // MARK: - Candidate Lists (for learning)

    /// All amount candidates with full context (for learning)
    /// Not persisted long-term, only used during correction flow
    let amountCandidates: [AmountCandidate]?

    /// All date candidates with full context (for learning)
    let dateCandidates: [DateCandidate]?

    /// All vendor candidates with full context (for learning)
    let vendorCandidates: [VendorCandidate]?

    // MARK: - Confidence and Metadata

    /// Overall confidence score (0.0 to 1.0)
    let overallConfidence: Double

    /// Per-field confidence scores
    let fieldConfidences: FieldConfidences?

    /// Analysis provider identifier (e.g., "local", "openai", "gemini")
    let provider: String

    /// Analysis version for schema evolution
    let version: Int

    /// Raw text hints for debugging (optional, not stored long-term in production)
    let rawHints: String?

    /// Raw OCR text for keyword learning (optional, not stored long-term)
    let rawOCRText: String?

    // MARK: - Initialization

    init(
        documentType: DocumentType? = nil,
        vendorName: String? = nil,
        vendorAddress: String? = nil,
        vendorNIP: String? = nil,
        vendorREGON: String? = nil,
        amount: Decimal? = nil,
        currency: String? = nil,
        dueDate: Date? = nil,
        documentNumber: String? = nil,
        bankAccountNumber: String? = nil,
        suggestedAmounts: [(Decimal, String)] = [],
        amountCandidates: [AmountCandidate]? = nil,
        dateCandidates: [DateCandidate]? = nil,
        vendorCandidates: [VendorCandidate]? = nil,
        overallConfidence: Double = 0.0,
        fieldConfidences: FieldConfidences? = nil,
        provider: String = "local",
        version: Int = 1,
        rawHints: String? = nil,
        rawOCRText: String? = nil
    ) {
        self.documentType = documentType
        self.vendorName = vendorName
        self.vendorAddress = vendorAddress
        self.vendorNIP = vendorNIP
        self.vendorREGON = vendorREGON
        self.amount = amount
        self.currency = currency
        self.dueDate = dueDate
        self.documentNumber = documentNumber
        self.bankAccountNumber = bankAccountNumber
        self.suggestedAmounts = suggestedAmounts
        self.amountCandidates = amountCandidates
        self.dateCandidates = dateCandidates
        self.vendorCandidates = vendorCandidates
        self.overallConfidence = overallConfidence
        self.fieldConfidences = fieldConfidences
        self.provider = provider
        self.version = version
        self.rawHints = rawHints
        self.rawOCRText = rawOCRText
    }

    /// Empty result for when analysis fails or returns nothing
    static let empty = DocumentAnalysisResult(
        overallConfidence: 0.0,
        provider: "local",
        version: 1
    )

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case documentType, vendorName, vendorAddress, vendorNIP, vendorREGON
        case amount, currency, dueDate
        case documentNumber, bankAccountNumber, suggestedAmounts
        case amountCandidates, dateCandidates, vendorCandidates
        case overallConfidence, fieldConfidences, provider, version, rawHints, rawOCRText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentType = try container.decodeIfPresent(DocumentType.self, forKey: .documentType)
        vendorName = try container.decodeIfPresent(String.self, forKey: .vendorName)
        vendorAddress = try container.decodeIfPresent(String.self, forKey: .vendorAddress)
        vendorNIP = try container.decodeIfPresent(String.self, forKey: .vendorNIP)
        vendorREGON = try container.decodeIfPresent(String.self, forKey: .vendorREGON)
        amount = try container.decodeIfPresent(Decimal.self, forKey: .amount)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        documentNumber = try container.decodeIfPresent(String.self, forKey: .documentNumber)
        bankAccountNumber = try container.decodeIfPresent(String.self, forKey: .bankAccountNumber)

        // Decode suggested amounts as array of SuggestedAmount structs
        let suggestedAmountStructs = try container.decodeIfPresent([SuggestedAmount].self, forKey: .suggestedAmounts) ?? []
        suggestedAmounts = suggestedAmountStructs.map { ($0.value, $0.context) }

        // Decode candidate lists for learning
        amountCandidates = try container.decodeIfPresent([AmountCandidate].self, forKey: .amountCandidates)
        dateCandidates = try container.decodeIfPresent([DateCandidate].self, forKey: .dateCandidates)
        vendorCandidates = try container.decodeIfPresent([VendorCandidate].self, forKey: .vendorCandidates)

        overallConfidence = try container.decode(Double.self, forKey: .overallConfidence)
        fieldConfidences = try container.decodeIfPresent(FieldConfidences.self, forKey: .fieldConfidences)
        provider = try container.decode(String.self, forKey: .provider)
        version = try container.decode(Int.self, forKey: .version)
        rawHints = try container.decodeIfPresent(String.self, forKey: .rawHints)
        rawOCRText = try container.decodeIfPresent(String.self, forKey: .rawOCRText)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(documentType, forKey: .documentType)
        try container.encodeIfPresent(vendorName, forKey: .vendorName)
        try container.encodeIfPresent(vendorAddress, forKey: .vendorAddress)
        try container.encodeIfPresent(vendorNIP, forKey: .vendorNIP)
        try container.encodeIfPresent(vendorREGON, forKey: .vendorREGON)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(documentNumber, forKey: .documentNumber)
        try container.encodeIfPresent(bankAccountNumber, forKey: .bankAccountNumber)

        // Encode suggested amounts as array of SuggestedAmount structs
        let suggestedAmountStructs = suggestedAmounts.map { SuggestedAmount(value: $0.0, context: $0.1) }
        try container.encode(suggestedAmountStructs, forKey: .suggestedAmounts)

        // Encode candidate lists for learning
        try container.encodeIfPresent(amountCandidates, forKey: .amountCandidates)
        try container.encodeIfPresent(dateCandidates, forKey: .dateCandidates)
        try container.encodeIfPresent(vendorCandidates, forKey: .vendorCandidates)

        try container.encode(overallConfidence, forKey: .overallConfidence)
        try container.encodeIfPresent(fieldConfidences, forKey: .fieldConfidences)
        try container.encode(provider, forKey: .provider)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(rawHints, forKey: .rawHints)
        try container.encodeIfPresent(rawOCRText, forKey: .rawOCRText)
    }

    static func == (lhs: DocumentAnalysisResult, rhs: DocumentAnalysisResult) -> Bool {
        lhs.documentType == rhs.documentType &&
        lhs.vendorName == rhs.vendorName &&
        lhs.vendorAddress == rhs.vendorAddress &&
        lhs.amount == rhs.amount &&
        lhs.currency == rhs.currency &&
        lhs.dueDate == rhs.dueDate &&
        lhs.documentNumber == rhs.documentNumber &&
        lhs.bankAccountNumber == rhs.bankAccountNumber &&
        lhs.overallConfidence == rhs.overallConfidence &&
        lhs.fieldConfidences == rhs.fieldConfidences &&
        lhs.provider == rhs.provider &&
        lhs.version == rhs.version &&
        lhs.rawHints == rhs.rawHints &&
        lhs.rawOCRText == rhs.rawOCRText
    }
}

/// Helper struct for encoding/decoding suggested amounts
private struct SuggestedAmount: Codable {
    let value: Decimal
    let context: String
}

// MARK: - Field Confidences

/// Per-field confidence scores for granular feedback
struct FieldConfidences: Codable, Equatable, Sendable {
    let vendorName: Double?
    let amount: Double?
    let dueDate: Double?
    let documentNumber: Double?

    init(
        vendorName: Double? = nil,
        amount: Double? = nil,
        dueDate: Double? = nil,
        documentNumber: Double? = nil
    ) {
        self.vendorName = vendorName
        self.amount = amount
        self.dueDate = dueDate
        self.documentNumber = documentNumber
    }
}
