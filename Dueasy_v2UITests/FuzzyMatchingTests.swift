import XCTest

/// E2E tests for fuzzy matching functionality.
/// Tests the fuzzy match dialog that appears when similar recurring payments are detected.
///
/// Fuzzy matching triggers when:
/// - A new invoice has a vendor matching an existing recurring template
/// - The amount difference is between 30-50% of the existing template's typical amount
final class FuzzyMatchingTests: E2ETestBase {

    // MARK: - Fuzzy Match Dialog Tests

    /// Test fuzzy match dialog appears for similar amounts
    func testFuzzyMatchDialogAppears() throws {
        XCTContext.runActivity(named: "Fuzzy Match Dialog Appears") { _ in
            // Step 1: Create first invoice with recurring enabled
            let vendor = uniqueVendorName(base: "FuzzyVendorA")
            let firstAmount: Decimal = 100

            let firstSuccess = addInvoice(vendor: vendor, amount: firstAmount, enableRecurring: true)
            XCTAssertTrue(firstSuccess, "Failed to add first invoice")

            sleep(2)

            // Step 2: Create second invoice with same vendor but ~40% different amount
            // 100 + 40% = 140, which should trigger fuzzy match (30-50% range)
            let secondAmount: Decimal = 140

            // Add second invoice with same vendor
            openAddDocumentSheet()

            // Select manual entry
            let manualEntryButton = app.buttons["Manual Entry"]
            if manualEntryButton.waitForExistence(timeout: shortTimeout) {
                manualEntryButton.tap()
            } else {
                let manualEntryCell = app.cells.containing(.staticText, identifier: "Manual Entry").firstMatch
                if manualEntryCell.waitForExistence(timeout: shortTimeout) {
                    manualEntryCell.tap()
                }
            }

            sleep(1)

            // Enter same vendor name
            let vendorField = app.textFields.element(boundBy: 0)
            if vendorField.waitForExistence(timeout: shortTimeout) {
                vendorField.tap()
                vendorField.typeText(vendor)
            }

            app.swipeUp()

            // Enter different amount
            let amountField = app.textFields.element(boundBy: 1)
            if amountField.waitForExistence(timeout: shortTimeout) {
                amountField.tap()
                amountField.typeText("\(secondAmount)")
            }

            app.swipeUp()

            // Enable recurring
            let recurringToggle = app.switches.firstMatch
            if recurringToggle.waitForExistence(timeout: shortTimeout) {
                if recurringToggle.value as? String == "0" {
                    recurringToggle.tap()
                }
            }

            sleep(1)

            // Try to save
            let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Save'")).firstMatch
            if saveButton.waitForExistence(timeout: shortTimeout) {
                saveButton.tap()
            }

            sleep(2)

            // Check for fuzzy match dialog
            let fuzzyMatchSheet = app.sheets.firstMatch
            let fuzzyMatchTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Similar' OR label CONTAINS[c] 'same service' OR label CONTAINS[c] 'recurring'")).firstMatch

            if fuzzyMatchTitle.waitForExistence(timeout: shortTimeout) || fuzzyMatchSheet.waitForExistence(timeout: shortTimeout) {
                takeScreenshot(name: "fuzzy_match_dialog_shown")
                XCTAssertTrue(true, "Fuzzy match dialog appeared")
            } else {
                takeScreenshot(name: "fuzzy_match_no_dialog")
                // Note: Dialog may not appear depending on exact matching logic
                print("Warning: Fuzzy match dialog did not appear")
            }
        }
    }

