import Foundation
import os.log

// MARK: - Document Language Hint

/// Hint for the parser about the document's language/locale.
/// Used to disambiguate date formats (DD/MM vs MM/DD) and other locale-specific patterns.
enum DocumentLanguageHint: String, Sendable {
    case polish     // DD.MM.YYYY preferred, comma decimal
    case english    // MM/DD/YYYY preferred, dot decimal
    case unknown    // No preference - use heuristics
}

// MARK: - Date Parse Result

/// A parsed date with its interpretation details for disambiguation.
struct DateParseResult: Sendable {
    let date: Date
    let pattern: String
    /// Confidence in the interpretation (0.0-1.0).
    /// Lower when ambiguous (e.g., 01/05/2026 could be Jan 5 or May 1).
    let confidence: Double
}

// MARK: - Date Parser

/// Multi-format date parser supporting Polish, English/US, and ISO date formats.
/// Handles both numeric and verbal date representations.
///
/// **Supported Numeric Formats:**
/// - European (Polish): DD.MM.YYYY, DD-MM-YYYY, DD/MM/YYYY
/// - US/English: MM/DD/YYYY, MM-DD-YYYY
/// - ISO: YYYY-MM-DD, YYYY.MM.DD, YYYY/MM/DD
///
/// **Disambiguation Strategy for DD/MM vs MM/DD:**
/// 1. If separator is period (.), assume European (DD.MM.YYYY) -- standard in Poland/EU
/// 2. If year is first (YYYY-...), assume ISO format
/// 3. If first number > 12, it must be a day (DD/MM)
/// 4. If second number > 12, it must be a day (MM/DD)
/// 5. If both <= 12 and ambiguous, use language hint or return both candidates
/// 6. Period separator strongly implies European format
///
/// **Verbal Formats:**
/// - Polish: "31 stycznia 2026", "1 sty 2026"
/// - English: "January 31, 2026", "Jan 31, 2026", "31 January 2026"
final class DateParser: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "DateParser")

    /// Language hint for disambiguation. Set by the parser when document language is detected.
    var languageHint: DocumentLanguageHint = .unknown

    // MARK: - Polish Month Names

    /// Full Polish month names (genitive case, as used in dates)
    private let polishMonthsFull: [String: Int] = [
        "stycznia": 1, "lutego": 2, "marca": 3, "kwietnia": 4,
        "maja": 5, "czerwca": 6, "lipca": 7, "sierpnia": 8,
        "wrzesnia": 9, "września": 9, "pazdziernika": 10, "października": 10,
        "listopada": 11, "grudnia": 12
    ]

    /// Short Polish month names
    private let polishMonthsShort: [String: Int] = [
        "sty": 1, "lut": 2, "mar": 3, "kwi": 4,
        "maj": 5, "cze": 6, "lip": 7, "sie": 8,
        "wrz": 9, "paz": 10, "paź": 10, "lis": 11, "gru": 12
    ]

    // MARK: - English Month Names

    /// Full English month names
    private let englishMonthsFull: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4,
        "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11, "december": 12
    ]

    /// Short English month names
    private let englishMonthsShort: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4,
        "may": 5, "jun": 6, "jul": 7, "aug": 8,
        "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    // MARK: - Date Formatters (Lazy)

    /// Cache of date formatters for reuse
    private var formatters: [String: DateFormatter] = [:]

    private func formatter(for format: String) -> DateFormatter {
        if let cached = formatters[format] {
            return cached
        }

        let df = DateFormatter()
        df.dateFormat = format
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        formatters[format] = df
        return df
    }

    // MARK: - Main Parsing Method

    /// Parse a date string using multiple format strategies.
    /// Returns the highest-confidence interpretation.
    /// - Parameter text: Text containing a date
    /// - Returns: Parsed Date or nil if no format matches
    func parseDate(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try numeric formats first (most common)
        if let date = parseNumericDate(trimmed) {
            return date
        }

        // Try Polish verbal formats
        if let date = parsePolishVerbalDate(trimmed) {
            return date
        }

        // Try English verbal formats
        if let date = parseEnglishVerbalDate(trimmed) {
            return date
        }

        logger.debug("Failed to parse date: '\(trimmed)'")
        return nil
    }

    /// Parse date and return the matched pattern for debugging.
    /// Uses smart disambiguation for ambiguous dates.
    func parseDateWithPattern(from text: String) -> (date: Date, pattern: String)? {
        let results = parseDateCandidates(from: text)
        // Return the highest confidence result
        return results.first.map { ($0.date, $0.pattern) }
    }

    /// Parse date and return ALL possible interpretations with confidence scores.
    /// Used by the due date extraction to provide alternatives when dates are ambiguous.
    func parseDateCandidates(from text: String) -> [DateParseResult] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [DateParseResult] = []

        // Try numeric formats with disambiguation
        results.append(contentsOf: parseNumericDateCandidates(trimmed))

        // Try Polish verbal
        if let result = parsePolishVerbalDateWithPattern(trimmed) {
            results.append(DateParseResult(date: result.date, pattern: result.pattern, confidence: 0.95))
        }

        // Try English verbal
        if let result = parseEnglishVerbalDateWithPattern(trimmed) {
            results.append(DateParseResult(date: result.date, pattern: result.pattern, confidence: 0.95))
        }

        // Sort by confidence descending, deduplicate same dates
        var seen = Set<String>()
        let deduplicated = results
            .sorted { $0.confidence > $1.confidence }
            .filter { result in
                let key = "\(result.date.timeIntervalSinceReferenceDate)"
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }

        return deduplicated
    }

    // MARK: - Numeric Date Parsing with Disambiguation

    /// Parse numeric dates with smart DD/MM vs MM/DD disambiguation.
    /// Returns all valid interpretations with confidence scores.
    private func parseNumericDateCandidates(_ text: String) -> [DateParseResult] {
        var results: [DateParseResult] = []

        // ISO format: YYYY-MM-DD, YYYY.MM.DD, YYYY/MM/DD (unambiguous)
        let isoPattern = #"(\d{4})([-./])(\d{1,2})\2(\d{1,2})"#
        if let regex = try? NSRegularExpression(pattern: isoPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let yearRange = Range(match.range(at: 1), in: text),
           let monthRange = Range(match.range(at: 3), in: text),
           let dayRange = Range(match.range(at: 4), in: text),
           let year = Int(text[yearRange]),
           let month = Int(text[monthRange]),
           let day = Int(text[dayRange]) {

            if let date = makeDate(year: year, month: month, day: day) {
                let sep = match.range(at: 2)
                let sepRange = Range(sep, in: text)!
                let separator = String(text[sepRange])
                results.append(DateParseResult(
                    date: date,
                    pattern: "yyyy\(separator)MM\(separator)dd",
                    confidence: 0.95
                ))
                return results // ISO is unambiguous
            }
        }

        // Non-ISO: NN{sep}NN{sep}YYYY -- could be DD/MM or MM/DD
        let ambiguousPattern = #"(\d{1,2})([-./])(\d{1,2})\2(\d{4})"#
        if let regex = try? NSRegularExpression(pattern: ambiguousPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let firstRange = Range(match.range(at: 1), in: text),
           let sepRange = Range(match.range(at: 2), in: text),
           let secondRange = Range(match.range(at: 3), in: text),
           let yearRange = Range(match.range(at: 4), in: text),
           let first = Int(text[firstRange]),
           let second = Int(text[secondRange]),
           let year = Int(text[yearRange]) {

            let separator = String(text[sepRange])

            // Rule 1: Period separator strongly implies European DD.MM.YYYY
            // This is the standard format in Poland and most of continental Europe.
            if separator == "." {
                if let date = makeDate(year: year, month: second, day: first) {
                    results.append(DateParseResult(
                        date: date,
                        pattern: "dd.MM.yyyy",
                        confidence: 0.95
                    ))
                }
                return results
            }

            // Rule 2: Disambiguate based on value ranges
            let firstCouldBeMonth = first >= 1 && first <= 12
            let firstCouldBeDay = first >= 1 && first <= 31
            let secondCouldBeMonth = second >= 1 && second <= 12
            let secondCouldBeDay = second >= 1 && second <= 31

            // Case A: first > 12 -- must be day (DD/MM format, European)
            if !firstCouldBeMonth && firstCouldBeDay && secondCouldBeMonth {
                if let date = makeDate(year: year, month: second, day: first) {
                    results.append(DateParseResult(
                        date: date,
                        pattern: "dd\(separator)MM\(separator)yyyy",
                        confidence: 0.95
                    ))
                }
                return results
            }

            // Case B: second > 12 -- must be day (MM/DD format, US)
            if firstCouldBeMonth && !secondCouldBeMonth && secondCouldBeDay {
                if let date = makeDate(year: year, month: first, day: second) {
                    results.append(DateParseResult(
                        date: date,
                        pattern: "MM\(separator)dd\(separator)yyyy",
                        confidence: 0.95
                    ))
                }
                return results
            }

            // Case C: Both could be either -- AMBIGUOUS
            // Use language hint to pick primary, provide alternative
            if firstCouldBeMonth && secondCouldBeMonth && firstCouldBeDay && secondCouldBeDay {
                let europeanDate = makeDate(year: year, month: second, day: first)   // DD/MM
                let usDate = makeDate(year: year, month: first, day: second)         // MM/DD

                switch languageHint {
                case .polish:
                    // Strong preference for European DD/MM
                    if let date = europeanDate {
                        results.append(DateParseResult(
                            date: date,
                            pattern: "dd\(separator)MM\(separator)yyyy",
                            confidence: 0.90
                        ))
                    }
                    if let date = usDate, date != europeanDate {
                        results.append(DateParseResult(
                            date: date,
                            pattern: "MM\(separator)dd\(separator)yyyy",
                            confidence: 0.40
                        ))
                    }

                case .english:
                    // Strong preference for US MM/DD
                    if let date = usDate {
                        results.append(DateParseResult(
                            date: date,
                            pattern: "MM\(separator)dd\(separator)yyyy",
                            confidence: 0.90
                        ))
                    }
                    if let date = europeanDate, date != usDate {
                        results.append(DateParseResult(
                            date: date,
                            pattern: "dd\(separator)MM\(separator)yyyy",
                            confidence: 0.40
                        ))
                    }

                case .unknown:
                    // Slight preference for European (existing behavior), but offer both
                    // Slash separator is more common in US format, dash in European
                    let preferUS = separator == "/"
                    let primaryConf = 0.70
                    let altConf = 0.55

                    if preferUS {
                        if let date = usDate {
                            results.append(DateParseResult(
                                date: date,
                                pattern: "MM\(separator)dd\(separator)yyyy",
                                confidence: primaryConf
                            ))
                        }
                        if let date = europeanDate, date != usDate {
                            results.append(DateParseResult(
                                date: date,
                                pattern: "dd\(separator)MM\(separator)yyyy",
                                confidence: altConf
                            ))
                        }
                    } else {
                        if let date = europeanDate {
                            results.append(DateParseResult(
                                date: date,
                                pattern: "dd\(separator)MM\(separator)yyyy",
                                confidence: primaryConf
                            ))
                        }
                        if let date = usDate, date != europeanDate {
                            results.append(DateParseResult(
                                date: date,
                                pattern: "MM\(separator)dd\(separator)yyyy",
                                confidence: altConf
                            ))
                        }
                    }
                }

                return results
            }

            // Case D: Neither interpretation works (invalid date)
            // Try both and return whichever is valid
            if let date = makeDate(year: year, month: second, day: first) {
                results.append(DateParseResult(
                    date: date,
                    pattern: "dd\(separator)MM\(separator)yyyy",
                    confidence: 0.70
                ))
            }
            if let date = makeDate(year: year, month: first, day: second) {
                results.append(DateParseResult(
                    date: date,
                    pattern: "MM\(separator)dd\(separator)yyyy",
                    confidence: 0.70
                ))
            }
        }

        return results
    }

    /// Legacy numeric date parsing - returns the best interpretation.
    private func parseNumericDate(_ text: String) -> Date? {
        let candidates = parseNumericDateCandidates(text)
        return candidates.first?.date
    }

    /// Create a date from components, validating it is a real calendar date.
    private func makeDate(year: Int, month: Int, day: Int) -> Date? {
        guard month >= 1 && month <= 12 && day >= 1 && day <= 31 else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day

        guard let date = Calendar.current.date(from: components) else {
            return nil
        }

        // Verify the date components match (catches invalid dates like Feb 30)
        let resultComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard resultComponents.year == year &&
              resultComponents.month == month &&
              resultComponents.day == day else {
            return nil
        }

        return isReasonableDate(date) ? date : nil
    }

    // MARK: - Polish Verbal Date Parsing

    private func parsePolishVerbalDate(_ text: String) -> Date? {
        parsePolishVerbalDateWithPattern(text)?.date
    }

    private func parsePolishVerbalDateWithPattern(_ text: String) -> (date: Date, pattern: String)? {
        let normalized = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Pattern: "31 stycznia 2026" or "1 sty 2026"
        let pattern = #"(\d{1,2})\s+(\w+)\s+(\d{4})"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) else {
            return nil
        }

        guard let dayRange = Range(match.range(at: 1), in: normalized),
              let monthRange = Range(match.range(at: 2), in: normalized),
              let yearRange = Range(match.range(at: 3), in: normalized) else {
            return nil
        }

        guard let day = Int(normalized[dayRange]),
              let year = Int(normalized[yearRange]) else {
            return nil
        }

        let monthString = String(normalized[monthRange])

        // Try full month name first
        var month: Int?
        for (name, num) in polishMonthsFull {
            let normalizedName = name.folding(options: .diacriticInsensitive, locale: .current)
            if normalizedName == monthString || name == monthString {
                month = num
                break
            }
        }

        // Try short month name
        if month == nil {
            for (name, num) in polishMonthsShort {
                let normalizedName = name.folding(options: .diacriticInsensitive, locale: .current)
                if monthString.hasPrefix(normalizedName) || monthString.hasPrefix(name) {
                    month = num
                    break
                }
            }
        }

        guard let resolvedMonth = month else {
            return nil
        }

        guard let date = makeDate(year: year, month: resolvedMonth, day: day) else {
            return nil
        }

        let patternName = "Polish verbal: \(day) \(monthString) \(year)"
        logger.debug("Parsed Polish verbal date: '\(text)' -> \(date)")
        return (date, patternName)
    }

    // MARK: - English Verbal Date Parsing

    private func parseEnglishVerbalDate(_ text: String) -> Date? {
        parseEnglishVerbalDateWithPattern(text)?.date
    }

    private func parseEnglishVerbalDateWithPattern(_ text: String) -> (date: Date, pattern: String)? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Pattern 1: "January 31, 2026" or "Jan 31, 2026" or "Jan. 31, 2026"
        let pattern1 = #"(\w+)\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})"#

        // Pattern 2: "31 January 2026" or "31 Jan 2026" or "31st January 2026"
        let pattern2 = #"(\d{1,2})(?:st|nd|rd|th)?\s+(\w+)\.?,?\s+(\d{4})"#

        // Try pattern 1 (Month Day, Year)
        if let result = parseEnglishPattern(normalized, pattern: pattern1, dayGroup: 2, monthGroup: 1, yearGroup: 3) {
            return result
        }

        // Try pattern 2 (Day Month Year)
        if let result = parseEnglishPattern(normalized, pattern: pattern2, dayGroup: 1, monthGroup: 2, yearGroup: 3) {
            return result
        }

        return nil
    }

    private func parseEnglishPattern(
        _ text: String,
        pattern: String,
        dayGroup: Int,
        monthGroup: Int,
        yearGroup: Int
    ) -> (date: Date, pattern: String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        guard let dayRange = Range(match.range(at: dayGroup), in: text),
              let monthRange = Range(match.range(at: monthGroup), in: text),
              let yearRange = Range(match.range(at: yearGroup), in: text) else {
            return nil
        }

        guard let day = Int(text[dayRange]),
              let year = Int(text[yearRange]) else {
            return nil
        }

        let monthString = String(text[monthRange]).lowercased()

        // Try full month name
        var month = englishMonthsFull[monthString]

        // Try short month name
        if month == nil {
            for (name, num) in englishMonthsShort {
                if monthString.hasPrefix(name) {
                    month = num
                    break
                }
            }
        }

        guard let resolvedMonth = month else {
            return nil
        }

        guard let date = makeDate(year: year, month: resolvedMonth, day: day) else {
            return nil
        }

        let patternName = "English verbal"
        logger.debug("Parsed English verbal date: '\(text)' -> \(date)")
        return (date, patternName)
    }

    // MARK: - Date Validation

    /// Check if a date is reasonable (not too far in past or future)
    private func isReasonableDate(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()

        // Allow dates up to 5 years in the past
        let fiveYearsAgo = calendar.date(byAdding: .year, value: -5, to: now)!

        // Allow dates up to 2 years in the future
        let twoYearsFromNow = calendar.date(byAdding: .year, value: 2, to: now)!

        return date >= fiveYearsAgo && date <= twoYearsFromNow
    }

    // MARK: - Date Extraction from Text

    /// Extract all date candidates from text
    func extractAllDates(from text: String) -> [(date: Date, range: Range<String.Index>, pattern: String)] {
        var results: [(date: Date, range: Range<String.Index>, pattern: String)] = []

        // Numeric date patterns
        let numericPatterns = [
            #"\d{4}[-./]\d{1,2}[-./]\d{1,2}"#,     // ISO: YYYY-MM-DD
            #"\d{1,2}[-./]\d{1,2}[-./]\d{4}"#       // DD/MM/YYYY or MM/DD/YYYY
        ]

        for pattern in numericPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let dateString = String(text[range])
                        let candidates = parseNumericDateCandidates(dateString)
                        for candidate in candidates {
                            results.append((candidate.date, range, candidate.pattern))
                        }
                    }
                }
            }
        }

        // English verbal: "Month Day, Year" pattern
        let englishVerbalPattern = #"\w+\.?\s+\d{1,2}(?:st|nd|rd|th)?,?\s+\d{4}"#
        if let regex = try? NSRegularExpression(pattern: englishVerbalPattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let dateString = String(text[range])
                    if let result = parseEnglishVerbalDateWithPattern(dateString) {
                        results.append((result.date, range, result.pattern))
                    }
                }
            }
        }

        // Verbal date patterns: "Day Month Year"
        let verbalPattern = #"\d{1,2}(?:st|nd|rd|th)?\s+\w+\.?\s+\d{4}"#
        if let regex = try? NSRegularExpression(pattern: verbalPattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let dateString = String(text[range])
                    if let result = parsePolishVerbalDateWithPattern(dateString) {
                        results.append((result.date, range, result.pattern))
                    } else if let result = parseEnglishVerbalDateWithPattern(dateString) {
                        results.append((result.date, range, result.pattern))
                    }
                }
            }
        }

        return results
    }
}
