import XCTest
@testable import Dueasy_v2

/// Unit tests for FuzzyMatchCalculator.
/// Tests threshold boundaries for fuzzy matching:
/// - < 30%: auto-match (amount is close enough)
/// - 30-50%: fuzzy zone (needs user confirmation)
/// - > 50%: auto-create new (amount is too different)
final class FuzzyMatchCalculatorTests: XCTestCase {

    // MARK: - Percent Difference Calculation Tests

    func testCalculatePercentDifference_identicalAmounts_returnsZero() {
        let result = FuzzyMatchCalculator.calculatePercentDifference(
            newAmount: 100,
            existingMin: 100,
            existingMax: 100
        )

        XCTAssertEqual(result, 0.0, accuracy: 0.001)
    }

    func testCalculatePercentDifference_withinRange_returnsZero() {
        // New amount is exactly at the midpoint of the range
        let result = FuzzyMatchCalculator.calculatePercentDifference(
            newAmount: 150,
            existingMin: 100,
            existingMax: 200
        )

        XCTAssertEqual(result, 0.0, accuracy: 0.001)
    }

    func testCalculatePercentDifference_10PercentHigher_returns10Percent() {
        let result = FuzzyMatchCalculator.calculatePercentDifference(
            newAmount: 110,
            existingMin: 100,
            existingMax: 100
        )

        XCTAssertEqual(result, 0.10, accuracy: 0.001)
    }

    func testCalculatePercentDifference_50PercentHigher_returns50Percent() {
        let result = FuzzyMatchCalculator.calculatePercentDifference(
            newAmount: 150,
            existingMin: 100,
            existingMax: 100
        )

        XCTAssertEqual(result, 0.50, accuracy: 0.001)
    }

    func testCalculatePercentDifference_nilMin_returns100Percent() {
        let result = FuzzyMatchCalculator.calculatePercentDifference(
            newAmount: 100,
            existingMin: nil,
            existingMax: 100
        )

        XCTAssertEqual(result, 1.0, accuracy: 0.001)
    }

    func testCalculatePercentDifference_zeroMidpoint_returns100Percent() {
        let result = FuzzyMatchCalculator.calculatePercentDifference(
            newAmount: 100,
            existingMin: 0,
            existingMax: 0
        )

        XCTAssertEqual(result, 1.0, accuracy: 0.001)
    }

    // MARK: - Threshold Boundary Tests

    func testCategorize_29PercentDifference_returnsAutoMatch() {
        // 29% is below the 30% threshold - should auto-match
        let category = FuzzyMatchCalculator.categorize(percentDifference: 0.29)

        XCTAssertEqual(category, .autoMatch)
    }

    func testCategorize_30PercentDifference_returnsFuzzyZone() {
        // 30% is at the threshold - should be fuzzy zone (>=30%)
        let category = FuzzyMatchCalculator.categorize(percentDifference: 0.30)

        XCTAssertEqual(category, .fuzzyZone)
    }

    func testCategorize_40PercentDifference_returnsFuzzyZone() {
        // 40% is in the middle of the fuzzy zone
        let category = FuzzyMatchCalculator.categorize(percentDifference: 0.40)

        XCTAssertEqual(category, .fuzzyZone)
    }

    func testCategorize_50PercentDifference_returnsAutoCreateNew() {
        // 50% is at the upper threshold - should auto-create new (>=50%)
        let category = FuzzyMatchCalculator.categorize(percentDifference: 0.50)

        XCTAssertEqual(category, .autoCreateNew)
    }

    func testCategorize_51PercentDifference_returnsAutoCreateNew() {
        // 51% is above the 50% threshold - should auto-create new
        let category = FuzzyMatchCalculator.categorize(percentDifference: 0.51)

        XCTAssertEqual(category, .autoCreateNew)
    }

    func testCategorize_100PercentDifference_returnsAutoCreateNew() {
        // 100% (double the amount) should definitely auto-create new
        let category = FuzzyMatchCalculator.categorize(percentDifference: 1.0)

        XCTAssertEqual(category, .autoCreateNew)
    }

    // MARK: - Real-World Scenario Tests

    func testScenario_utilitiesBillIncrease_smallVariation() {
        // Utility bill was 173 PLN, new bill is 180 PLN
        // This is a ~4% increase - should auto-match
        let percentDiff = FuzzyMatchCalculator.calculatePercentDifference(
            newAmount: 180,
            existingMin: 170,
            existingMax: 176
        )
        let category = FuzzyMatchCalculator.categorize(percentDifference: percentDiff)

        XCTAssertLessThan(percentDiff, 0.30)
        XCTAssertEqual(category, .autoMatch)
    }

    func testScenario_subscriptionPriceIncrease_moderateVariation() {
        // Subscription was 50 PLN, increased to 70 PLN
        // This is a 40% increase - should need confirmation
        let percentDiff = FuzzyMatchCalculator.calculatePercentDifference(
            newAmount: 70,
            existingMin: 50,
            existingMax: 50
        )
        let category = FuzzyMatchCalculator.categorize(percentDifference: percentDiff)

        XCTAssertEqual(category, .fuzzyZone)
    }

    func testScenario_differentServiceFromSameVendor() {
        // Santander credit card payment is 500 PLN
        // New document is Santander loan payment at 1200 PLN
        // This is 140% different - should auto-create new template
        let percentDiff = FuzzyMatchCalculator.calculatePercentDifference(
            newAmount: 1200,
            existingMin: 500,
            existingMax: 500
        )
        let category = FuzzyMatchCalculator.categorize(percentDifference: percentDiff)

        XCTAssertGreaterThan(percentDiff, 0.50)
        XCTAssertEqual(category, .autoCreateNew)
    }

    func testScenario_exactBoundary_29Point99Percent() {
        // Edge case: just under 30%
        let category = FuzzyMatchCalculator.categorize(percentDifference: 0.2999)

        XCTAssertEqual(category, .autoMatch)
    }

    func testScenario_exactBoundary_49Point99Percent() {
        // Edge case: just under 50%
        let category = FuzzyMatchCalculator.categorize(percentDifference: 0.4999)

        XCTAssertEqual(category, .fuzzyZone)
    }

    // MARK: - Threshold Constants Tests

    func testThresholdConstants_autoMatchIs30Percent() {
        XCTAssertEqual(FuzzyMatchThreshold.autoMatchThreshold, 0.30)
    }

    func testThresholdConstants_createNewIs50Percent() {
        XCTAssertEqual(FuzzyMatchThreshold.createNewThreshold, 0.50)
    }
}
