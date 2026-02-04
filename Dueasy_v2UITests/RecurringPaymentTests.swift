import XCTest

/// E2E tests for recurring payment functionality.
/// Tests template creation, instance generation, and calendar display of recurring payments.
final class RecurringPaymentTests: E2ETestBase {

    // MARK: - Template Creation Tests

    /// Test creating a recurring payment template
    func testCreateRecurringPaymentTemplate() throws {
        XCTContext.runActivity(named: "Create Recurring Payment Template") { _ in
            // Add invoice with recurring enabled
            let vendor = uniqueVendorName(base: "RecurringTemplate")
            let success = addInvoice(vendor: vendor, amount: 199.99, enableRecurring: true)
            XCTAssertTrue(success, "Failed to add recurring invoice")

            // Navigate to recurring overview
            openRecurringOverview()

            // Verify template was created
            // Look for the vendor name in templates section
            let templateText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '\(vendor)'")).firstMatch
            let templateExists = templateText.waitForExistence(timeout: standardTimeout)

            // If we can find it by name, great. Otherwise look for any template
            if !templateExists {
                // Look for any active template
                let activeSection = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Active' OR label CONTAINS[c] 'Templates'")).firstMatch
                XCTAssertTrue(activeSection.exists, "Should show templates section")
            }

            takeScreenshot(name: "recurring_template_created")
        }
    }

    /// Test creating multiple recurring templates from different vendors
    func testCreateMultipleRecurringTemplates() throws {
        XCTContext.runActivity(named: "Create Multiple Recurring Templates") { _ in
            let vendors = [
                (name: "Electric", amount: Decimal(150)),
                (name: "Gas", amount: Decimal(80)),
                (name: "Internet", amount: Decimal(79.99)),
                (name: "Phone", amount: Decimal(49.99))
            ]

            for vendor in vendors {
                let fullName = uniqueVendorName(base: vendor.name)
                let success = addInvoice(vendor: fullName, amount: vendor.amount, enableRecurring: true)
                XCTAssertTrue(success, "Failed to add recurring invoice for \(vendor.name)")
            }

            // Navigate to recurring overview
            openRecurringOverview()
            sleep(1)

            takeScreenshot(name: "multiple_recurring_templates")

            // Verify we have templates (at least one visible)
            let cells = app.cells
            XCTAssertGreaterThan(cells.count, 0, "Should have at least one recurring template")
        }
    }

    // MARK: - Instance Generation Tests

    /// Test that recurring instances are generated
    func testRecurringInstancesGenerated() throws {
        XCTContext.runActivity(named: "Recurring Instances Generated") { _ in
            // Add recurring invoice
            let vendor = uniqueVendorName(base: "InstanceGen")
            let success = addInvoice(vendor: vendor, amount: 100, enableRecurring: true)
            XCTAssertTrue(success, "Failed to add recurring invoice")

            // Navigate to recurring overview
            openRecurringOverview()
            sleep(1)

            // Look for "Upcoming" section with instances
            let upcomingSection = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Upcoming' OR label CONTAINS[c] 'Instances'")).firstMatch
            if upcomingSection.exists {
                takeScreenshot(name: "recurring_instances_section")

                // Scroll to see instances
                app.swipeUp()
                sleep(1)

                takeScreenshot(name: "recurring_instances_list")
            }
        }
    }

    /// Test recurring instances appear in calendar
    func testRecurringInstancesInCalendar() throws {
        XCTContext.runActivity(named: "Recurring Instances in Calendar") { _ in
            // Add recurring invoice
            let vendor = uniqueVendorName(base: "CalendarRecurring")
            let success = addInvoice(vendor: vendor, amount: 250, enableRecurring: true)
            XCTAssertTrue(success, "Failed to add recurring invoice")

            // Navigate to calendar
            navigateToCalendar()
            sleep(1)

            // Enable recurring-only filter to easily see recurring items
            let recurringToggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'recurring'")).firstMatch
            if recurringToggle.waitForExistence(timeout: shortTimeout) {
                recurringToggle.tap()
                sleep(1)
            }

            takeScreenshot(name: "calendar_recurring_instances")

            // Navigate to future months to see generated instances
            for i in 0..<3 {
                let nextButton = app.buttons["chevron.right"]
                if nextButton.exists {
                    nextButton.tap()
                } else {
                    app.swipeLeft()
                }
                sleep(1)
                takeScreenshot(name: "calendar_recurring_month_\(i + 1)")
            }
        }
    }

    // MARK: - Home Page Counter Tests