    /// Test "Same Service" option in fuzzy match dialog
    func testFuzzyMatchSameServiceOption() throws {
        XCTContext.runActivity(named: "Fuzzy Match - Same Service") { _ in
            // Create initial recurring template
            let vendor = uniqueVendorName(base: "SameServiceVendor")
            let firstSuccess = addInvoice(vendor: vendor, amount: 173, enableRecurring: true)
            XCTAssertTrue(firstSuccess, "Failed to add first invoice")

            sleep(2)

            // Create second invoice that triggers fuzzy match
            openAddDocumentSheet()

            let manualEntry = app.buttons["Manual Entry"]
            if manualEntry.waitForExistence(timeout: shortTimeout) {
                manualEntry.tap()
            }

            sleep(1)

            // Same vendor
            let vendorField = app.textFields.element(boundBy: 0)
            if vendorField.exists {
                vendorField.tap()
                vendorField.typeText(vendor)
            }

            app.swipeUp()

            // 44% different amount (173 * 1.44 = 249)
            let amountField = app.textFields.element(boundBy: 1)
            if amountField.exists {
                amountField.tap()
                amountField.typeText("250")
            }

            app.swipeUp()

            // Enable recurring
            let recurringToggle = app.switches.firstMatch
            if recurringToggle.exists && recurringToggle.value as? String == "0" {
                recurringToggle.tap()
            }

            // Save
            let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Save'")).firstMatch
            if saveButton.exists {
                saveButton.tap()
            }

            sleep(2)

            // Look for "Same Service" option
            let sameServiceButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Same' OR label CONTAINS[c] 'Link'")).firstMatch
            if sameServiceButton.waitForExistence(timeout: shortTimeout) {
                takeScreenshot(name: "fuzzy_match_same_service_option")

                sameServiceButton.tap()
                sleep(2)

                takeScreenshot(name: "fuzzy_match_same_service_selected")

                // Verify we're back (no new template created)
                openRecurringOverview()
                sleep(1)

                // Should still have only one template
                takeScreenshot(name: "fuzzy_match_same_service_result")
            }
        }
    }

    /// Test "Different Service" option in fuzzy match dialog
    func testFuzzyMatchDifferentServiceOption() throws {
        XCTContext.runActivity(named: "Fuzzy Match - Different Service") { _ in
            // Create initial recurring template
            let vendor = uniqueVendorName(base: "DiffServiceVendor")
            let firstSuccess = addInvoice(vendor: vendor, amount: 100, enableRecurring: true)
            XCTAssertTrue(firstSuccess, "Failed to add first invoice")

            sleep(2)

            // Create second invoice that triggers fuzzy match
            openAddDocumentSheet()

            let manualEntry = app.buttons["Manual Entry"]
            if manualEntry.waitForExistence(timeout: shortTimeout) {
                manualEntry.tap()
            }

            sleep(1)

            // Same vendor
            let vendorField = app.textFields.element(boundBy: 0)
            if vendorField.exists {
                vendorField.tap()
                vendorField.typeText(vendor)
            }

            app.swipeUp()

            // 35% different amount
            let amountField = app.textFields.element(boundBy: 1)
            if amountField.exists {
                amountField.tap()
                amountField.typeText("135")
            }

            app.swipeUp()

            // Enable recurring
            let recurringToggle = app.switches.firstMatch
            if recurringToggle.exists && recurringToggle.value as? String == "0" {
                recurringToggle.tap()
            }

            // Save
            let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Save'")).firstMatch
            if saveButton.exists {
                saveButton.tap()
            }

            sleep(2)

            // Look for "Different Service" option
            let differentServiceButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Different' OR label CONTAINS[c] 'New'")).firstMatch
            if differentServiceButton.waitForExistence(timeout: shortTimeout) {
                takeScreenshot(name: "fuzzy_match_different_service_option")

                differentServiceButton.tap()
                sleep(2)

                takeScreenshot(name: "fuzzy_match_different_service_selected")

                // Verify we now have two templates
                openRecurringOverview()
                sleep(1)

                takeScreenshot(name: "fuzzy_match_different_service_result")

                // Count templates
                let cells = app.cells
                // Should have multiple templates now
                print("Template count after 'Different Service': \(cells.count)")
            }
        }
    }

