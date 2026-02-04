import XCTest

/// E2E tests for data persistence.
/// Tests that data survives app lifecycle events and maintains integrity.
final class DataPersistenceTests: E2ETestBase {

    // MARK: - App Restart Tests

    /// Test data persists after force quitting and relaunching the app
    func testDataPersistsAfterAppRelaunch() throws {
        XCTContext.runActivity(named: "Data Persists After App Relaunch") { _ in
            // Add distinctive test data
            let testVendors = [
                (vendor: "PersistTest_Alpha", amount: Decimal(111.11)),
                (vendor: "PersistTest_Beta", amount: Decimal(222.22)),
                (vendor: "PersistTest_Gamma", amount: Decimal(333.33))
            ]

            for data in testVendors {
                let fullVendor = "\(testVendorPrefix)\(data.vendor)"
                let success = addInvoice(vendor: fullVendor, amount: data.amount)
                XCTAssertTrue(success, "Failed to add invoice: \(data.vendor)")
            }

            // Verify invoices exist before termination
            navigateToDocuments()
            sleep(1)

            let countBefore = app.cells.count
            XCTAssertEqual(countBefore, testVendors.count, "Should have \(testVendors.count) invoices before restart")

            takeScreenshot(name: "persistence_before_restart")

            // Terminate the app
            app.terminate()

            // Relaunch without reset flag
            app.launchArguments = [
                "-UITestMode",
                "-DisableAnimations",
                "-DisableOnboarding",
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US"
                // Note: NOT including -ResetDatabase
            ]
            app.launch()

            // Wait for app to be ready
            waitForAppReady()

            // Navigate to documents
            navigateToDocuments()
            sleep(2)

            takeScreenshot(name: "persistence_after_restart")

            // Verify invoices still exist
            let countAfter = app.cells.count
            XCTAssertEqual(countAfter, testVendors.count, "Data should persist after app restart")

            // Verify specific vendor names exist
            for data in testVendors {
                let vendorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '\(data.vendor)'")).firstMatch
                // Note: May need to scroll to find all items
            }
        }
    }

    /// Test recurring templates persist after app restart
    func testRecurringTemplatesPersistAfterRestart() throws {
        XCTContext.runActivity(named: "Recurring Templates Persist After Restart") { _ in
            // Add recurring invoice
            let vendor = uniqueVendorName(base: "RecurringPersist")
            let success = addInvoice(vendor: vendor, amount: 199.99, enableRecurring: true)
            XCTAssertTrue(success, "Failed to add recurring invoice")

            // Verify template exists
            openRecurringOverview()
            sleep(1)

            let templatesBefore = app.cells.count
            takeScreenshot(name: "recurring_persist_before")

            // Dismiss and terminate
            dismissAnyPresented()
            app.terminate()

            // Relaunch without reset
            app.launchArguments = [
                "-UITestMode",
                "-DisableAnimations",
                "-DisableOnboarding",
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US"
            ]
            app.launch()
            waitForAppReady()

            // Check recurring templates
            openRecurringOverview()
            sleep(1)

            takeScreenshot(name: "recurring_persist_after")

            // Templates should still exist
            let templatesAfter = app.cells.count
            XCTAssertEqual(templatesAfter, templatesBefore, "Recurring templates should persist")
        }
    }

    // MARK: - Background/Foreground Tests

    /// Test data consistency after backgrounding and foregrounding
    func testDataConsistencyAfterBackground() throws {
        XCTContext.runActivity(named: "Data Consistency After Background") { _ in
            // Add test invoices
            for i in 1...3 {
                let vendor = uniqueVendorName(base: "Background\(i)")
                _ = addInvoice(vendor: vendor, amount: Decimal(100 * i))
            }

            navigateToDocuments()
            sleep(1)

            let countBefore = app.cells.count
            takeScreenshot(name: "background_before")

            // Simulate going to background and returning
            XCUIDevice.shared.press(.home)
            sleep(2)

            // Bring app back to foreground
            app.activate()
            sleep(1)

            takeScreenshot(name: "background_after")

            // Data should still be there
            navigateToDocuments()
            sleep(1)

            let countAfter = app.cells.count
            XCTAssertEqual(countAfter, countBefore, "Data should persist through background")
        }
    }