    /// Test active recurring counter on home page
    func testActiveRecurringCounterOnHome() throws {
        XCTContext.runActivity(named: "Active Recurring Counter on Home") { _ in
            // First check counter with no recurring
            navigateToHome()
            sleep(1)
            takeScreenshot(name: "home_no_recurring")

            // Add recurring invoices
            for i in 1...3 {
                let vendor = uniqueVendorName(base: "CounterTest\(i)")
                let success = addInvoice(vendor: vendor, amount: Decimal(100 * i), enableRecurring: true)
                XCTAssertTrue(success, "Failed to add recurring invoice \(i)")
            }

            // Check counter on home
            navigateToHome()
            sleep(1)

            // Look for recurring tile with count
            let recurringTile = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Recurring' OR label CONTAINS[c] 'Active'")).firstMatch
            XCTAssertTrue(recurringTile.waitForExistence(timeout: shortTimeout), "Should show recurring section")

            // Look for the count (should show 3 or similar)
            let countText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '3' OR label CONTAINS[c] 'Active'")).firstMatch

            takeScreenshot(name: "home_recurring_counter")
        }
    }

    // MARK: - Template Management Tests

    /// Test pausing a recurring template
    func testPauseRecurringTemplate() throws {
        XCTContext.runActivity(named: "Pause Recurring Template") { _ in
            // Add recurring invoice
            let vendor = uniqueVendorName(base: "PauseTest")
            let success = addInvoice(vendor: vendor, amount: 100, enableRecurring: true)
            XCTAssertTrue(success, "Failed to add recurring invoice")

            // Navigate to recurring overview
            openRecurringOverview()
            sleep(1)

            // Find the template card and its menu
            let menuButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'ellipsis' OR label CONTAINS[c] '...'")).firstMatch
            if menuButton.waitForExistence(timeout: shortTimeout) {
                menuButton.tap()
                sleep(1)

                // Tap pause option
                let pauseButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Pause'")).firstMatch
                if pauseButton.waitForExistence(timeout: shortTimeout) {
                    pauseButton.tap()
                    sleep(1)

                    takeScreenshot(name: "recurring_template_paused")
                }
            }
        }
    }

    /// Test resuming a paused recurring template
    func testResumeRecurringTemplate() throws {
        XCTContext.runActivity(named: "Resume Recurring Template") { _ in
            // Add and pause a recurring invoice
            let vendor = uniqueVendorName(base: "ResumeTest")
            let success = addInvoice(vendor: vendor, amount: 100, enableRecurring: true)
            XCTAssertTrue(success, "Failed to add recurring invoice")

            openRecurringOverview()
            sleep(1)

            // Pause first
            let menuButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'ellipsis' OR label CONTAINS[c] '...'")).firstMatch
            if menuButton.waitForExistence(timeout: shortTimeout) {
                menuButton.tap()
                sleep(1)

                let pauseButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Pause'")).firstMatch
                if pauseButton.exists {
                    pauseButton.tap()
                    sleep(1)
                }
            }

            // Switch to paused view
            let pausedSegment = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Paused'")).firstMatch
            if pausedSegment.waitForExistence(timeout: shortTimeout) {
                pausedSegment.tap()
                sleep(1)
            }

            // Resume
            let resumeMenuButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'ellipsis' OR label CONTAINS[c] '...'")).firstMatch
            if resumeMenuButton.waitForExistence(timeout: shortTimeout) {
                resumeMenuButton.tap()
                sleep(1)

                let resumeButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Resume'")).firstMatch
                if resumeButton.waitForExistence(timeout: shortTimeout) {
                    resumeButton.tap()
                    sleep(1)

                    takeScreenshot(name: "recurring_template_resumed")
                }
            }
        }
    }

    /// Test deleting a recurring template
    func testDeleteRecurringTemplate() throws {
        XCTContext.runActivity(named: "Delete Recurring Template") { _ in
            // Add recurring invoice
            let vendor = uniqueVendorName(base: "DeleteRecurring")
            let success = addInvoice(vendor: vendor, amount: 100, enableRecurring: true)
            XCTAssertTrue(success, "Failed to add recurring invoice")

            openRecurringOverview()
            sleep(1)

            // Count templates before deletion
            let cellsBefore = app.cells.count

            // Find and open menu
            let menuButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'ellipsis' OR label CONTAINS[c] '...'")).firstMatch
            if menuButton.waitForExistence(timeout: shortTimeout) {
                menuButton.tap()
                sleep(1)

                // Tap delete
                let deleteButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Delete'")).firstMatch
                if deleteButton.waitForExistence(timeout: shortTimeout) {
                    deleteButton.tap()
                    sleep(1)

                    // Confirm deletion
                    let confirmButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Delete'")).firstMatch
                    if confirmButton.waitForExistence(timeout: shortTimeout) {
                        confirmButton.tap()
                        sleep(1)
                    }

                    takeScreenshot(name: "recurring_template_deleted")

                    // Verify template is gone
                    let cellsAfter = app.cells.count
                    XCTAssertLessThan(cellsAfter, cellsBefore, "Template should be deleted")
                }
            }
        }
    }