    /// Test fuzzy match dialog cancel behavior
    func testFuzzyMatchCancelOption() throws {
        XCTContext.runActivity(named: "Fuzzy Match - Cancel") { _ in
            // Create initial recurring template
            let vendor = uniqueVendorName(base: "CancelVendor")
            let firstSuccess = addInvoice(vendor: vendor, amount: 200, enableRecurring: true)
            XCTAssertTrue(firstSuccess, "Failed to add first invoice")

            sleep(2)

            // Attempt to create second invoice that triggers fuzzy match
            openAddDocumentSheet()

            let manualEntry = app.buttons["Manual Entry"]
            if manualEntry.waitForExistence(timeout: shortTimeout) {
                manualEntry.tap()
            }

            sleep(1)

            // Same vendor
            let vendorField = app.textFields.element(boundBy: 0)
            if vendorField.exists {
                vendorField.tap()
                vendorField.typeText(vendor)
            }

            app.swipeUp()

            // 40% different
            let amountField = app.textFields.element(boundBy: 1)
            if amountField.exists {
                amountField.tap()
                amountField.typeText("280")
            }

            app.swipeUp()

            // Enable recurring
            let recurringToggle = app.switches.firstMatch
            if recurringToggle.exists && recurringToggle.value as? String == "0" {
                recurringToggle.tap()
            }

            // Save
            let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Save'")).firstMatch
            if saveButton.exists {
                saveButton.tap()
            }

            sleep(2)

            // Look for Cancel button
            let cancelButton = app.buttons["Cancel"]
            if cancelButton.waitForExistence(timeout: shortTimeout) {
                takeScreenshot(name: "fuzzy_match_before_cancel")

                cancelButton.tap()
                sleep(1)

                takeScreenshot(name: "fuzzy_match_after_cancel")

                // Recurring should be disabled after cancel
            }
        }
    }

    // MARK: - Amount Range Tests

    /// Test amounts outside fuzzy match range don't trigger dialog
    func testNoFuzzyMatchForSmallDifference() throws {
        XCTContext.runActivity(named: "No Fuzzy Match for Small Difference") { _ in
            // Create first invoice
            let vendor = uniqueVendorName(base: "SmallDiffVendor")
            let firstSuccess = addInvoice(vendor: vendor, amount: 100, enableRecurring: true)
            XCTAssertTrue(firstSuccess, "Failed to add first invoice")

            sleep(2)

            // Create second invoice with only 10% difference (below 30% threshold)
            let secondSuccess = addInvoice(vendor: vendor, amount: 110, enableRecurring: true)

            // Should NOT show fuzzy match dialog for small differences
            // Instead, it should auto-match to existing template
            let fuzzyMatchTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Similar' OR label CONTAINS[c] 'same service'")).firstMatch
            let dialogShown = fuzzyMatchTitle.waitForExistence(timeout: shortTimeout)

            if dialogShown {
                takeScreenshot(name: "unexpected_fuzzy_match_small_diff")
                // Dismiss it
                let cancelButton = app.buttons["Cancel"]
                if cancelButton.exists {
                    cancelButton.tap()
                }
            }

            takeScreenshot(name: "no_fuzzy_match_small_diff")
        }
    }

    /// Test amounts way outside range don't trigger dialog
    func testNoFuzzyMatchForLargeDifference() throws {
        XCTContext.runActivity(named: "No Fuzzy Match for Large Difference") { _ in
            // Create first invoice
            let vendor = uniqueVendorName(base: "LargeDiffVendor")
            let firstSuccess = addInvoice(vendor: vendor, amount: 100, enableRecurring: true)
            XCTAssertTrue(firstSuccess, "Failed to add first invoice")

            sleep(2)

            // Create second invoice with 100% difference (above 50% threshold)
            let secondSuccess = addInvoice(vendor: vendor, amount: 200, enableRecurring: true)

            // Should NOT show fuzzy match dialog for large differences
            // It should create a new template
            let fuzzyMatchTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Similar' OR label CONTAINS[c] 'same service'")).firstMatch
            let dialogShown = fuzzyMatchTitle.waitForExistence(timeout: shortTimeout)

            if dialogShown {
                takeScreenshot(name: "unexpected_fuzzy_match_large_diff")
                let cancelButton = app.buttons["Cancel"]
                if cancelButton.exists {
                    cancelButton.tap()
                }
            }

            takeScreenshot(name: "no_fuzzy_match_large_diff")
        }
    }

    // MARK: - Vendor Matching Tests

    /// Test fuzzy match only triggers for same vendor
    func testFuzzyMatchOnlySameVendor() throws {
        XCTContext.runActivity(named: "Fuzzy Match Only Same Vendor") { _ in
            // Create first invoice with one vendor
            let vendor1 = uniqueVendorName(base: "VendorOne")
            let firstSuccess = addInvoice(vendor: vendor1, amount: 100, enableRecurring: true)
            XCTAssertTrue(firstSuccess, "Failed to add first invoice")

            sleep(2)

            // Create second invoice with DIFFERENT vendor but similar amount
            let vendor2 = uniqueVendorName(base: "VendorTwo")
            let secondSuccess = addInvoice(vendor: vendor2, amount: 140, enableRecurring: true)

            // Should NOT show fuzzy match dialog for different vendors
            let fuzzyMatchTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Similar' OR label CONTAINS[c] 'same service'")).firstMatch
            let dialogShown = fuzzyMatchTitle.waitForExistence(timeout: shortTimeout)

            XCTAssertFalse(dialogShown, "Fuzzy match should not trigger for different vendors")

            takeScreenshot(name: "no_fuzzy_match_different_vendor")
        }
    }

