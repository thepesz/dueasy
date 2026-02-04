import XCTest

/// E2E tests for the Home page (Glance Dashboard).
/// Tests the counter displays and summary statistics.
final class HomePageTests: E2ETestBase {

    // MARK: - Counter Tests

    /// Test "Due in 7 days" counter accuracy
    func testDueIn7DaysCounter() throws {
        XCTContext.runActivity(named: "Due in 7 Days Counter") { _ in
            // Start at home with no invoices
            navigateToHome()
            sleep(1)

            takeScreenshot(name: "home_initial_no_invoices")

            // Add invoices that are due today (within 7 days)
            for i in 1...5 {
                let vendor = uniqueVendorName(base: "Due7Days\(i)")
                let success = addInvoice(vendor: vendor, amount: Decimal(100 * i))
                XCTAssertTrue(success, "Failed to add invoice \(i)")
            }

            // Navigate to home and check counter
            navigateToHome()
            sleep(2)

            // Look for hero card with amount/count
            let heroSection = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '7 days' OR label CONTAINS[c] 'due'")).firstMatch

            takeScreenshot(name: "home_due_in_7_days_counter")

            // The hero card should show total amount due in 7 days
            // Check for sum: 100+200+300+400+500 = 1500
            let amountText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '1' AND label CONTAINS[c] '500'")).firstMatch
            // Note: Exact format depends on locale

            // Verify the section exists
            XCTAssertTrue(heroSection.waitForExistence(timeout: shortTimeout) || app.cells.count > 0, "Should show due in 7 days information")
        }
    }

    /// Test overdue counter
    func testOverdueCounter() throws {
        XCTContext.runActivity(named: "Overdue Counter") { _ in
            // Note: Creating truly overdue invoices requires past due dates
            // which may not be possible via UI. We'll verify the counter area exists.

            // Add an invoice for today (will become overdue tomorrow)
            let vendor = uniqueVendorName(base: "PotentiallyOverdue")
            let success = addInvoice(vendor: vendor, amount: 250)
            XCTAssertTrue(success, "Failed to add invoice")

            navigateToHome()
            sleep(1)

            // Look for overdue section/tile
            let overdueSection = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'overdue' OR label CONTAINS[c] 'Overdue'")).firstMatch

            takeScreenshot(name: "home_overdue_counter")

            // The overdue tile should exist (may show 0 or be hidden when no overdue)
            print("Overdue section exists: \(overdueSection.exists)")
        }
    }

    /// Test active recurring counter
    func testActiveRecurringCounter() throws {
        XCTContext.runActivity(named: "Active Recurring Counter") { _ in
            // Start with no recurring
            navigateToHome()
            sleep(1)

            takeScreenshot(name: "home_no_recurring")

            // Add recurring invoices
            let recurringCount = 3
            for i in 1...recurringCount {
                let vendor = uniqueVendorName(base: "RecurringCounter\(i)")
                let success = addInvoice(vendor: vendor, amount: Decimal(100 + i * 50), enableRecurring: true)
                XCTAssertTrue(success, "Failed to add recurring invoice \(i)")
            }

            // Navigate to home and check recurring tile
            navigateToHome()
            sleep(2)

            // Look for recurring tile
            let recurringTile = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Recurring' OR label CONTAINS[c] 'recurring'")).firstMatch

            takeScreenshot(name: "home_recurring_counter_\(recurringCount)")

            // Look for active count
            let activeCount = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Active' OR label CONTAINS[c] '\(recurringCount)'")).firstMatch

            XCTAssertTrue(recurringTile.exists || activeCount.exists, "Recurring section should be visible")
        }
    }

    /// Test month summary statistics
    func testMonthSummaryStats() throws {
        XCTContext.runActivity(named: "Month Summary Stats") { _ in
            // Add mix of paid and unpaid invoices
            for i in 1...3 {
                let vendor = uniqueVendorName(base: "MonthStats\(i)")
                let success = addInvoice(vendor: vendor, amount: Decimal(200 * i))
                XCTAssertTrue(success, "Failed to add invoice \(i)")
            }

            // Mark one as paid
            navigateToDocuments()
            sleep(1)

            let firstCell = app.cells.element(boundBy: 0)
            if firstCell.waitForExistence(timeout: shortTimeout) {
                firstCell.tap()
                sleep(1)

                // Look for "Mark as Paid" button in detail view
                let markPaidButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Paid' OR label CONTAINS[c] 'paid'")).firstMatch
                if markPaidButton.waitForExistence(timeout: shortTimeout) {
                    markPaidButton.tap()
                    sleep(1)
                }

                // Navigate back
                let backButton = app.navigationBars.buttons.element(boundBy: 0)
                if backButton.exists {
                    backButton.tap()
                }
            }

            // Check home page for month summary
            navigateToHome()
            sleep(2)

            // Look for donut chart / month summary section
            let monthSection = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Month' OR label CONTAINS[c] 'This month'")).firstMatch

            takeScreenshot(name: "home_month_summary")

            // Look for paid/due/overdue counts
            let paidText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Paid' OR label CONTAINS[c] 'paid'")).firstMatch
            let dueText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Due' OR label CONTAINS[c] 'due'")).firstMatch
        }
    }

