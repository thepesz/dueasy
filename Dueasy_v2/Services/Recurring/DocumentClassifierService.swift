import Foundation

/// Service for classifying documents by category using keyword matching.
/// Supports both Polish and English keywords for accurate categorization.
///
/// The classifier is used for:
/// - Auto-detection category gate (reject fuel, grocery, retail, receipt)
/// - UI display of document category
/// - Confidence scoring for recurring detection
protocol DocumentClassifierServiceProtocol: Sendable {
    /// Classifies a document based on vendor name, text content, and other metadata.
    /// - Parameters:
    ///   - vendorName: Vendor or seller name
    ///   - ocrText: Full OCR text from document (optional)
    ///   - amount: Document amount (optional, used for heuristics)
    /// - Returns: Classified category with confidence score
    func classify(vendorName: String, ocrText: String?, amount: Decimal?) -> ClassificationResult
}

/// Result of document classification
struct ClassificationResult: Sendable {
    /// The detected category
    let category: DocumentCategory

    /// Confidence score (0.0 to 1.0)
    let confidence: Double

    /// Keywords that triggered this classification
    let matchedKeywords: [String]
}

/// Default implementation of DocumentClassifierService
final class DocumentClassifierService: DocumentClassifierServiceProtocol, @unchecked Sendable {

    // MARK: - Keyword Definitions

    /// Keywords for each category (Polish and English)
    private static let categoryKeywords: [DocumentCategory: [String]] = [
        .utility: [
            // Polish - Electricity
            "energia", "energetyka", "pge", "tauron", "enea", "energa", "innogy", "e.on",
            "prąd", "prad", "elektryczność", "elektrycznosc", "kwh", "mwh",
            // Polish - Gas
            "gaz", "gazownia", "pgnig", "psg", "fortum",
            // Polish - Water
            "woda", "wodociągi", "wodociagi", "kanalizacja", "mpwik", "aquanet",
            // Polish - Heating
            "ciepło", "cieplo", "ogrzewanie", "veolia", "kogeneracja",
            // English
            "electricity", "power", "gas", "water", "utility", "utilities", "heating", "energy"
        ],

        .telecom: [
            // Polish
            "orange", "play", "plus", "t-mobile", "tmobile", "vectra", "upc", "netia",
            "multimedia", "inea", "toya", "cyfrowypolsat", "polkomtel",
            "telefon", "internet", "abonament", "roaming", "sms", "mms",
            "telekomunikacja", "operator", "telewizja", "tv", "kablówka", "kablowka",
            // English
            "phone", "mobile", "cellular", "broadband", "fiber", "telecom", "telecommunications"
        ],

        .rent: [
            // Polish
            "czynsz", "najem", "wynajem", "dzierżawa", "dzierzawa", "lokalu", "mieszkania",
            "administracja", "wspólnota", "wspolnota", "spoldzielnia", "spółdzielnia",
            "zarządca", "zarzadca", "nieruchomości", "nieruchomosci", "opłata eksploatacyjna",
            "oplata eksploatacyjna", "fundusz remontowy",
            // English
            "rent", "lease", "apartment", "housing", "property management", "landlord",
            "tenant", "rental"
        ],

        .insurance: [
            // Polish
            "ubezpieczenie", "polisa", "składka", "skladka", "towarzystwo ubezpieczeń",
            "pzu", "warta", "allianz", "ergo hestia", "axa", "generali", "uniqa",
            "compensa", "link4", "aviva", "metlife", "nationale nederlanden",
            "oc", "ac", "nw", "nnw", "autocasco", "komunikacyjne", "majątkowe", "majatkowe",
            "na życie", "na zycie", "zdrowotne",
            // English
            "insurance", "policy", "premium", "coverage", "claim", "insurer", "underwriter"
        ],

        .subscription: [
            // Polish
            "subskrypcja", "abonament", "miesięczny", "miesieczny", "roczny",
            "odnowienie", "licencja", "dostęp", "dostep", "członkostwo", "czlonkostwo",
            // English
            "subscription", "netflix", "spotify", "amazon prime", "disney", "hbo", "apple",
            "google", "microsoft", "adobe", "dropbox", "slack", "zoom", "github",
            "membership", "monthly", "yearly", "annual", "recurring", "renewal"
        ],

        .fuel: [
            // Polish
            "paliwo", "benzyna", "diesel", "olej napędowy", "olej napedowy", "lpg", "cng",
            "stacja paliw", "stacja benzynowa", "tankowanie", "litr", "litry",
            "orlen", "bp", "shell", "circle k", "lotos", "amic", "moya",
            // English
            "fuel", "gas station", "petrol", "gasoline", "diesel", "filling station"
        ],

        .grocery: [
            // Polish
            "spożywcze", "spozywcze", "żywność", "zywnosc", "artykuły spożywcze",
            "biedronka", "lidl", "kaufland", "auchan", "carrefour", "tesco", "netto",
            "żabka", "zabka", "freshmarket", "stokrotka", "dino", "intermarche",
            "delikatesy", "supermarket", "hipermarket", "sklep spożywczy",
            // English
            "grocery", "groceries", "food", "supermarket", "market"
        ],

        .retail: [
            // Polish
            "sklep", "zakupy", "detaliczny", "mediamarkt", "rtv euro agd", "media expert",
            "komputronik", "x-kom", "morele", "allegro", "amazon", "empik", "smyk",
            "pepco", "action", "ikea", "castorama", "leroy merlin", "obi",
            "decathlon", "go sport", "hm", "zara", "reserved", "ccc", "deichmann",
            // English
            "retail", "store", "shop", "purchase", "electronics", "clothing", "home"
        ],

        .receipt: [
            // Polish
            "paragon", "rachunek", "dowód zakupu", "dowod zakupu", "kasa fiskalna",
            "nr kasy", "nr paragonu", "fiskalny",
            // English
            "receipt", "cash register", "pos", "point of sale"
        ],

        .invoiceGeneric: [
            // Polish
            "faktura", "fv", "vat", "netto", "brutto", "usługi", "uslugi",
            "zlecenie", "umowa", "kontrakt", "projekt", "konsultacje", "doradztwo",
            "marketing", "reklama", "it", "informatyka", "programowanie",
            "księgowość", "ksiegowosc", "prawne", "budowlane", "transport",
            // English
            "invoice", "professional services", "consulting", "contractor", "freelance"
        ]
    ]