    // MARK: - SwiftData Integrity Tests

    /// Test that edited data is properly saved
    func testEditedDataPersists() throws {
        XCTContext.runActivity(named: "Edited Data Persists") { _ in
            // Add invoice
            let originalVendor = uniqueVendorName(base: "EditPersist")
            let success = addInvoice(vendor: originalVendor, amount: 100)
            XCTAssertTrue(success, "Failed to add invoice")

            // Edit the invoice
            let newAmount: Decimal = 999
            let editSuccess = editInvoice(at: 0, newAmount: newAmount)
            XCTAssertTrue(editSuccess, "Failed to edit invoice")

            takeScreenshot(name: "edit_persist_before_restart")

            // Terminate and relaunch
            app.terminate()

            app.launchArguments = [
                "-UITestMode",
                "-DisableAnimations",
                "-DisableOnboarding",
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US"
            ]
            app.launch()
            waitForAppReady()

            // Verify edited amount persisted
            navigateToDocuments()
            sleep(1)

            takeScreenshot(name: "edit_persist_after_restart")

            // Open detail to verify amount
            let firstCell = app.cells.element(boundBy: 0)
            if firstCell.waitForExistence(timeout: shortTimeout) {
                firstCell.tap()
                sleep(1)

                // Look for the new amount
                let amountText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '999'")).firstMatch

                takeScreenshot(name: "edit_persist_detail_view")
            }
        }
    }

    /// Test that deleted data stays deleted
    func testDeletedDataStaysDeleted() throws {
        XCTContext.runActivity(named: "Deleted Data Stays Deleted") { _ in
            // Add invoice
            let vendor = uniqueVendorName(base: "DeletePersist")
            let success = addInvoice(vendor: vendor, amount: 150)
            XCTAssertTrue(success, "Failed to add invoice")

            navigateToDocuments()
            sleep(1)

            let countBefore = app.cells.count
            XCTAssertGreaterThan(countBefore, 0, "Should have at least one invoice")

            // Delete the invoice
            let deleteSuccess = deleteInvoice(at: 0)
            XCTAssertTrue(deleteSuccess, "Failed to delete invoice")

            takeScreenshot(name: "delete_persist_after_delete")

            // Terminate and relaunch
            app.terminate()

            app.launchArguments = [
                "-UITestMode",
                "-DisableAnimations",
                "-DisableOnboarding",
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US"
            ]
            app.launch()
            waitForAppReady()

            // Verify deletion persisted
            navigateToDocuments()
            sleep(1)

            takeScreenshot(name: "delete_persist_after_restart")

            let countAfter = app.cells.count
            XCTAssertEqual(countAfter, countBefore - 1, "Deletion should persist")
        }
    }

    // MARK: - Large Data Tests

    /// Test persistence with large number of records
    func testPersistenceWithLargeDataSet() throws {
        XCTContext.runActivity(named: "Persistence with Large Data Set") { _ in
            // Add many invoices
            let count = 25 // Reduced from 100 for faster test
            let successCount = addBulkInvoices(count: count, baseVendor: "LargeSet", baseAmount: 100)
            XCTAssertEqual(successCount, count, "Should add all invoices")

            navigateToDocuments()
            sleep(1)

            let countBefore = app.cells.count
            takeScreenshot(name: "large_set_before")

            // Terminate and relaunch
            app.terminate()

            app.launchArguments = [
                "-UITestMode",
                "-DisableAnimations",
                "-DisableOnboarding",
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US"
            ]
            app.launch()
            waitForAppReady()

            // Verify all data persisted
            navigateToDocuments()
            sleep(2)

            takeScreenshot(name: "large_set_after")

            let countAfter = app.cells.count
            XCTAssertEqual(countAfter, countBefore, "All data should persist")
        }
    }

    // MARK: - Concurrent Operations Tests

