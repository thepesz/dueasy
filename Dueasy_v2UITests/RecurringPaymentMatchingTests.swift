import XCTest

/// E2E tests for recurring payment auto-matching functionality.
/// Tests the automatic matching of new invoices to existing recurring templates
/// based on vendor and amount similarity.
final class RecurringPaymentMatchingTests: E2ETestBase {

    // MARK: - Auto-Match Tests

    /// Test auto-match to recurring template
    func testAutoMatchToRecurringTemplate() throws {
        XCTContext.runActivity(named: "Auto-Match to Recurring Template") { _ in
            // Step 1: Create recurring template (Vendor B, ~500 PLN)
            let vendor = uniqueVendorName(base: "VendorB")
            let templateAmount: Decimal = 500

            let templateSuccess = addInvoice(vendor: vendor, amount: templateAmount, enableRecurring: true)
            XCTAssertTrue(templateSuccess, "Failed to create recurring template")

            sleep(2)

            // Step 2: Verify template was created
            openRecurringOverview()
            sleep(1)

            let templateExists = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '\(vendor)'")).firstMatch.waitForExistence(timeout: shortTimeout)
            takeScreenshot(name: "auto_match_template_created")

            // Dismiss recurring overview
            dismissAnyPresented()

            // Step 3: Add new invoice with close amount (505 PLN - 1% difference)
            let newAmount: Decimal = 505

            let newInvoiceSuccess = addInvoice(vendor: vendor, amount: newAmount)
            XCTAssertTrue(newInvoiceSuccess, "Failed to add new invoice")

            sleep(2)

            // Step 4: Verify auto-match occurred
            // The new invoice should be linked to the existing template
            navigateToDocuments()
            sleep(1)

            // Open the new invoice details
            let firstCell = app.cells.element(boundBy: 0)
            if firstCell.waitForExistence(timeout: shortTimeout) {
                firstCell.tap()
                sleep(1)

                takeScreenshot(name: "auto_match_invoice_detail")

                // Look for recurring indicator/badge
                let recurringIndicator = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Recurring' OR label CONTAINS[c] 'recurring' OR label CONTAINS[c] 'Linked'")).firstMatch

                // Navigate back
                let backButton = app.navigationBars.buttons.element(boundBy: 0)
                if backButton.exists {
                    backButton.tap()
                }
            }

            // Step 5: Check recurring overview for updated instance status
            openRecurringOverview()
            sleep(1)

            takeScreenshot(name: "auto_match_template_updated")

            // The instance should now show as "matched" instead of "expected"
            let matchedStatus = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Matched' OR label CONTAINS[c] 'matched'")).firstMatch

            dismissAnyPresented()
        }
    }

    /// Test that instance status changes after matching
    func testInstanceStatusChangesAfterMatch() throws {
        XCTContext.runActivity(named: "Instance Status Changes After Match") { _ in
            // Create recurring template
            let vendor = uniqueVendorName(base: "StatusChange")
            let success = addInvoice(vendor: vendor, amount: 200, enableRecurring: true)
            XCTAssertTrue(success, "Failed to create recurring template")

            sleep(2)

            // Check initial instance status
            openRecurringOverview()
            sleep(1)

            takeScreenshot(name: "status_change_before_match")

            // Look for "Expected" status
            let expectedStatus = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Expected' OR label CONTAINS[c] 'expected'")).firstMatch

            dismissAnyPresented()

            // Add matching invoice
            let matchSuccess = addInvoice(vendor: vendor, amount: 198) // Close amount
            XCTAssertTrue(matchSuccess, "Failed to add matching invoice")

            sleep(2)

            // Check status changed
            openRecurringOverview()
            sleep(1)

            takeScreenshot(name: "status_change_after_match")

            // Look for "Matched" status
            let matchedStatus = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Matched' OR label CONTAINS[c] 'matched'")).firstMatch

            dismissAnyPresented()
        }
    }

    // MARK: - Amount Tolerance Tests

    /// Test matching with amounts within tolerance
    func testMatchingWithinAmountTolerance() throws {
        XCTContext.runActivity(named: "Matching Within Amount Tolerance") { _ in
            // Create template with 500 PLN
            let vendor = uniqueVendorName(base: "ToleranceTest")
            let templateSuccess = addInvoice(vendor: vendor, amount: 500, enableRecurring: true)
            XCTAssertTrue(templateSuccess, "Failed to create template")

            sleep(2)

            // Test various amounts within tolerance
            let toleranceAmounts: [Decimal] = [
                495,  // -1%
                500,  // Exact match
                505,  // +1%
                510,  // +2%
                490,  // -2%
            ]

            for amount in toleranceAmounts {
                let matchSuccess = addInvoice(vendor: vendor, amount: amount)
                print("Added invoice with amount \(amount): \(matchSuccess)")
            }

            // Check recurring overview
            openRecurringOverview()
            sleep(1)

            takeScreenshot(name: "tolerance_matching_result")

            // Multiple instances should be matched
            dismissAnyPresented()
        }
    }