    /// Keywords that strongly indicate NOT a recurring payment
    private static let nonRecurringKeywords: [String] = [
        // Polish
        "jednorazowy", "jednorazowa", "okazja", "promocja", "wyprzedaż", "wyprzedaz",
        "zwrot", "reklamacja", "naprawa", "serwis", "części", "czesci",
        // English
        "one-time", "one time", "sale", "clearance", "refund", "repair", "parts"
    ]

    /// Keywords that strongly indicate recurring payment
    private static let recurringKeywords: [String] = [
        // Polish
        "miesięczny", "miesieczny", "miesięcznie", "miesiecznie",
        "kwartalny", "kwartalnie", "roczny", "rocznie", "co miesiąc", "co miesiac",
        "abonament", "subskrypcja", "składka", "skladka", "opłata stała", "oplata stala",
        "rata", "raty",
        // English
        "monthly", "quarterly", "yearly", "annual", "recurring", "subscription",
        "installment", "regular payment"
    ]

    // MARK: - DocumentClassifierServiceProtocol

    func classify(vendorName: String, ocrText: String?, amount: Decimal?) -> ClassificationResult {
        // Combine vendor name and OCR text for analysis
        let searchText = [vendorName.lowercased(), ocrText?.lowercased() ?? ""]
            .joined(separator: " ")
            .folding(options: .diacriticInsensitive, locale: .current)

        var bestCategory: DocumentCategory = .unknown
        var bestScore: Double = 0.0
        var bestKeywords: [String] = []

        // Check each category
        for (category, keywords) in Self.categoryKeywords {
            var matchedKeywords: [String] = []
            var score: Double = 0.0

            for keyword in keywords {
                let normalizedKeyword = keyword.folding(options: .diacriticInsensitive, locale: .current)
                if searchText.contains(normalizedKeyword) {
                    matchedKeywords.append(keyword)
                    // Weight keywords by specificity
                    if keyword.count > 5 {
                        score += 0.3 // Longer keywords are more specific
                    } else {
                        score += 0.15
                    }
                }
            }

            // Normalize score
            let normalizedScore = min(score, 1.0)

            if normalizedScore > bestScore {
                bestScore = normalizedScore
                bestCategory = category
                bestKeywords = matchedKeywords
            }
        }

        // Apply heuristics
        // Small amounts (< 50 PLN) are more likely to be retail/grocery
        if let amount = amount, amount < 50 {
            if bestCategory == .invoiceGeneric || bestCategory == .unknown {
                // Might be retail or grocery
                if bestScore < 0.5 {
                    bestCategory = .retail
                    bestScore = 0.3
                }
            }
        }

        // Very high amounts might be rent or insurance
        if let amount = amount, amount > 2000 {
            if bestCategory == .unknown && bestScore < 0.3 {
                bestCategory = .invoiceGeneric
                bestScore = 0.25
            }
        }

        return ClassificationResult(
            category: bestCategory,
            confidence: bestScore,
            matchedKeywords: bestKeywords
        )
    }

    // MARK: - Helper Methods

    /// Checks if the document text contains recurring keywords
    func hasRecurringKeywords(in text: String) -> Bool {
        let normalizedText = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        return Self.recurringKeywords.contains { keyword in
            normalizedText.contains(keyword.folding(options: .diacriticInsensitive, locale: .current))
        }
    }

    /// Checks if the document text contains non-recurring keywords
    func hasNonRecurringKeywords(in text: String) -> Bool {
        let normalizedText = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        return Self.nonRecurringKeywords.contains { keyword in
            normalizedText.contains(keyword.folding(options: .diacriticInsensitive, locale: .current))
        }
    }
}
