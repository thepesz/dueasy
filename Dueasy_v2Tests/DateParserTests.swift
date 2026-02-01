import XCTest
@testable import Dueasy_v2

final class DateParserTests: XCTestCase {

    var dateParser: DateParser!

    override func setUp() {
        super.setUp()
        dateParser = DateParser()
    }

    override func tearDown() {
        dateParser = nil
        super.tearDown()
    }

    // MARK: - Numeric Date Parsing Tests

    func testNumericDatesWithDots() {
        // DD.MM.YYYY format
        let date1 = dateParser.parseDate(from: "15.01.2024")
        XCTAssertNotNil(date1)
        assertDateComponents(date1!, day: 15, month: 1, year: 2024)

        let date2 = dateParser.parseDate(from: "31.12.2025")
        XCTAssertNotNil(date2)
        assertDateComponents(date2!, day: 31, month: 12, year: 2025)
    }

    func testNumericDatesWithDashes() {
        // DD-MM-YYYY format
        let date1 = dateParser.parseDate(from: "15-01-2024")
        XCTAssertNotNil(date1)
        assertDateComponents(date1!, day: 15, month: 1, year: 2024)

        // YYYY-MM-DD format (ISO)
        let date2 = dateParser.parseDate(from: "2024-01-15")
        XCTAssertNotNil(date2)
        assertDateComponents(date2!, day: 15, month: 1, year: 2024)
    }

    func testNumericDatesWithSlashes() {
        // DD/MM/YYYY format
        let date1 = dateParser.parseDate(from: "15/01/2024")
        XCTAssertNotNil(date1)
        assertDateComponents(date1!, day: 15, month: 1, year: 2024)
    }

    func testSingleDigitDayMonth() {
        // Single digit day/month
        let date1 = dateParser.parseDate(from: "1.01.2024")
        XCTAssertNotNil(date1)
        assertDateComponents(date1!, day: 1, month: 1, year: 2024)

        let date2 = dateParser.parseDate(from: "5/3/2024")
        XCTAssertNotNil(date2)
        assertDateComponents(date2!, day: 5, month: 3, year: 2024)
    }

    // MARK: - Polish Verbal Date Parsing Tests

    func testPolishFullMonthNames() {
        let testCases: [(String, Int, Int, Int)] = [
            ("31 stycznia 2024", 31, 1, 2024),
            ("15 lutego 2024", 15, 2, 2024),
            ("1 marca 2024", 1, 3, 2024),
            ("10 kwietnia 2024", 10, 4, 2024),
            ("20 maja 2024", 20, 5, 2024),
            ("5 czerwca 2024", 5, 6, 2024),
            ("15 lipca 2024", 15, 7, 2024),
            ("25 sierpnia 2024", 25, 8, 2024),
            ("30 wrzesnia 2024", 30, 9, 2024),  // Without diacritic
            ("30 września 2024", 30, 9, 2024),  // With diacritic
            ("31 pazdziernika 2024", 31, 10, 2024),  // Without diacritic
            ("31 października 2024", 31, 10, 2024),  // With diacritic
            ("15 listopada 2024", 15, 11, 2024),
            ("25 grudnia 2024", 25, 12, 2024)
        ]

        for (input, day, month, year) in testCases {
            let date = dateParser.parseDate(from: input)
            XCTAssertNotNil(date, "Failed to parse: \(input)")
            if let date = date {
                assertDateComponents(date, day: day, month: month, year: year, message: "Wrong components for: \(input)")
            }
        }
    }

    func testPolishShortMonthNames() {
        let testCases: [(String, Int, Int, Int)] = [
            ("31 sty 2024", 31, 1, 2024),
            ("15 lut 2024", 15, 2, 2024),
            ("1 mar 2024", 1, 3, 2024),
            ("10 kwi 2024", 10, 4, 2024),
            ("20 maj 2024", 20, 5, 2024),
            ("5 cze 2024", 5, 6, 2024),
            ("15 lip 2024", 15, 7, 2024),
            ("25 sie 2024", 25, 8, 2024),
            ("30 wrz 2024", 30, 9, 2024),
            ("31 paz 2024", 31, 10, 2024),
            ("15 lis 2024", 15, 11, 2024),
            ("25 gru 2024", 25, 12, 2024)
        ]

        for (input, day, month, year) in testCases {
            let date = dateParser.parseDate(from: input)
            XCTAssertNotNil(date, "Failed to parse: \(input)")
            if let date = date {
                assertDateComponents(date, day: day, month: month, year: year, message: "Wrong components for: \(input)")
            }
        }
    }

    // MARK: - English Verbal Date Parsing Tests