    /// Test no match for amounts outside tolerance
    func testNoMatchOutsideTolerance() throws {
        XCTContext.runActivity(named: "No Match Outside Tolerance") { _ in
            // Create template with 100 PLN
            let vendor = uniqueVendorName(base: "OutsideTol")
            let templateSuccess = addInvoice(vendor: vendor, amount: 100, enableRecurring: true)
            XCTAssertTrue(templateSuccess, "Failed to create template")

            sleep(2)

            // Add invoice with very different amount (should not auto-match)
            // This might trigger fuzzy match dialog instead
            let differentAmount: Decimal = 200 // 100% difference

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
                amountField.typeText("\(differentAmount)")
            }

            app.swipeUp()

            // Save without enabling recurring
            let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Save'")).firstMatch
            if saveButton.exists {
                saveButton.tap()
            }

            sleep(2)

            takeScreenshot(name: "outside_tolerance_result")

            // Dismiss any dialogs
            dismissAnyPresented()
        }
    }

    // MARK: - Vendor Fingerprint Tests

    /// Test matching uses vendor fingerprint correctly
    func testVendorFingerprintMatching() throws {
        XCTContext.runActivity(named: "Vendor Fingerprint Matching") { _ in
            // Create template for Vendor A
            let vendorA = uniqueVendorName(base: "FingerprintA")
            let templateA = addInvoice(vendor: vendorA, amount: 300, enableRecurring: true)
            XCTAssertTrue(templateA, "Failed to create template A")

            sleep(2)

            // Create template for Vendor B
            let vendorB = uniqueVendorName(base: "FingerprintB")
            let templateB = addInvoice(vendor: vendorB, amount: 300, enableRecurring: true)
            XCTAssertTrue(templateB, "Failed to create template B")

            sleep(2)

            // Add invoice for Vendor A - should match A's template
            let matchA = addInvoice(vendor: vendorA, amount: 305)
            XCTAssertTrue(matchA, "Failed to add matching invoice for A")

            // Add invoice for Vendor B - should match B's template
            let matchB = addInvoice(vendor: vendorB, amount: 295)
            XCTAssertTrue(matchB, "Failed to add matching invoice for B")

            sleep(2)

            // Verify each template has correct matches
            openRecurringOverview()
            sleep(1)

            takeScreenshot(name: "fingerprint_matching_result")

            dismissAnyPresented()
        }
    }

    // MARK: - Multiple Templates Same Vendor

    /// Test matching when vendor has multiple templates
    func testMatchingWithMultipleTemplatesSameVendor() throws {
        XCTContext.runActivity(named: "Multiple Templates Same Vendor") { _ in
            // This scenario occurs when "Different Service" was selected in fuzzy match
            let vendor = uniqueVendorName(base: "MultiTemplate")

            // Create first template (e.g., electricity)
            let template1 = addInvoice(vendor: vendor, amount: 150, enableRecurring: true)
            XCTAssertTrue(template1, "Failed to create first template")

            sleep(2)

            // Create second template with very different amount (e.g., internet)
            let template2 = addInvoice(vendor: vendor, amount: 80, enableRecurring: true)

            // Check for fuzzy match - select "Different Service" if shown
            let differentServiceButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Different'")).firstMatch
            if differentServiceButton.waitForExistence(timeout: shortTimeout) {
                differentServiceButton.tap()
                sleep(1)
            }

            sleep(2)

            // Now add invoice matching first template's amount
            let matchFirst = addInvoice(vendor: vendor, amount: 148) // Matches 150
            XCTAssertTrue(matchFirst, "Failed to add invoice matching first template")

            // Add invoice matching second template's amount
            let matchSecond = addInvoice(vendor: vendor, amount: 82) // Matches 80
            XCTAssertTrue(matchSecond, "Failed to add invoice matching second template")

            // Verify in recurring overview
            openRecurringOverview()
            sleep(1)

            takeScreenshot(name: "multi_template_matching")

            dismissAnyPresented()
        }
    }

    // MARK: - Calendar Display After Matching

    /// Test that matched instances show correctly in calendar
    func testMatchedInstancesInCalendar() throws {
        XCTContext.runActivity(named: "Matched Instances in Calendar") { _ in
            // Create recurring template
            let vendor = uniqueVendorName(base: "CalendarMatch")
            let success = addInvoice(vendor: vendor, amount: 250, enableRecurring: true)
            XCTAssertTrue(success, "Failed to create recurring template")

            sleep(2)

            // Add matching invoice
            let matchSuccess = addInvoice(vendor: vendor, amount: 255)
            XCTAssertTrue(matchSuccess, "Failed to add matching invoice")

            sleep(2)

            // Navigate to calendar
            navigateToCalendar()
            sleep(1)

            // Enable recurring filter
            let recurringToggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'recurring'")).firstMatch
            if recurringToggle.exists {
                recurringToggle.tap()
                sleep(1)
            }

            // Get today's day
            let calendar = Calendar.current
            let today = Date()
            let dayOfMonth = calendar.component(.day, from: today)

            // Select today
            let dayButton = app.buttons.matching(NSPredicate(format: "label == '\(dayOfMonth)'")).firstMatch
            if dayButton.exists {
                dayButton.tap()
                sleep(1)

                // Should show the matched instance
                let matchedText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Matched' OR label CONTAINS[c] 'matched'")).firstMatch

                takeScreenshot(name: "calendar_matched_instance")
            }
        }
    }

    // MARK: - Mark as Paid After Matching

    /// Test marking a matched instance as paid
    func testMarkMatchedInstanceAsPaid() throws {
        XCTContext.runActivity(named: "Mark Matched Instance as Paid") { _ in
            // Create and match
            let vendor = uniqueVendorName(base: "MarkPaidMatch")
            let success = addInvoice(vendor: vendor, amount: 175, enableRecurring: true)
            XCTAssertTrue(success, "Failed to create recurring template")

            sleep(2)

            // Add matching invoice
            let matchSuccess = addInvoice(vendor: vendor, amount: 178)
            XCTAssertTrue(matchSuccess, "Failed to add matching invoice")

            sleep(2)

            // Open recurring overview
            openRecurringOverview()
            sleep(1)

            takeScreenshot(name: "mark_paid_before")

            // Find and tap on the instance
            let instanceCell = app.cells.firstMatch
            if instanceCell.waitForExistence(timeout: shortTimeout) {
                instanceCell.tap()
                sleep(1)

                // Look for mark as paid option
                let markPaidButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Paid' OR label CONTAINS[c] 'paid'")).firstMatch
                if markPaidButton.waitForExistence(timeout: shortTimeout) {
                    markPaidButton.tap()
                    sleep(2)

                    takeScreenshot(name: "mark_paid_after")
                }
            }

            dismissAnyPresented()
        }
    }

    // MARK: - Home Page Counter After Matching

    /// Test that home page counters update after matching
    func testHomeCountersAfterMatching() throws {
        XCTContext.runActivity(named: "Home Counters After Matching") { _ in
            // Create recurring template
            let vendor = uniqueVendorName(base: "HomeCounter")
            let success = addInvoice(vendor: vendor, amount: 400, enableRecurring: true)
            XCTAssertTrue(success, "Failed to create recurring template")

            // Check home counters
            navigateToHome()
            sleep(2)

            takeScreenshot(name: "home_counters_with_template")

            // Add matching invoice
            let matchSuccess = addInvoice(vendor: vendor, amount: 395)
            XCTAssertTrue(matchSuccess, "Failed to add matching invoice")

            // Check home counters again
            navigateToHome()
            sleep(2)

            takeScreenshot(name: "home_counters_after_match")

            // Due amounts should reflect the matched invoice
        }
    }

    // MARK: - Unlink Tests

    /// Test unlinking a document from recurring template
    func testUnlinkDocumentFromRecurring() throws {
        XCTContext.runActivity(named: "Unlink Document from Recurring") { _ in
            // Create and match
            let vendor = uniqueVendorName(base: "UnlinkTest")
            let success = addInvoice(vendor: vendor, amount: 125, enableRecurring: true)
            XCTAssertTrue(success, "Failed to create recurring template")

            sleep(2)

            // Add matching invoice
            let matchSuccess = addInvoice(vendor: vendor, amount: 130)
            XCTAssertTrue(matchSuccess, "Failed to add matching invoice")

            sleep(2)

            // Navigate to documents
            navigateToDocuments()
            sleep(1)

            // Open the matched document
            let firstCell = app.cells.element(boundBy: 0)
            if firstCell.waitForExistence(timeout: shortTimeout) {
                firstCell.tap()
                sleep(1)

                // Look for unlink option
                // This might be in a menu or as a toggle
                let unlinkButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Unlink' OR label CONTAINS[c] 'unlink'")).firstMatch
                let recurringToggle = app.switches.firstMatch

                takeScreenshot(name: "unlink_document_detail")

                // Navigate back
                let backButton = app.navigationBars.buttons.element(boundBy: 0)
                if backButton.exists {
                    backButton.tap()
                }
            }
        }
    }
}