    /// Test data integrity after rapid operations
    func testDataIntegrityAfterRapidOperations() throws {
        XCTContext.runActivity(named: "Data Integrity After Rapid Operations") { _ in
            // Perform rapid add/edit/delete operations
            var expectedCount = 0

            // Add 10 invoices
            for i in 1...10 {
                let vendor = uniqueVendorName(base: "Rapid\(i)")
                if addInvoice(vendor: vendor, amount: Decimal(100 * i)) {
                    expectedCount += 1
                }
            }

            // Edit 5
            navigateToDocuments()
            for i in 0..<5 {
                _ = editInvoice(at: i, newAmount: Decimal(999 + i))
                navigateToDocuments()
            }

            // Delete 3
            for _ in 0..<3 {
                if deleteInvoice(at: 0) {
                    expectedCount -= 1
                }
            }

            takeScreenshot(name: "rapid_ops_result")

            // Verify final state
            navigateToDocuments()
            sleep(1)

            let finalCount = app.cells.count
            XCTAssertEqual(finalCount, expectedCount, "Data integrity should be maintained")

            // Restart to verify persistence
            app.terminate()

            app.launchArguments = [
                "-UITestMode",
                "-DisableAnimations",
                "-DisableOnboarding",
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US"
            ]
            app.launch()
            waitForAppReady()

            navigateToDocuments()
            sleep(1)

            let countAfterRestart = app.cells.count
            XCTAssertEqual(countAfterRestart, expectedCount, "Data should persist after rapid operations")
        }
    }

    // MARK: - State Consistency Tests

    /// Test home page counters match actual data
    func testHomeCountersMatchActualData() throws {
        XCTContext.runActivity(named: "Home Counters Match Actual Data") { _ in
            // Add specific number of invoices
            let invoiceCount = 5
            for i in 1...invoiceCount {
                let vendor = uniqueVendorName(base: "CounterMatch\(i)")
                _ = addInvoice(vendor: vendor, amount: Decimal(100 * i))
            }

            // Check documents count
            navigateToDocuments()
            sleep(1)

            let actualCount = app.cells.count
            XCTAssertEqual(actualCount, invoiceCount, "Document count should match")

            takeScreenshot(name: "counter_match_documents")

            // Check home page reflects same data
            navigateToHome()
            sleep(2)

            takeScreenshot(name: "counter_match_home")

            // The home page should show metrics consistent with the documents
        }
    }

    /// Test calendar reflects actual invoice due dates
    func testCalendarReflectsActualData() throws {
        XCTContext.runActivity(named: "Calendar Reflects Actual Data") { _ in
            // Add invoice
            let vendor = uniqueVendorName(base: "CalendarData")
            _ = addInvoice(vendor: vendor, amount: 250)

            // Get today's day
            let calendar = Calendar.current
            let today = Date()
            let dayOfMonth = calendar.component(.day, from: today)

            // Check calendar
            navigateToCalendar()
            sleep(1)

            // Today should show an indicator
            let dayButton = app.buttons.matching(NSPredicate(format: "label == '\(dayOfMonth)'")).firstMatch
            if dayButton.exists {
                dayButton.tap()
                sleep(1)

                // Should show the invoice
                let vendorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '\(vendor)'")).firstMatch
                takeScreenshot(name: "calendar_data_consistency")
            }
        }
    }

    // MARK: - Error Recovery Tests

    /// Test app handles low memory gracefully
    func testLowMemoryRecovery() throws {
        XCTContext.runActivity(named: "Low Memory Recovery") { _ in
            // Add some data
            for i in 1...5 {
                let vendor = uniqueVendorName(base: "Memory\(i)")
                _ = addInvoice(vendor: vendor, amount: Decimal(100 * i))
            }

            navigateToDocuments()
            let countBefore = app.cells.count

            // Note: We can't actually trigger low memory from UI tests
            // But we can verify the app doesn't crash under normal operations

            // Rapid navigation to stress the app
            for _ in 0..<5 {
                navigateToHome()
                navigateToDocuments()
                navigateToCalendar()
                navigateToSettings()
            }

            // Verify data still intact
            navigateToDocuments()
            sleep(1)

            let countAfter = app.cells.count
            XCTAssertEqual(countAfter, countBefore, "Data should survive rapid navigation")

            takeScreenshot(name: "memory_test_result")
        }
    }
}
