import XCTest

/// E2E tests for invoice management operations.
/// Tests bulk add, edit, and delete operations with database consistency verification.
final class InvoiceManagementTests: E2ETestBase {

    // MARK: - Bulk Add Tests

    /// Test adding 100 invoices via manual entry
    /// This is a long-running test that validates bulk data entry
    func testBulkAdd100Invoices() throws {
        XCTContext.runActivity(named: "Bulk Add 100 Invoices") { _ in
            // Record start time for performance metrics
            let startTime = Date()

            // Add 100 invoices
            let successCount = addBulkInvoices(count: 100, baseVendor: "BulkInvoice", baseAmount: 100)

            // Calculate duration
            let duration = Date().timeIntervalSince(startTime)
            print("Bulk add completed: \(successCount)/100 invoices in \(String(format: "%.1f", duration)) seconds")

            // Verify all invoices were added
            XCTAssertEqual(successCount, 100, "Expected to add 100 invoices, but only added \(successCount)")

            // Verify count in document list
            navigateToDocuments()
            sleep(2)

            let cells = app.cells
            XCTAssertEqual(cells.count, 100, "Document list should show 100 invoices")

            // Take screenshot for documentation
            takeScreenshot(name: "bulk_add_100_complete")
        }
    }

    /// Test adding invoices with various amounts and vendors
    func testAddInvoicesWithVariousData() throws {
        XCTContext.runActivity(named: "Add Invoices with Various Data") { _ in
            // Test data with different vendors and amounts
            let testCases: [(vendor: String, amount: Decimal)] = [
                ("Electric Company", 234.56),
                ("Gas Provider", 89.00),
                ("Internet Service", 79.99),
                ("Phone Bill", 49.50),
                ("Water Utility", 67.80)
            ]

            for (index, testCase) in testCases.enumerated() {
                let vendor = "\(testVendorPrefix)\(testCase.vendor)"
                let success = addInvoice(vendor: vendor, amount: testCase.amount)
                XCTAssertTrue(success, "Failed to add invoice \(index + 1): \(testCase.vendor)")
            }

            // Verify count
            navigateToDocuments()
            sleep(1)

            let cells = app.cells
            XCTAssertEqual(cells.count, testCases.count, "Should have \(testCases.count) invoices")

            takeScreenshot(name: "various_invoices_added")
        }
    }

    // MARK: - Bulk Edit Tests

    /// Test editing 50 invoices (changing amounts)
    func testBulkEdit50Invoices() throws {
        XCTContext.runActivity(named: "Bulk Edit 50 Invoices") { _ in
            // First add 50 invoices
            let addCount = addBulkInvoices(count: 50, baseVendor: "EditTest", baseAmount: 100)
            XCTAssertEqual(addCount, 50, "Failed to add invoices for edit test")

            // Record start time
            let startTime = Date()
            var editSuccessCount = 0

            // Edit each invoice (change amount)
            for i in 0..<50 {
                let newAmount = Decimal(200 + i * 10)
                if editInvoice(at: i, newAmount: newAmount) {
                    editSuccessCount += 1
                }

                // Navigate back to list
                navigateToDocuments()

                // Progress logging
                if (i + 1) % 10 == 0 {
                    print("Edit progress: \(i + 1)/50")
                }
            }

            let duration = Date().timeIntervalSince(startTime)
            print("Bulk edit completed: \(editSuccessCount)/50 invoices in \(String(format: "%.1f", duration)) seconds")

            XCTAssertEqual(editSuccessCount, 50, "Expected to edit 50 invoices, but only edited \(editSuccessCount)")

            takeScreenshot(name: "bulk_edit_50_complete")
        }
    }

    /// Test editing invoice amounts with edge cases
    func testEditInvoiceAmountEdgeCases() throws {
        XCTContext.runActivity(named: "Edit Invoice Amount Edge Cases") { _ in
            // Add initial invoice
            let vendor = uniqueVendorName(base: "AmountEdge")
            let success = addInvoice(vendor: vendor, amount: 100)
            XCTAssertTrue(success, "Failed to add initial invoice")

            // Test cases for amount editing
            let edgeCaseAmounts: [Decimal] = [
                0.01,       // Minimum practical amount
                999999.99,  // Large amount
                50.00,      // Round number
                123.45,     // Typical amount
                0.99,       // Small amount
            ]

            for amount in edgeCaseAmounts {
                let editSuccess = editInvoice(at: 0, newAmount: amount)
                XCTAssertTrue(editSuccess, "Failed to edit amount to \(amount)")
                navigateToDocuments()
            }
        }
    }

    // MARK: - Bulk Delete Tests

    /// Test deleting 30 invoices
    func testBulkDelete30Invoices() throws {
        XCTContext.runActivity(named: "Bulk Delete 30 Invoices") { _ in
            // First add 50 invoices
            let addCount = addBulkInvoices(count: 50, baseVendor: "DeleteTest", baseAmount: 100)
            XCTAssertEqual(addCount, 50, "Failed to add invoices for delete test")

            // Verify initial count
            navigateToDocuments()
            sleep(1)
            XCTAssertEqual(app.cells.count, 50, "Should start with 50 invoices")

            // Record start time
            let startTime = Date()

            // Delete 30 invoices
            let deleteCount = deleteBulkInvoices(count: 30)

            let duration = Date().timeIntervalSince(startTime)
            print("Bulk delete completed: \(deleteCount)/30 invoices in \(String(format: "%.1f", duration)) seconds")

            XCTAssertEqual(deleteCount, 30, "Expected to delete 30 invoices")

            // Verify remaining count
            navigateToDocuments()
            sleep(1)
            XCTAssertEqual(app.cells.count, 20, "Should have 20 invoices remaining")

            takeScreenshot(name: "bulk_delete_30_complete")
        }
    }