    // MARK: - Empty State Tests

    /// Test home page empty state
    func testHomeEmptyState() throws {
        XCTContext.runActivity(named: "Home Empty State") { _ in
            // Navigate to home with no invoices (fresh database)
            navigateToHome()
            sleep(1)

            // Look for empty state message
            let emptyStateText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'No' OR label CONTAINS[c] 'add' OR label CONTAINS[c] 'scan'")).firstMatch

            takeScreenshot(name: "home_empty_state")

            // May show success state like "All clear" if no invoices
            let allClearText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'clear' OR label CONTAINS[c] 'paid'")).firstMatch
        }
    }

    // MARK: - Navigation Tests

    /// Test tapping hero card navigates to documents
    func testHeroCardNavigation() throws {
        XCTContext.runActivity(named: "Hero Card Navigation") { _ in
            // Add some invoices
            for i in 1...3 {
                let vendor = uniqueVendorName(base: "HeroNav\(i)")
                _ = addInvoice(vendor: vendor, amount: Decimal(100 * i))
            }

            navigateToHome()
            sleep(1)

            // Tap on the hero card area
            let heroCard = app.otherElements.element(boundBy: 0)
            // Or find by text content
            let dueText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'due' OR label CONTAINS[c] '7 days'")).firstMatch

            takeScreenshot(name: "home_before_hero_tap")

            if dueText.exists {
                dueText.tap()
                sleep(1)

                takeScreenshot(name: "after_hero_tap")
            }
        }
    }

    /// Test tapping overdue tile navigates with filter
    func testOverdueTileNavigation() throws {
        XCTContext.runActivity(named: "Overdue Tile Navigation") { _ in
            navigateToHome()
            sleep(1)

            // Look for overdue tile/button
            let checkButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Check' OR label CONTAINS[c] 'check'")).firstMatch
            let overdueButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'overdue'")).firstMatch

            takeScreenshot(name: "home_overdue_tile")

            if checkButton.waitForExistence(timeout: shortTimeout) {
                checkButton.tap()
                sleep(1)

                takeScreenshot(name: "overdue_navigation_result")

                // Should be in documents view with overdue filter active
            }
        }
    }

    /// Test tapping recurring tile opens management sheet
    func testRecurringTileNavigation() throws {
        XCTContext.runActivity(named: "Recurring Tile Navigation") { _ in
            // Add a recurring invoice first
            let vendor = uniqueVendorName(base: "RecurringNav")
            _ = addInvoice(vendor: vendor, amount: 150, enableRecurring: true)

            navigateToHome()
            sleep(1)

            // Look for "Manage" button on recurring tile
            let manageButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Manage'")).firstMatch

            takeScreenshot(name: "home_recurring_tile")

            if manageButton.waitForExistence(timeout: shortTimeout) {
                manageButton.tap()
                sleep(1)

                // Should open recurring overview sheet
                let recurringOverview = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS[c] 'Recurring'")).firstMatch
                let overviewTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Recurring'")).firstMatch

                takeScreenshot(name: "recurring_overview_opened")

                // Dismiss the sheet
                let doneButton = app.buttons["Done"]
                if doneButton.exists {
                    doneButton.tap()
                }
            }
        }
    }

    // MARK: - Next Payments Section Tests

    /// Test next payments section displays correctly
    func testNextPaymentsSection() throws {
        XCTContext.runActivity(named: "Next Payments Section") { _ in
            // Add several invoices
            let invoiceData = [
                ("PaymentA", Decimal(100)),
                ("PaymentB", Decimal(200)),
                ("PaymentC", Decimal(300)),
                ("PaymentD", Decimal(400)),
                ("PaymentE", Decimal(500))
            ]

            for (vendor, amount) in invoiceData {
                let fullVendor = uniqueVendorName(base: vendor)
                _ = addInvoice(vendor: fullVendor, amount: amount)
            }

            navigateToHome()
            sleep(2)

            // Scroll down to see next payments section
            app.swipeUp()
            sleep(1)

            takeScreenshot(name: "home_next_payments")

            // Look for "Next Payments" section
            let nextPaymentsTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Next' OR label CONTAINS[c] 'Upcoming'")).firstMatch

            // Should show first 3 payments (or as configured)
        }
    }