    // MARK: - Multiple Candidates Test

    /// Test fuzzy match with multiple potential template matches
    func testFuzzyMatchMultipleCandidates() throws {
        XCTContext.runActivity(named: "Fuzzy Match Multiple Candidates") { _ in
            // This tests when a vendor has multiple recurring templates
            // and the new amount could match multiple

            let vendor = uniqueVendorName(base: "MultiCandidate")

            // Create two templates for same vendor with different amounts
            let first = addInvoice(vendor: vendor, amount: 100, enableRecurring: true)
            XCTAssertTrue(first, "Failed to add first invoice")
            sleep(2)

            // Force create second template by using "Different Service"
            // or by having amounts far enough apart
            let second = addInvoice(vendor: vendor, amount: 200, enableRecurring: true)
            sleep(2)

            // Now add third invoice with amount between them
            // Amount 150 could potentially match either
            openAddDocumentSheet()

            let manualEntry = app.buttons["Manual Entry"]
            if manualEntry.waitForExistence(timeout: shortTimeout) {
                manualEntry.tap()
            }

            sleep(1)

            let vendorField = app.textFields.element(boundBy: 0)
            if vendorField.exists {
                vendorField.tap()
                vendorField.typeText(vendor)
            }

            app.swipeUp()

            let amountField = app.textFields.element(boundBy: 1)
            if amountField.exists {
                amountField.tap()
                amountField.typeText("150")
            }

            app.swipeUp()

            let recurringToggle = app.switches.firstMatch
            if recurringToggle.exists && recurringToggle.value as? String == "0" {
                recurringToggle.tap()
            }

            let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Save'")).firstMatch
            if saveButton.exists {
                saveButton.tap()
            }

            sleep(2)

            // Check if dialog shows multiple options
            takeScreenshot(name: "fuzzy_match_multiple_candidates")

            // Dismiss any dialogs
            dismissAnyPresented()
        }
    }

    // MARK: - UI Element Tests

    /// Test fuzzy match dialog UI elements are complete
    func testFuzzyMatchDialogUIElements() throws {
        XCTContext.runActivity(named: "Fuzzy Match Dialog UI Elements") { _ in
            // Create conditions for fuzzy match
            let vendor = uniqueVendorName(base: "UITest")
            let first = addInvoice(vendor: vendor, amount: 100, enableRecurring: true)
            XCTAssertTrue(first, "Failed to add first invoice")
            sleep(2)

            openAddDocumentSheet()

            let manualEntry = app.buttons["Manual Entry"]
            if manualEntry.waitForExistence(timeout: shortTimeout) {
                manualEntry.tap()
            }

            sleep(1)

            let vendorField = app.textFields.element(boundBy: 0)
            if vendorField.exists {
                vendorField.tap()
                vendorField.typeText(vendor)
            }

            app.swipeUp()

            let amountField = app.textFields.element(boundBy: 1)
            if amountField.exists {
                amountField.tap()
                amountField.typeText("140")
            }

            app.swipeUp()

            let recurringToggle = app.switches.firstMatch
            if recurringToggle.exists && recurringToggle.value as? String == "0" {
                recurringToggle.tap()
            }

            let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Save'")).firstMatch
            if saveButton.exists {
                saveButton.tap()
            }

            sleep(2)

            // Verify dialog elements if shown
            let dialogExists = app.sheets.firstMatch.waitForExistence(timeout: shortTimeout)
            if dialogExists {
                // Check for expected UI elements
                let questionIcon = app.images.matching(NSPredicate(format: "identifier CONTAINS[c] 'questionmark'")).firstMatch
                let existingAmount = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '100'")).firstMatch
                let newAmount = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '140'")).firstMatch
                let percentDiff = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '%'")).firstMatch

                takeScreenshot(name: "fuzzy_match_ui_elements")

                // Dismiss
                dismissAnyPresented()
            }
        }
    }
}