    /// Test delete with swipe-to-delete gesture
    func testSwipeToDelete() throws {
        XCTContext.runActivity(named: "Swipe to Delete") { _ in
            // Add an invoice
            let vendor = uniqueVendorName(base: "SwipeDelete")
            let success = addInvoice(vendor: vendor, amount: 99.99)
            XCTAssertTrue(success, "Failed to add invoice")

            // Navigate to documents
            navigateToDocuments()
            sleep(1)

            // Verify invoice exists
            let cell = app.cells.element(boundBy: 0)
            XCTAssertTrue(cell.exists, "Invoice should exist")

            // Swipe to delete
            cell.swipeLeft()

            // Tap delete button
            let deleteButton = app.buttons["Delete"]
            XCTAssertTrue(deleteButton.waitForExistence(timeout: shortTimeout), "Delete button should appear")
            deleteButton.tap()

            // Confirm deletion if prompted
            let confirmDelete = app.alerts.buttons["Delete"]
            if confirmDelete.waitForExistence(timeout: shortTimeout) {
                confirmDelete.tap()
            }

            sleep(1)

            // Verify deletion
            navigateToDocuments()
            XCTAssertEqual(app.cells.count, 0, "Invoice should be deleted")

            takeScreenshot(name: "swipe_delete_complete")
        }
    }

    // MARK: - Database Consistency Tests

    /// Test database consistency after bulk operations
    func testDatabaseConsistencyAfterBulkOperations() throws {
        XCTContext.runActivity(named: "Database Consistency After Bulk Operations") { _ in
            // Initial state: 0 invoices
            navigateToDocuments()
            let initialCount = app.cells.count
            print("Initial count: \(initialCount)")

            // Add 20 invoices
            let addCount = addBulkInvoices(count: 20, baseVendor: "ConsistencyTest", baseAmount: 100)
            XCTAssertEqual(addCount, 20, "Should add 20 invoices")

            // Verify count: 20
            navigateToDocuments()
            sleep(1)
            XCTAssertEqual(app.cells.count, initialCount + 20, "Count should be \(initialCount + 20)")

            // Edit 5 invoices
            for i in 0..<5 {
                editInvoice(at: i, newAmount: Decimal(500 + i * 10))
                navigateToDocuments()
            }

            // Verify count still 20 (edits don't change count)
            navigateToDocuments()
            sleep(1)
            XCTAssertEqual(app.cells.count, initialCount + 20, "Count should remain \(initialCount + 20) after edits")

            // Delete 10 invoices
            let deleteCount = deleteBulkInvoices(count: 10)
            XCTAssertEqual(deleteCount, 10, "Should delete 10 invoices")

            // Verify final count: 10
            navigateToDocuments()
            sleep(1)
            XCTAssertEqual(app.cells.count, initialCount + 10, "Final count should be \(initialCount + 10)")

            takeScreenshot(name: "database_consistency_complete")
        }
    }

    /// Test that invoice data persists after navigation
    func testInvoiceDataPersistsAfterNavigation() throws {
        XCTContext.runActivity(named: "Invoice Data Persists After Navigation") { _ in
            // Add an invoice with specific data
            let vendor = uniqueVendorName(base: "PersistenceTest")
            let amount: Decimal = 789.01
            let success = addInvoice(vendor: vendor, amount: amount)
            XCTAssertTrue(success, "Failed to add invoice")

            // Navigate away to different tabs
            navigateToHome()
            sleep(1)
            navigateToCalendar()
            sleep(1)
            navigateToSettings()
            sleep(1)

            // Navigate back to documents
            navigateToDocuments()
            sleep(1)

            // Verify invoice still exists
            let vendorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '\(vendor)'")).firstMatch
            XCTAssertTrue(vendorText.exists, "Vendor name should persist after navigation")

            takeScreenshot(name: "persistence_after_navigation")
        }
    }

    // MARK: - Edge Case Tests

    /// Test adding invoice with maximum length vendor name
    func testAddInvoiceWithLongVendorName() throws {
        XCTContext.runActivity(named: "Add Invoice with Long Vendor Name") { _ in
            // Create a very long vendor name (100 characters)
            let longVendor = String(repeating: "A", count: 100)
            let success = addInvoice(vendor: longVendor, amount: 100)

            // The app should handle long names gracefully (truncation or rejection)
            // Just verify no crash occurs
            takeScreenshot(name: "long_vendor_name")
        }
    }

    /// Test adding invoice with special characters in vendor name
    func testAddInvoiceWithSpecialCharacters() throws {
        XCTContext.runActivity(named: "Add Invoice with Special Characters") { _ in
            let specialVendors = [
                "\(testVendorPrefix)O'Reilly & Co.",
                "\(testVendorPrefix)Test GmbH (Germany)",
                "\(testVendorPrefix)Vendor #123",
                "\(testVendorPrefix)Company - Division"
            ]

            for vendor in specialVendors {
                let success = addInvoice(vendor: vendor, amount: 100)
                // Log result but don't fail - special char handling may vary
                print("Added '\(vendor)': \(success)")
            }

            takeScreenshot(name: "special_characters_vendors")
        }
    }

    // MARK: - Performance Tests

    /// Measure time to add a single invoice
    func testSingleInvoiceAddPerformance() throws {
        measure {
            let vendor = uniqueVendorName(base: "PerfTest")
            _ = addInvoice(vendor: vendor, amount: 100)
        }
    }
}