    func testEnglishFullMonthNames() {
        let testCases: [(String, Int, Int, Int)] = [
            ("January 31, 2024", 31, 1, 2024),
            ("February 15, 2024", 15, 2, 2024),
            ("March 1, 2024", 1, 3, 2024),
            ("April 10, 2024", 10, 4, 2024),
            ("May 20, 2024", 20, 5, 2024),
            ("June 5, 2024", 5, 6, 2024),
            ("July 15, 2024", 15, 7, 2024),
            ("August 25, 2024", 25, 8, 2024),
            ("September 30, 2024", 30, 9, 2024),
            ("October 31, 2024", 31, 10, 2024),
            ("November 15, 2024", 15, 11, 2024),
            ("December 25, 2024", 25, 12, 2024)
        ]

        for (input, day, month, year) in testCases {
            let date = dateParser.parseDate(from: input)
            XCTAssertNotNil(date, "Failed to parse: \(input)")
            if let date = date {
                assertDateComponents(date, day: day, month: month, year: year, message: "Wrong components for: \(input)")
            }
        }
    }

    func testEnglishDayMonthYear() {
        // Day Month Year format (British style)
        let date1 = dateParser.parseDate(from: "31 January 2024")
        XCTAssertNotNil(date1)
        assertDateComponents(date1!, day: 31, month: 1, year: 2024)

        let date2 = dateParser.parseDate(from: "15 Feb 2024")
        XCTAssertNotNil(date2)
        assertDateComponents(date2!, day: 15, month: 2, year: 2024)
    }

    func testEnglishShortMonthNames() {
        let testCases: [(String, Int, Int, Int)] = [
            ("Jan 31, 2024", 31, 1, 2024),
            ("Feb 15, 2024", 15, 2, 2024),
            ("Mar 1, 2024", 1, 3, 2024),
            ("Apr 10, 2024", 10, 4, 2024),
            ("May 20, 2024", 20, 5, 2024),
            ("Jun 5, 2024", 5, 6, 2024),
            ("Jul 15, 2024", 15, 7, 2024),
            ("Aug 25, 2024", 25, 8, 2024),
            ("Sep 30, 2024", 30, 9, 2024),
            ("Oct 31, 2024", 31, 10, 2024),
            ("Nov 15, 2024", 15, 11, 2024),
            ("Dec 25, 2024", 25, 12, 2024)
        ]

        for (input, day, month, year) in testCases {
            let date = dateParser.parseDate(from: input)
            XCTAssertNotNil(date, "Failed to parse: \(input)")
            if let date = date {
                assertDateComponents(date, day: day, month: month, year: year, message: "Wrong components for: \(input)")
            }
        }
    }

    // MARK: - Date Extraction from Context

    func testDateExtractionFromContext() {
        // Date embedded in text
        let result1 = dateParser.parseDateWithPattern(from: "Termin płatności: 31.01.2024")
        XCTAssertNotNil(result1)
        assertDateComponents(result1!.date, day: 31, month: 1, year: 2024)

        let result2 = dateParser.parseDateWithPattern(from: "Due date: January 15, 2024")
        XCTAssertNotNil(result2)
        assertDateComponents(result2!.date, day: 15, month: 1, year: 2024)

        let result3 = dateParser.parseDateWithPattern(from: "Płatne do 28 lutego 2024")
        XCTAssertNotNil(result3)
        assertDateComponents(result3!.date, day: 28, month: 2, year: 2024)
    }

    // MARK: - Edge Cases

    func testLeapYearDates() {
        // Feb 29 in leap year
        let date1 = dateParser.parseDate(from: "29.02.2024")
        XCTAssertNotNil(date1)
        assertDateComponents(date1!, day: 29, month: 2, year: 2024)

        // Feb 29 in non-leap year should still parse (DateFormatter may roll over)
        // The date parser just parses, it doesn't validate leap years
    }

    func testInvalidDates() {
        // Completely invalid
        XCTAssertNil(dateParser.parseDate(from: "not a date"))
        XCTAssertNil(dateParser.parseDate(from: "ABC Company"))
        XCTAssertNil(dateParser.parseDate(from: "12345"))

        // Very old dates (beyond 5 years)
        XCTAssertNil(dateParser.parseDate(from: "01.01.2010"))

        // Future dates (beyond 2 years)
        XCTAssertNil(dateParser.parseDate(from: "01.01.2030"))
    }

    func testAllDateExtraction() {
        let text = "Data wystawienia: 15.01.2024, Termin płatności: 31.01.2024"
        let dates = dateParser.extractAllDates(from: text)

        XCTAssertEqual(dates.count, 2)
        if dates.count == 2 {
            assertDateComponents(dates[0].date, day: 15, month: 1, year: 2024)
            assertDateComponents(dates[1].date, day: 31, month: 1, year: 2024)
        }
    }

    // MARK: - Helper Methods

    private func assertDateComponents(
        _ date: Date,
        day: Int,
        month: Int,
        year: Int,
        message: String = ""
    ) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .month, .year], from: date)

        XCTAssertEqual(components.day, day, "Day mismatch. \(message)")
        XCTAssertEqual(components.month, month, "Month mismatch. \(message)")
        XCTAssertEqual(components.year, year, "Year mismatch. \(message)")
    }
}
