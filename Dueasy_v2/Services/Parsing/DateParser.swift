import Foundation
import os.log

// MARK: - Date Parser

/// Multi-format date parser supporting Polish and English date formats.
/// Handles both numeric and verbal date representations.
final class DateParser: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "DateParser")

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

    /// Parse a date string using multiple format strategies
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

    /// Parse date and return the matched pattern for debugging
    func parseDateWithPattern(from text: String) -> (date: Date, pattern: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try numeric formats
        let numericFormats = [
            ("dd.MM.yyyy", #"(\d{2})\.(\d{2})\.(\d{4})"#),
            ("dd-MM-yyyy", #"(\d{2})-(\d{2})-(\d{4})"#),
            ("dd/MM/yyyy", #"(\d{2})/(\d{2})/(\d{4})"#),
            ("yyyy-MM-dd", #"(\d{4})-(\d{2})-(\d{2})"#),
            ("yyyy.MM.dd", #"(\d{4})\.(\d{2})\.(\d{2})"#),
            ("yyyy/MM/dd", #"(\d{4})/(\d{2})/(\d{2})"#),
            ("d.MM.yyyy", #"(\d{1,2})\.(\d{2})\.(\d{4})"#),
            ("d-MM-yyyy", #"(\d{1,2})-(\d{2})-(\d{4})"#),
            ("d/MM/yyyy", #"(\d{1,2})/(\d{2})/(\d{4})"#)
        ]

        for (format, pattern) in numericFormats {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let matchRange = Range(match.range, in: trimmed) {
                let dateString = String(trimmed[matchRange])
                if let date = formatter(for: format).date(from: dateString) {
                    return (date, format)
                }
                // Try with flexible formatter
                let flexibleFormat = format.replacingOccurrences(of: "dd", with: "d")
                    .replacingOccurrences(of: "MM", with: "M")
                if let date = formatter(for: flexibleFormat).date(from: dateString) {
                    return (date, flexibleFormat)
                }
            }
        }

        // Try Polish verbal
        if let result = parsePolishVerbalDateWithPattern(trimmed) {
            return result
        }

        // Try English verbal
        if let result = parseEnglishVerbalDateWithPattern(trimmed) {
            return result
        }

        return nil
    }

    // MARK: - Numeric Date Parsing

    private func parseNumericDate(_ text: String) -> Date? {
        let formats = [
            "dd.MM.yyyy",
            "dd-MM-yyyy",
            "dd/MM/yyyy",
            "yyyy-MM-dd",
            "yyyy.MM.dd",
            "yyyy/MM/dd",
            "d.MM.yyyy",
            "d-MM-yyyy",
            "d/MM/yyyy",
            "d.M.yyyy",
            "d-M-yyyy",
            "d/M/yyyy"
        ]

        // Try to extract date substring using regex
        let datePatterns = [
            #"\d{2}[-./]\d{2}[-./]\d{4}"#,
            #"\d{4}[-./]\d{2}[-./]\d{2}"#,
            #"\d{1,2}[-./]\d{1,2}[-./]\d{4}"#
        ]

        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let matchRange = Range(match.range, in: text) {
                let dateString = String(text[matchRange])

                for format in formats {
                    if let date = formatter(for: format).date(from: dateString) {
                        // Validate the date is reasonable (not too far in past or future)
                        if isReasonableDate(date) {
                            logger.debug("Parsed numeric date '\(dateString)' with format '\(format)'")
                            return date
                        }
                    }
                }
            }
        }

        return nil
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

        var components = DateComponents()
        components.day = day
        components.month = resolvedMonth
        components.year = year

        guard let date = Calendar.current.date(from: components),
              isReasonableDate(date) else {
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

        // Pattern 1: "January 31, 2026" or "Jan 31, 2026"
        let pattern1 = #"(\w+)\s+(\d{1,2}),?\s+(\d{4})"#

        // Pattern 2: "31 January 2026" or "31 Jan 2026"
        let pattern2 = #"(\d{1,2})\s+(\w+),?\s+(\d{4})"#

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

        var components = DateComponents()
        components.day = day
        components.month = resolvedMonth
        components.year = year

        guard let date = Calendar.current.date(from: components),
              isReasonableDate(date) else {
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
            #"\d{2}[-./]\d{2}[-./]\d{4}"#,
            #"\d{4}[-./]\d{2}[-./]\d{2}"#,
            #"\d{1,2}[-./]\d{1,2}[-./]\d{4}"#
        ]

        for pattern in numericPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let dateString = String(text[range])
                        if let date = parseNumericDate(dateString) {
                            results.append((date, range, "numeric"))
                        }
                    }
                }
            }
        }

        // Verbal date patterns
        let verbalPattern = #"\d{1,2}\s+\w+\s+\d{4}"#
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
