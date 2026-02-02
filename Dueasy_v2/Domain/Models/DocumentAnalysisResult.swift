import Foundation

/// Result of document analysis (OCR + parsing).
/// This is the stable contract for both local parsing (Iteration 1) and AI analysis (Iteration 2).
/// JSON-serializable for backend communication.
///
/// ## Privacy and OCR Text Handling
///
/// **IMPORTANT**: The `rawOCRText` field is used ONLY for transient processing:
/// - Passed to keyword learning service during user correction flow
/// - Sent to cloud analysis (with user consent via `cloudAnalysisEnabled` setting)
/// - **NEVER persisted** to database or local storage
///
/// Raw OCR text is sensitive because it may contain:
/// - Vendor names and addresses (PII)
/// - Financial amounts and account numbers
/// - Personal information from documents
///
/// Only derived learning data (keywords, patterns, confidence scores) is stored.
/// See `LearningData` and `VendorProfileV2` for privacy-safe storage models.
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

    /// All NIP candidates with full context
    let nipCandidates: [NIPCandidate]?

    /// All bank account candidates with full context
    let bankAccountCandidates: [BankAccountCandidate]?

    /// All document number candidates with full context
    let documentNumberCandidates: [ExtractionCandidate]?

    // MARK: - Evidence Bounding Boxes (for UI highlighting)

    /// Bounding box of the extracted vendor name
    let vendorEvidence: BoundingBox?

    /// Bounding box of the extracted amount
    let amountEvidence: BoundingBox?

    /// Bounding box of the extracted due date
    let dueDateEvidence: BoundingBox?

    /// Bounding box of the extracted document number
    let documentNumberEvidence: BoundingBox?

    /// Bounding box of the extracted NIP
    let nipEvidence: BoundingBox?

    /// Bounding box of the extracted bank account
    let bankAccountEvidence: BoundingBox?

    // MARK: - Extraction Methods (for debugging/learning)

    /// Method used to extract vendor name
    let vendorExtractionMethod: ExtractionMethod?

    /// Method used to extract amount
    let amountExtractionMethod: ExtractionMethod?

    /// Method used to extract due date
    let dueDateExtractionMethod: ExtractionMethod?

    /// Method used to extract NIP
    let nipExtractionMethod: ExtractionMethod?

    // MARK: - Confidence and Metadata

    /// Overall confidence score (0.0 to 1.0)
    let overallConfidence: Double

    /// Per-field confidence scores
    let fieldConfidences: FieldConfidences?

    /// Analysis provider identifier (e.g., "local", "local-layout", "openai", "gemini")
    let provider: String

    /// Analysis version for schema evolution
    let version: Int

    /// Raw text hints for debugging (optional, not stored long-term in production)
    let rawHints: String?

    /// Raw OCR text for keyword learning (optional, NEVER persisted).
    ///
    /// **Privacy Policy**:
    /// - Used transiently during parsing session only
    /// - Fed to `KeywordLearningService.learnFromCorrection()` for pattern extraction
    /// - Sent to cloud analysis if user has enabled `cloudAnalysisEnabled` setting
    /// - **NEVER stored** in FinanceDocument, LearningData, or any persistent model
    /// - Discarded after the review/save flow completes
    ///
    /// Only derived data (keywords, field positions, confidence scores) is persisted.
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
        nipCandidates: [NIPCandidate]? = nil,
        bankAccountCandidates: [BankAccountCandidate]? = nil,
        documentNumberCandidates: [ExtractionCandidate]? = nil,
        vendorEvidence: BoundingBox? = nil,
        amountEvidence: BoundingBox? = nil,
        dueDateEvidence: BoundingBox? = nil,
        documentNumberEvidence: BoundingBox? = nil,
        nipEvidence: BoundingBox? = nil,
        bankAccountEvidence: BoundingBox? = nil,
        vendorExtractionMethod: ExtractionMethod? = nil,
        amountExtractionMethod: ExtractionMethod? = nil,
        dueDateExtractionMethod: ExtractionMethod? = nil,
        nipExtractionMethod: ExtractionMethod? = nil,
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
        self.nipCandidates = nipCandidates
        self.bankAccountCandidates = bankAccountCandidates
        self.documentNumberCandidates = documentNumberCandidates
        self.vendorEvidence = vendorEvidence
        self.amountEvidence = amountEvidence
        self.dueDateEvidence = dueDateEvidence
        self.documentNumberEvidence = documentNumberEvidence
        self.nipEvidence = nipEvidence
        self.bankAccountEvidence = bankAccountEvidence
        self.vendorExtractionMethod = vendorExtractionMethod
        self.amountExtractionMethod = amountExtractionMethod
        self.dueDateExtractionMethod = dueDateExtractionMethod
        self.nipExtractionMethod = nipExtractionMethod
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
        case nipCandidates, bankAccountCandidates, documentNumberCandidates
        case vendorEvidence, amountEvidence, dueDateEvidence
        case documentNumberEvidence, nipEvidence, bankAccountEvidence
        case vendorExtractionMethod, amountExtractionMethod
        case dueDateExtractionMethod, nipExtractionMethod
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
        nipCandidates = try container.decodeIfPresent([NIPCandidate].self, forKey: .nipCandidates)
        bankAccountCandidates = try container.decodeIfPresent([BankAccountCandidate].self, forKey: .bankAccountCandidates)
        documentNumberCandidates = try container.decodeIfPresent([ExtractionCandidate].self, forKey: .documentNumberCandidates)

        // Decode evidence bounding boxes
        vendorEvidence = try container.decodeIfPresent(BoundingBox.self, forKey: .vendorEvidence)
        amountEvidence = try container.decodeIfPresent(BoundingBox.self, forKey: .amountEvidence)
        dueDateEvidence = try container.decodeIfPresent(BoundingBox.self, forKey: .dueDateEvidence)
        documentNumberEvidence = try container.decodeIfPresent(BoundingBox.self, forKey: .documentNumberEvidence)
        nipEvidence = try container.decodeIfPresent(BoundingBox.self, forKey: .nipEvidence)
        bankAccountEvidence = try container.decodeIfPresent(BoundingBox.self, forKey: .bankAccountEvidence)

        // Decode extraction methods
        vendorExtractionMethod = try container.decodeIfPresent(ExtractionMethod.self, forKey: .vendorExtractionMethod)
        amountExtractionMethod = try container.decodeIfPresent(ExtractionMethod.self, forKey: .amountExtractionMethod)
        dueDateExtractionMethod = try container.decodeIfPresent(ExtractionMethod.self, forKey: .dueDateExtractionMethod)
        nipExtractionMethod = try container.decodeIfPresent(ExtractionMethod.self, forKey: .nipExtractionMethod)

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
        try container.encodeIfPresent(nipCandidates, forKey: .nipCandidates)
        try container.encodeIfPresent(bankAccountCandidates, forKey: .bankAccountCandidates)
        try container.encodeIfPresent(documentNumberCandidates, forKey: .documentNumberCandidates)

        // Encode evidence bounding boxes
        try container.encodeIfPresent(vendorEvidence, forKey: .vendorEvidence)
        try container.encodeIfPresent(amountEvidence, forKey: .amountEvidence)
        try container.encodeIfPresent(dueDateEvidence, forKey: .dueDateEvidence)
        try container.encodeIfPresent(documentNumberEvidence, forKey: .documentNumberEvidence)
        try container.encodeIfPresent(nipEvidence, forKey: .nipEvidence)
        try container.encodeIfPresent(bankAccountEvidence, forKey: .bankAccountEvidence)

        // Encode extraction methods
        try container.encodeIfPresent(vendorExtractionMethod, forKey: .vendorExtractionMethod)
        try container.encodeIfPresent(amountExtractionMethod, forKey: .amountExtractionMethod)
        try container.encodeIfPresent(dueDateExtractionMethod, forKey: .dueDateExtractionMethod)
        try container.encodeIfPresent(nipExtractionMethod, forKey: .nipExtractionMethod)

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
        lhs.rawOCRText == rhs.rawOCRText &&
        lhs.vendorEvidence == rhs.vendorEvidence &&
        lhs.amountEvidence == rhs.amountEvidence &&
        lhs.dueDateEvidence == rhs.dueDateEvidence &&
        lhs.vendorExtractionMethod == rhs.vendorExtractionMethod &&
        lhs.amountExtractionMethod == rhs.amountExtractionMethod
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
    let nip: Double?
    let bankAccount: Double?

    init(
        vendorName: Double? = nil,
        amount: Double? = nil,
        dueDate: Double? = nil,
        documentNumber: Double? = nil,
        nip: Double? = nil,
        bankAccount: Double? = nil
    ) {
        self.vendorName = vendorName
        self.amount = amount
        self.dueDate = dueDate
        self.documentNumber = documentNumber
        self.nip = nip
        self.bankAccount = bankAccount
    }
}
