import XCTest

/// Base class for all E2E UI tests.
/// Provides common helper methods, app launch configuration, and test data management.
///
/// ## Test Architecture
/// - All tests use deterministic test data with unique identifiers
/// - Database is cleared before each test via launch arguments
/// - Tests use accessibility identifiers for element lookup
/// - Performance-sensitive operations use appropriate timeouts
///
/// ## Launch Arguments
/// - `-UITestMode`: Enables test mode in the app
/// - `-ResetDatabase`: Clears all data before test starts
/// - `-DisableAnimations`: Speeds up test execution
/// - `-MockDateProvider`: Uses deterministic dates for testing
class E2ETestBase: XCTestCase {

    // MARK: - Properties

    var app: XCUIApplication!

    /// Standard timeout for element existence checks
    let standardTimeout: TimeInterval = 10.0

    /// Extended timeout for operations that may take longer (bulk operations, etc.)
    let extendedTimeout: TimeInterval = 30.0

    /// Short timeout for elements that should appear quickly
    let shortTimeout: TimeInterval = 3.0

    /// Test vendor name prefix for unique identification
    let testVendorPrefix = "E2ETest_"

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Continue after failures to see all issues in a test run
        continueAfterFailure = false

        // Initialize the app
        app = XCUIApplication()

        // Configure launch arguments for test mode
        configureLaunchArguments()

        // Launch the app
        app.launch()