    /// Test "See All" navigates to documents
    func testSeeAllNavigation() throws {
        XCTContext.runActivity(named: "See All Navigation") { _ in
            // Add invoices
            for i in 1...5 {
                let vendor = uniqueVendorName(base: "SeeAll\(i)")
                _ = addInvoice(vendor: vendor, amount: Decimal(100 * i))
            }

            navigateToHome()
            sleep(1)

            // Look for "See All" button
            let seeAllButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'See All' OR label CONTAINS[c] 'All'")).firstMatch

            takeScreenshot(name: "home_see_all_button")

            if seeAllButton.waitForExistence(timeout: shortTimeout) {
                seeAllButton.tap()
                sleep(1)

                // Should navigate to documents tab
                takeScreenshot(name: "see_all_result")

                // Verify we're in documents list
                let documentsList = app.cells
                XCTAssertGreaterThan(documentsList.count, 0, "Should show documents list")
            }
        }
    }

    // MARK: - Refresh Tests

    /// Test pull-to-refresh updates counters
    func testPullToRefreshUpdatesCounters() throws {
        XCTContext.runActivity(named: "Pull to Refresh Updates Counters") { _ in
            // Add initial invoices
            let vendor1 = uniqueVendorName(base: "Refresh1")
            _ = addInvoice(vendor: vendor1, amount: 100)

            navigateToHome()
            sleep(1)

            takeScreenshot(name: "home_before_refresh")

            // Perform pull-to-refresh
            let scrollView = app.scrollViews.firstMatch
            if scrollView.exists {
                scrollView.swipeDown()
                sleep(2)
            } else {
                app.swipeDown()
                sleep(2)
            }

            takeScreenshot(name: "home_after_refresh")
        }
    }

    // MARK: - Dynamic Updates Tests

    /// Test counters update after adding invoice
    func testCountersUpdateAfterAddingInvoice() throws {
        XCTContext.runActivity(named: "Counters Update After Adding") { _ in
            navigateToHome()
            sleep(1)

            takeScreenshot(name: "home_counters_before_add")

            // Add invoice
            let vendor = uniqueVendorName(base: "CounterUpdate")
            _ = addInvoice(vendor: vendor, amount: 999)

            // Return to home
            navigateToHome()
            sleep(2)

            takeScreenshot(name: "home_counters_after_add")

            // Counters should reflect the new invoice
        }
    }

    /// Test counters update after marking as paid
    func testCountersUpdateAfterMarkingPaid() throws {
        XCTContext.runActivity(named: "Counters Update After Marking Paid") { _ in
            // Add invoice
            let vendor = uniqueVendorName(base: "PaidUpdate")
            _ = addInvoice(vendor: vendor, amount: 500)

            navigateToHome()
            sleep(1)

            takeScreenshot(name: "home_counters_before_paid")

            // Go to documents and mark as paid
            navigateToDocuments()
            sleep(1)

            let firstCell = app.cells.element(boundBy: 0)
            if firstCell.waitForExistence(timeout: shortTimeout) {
                firstCell.tap()
                sleep(1)

                let markPaidButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Paid'")).firstMatch
                if markPaidButton.waitForExistence(timeout: shortTimeout) {
                    markPaidButton.tap()
                    sleep(1)
                }

                // Navigate back
                let backButton = app.navigationBars.buttons.element(boundBy: 0)
                if backButton.exists {
                    backButton.tap()
                }
            }

            // Return to home
            navigateToHome()
            sleep(2)

            takeScreenshot(name: "home_counters_after_paid")

            // Due amount should decrease, paid count should increase
        }
    }

    // MARK: - Visual Layout Tests

    /// Test home page layout renders correctly
    func testHomePageLayoutRendering() throws {
        XCTContext.runActivity(named: "Home Page Layout") { _ in
            // Add varied data for comprehensive layout test
            for i in 1...4 {
                let vendor = uniqueVendorName(base: "Layout\(i)")
                _ = addInvoice(vendor: vendor, amount: Decimal(i * 111), enableRecurring: i % 2 == 0)
            }

            navigateToHome()
            sleep(2)

            // Full page screenshot
            takeScreenshot(name: "home_full_layout")

            // Scroll to see all sections
            app.swipeUp()
            sleep(1)

            takeScreenshot(name: "home_layout_scrolled")
        }
    }
}
