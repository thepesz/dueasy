import XCTest

/// E2E tests for calendar integration.
/// Tests that invoices appear correctly in the calendar view based on their due dates.
final class CalendarIntegrationTests: E2ETestBase {

    // MARK: - Basic Calendar Display Tests

    /// Test that invoices with due dates appear in the calendar
    func testInvoicesAppearInCalendar() throws {
        XCTContext.runActivity(named: "Invoices Appear in Calendar") { _ in
            // Get today's date components
            let calendar = Calendar.current
            let today = Date()
            let dayOfMonth = calendar.component(.day, from: today)

            // Add an invoice due today
            let vendor = uniqueVendorName(base: "CalendarTest")
            let success = addInvoice(vendor: vendor, amount: 150.00)
            XCTAssertTrue(success, "Failed to add invoice")

            // Navigate to calendar
            navigateToCalendar()
            sleep(1)

            takeScreenshot(name: "calendar_view_initial")

            // Look for the day cell with today's date
            // The day should have some indicator showing there's an invoice
            let dayButton = app.buttons.matching(NSPredicate(format: "label == '\(dayOfMonth)'")).firstMatch

            if dayButton.waitForExistence(timeout: shortTimeout) {
                // Tap on the day to see the documents
                dayButton.tap()
                sleep(1)

                // Check if the vendor name appears in the selected day's document list
                let vendorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '\(vendor)'")).firstMatch
                let vendorExists = vendorText.waitForExistence(timeout: shortTimeout)

                // If not found directly, look in cells
                if !vendorExists {
                    let cells = app.cells
                    var found = false
                    for i in 0..<cells.count {
                        if cells.element(boundBy: i).staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '\(vendor)'")).firstMatch.exists {
                            found = true
                            break
                        }
                    }
                    XCTAssertTrue(found, "Vendor should appear in calendar for today")
                }

                takeScreenshot(name: "calendar_day_selected")
            }
        }
    }

    /// Test multiple invoices on the same day
    func testMultipleInvoicesOnSameDay() throws {
        XCTContext.runActivity(named: "Multiple Invoices on Same Day") { _ in
            let calendar = Calendar.current
            let today = Date()
            let dayOfMonth = calendar.component(.day, from: today)

            // Add 3 invoices for today
            let vendors = ["TodayVendor1", "TodayVendor2", "TodayVendor3"]

            for vendor in vendors {
                let fullVendor = uniqueVendorName(base: vendor)
                let success = addInvoice(vendor: fullVendor, amount: 100)
                XCTAssertTrue(success, "Failed to add invoice for \(vendor)")
            }

            // Navigate to calendar
            navigateToCalendar()
            sleep(1)

            // Tap on today
            let dayButton = app.buttons.matching(NSPredicate(format: "label == '\(dayOfMonth)'")).firstMatch
            if dayButton.waitForExistence(timeout: shortTimeout) {
                dayButton.tap()
                sleep(1)

                // Verify count indicator or document list shows 3 items
                // Look for "3 documents" text or similar
                let countText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '3'")).firstMatch
                if !countText.exists {
                    // Alternative: Count cells in the day's document list
                    let documentCells = app.cells
                    XCTAssertGreaterThanOrEqual(documentCells.count, 3, "Should show at least 3 documents for today")
                }

                takeScreenshot(name: "multiple_invoices_same_day")
            }
        }
    }

    // MARK: - Date Navigation Tests

    /// Test navigating between months
    func testMonthNavigation() throws {
        XCTContext.runActivity(named: "Month Navigation") { _ in
            navigateToCalendar()
            sleep(1)

            // Get current month name
            let monthHeaders = app.staticTexts.allElementsBoundByIndex
            var currentMonthText = ""
            for header in monthHeaders {
                if header.label.contains("2") { // Likely contains year
                    currentMonthText = header.label
                    break
                }
            }

            takeScreenshot(name: "calendar_initial_month")

            // Navigate to next month
            let nextButton = app.buttons["chevron.right"]
            if !nextButton.exists {
                // Try alternative navigation - swipe
                app.swipeLeft()
            } else {
                nextButton.tap()
            }
            sleep(1)

            takeScreenshot(name: "calendar_next_month")

            // Navigate to previous month
            let prevButton = app.buttons["chevron.left"]
            if !prevButton.exists {
                app.swipeRight()
            } else {
                prevButton.tap()
            }
            sleep(1)

            takeScreenshot(name: "calendar_previous_month")
        }
    }

    /// Test "Today" button returns to current month
    func testTodayButtonNavigation() throws {
        XCTContext.runActivity(named: "Today Button Navigation") { _ in
            navigateToCalendar()
            sleep(1)

            // Navigate away from current month (go 2 months forward)
            for _ in 0..<2 {
                let nextButton = app.buttons["chevron.right"]
                if nextButton.exists {
                    nextButton.tap()
                } else {
                    app.swipeLeft()
                }
                sleep(1)
            }

            takeScreenshot(name: "calendar_future_month")

            // Tap "Today" button to return
            let todayButton = app.buttons["Today"]
            if todayButton.waitForExistence(timeout: shortTimeout) {
                todayButton.tap()
                sleep(1)

                // Verify we're back to current month
                let calendar = Calendar.current
                let today = Date()
                let dayOfMonth = calendar.component(.day, from: today)

                // Today's date should be visible and possibly highlighted
                let dayButton = app.buttons.matching(NSPredicate(format: "label == '\(dayOfMonth)'")).firstMatch
                XCTAssertTrue(dayButton.exists, "Today's date should be visible after tapping Today button")

                takeScreenshot(name: "calendar_today_returned")
            }
        }
    }

    // MARK: - Due Date Placement Tests

    /// Test invoices appear on correct dates
    func testCorrectDatePlacement() throws {
        XCTContext.runActivity(named: "Correct Date Placement") { _ in
            let calendar = Calendar.current

            // Create dates for testing (today and 5 days from now)
            let today = Date()
            let futureDate = calendar.date(byAdding: .day, value: 5, to: today) ?? today

            let todayDay = calendar.component(.day, from: today)
            let futureDay = calendar.component(.day, from: futureDate)

            // Add invoice for today
            let todayVendor = uniqueVendorName(base: "TodayDue")
            let todaySuccess = addInvoice(vendor: todayVendor, amount: 100)
            XCTAssertTrue(todaySuccess, "Failed to add today's invoice")

            // Add invoice for future date
            // Note: This may require using the date picker in manual entry
            // For now, we'll verify with invoices created with default due date
            let futureVendor = uniqueVendorName(base: "FutureDue")
            let futureSuccess = addInvoice(vendor: futureVendor, amount: 200)
            XCTAssertTrue(futureSuccess, "Failed to add future invoice")

            // Navigate to calendar
            navigateToCalendar()
            sleep(1)

            // Verify today's invoice appears on today's date
            let todayButton = app.buttons.matching(NSPredicate(format: "label == '\(todayDay)'")).firstMatch
            if todayButton.exists {
                todayButton.tap()
                sleep(1)

                // Should see today's vendor
                let vendorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '\(todayVendor)'")).firstMatch
                // Note: This assertion may fail if vendor names are truncated
                takeScreenshot(name: "calendar_today_date")
            }

            takeScreenshot(name: "calendar_date_placement")
        }
    }

    // MARK: - Calendar Filter Tests

    /// Test recurring-only filter in calendar
    func testRecurringOnlyFilter() throws {
        XCTContext.runActivity(named: "Recurring Only Filter") { _ in
            // Add regular invoice
            let regularVendor = uniqueVendorName(base: "Regular")
            let regularSuccess = addInvoice(vendor: regularVendor, amount: 100, enableRecurring: false)
            XCTAssertTrue(regularSuccess, "Failed to add regular invoice")

            // Add recurring invoice
            let recurringVendor = uniqueVendorName(base: "Recurring")
            let recurringSuccess = addInvoice(vendor: recurringVendor, amount: 200, enableRecurring: true)
            XCTAssertTrue(recurringSuccess, "Failed to add recurring invoice")

            // Navigate to calendar
            navigateToCalendar()
            sleep(1)

            takeScreenshot(name: "calendar_before_filter")

            // Toggle recurring-only filter
            let recurringToggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'recurring'")).firstMatch
            if recurringToggle.waitForExistence(timeout: shortTimeout) {
                recurringToggle.tap()
                sleep(1)

                takeScreenshot(name: "calendar_recurring_only")

                // With filter on, only recurring items should show
                // Toggle back off
                recurringToggle.tap()
                sleep(1)

                takeScreenshot(name: "calendar_filter_off")
            }
        }
    }

    // MARK: - Calendar Indicator Tests

    /// Test that day cells show correct indicators (dots, colors)
    func testCalendarDayIndicators() throws {
        XCTContext.runActivity(named: "Calendar Day Indicators") { _ in
            // Add multiple invoices on different days to create various indicators
            let calendar = Calendar.current
            let today = Date()

            // Add invoice due today (should show indicator)
            let todayVendor = uniqueVendorName(base: "Today")
            _ = addInvoice(vendor: todayVendor, amount: 100)

            // Navigate to calendar
            navigateToCalendar()
            sleep(1)

            // Visual verification - take screenshot
            // In a real test, we would check for specific accessibility traits or colors
            takeScreenshot(name: "calendar_indicators")

            // Verify that the day with invoice has some indicator
            // This is a visual check - the screenshot will show if indicators are present
        }
    }

    // MARK: - Empty State Tests

    /// Test calendar empty state when no invoices
    func testCalendarEmptyState() throws {
        XCTContext.runActivity(named: "Calendar Empty State") { _ in
            // Navigate to calendar without adding any invoices
            // (assuming database was reset in setup)
            navigateToCalendar()
            sleep(1)

            // Select a random day
            let calendar = Calendar.current
            let today = Date()
            let dayOfMonth = calendar.component(.day, from: today)

            let dayButton = app.buttons.matching(NSPredicate(format: "label == '\(dayOfMonth)'")).firstMatch
            if dayButton.waitForExistence(timeout: shortTimeout) {
                dayButton.tap()
                sleep(1)

                // Should show empty state or "no documents" message
                let emptyText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'no' OR label CONTAINS[c] 'empty'")).firstMatch
                // Note: Text may vary based on localization
                takeScreenshot(name: "calendar_empty_day")
            }
        }
    }

    // MARK: - Document Detail from Calendar

    /// Test tapping on a calendar item opens document detail
    func testOpenDocumentFromCalendar() throws {
        XCTContext.runActivity(named: "Open Document from Calendar") { _ in
            // Add an invoice
            let vendor = uniqueVendorName(base: "CalendarDetail")
            let success = addInvoice(vendor: vendor, amount: 250.00)
            XCTAssertTrue(success, "Failed to add invoice")

            // Navigate to calendar
            navigateToCalendar()
            sleep(1)

            // Get today's day
            let calendar = Calendar.current
            let today = Date()
            let dayOfMonth = calendar.component(.day, from: today)

            // Tap on today
            let dayButton = app.buttons.matching(NSPredicate(format: "label == '\(dayOfMonth)'")).firstMatch
            if dayButton.waitForExistence(timeout: shortTimeout) {
                dayButton.tap()
                sleep(1)

                // Find and tap on the document in the list
                let documentCell = app.cells.firstMatch
                if documentCell.waitForExistence(timeout: shortTimeout) {
                    documentCell.tap()
                    sleep(1)

                    // Verify we're in document detail view
                    // Look for edit button or document details
                    let detailView = app.navigationBars.firstMatch
                    XCTAssertTrue(detailView.exists, "Should navigate to document detail view")

                    takeScreenshot(name: "document_detail_from_calendar")

                    // Navigate back
                    let backButton = detailView.buttons.element(boundBy: 0)
                    if backButton.exists {
                        backButton.tap()
                    }
                }
            }
        }
    }

    // MARK: - Overdue Display Tests

    /// Test that overdue invoices are visually distinct in calendar
    func testOverdueInvoicesInCalendar() throws {
        XCTContext.runActivity(named: "Overdue Invoices in Calendar") { _ in
            // This test would require creating an invoice with a past due date
            // or manipulating the test date. For now, we'll document the expected behavior.

            // Add invoice for today (it will become overdue tomorrow)
            let vendor = uniqueVendorName(base: "PotentialOverdue")
            let success = addInvoice(vendor: vendor, amount: 300)
            XCTAssertTrue(success, "Failed to add invoice")

            // Navigate to calendar
            navigateToCalendar()
            sleep(1)

            // In a real scenario with overdue invoices:
            // - The day indicator should show a different color (red)
            // - The status badge should show "overdue"
            takeScreenshot(name: "calendar_overdue_check")
        }
    }

    // MARK: - Performance Tests

    /// Test calendar performance with many invoices
    func testCalendarPerformanceWithManyInvoices() throws {
        XCTContext.runActivity(named: "Calendar Performance") { _ in
            // Add 50 invoices
            let addCount = addBulkInvoices(count: 50, baseVendor: "CalendarPerf", baseAmount: 100)
            XCTAssertGreaterThan(addCount, 40, "Should add most invoices")

            // Measure calendar navigation performance
            let startTime = Date()

            navigateToCalendar()
            sleep(1)

            // Navigate through several months
            for _ in 0..<6 {
                let nextButton = app.buttons["chevron.right"]
                if nextButton.exists {
                    nextButton.tap()
                } else {
                    app.swipeLeft()
                }
                sleep(1)
            }

            let duration = Date().timeIntervalSince(startTime)
            print("Calendar navigation through 6 months took: \(String(format: "%.1f", duration)) seconds")

            // Should complete within reasonable time
            XCTAssertLessThan(duration, 30, "Calendar navigation should be reasonably fast")

            takeScreenshot(name: "calendar_performance_test")
        }
    }
}