        // Wait for app to be ready
        waitForAppReady()
    }

    override func tearDownWithError() throws {
        // Take screenshot on failure for debugging
        if testRun?.failureCount ?? 0 > 0 {
            takeScreenshot(name: "failure_\(name)")
        }

        app = nil
        try super.tearDownWithError()
    }

    // MARK: - Launch Configuration

    /// Configures launch arguments for test mode
    func configureLaunchArguments() {
        app.launchArguments = [
            "-UITestMode",
            "-ResetDatabase",
            "-DisableAnimations",
            "-DisableOnboarding",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]

        // Environment variables for test configuration
        app.launchEnvironment = [
            "UITEST_MODE": "1",
            "ANIMATIONS_DISABLED": "1"
        ]
    }

    /// Waits for the app to be fully loaded and ready for interaction
    func waitForAppReady() {
        // Wait for the main tab bar to appear, indicating app is ready
        let tabBar = app.tabBars.firstMatch
        let exists = tabBar.waitForExistence(timeout: standardTimeout)
        XCTAssertTrue(exists, "App failed to load - tab bar not found")
    }

    // MARK: - Navigation Helpers

    /// Navigates to the Home tab
    func navigateToHome() {
        XCTContext.runActivity(named: "Navigate to Home tab") { _ in
            let homeTab = app.tabBars.buttons["Home"]
            if homeTab.exists {
                homeTab.tap()
                sleep(1)
            }
        }
    }

    /// Navigates to the Documents tab
    func navigateToDocuments() {
        XCTContext.runActivity(named: "Navigate to Documents tab") { _ in
            let documentsTab = app.tabBars.buttons["Documents"]
            if documentsTab.exists {
                documentsTab.tap()
                sleep(1)
            }
        }
    }

    /// Navigates to the Calendar tab
    func navigateToCalendar() {
        XCTContext.runActivity(named: "Navigate to Calendar tab") { _ in
            let calendarTab = app.tabBars.buttons["Calendar"]
            if calendarTab.exists {
                calendarTab.tap()
                sleep(1)
            }
        }
    }

    /// Navigates to the Settings tab
    func navigateToSettings() {
        XCTContext.runActivity(named: "Navigate to Settings tab") { _ in
            let settingsTab = app.tabBars.buttons["Settings"]
            if settingsTab.exists {
                settingsTab.tap()
                sleep(1)
            }
        }
    }

    /// Opens the Add Document sheet
    func openAddDocumentSheet() {
        XCTContext.runActivity(named: "Open Add Document sheet") { _ in
            let addTab = app.tabBars.buttons["Add"]
            if addTab.exists {
                addTab.tap()
                // Wait for sheet to appear
                let sheet = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.navigationBars["Add Document"].firstMatch
                _ = sheet.waitForExistence(timeout: shortTimeout)
            }
        }
    }

    /// Opens the Recurring Overview sheet from Home view
    func openRecurringOverview() {
        XCTContext.runActivity(named: "Open Recurring Overview") { _ in
            navigateToHome()
            // Find and tap the "Manage" button on the recurring tile
            let manageButton = app.buttons["Manage"]
            if manageButton.waitForExistence(timeout: shortTimeout) {
                manageButton.tap()
                sleep(1)
            }
        }
    }

    // MARK: - Invoice Management Helpers

    /// Adds an invoice via manual entry
    /// - Parameters:
    ///   - vendor: Vendor name
    ///   - amount: Amount value
    ///   - dueDate: Due date (nil for today)
    ///   - enableRecurring: Whether to enable recurring payment
    /// - Returns: Whether the operation succeeded
    @discardableResult
    func addInvoice(
        vendor: String,
        amount: Decimal,
        dueDate: Date? = nil,
        currency: String = "PLN",
        enableRecurring: Bool = false
    ) -> Bool {
        return XCTContext.runActivity(named: "Add invoice: \(vendor) - \(amount) \(currency)") { _ -> Bool in
            // Open add document sheet
            openAddDocumentSheet()

            // Select manual entry option
            let manualEntryButton = app.buttons["Manual Entry"]
            if manualEntryButton.waitForExistence(timeout: shortTimeout) {
                manualEntryButton.tap()
            } else {
                // Try alternative identifier
                let manualEntryCell = app.cells.containing(.staticText, identifier: "Manual Entry").firstMatch
                if manualEntryCell.waitForExistence(timeout: shortTimeout) {
                    manualEntryCell.tap()
                } else {
                    XCTFail("Could not find Manual Entry option")
                    return false
                }
            }

            sleep(1)

            // Fill in vendor name
            let vendorField = app.textFields["Vendor Name"] .firstMatch
            if vendorField.waitForExistence(timeout: shortTimeout) {
                vendorField.tap()
                vendorField.typeText(vendor)
            } else {
                // Try finding by placeholder
                let vendorTextField = app.textFields.element(boundBy: 0)
                if vendorTextField.exists {
                    vendorTextField.tap()
                    vendorTextField.typeText(vendor)
                }
            }

            // Dismiss keyboard and scroll to amount field
            app.swipeUp()

            // Fill in amount
            let amountField = app.textFields.matching(identifier: "Amount").firstMatch
            if amountField.waitForExistence(timeout: shortTimeout) {
                amountField.tap()
                amountField.typeText("\(amount)")
            } else {
                // Try finding by position (usually second text field)
                let amountTextField = app.textFields.element(boundBy: 1)
                if amountTextField.exists {
                    amountTextField.tap()
                    amountTextField.typeText("\(amount)")
                }
            }

            // Scroll to find save button
            app.swipeUp()

            // Enable recurring if requested
            if enableRecurring {
                let recurringToggle = app.switches.matching(identifier: "Recurring Payment").firstMatch
                if recurringToggle.waitForExistence(timeout: shortTimeout) {
                    if recurringToggle.value as? String == "0" {
                        recurringToggle.tap()
                    }
                }
            }

            // Tap save button
            let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Save'")).firstMatch
            if saveButton.waitForExistence(timeout: shortTimeout) {
                saveButton.tap()
                sleep(2)
                return true
            }

            return false
        }
    }

    /// Adds multiple invoices in bulk
    /// - Parameters:
    ///   - count: Number of invoices to add
    ///   - baseVendor: Base vendor name (will be suffixed with index)
    ///   - baseAmount: Base amount (will be incremented)
    /// - Returns: Number of successfully added invoices
    func addBulkInvoices(count: Int, baseVendor: String = "BulkVendor", baseAmount: Decimal = 100) -> Int {
        return XCTContext.runActivity(named: "Add \(count) bulk invoices") { _ -> Int in
            var successCount = 0

            for i in 1...count {
                let vendor = "\(testVendorPrefix)\(baseVendor)_\(i)"
                let amount = baseAmount + Decimal(i)

                if addInvoice(vendor: vendor, amount: amount) {
                    successCount += 1
                }

                // Log progress every 10 invoices
                if i % 10 == 0 {
                    print("Progress: Added \(i)/\(count) invoices")
                }
            }

            return successCount
        }
    }

    /// Edits an invoice at the specified index in the document list
    /// - Parameters:
    ///   - index: Index of the invoice in the list
    ///   - newAmount: New amount to set (optional)
    ///   - newVendor: New vendor name (optional)
    /// - Returns: Whether the edit succeeded
    @discardableResult
    func editInvoice(at index: Int, newAmount: Decimal? = nil, newVendor: String? = nil) -> Bool {
        return XCTContext.runActivity(named: "Edit invoice at index \(index)") { _ -> Bool in
            navigateToDocuments()

            // Find and tap the invoice cell
            let cells = app.cells
            guard cells.count > index else {
                XCTFail("Invoice at index \(index) not found")
                return false
            }

            let cell = cells.element(boundBy: index)
            if cell.waitForExistence(timeout: shortTimeout) {
                cell.tap()
            } else {
                return false
            }

            sleep(1)

            // Wait for detail view
            let editButton = app.buttons["Edit"]
            if editButton.waitForExistence(timeout: shortTimeout) {
                editButton.tap()
            }

            sleep(1)

            // Update amount if provided
            if let newAmount = newAmount {
                let amountField = app.textFields.matching(identifier: "Amount").firstMatch
                if amountField.waitForExistence(timeout: shortTimeout) {
                    amountField.tap()
                    amountField.clearAndTypeText("\(newAmount)")
                }
            }

            // Update vendor if provided
            if let newVendor = newVendor {
                let vendorField = app.textFields.matching(identifier: "Vendor Name").firstMatch
                if vendorField.waitForExistence(timeout: shortTimeout) {
                    vendorField.tap()
                    vendorField.clearAndTypeText(newVendor)
                }
            }

            // Save changes
            let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Save'")).firstMatch
            if saveButton.waitForExistence(timeout: shortTimeout) {
                saveButton.tap()
                sleep(1)
                return true
            }

            return false
        }
    }

    /// Deletes an invoice at the specified index using swipe-to-delete
    /// - Parameter index: Index of the invoice in the list
    /// - Returns: Whether the deletion succeeded
    @discardableResult
    func deleteInvoice(at index: Int) -> Bool {
        return XCTContext.runActivity(named: "Delete invoice at index \(index)") { _ -> Bool in
            navigateToDocuments()

            let cells = app.cells
            guard cells.count > index else {
                return false
            }

            let cell = cells.element(boundBy: index)
            if cell.waitForExistence(timeout: shortTimeout) {
                // Swipe to delete
                cell.swipeLeft()

                // Tap delete button
                let deleteButton = app.buttons["Delete"]
                if deleteButton.waitForExistence(timeout: shortTimeout) {
                    deleteButton.tap()

                    // Confirm deletion if alert appears
                    let confirmButton = app.alerts.buttons["Delete"]
                    if confirmButton.waitForExistence(timeout: shortTimeout) {
                        confirmButton.tap()
                    }

                    sleep(1)
                    return true
                }
            }

            return false
        }
    }

    /// Deletes multiple invoices
    /// - Parameter count: Number of invoices to delete (from the top of the list)
    /// - Returns: Number of successfully deleted invoices
    func deleteBulkInvoices(count: Int) -> Int {
        return XCTContext.runActivity(named: "Delete \(count) invoices") { _ -> Int in
            var deletedCount = 0

            for _ in 0..<count {
                // Always delete from index 0 since list shifts after each deletion
                if deleteInvoice(at: 0) {
                    deletedCount += 1
                }
            }

            return deletedCount
        }
    }

    // MARK: - Recurring Payment Helpers

    /// Enables recurring payment for the last added invoice
    /// - Returns: Whether the operation succeeded
    @discardableResult
    func enableRecurringForLastInvoice() -> Bool {
        return XCTContext.runActivity(named: "Enable recurring for last invoice") { _ -> Bool in
            navigateToDocuments()

            // Tap the first (most recent) invoice
            let firstCell = app.cells.element(boundBy: 0)
            if firstCell.waitForExistence(timeout: shortTimeout) {
                firstCell.tap()
            } else {
                return false
            }

            sleep(1)

            // Look for recurring toggle in detail view
            let recurringToggle = app.switches.firstMatch
            if recurringToggle.waitForExistence(timeout: shortTimeout) {
                if recurringToggle.value as? String == "0" {
                    recurringToggle.tap()
                    sleep(1)

                    // Save if needed
                    let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Save'")).firstMatch
                    if saveButton.exists {
                        saveButton.tap()
                    }

                    return true
                }
            }

            // Navigate back
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            if backButton.exists {
                backButton.tap()
            }

            return false
        }
    }

    // MARK: - Verification Helpers

    /// Verifies the total count of invoices in the document list
    /// - Parameter expected: Expected count
    /// - Returns: Whether the count matches
    @discardableResult
    func verifyInvoiceCount(expected: Int) -> Bool {
        return XCTContext.runActivity(named: "Verify invoice count: \(expected)") { _ -> Bool in
            navigateToDocuments()
            sleep(1)

            let cells = app.cells
            let actualCount = cells.count

            XCTAssertEqual(actualCount, expected, "Invoice count mismatch: expected \(expected), got \(actualCount)")
            return actualCount == expected
        }
    }

    /// Verifies that the fuzzy match dialog is shown (or not shown)
    /// - Parameter shown: Whether the dialog should be shown
    /// - Returns: Whether the verification succeeded
    @discardableResult
    func verifyFuzzyMatchDialog(shown: Bool) -> Bool {
        return XCTContext.runActivity(named: "Verify fuzzy match dialog \(shown ? "shown" : "not shown")") { _ -> Bool in
            let fuzzyMatchTitle = app.staticTexts["Similar Recurring Payment Found"]
            let exists = fuzzyMatchTitle.waitForExistence(timeout: shortTimeout)

            if shown {
                XCTAssertTrue(exists, "Fuzzy match dialog should be shown but wasn't")
            } else {
                XCTAssertFalse(exists, "Fuzzy match dialog should not be shown but was")
            }

            return exists == shown
        }
    }

    /// Verifies the "Due in 7 days" counter on the home page
    /// - Parameter expected: Expected count
    /// - Returns: Whether the verification succeeded
    @discardableResult
    func verifyDueIn7DaysCounter(expected: Int) -> Bool {
        return XCTContext.runActivity(named: "Verify due in 7 days counter: \(expected)") { _ -> Bool in
            navigateToHome()
            sleep(1)

            // Look for the counter element
            let counterText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '\(expected)'")).firstMatch
            let exists = counterText.waitForExistence(timeout: shortTimeout)

            return exists
        }
    }

    /// Verifies that an invoice appears in the calendar on a specific date
    /// - Parameters:
    ///   - vendor: Vendor name to look for
    ///   - day: Day of the month
    /// - Returns: Whether the verification succeeded
    @discardableResult
    func verifyInvoiceInCalendar(vendor: String, onDay day: Int) -> Bool {
        return XCTContext.runActivity(named: "Verify \(vendor) in calendar on day \(day)") { _ -> Bool in
            navigateToCalendar()
            sleep(1)

            // Tap on the day
            let dayCell = app.buttons.matching(NSPredicate(format: "label == '\(day)'")).firstMatch
            if dayCell.waitForExistence(timeout: shortTimeout) {
                dayCell.tap()
                sleep(1)

                // Check if vendor appears in the selected day's documents
                let vendorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '\(vendor)'")).firstMatch
                return vendorText.waitForExistence(timeout: shortTimeout)
            }

            return false
        }
    }

    // MARK: - Utility Methods

    /// Takes a screenshot and attaches it to the test report
    /// - Parameter name: Name for the screenshot
    func takeScreenshot(name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Waits for a specific element to exist
    /// - Parameters:
    ///   - element: The element to wait for
    ///   - timeout: Maximum time to wait
    /// - Returns: Whether the element exists
    @discardableResult
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval? = nil) -> Bool {
        return element.waitForExistence(timeout: timeout ?? standardTimeout)
    }

    /// Dismisses any presented sheet or alert
    func dismissAnyPresented() {
        // Try to dismiss sheet by tapping cancel
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.exists {
            cancelButton.tap()
            return
        }

        // Try to dismiss alert
        let alertCancelButton = app.alerts.buttons["Cancel"]
        if alertCancelButton.exists {
            alertCancelButton.tap()
            return
        }

        // Try Done button
        let doneButton = app.buttons["Done"]
        if doneButton.exists {
            doneButton.tap()
            return
        }

        // Last resort: swipe down on sheet
        let sheet = app.sheets.firstMatch
        if sheet.exists {
            sheet.swipeDown()
        }
    }

    /// Scrolls until an element is visible
    /// - Parameter element: The element to scroll to
    func scrollToElement(_ element: XCUIElement) {
        var attempts = 0
        while !element.isHittable && attempts < 10 {
            app.swipeUp()
            attempts += 1
        }
    }

    /// Gets the current date formatted as the app would display it
    func currentFormattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }

    /// Generates a unique test vendor name
    func uniqueVendorName(base: String = "TestVendor") -> String {
        return "\(testVendorPrefix)\(base)_\(UUID().uuidString.prefix(8))"
    }
}

// MARK: - XCUIElement Extensions

extension XCUIElement {
    /// Clears existing text and types new text
    func clearAndTypeText(_ text: String) {
        guard let currentValue = self.value as? String, !currentValue.isEmpty else {
            self.typeText(text)
            return
        }

        // Select all and delete
        self.tap()
        self.tap(withNumberOfTaps: 3, numberOfTouches: 1) // Triple tap to select all

        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
        self.typeText(deleteString)
        self.typeText(text)
    }
}