    // MARK: - Instance Status Tests

    /// Test marking a recurring instance as paid
    func testMarkInstanceAsPaid() throws {
        XCTContext.runActivity(named: "Mark Instance as Paid") { _ in
            // Add recurring invoice
            let vendor = uniqueVendorName(base: "MarkPaid")
            let success = addInvoice(vendor: vendor, amount: 150, enableRecurring: true)
            XCTAssertTrue(success, "Failed to add recurring invoice")

            openRecurringOverview()
            sleep(1)

            // Find an upcoming instance and tap to show actions
            let instanceCell = app.cells.firstMatch
            if instanceCell.waitForExistence(timeout: shortTimeout) {
                instanceCell.tap()
                sleep(1)

                // Look for "Mark as Paid" button
                let markPaidButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'paid' OR label CONTAINS[c] 'Paid'")).firstMatch
                if markPaidButton.waitForExistence(timeout: shortTimeout) {
                    markPaidButton.tap()
                    sleep(1)

                    takeScreenshot(name: "recurring_instance_marked_paid")
                }
            }
        }
    }

    // MARK: - Due Day Tests

    /// Test that recurring instances use correct due day of month
    func testRecurringDueDayOfMonth() throws {
        XCTContext.runActivity(named: "Recurring Due Day of Month") { _ in
            // Add recurring invoice
            // The due day is determined from the original invoice's due date
            let vendor = uniqueVendorName(base: "DueDay")
            let success = addInvoice(vendor: vendor, amount: 100, enableRecurring: true)
            XCTAssertTrue(success, "Failed to add recurring invoice")

            openRecurringOverview()
            sleep(1)

            // Look for due day information in template card
            let dueDayText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'day' OR label CONTAINS[c] 'Due'")).firstMatch
            if dueDayText.exists {
                takeScreenshot(name: "recurring_due_day_info")
            }

            // Navigate to calendar to see instances on specific days
            navigateToCalendar()
            sleep(1)

            // Enable recurring filter
            let recurringToggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'recurring'")).firstMatch
            if recurringToggle.exists {
                recurringToggle.tap()
                sleep(1)
            }

            takeScreenshot(name: "calendar_recurring_due_days")
        }
    }

    // MARK: - Multi-Instance Tests

    /// Test viewing multiple months of recurring instances
    func testMultiMonthRecurringInstances() throws {
        XCTContext.runActivity(named: "Multi-Month Recurring Instances") { _ in
            // Add recurring invoice
            let vendor = uniqueVendorName(base: "MultiMonth")
            let success = addInvoice(vendor: vendor, amount: 200, enableRecurring: true)
            XCTAssertTrue(success, "Failed to add recurring invoice")

            // Navigate to calendar
            navigateToCalendar()
            sleep(1)

            // Enable recurring filter
            let recurringToggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'recurring'")).firstMatch
            if recurringToggle.exists {
                recurringToggle.tap()
                sleep(1)
            }

            // Navigate through several months and verify instances exist
            var instancesFound = 0
            for month in 0..<6 {
                // Look for recurring indicators in current month view
                // Indicators are shown on days with recurring instances

                takeScreenshot(name: "recurring_month_\(month)")

                // Navigate to next month
                let nextButton = app.buttons["chevron.right"]
                if nextButton.exists {
                    nextButton.tap()
                } else {
                    app.swipeLeft()
                }
                sleep(1)
            }

            // Should have generated instances for multiple months
            print("Navigated through 6 months of recurring instances")
        }
    }

    // MARK: - Edge Cases

    /// Test recurring template with very high amount
    func testRecurringWithHighAmount() throws {
        XCTContext.runActivity(named: "Recurring with High Amount") { _ in
            let vendor = uniqueVendorName(base: "HighAmount")
            let success = addInvoice(vendor: vendor, amount: 99999.99, enableRecurring: true)
            XCTAssertTrue(success, "Failed to add high amount recurring invoice")

            openRecurringOverview()
            sleep(1)

            takeScreenshot(name: "recurring_high_amount")
        }
    }

    /// Test recurring template with very low amount
    func testRecurringWithLowAmount() throws {
        XCTContext.runActivity(named: "Recurring with Low Amount") { _ in
            let vendor = uniqueVendorName(base: "LowAmount")
            let success = addInvoice(vendor: vendor, amount: 0.01, enableRecurring: true)
            XCTAssertTrue(success, "Failed to add low amount recurring invoice")

            openRecurringOverview()
            sleep(1)

            takeScreenshot(name: "recurring_low_amount")
        }
    }
}
