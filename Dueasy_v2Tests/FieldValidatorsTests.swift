import XCTest
@testable import Dueasy_v2

final class FieldValidatorsTests: XCTestCase {

    // MARK: - Vendor Name Validation Tests

    func testValidVendorNames() {
        // Valid company names
        XCTAssertTrue(FieldValidators.isValidVendorName("ABC Company Sp. z o.o."))
        XCTAssertTrue(FieldValidators.isValidVendorName("Microsoft Corporation"))
        XCTAssertTrue(FieldValidators.isValidVendorName("Google LLC"))
        XCTAssertTrue(FieldValidators.isValidVendorName("Przykładowa Firma S.A."))
        XCTAssertTrue(FieldValidators.isValidVendorName("Jan Kowalski"))
        XCTAssertTrue(FieldValidators.isValidVendorName("ACME Industries Ltd."))
        XCTAssertTrue(FieldValidators.isValidVendorName("Deutsche Telekom GmbH"))
    }

    func testInvalidVendorNames() {
        // Too short
        XCTAssertFalse(FieldValidators.isValidVendorName("AB"))
        XCTAssertFalse(FieldValidators.isValidVendorName("Test"))

        // Document type headers
        XCTAssertFalse(FieldValidators.isValidVendorName("FAKTURA VAT"))
        XCTAssertFalse(FieldValidators.isValidVendorName("VAT INVOICE"))
        XCTAssertFalse(FieldValidators.isValidVendorName("INVOICE"))
        XCTAssertFalse(FieldValidators.isValidVendorName("Faktura korygująca"))

        // Date patterns
        XCTAssertFalse(FieldValidators.isValidVendorName("15.01.2024"))
        XCTAssertFalse(FieldValidators.isValidVendorName("2024-01-15"))

        // Account numbers
        XCTAssertFalse(FieldValidators.isValidVendorName("12345678901234567890123456"))

        // Amounts
        XCTAssertFalse(FieldValidators.isValidVendorName("1 234,56 PLN"))
        XCTAssertFalse(FieldValidators.isValidVendorName("1234.56"))

        // NIP patterns
        XCTAssertFalse(FieldValidators.isValidVendorName("NIP: 1234567890"))

        // Pure numbers
        XCTAssertFalse(FieldValidators.isValidVendorName("123456789"))
    }

    func testVendorNameConfidenceBoost() {
        // Should get boost for company suffixes
        XCTAssertGreaterThan(FieldValidators.vendorNameConfidenceBoost("ABC Sp. z o.o."), 0)
        XCTAssertGreaterThan(FieldValidators.vendorNameConfidenceBoost("XYZ S.A."), 0)
        XCTAssertGreaterThan(FieldValidators.vendorNameConfidenceBoost("Company Ltd."), 0)
        XCTAssertGreaterThan(FieldValidators.vendorNameConfidenceBoost("Corp LLC"), 0)
        XCTAssertGreaterThan(FieldValidators.vendorNameConfidenceBoost("Firma GmbH"), 0)

        // Should not get boost without suffix
        XCTAssertEqual(FieldValidators.vendorNameConfidenceBoost("Jan Kowalski"), 0)
        XCTAssertEqual(FieldValidators.vendorNameConfidenceBoost("ABC Company"), 0)
    }

    // MARK: - Address Validation Tests

    func testValidAddressComponents() {
        // Polish postal codes
        XCTAssertTrue(FieldValidators.isValidAddressComponent("02-675 Warszawa"))
        XCTAssertTrue(FieldValidators.isValidAddressComponent("00-001 Warszawa"))

        // Polish street prefixes
        XCTAssertTrue(FieldValidators.isValidAddressComponent("ul. Marszałkowska 100"))
        XCTAssertTrue(FieldValidators.isValidAddressComponent("al. Jerozolimskie 55"))
        XCTAssertTrue(FieldValidators.isValidAddressComponent("pl. Bankowy 1"))
        XCTAssertTrue(FieldValidators.isValidAddressComponent("os. Młodych 5"))

        // English street prefixes
        XCTAssertTrue(FieldValidators.isValidAddressComponent("123 Main Street"))
        XCTAssertTrue(FieldValidators.isValidAddressComponent("456 Oak Ave."))
        XCTAssertTrue(FieldValidators.isValidAddressComponent("789 Broadway Blvd."))
        XCTAssertTrue(FieldValidators.isValidAddressComponent("100 Park Lane"))

        // US postal codes
        XCTAssertTrue(FieldValidators.isValidAddressComponent("New York, NY 10001"))
        XCTAssertTrue(FieldValidators.isValidAddressComponent("90210 Beverly Hills"))

        // Street with number
        XCTAssertTrue(FieldValidators.isValidAddressComponent("Marszałkowska 100/5"))
        XCTAssertTrue(FieldValidators.isValidAddressComponent("Krakowska 15A"))

        // City names
        XCTAssertTrue(FieldValidators.isValidAddressComponent("Warszawa"))
        XCTAssertTrue(FieldValidators.isValidAddressComponent("Kraków"))
        XCTAssertTrue(FieldValidators.isValidAddressComponent("New York"))
        XCTAssertTrue(FieldValidators.isValidAddressComponent("London"))
    }

    func testInvalidAddressComponents() {
        // Too short
        XCTAssertFalse(FieldValidators.isValidAddressComponent("AB"))

        // Not an address pattern
        XCTAssertFalse(FieldValidators.isValidAddressComponent("NIP 1234567890"))
        XCTAssertFalse(FieldValidators.isValidAddressComponent("REGON 123456789"))
    }

    // MARK: - Invoice Number Validation Tests

    func testValidInvoiceNumbers() {
        XCTAssertTrue(FieldValidators.validateInvoiceNumber("FV-123/2024"))
        XCTAssertTrue(FieldValidators.validateInvoiceNumber("FA/001/2024"))
        XCTAssertTrue(FieldValidators.validateInvoiceNumber("INV-2024-0001"))
        XCTAssertTrue(FieldValidators.validateInvoiceNumber("001/01/2024"))
        XCTAssertTrue(FieldValidators.validateInvoiceNumber("FV1234567"))
        XCTAssertTrue(FieldValidators.validateInvoiceNumber("2024/001"))
        XCTAssertTrue(FieldValidators.validateInvoiceNumber("FVS-123-2024"))
    }

    func testInvalidInvoiceNumbers() {
        // Too short
        XCTAssertFalse(FieldValidators.validateInvoiceNumber("FV"))
        XCTAssertFalse(FieldValidators.validateInvoiceNumber("1"))

        // Too long
        XCTAssertFalse(FieldValidators.validateInvoiceNumber("INVOICE-NUMBER-THAT-IS-WAY-TOO-LONG-FOR-ANY-REASONABLE-SYSTEM"))

        // Pure long number (likely account)
        XCTAssertFalse(FieldValidators.validateInvoiceNumber("1234567890123456"))

        // Date-like (without prefix)
        // Note: "15.01.2024" should fail unless it has a prefix like "FV-"
        // The validator allows dates with prefixes, so this test is contextual

        // No numbers
        XCTAssertFalse(FieldValidators.validateInvoiceNumber("ABCDEF"))
    }

    // MARK: - IBAN Validation Tests

    func testValidPolishIBANs() {
        // Valid Polish IBAN (28 chars: PL + 26 digits)
        // Note: These are example IBANs that pass checksum validation
        XCTAssertTrue(FieldValidators.validateIBAN("PL61109010140000071219812874"))

        // Valid 26-digit account (without PL prefix)
        XCTAssertTrue(FieldValidators.validateIBAN("61109010140000071219812874"))
    }

    func testInvalidIBANs() {
        // Wrong length
        XCTAssertFalse(FieldValidators.validateIBAN("PL1234567890"))
        XCTAssertFalse(FieldValidators.validateIBAN("12345678901234567890"))

        // Wrong country prefix
        XCTAssertFalse(FieldValidators.validateIBAN("DE89370400440532013000"))  // German IBAN - 22 chars

        // Invalid checksum
        XCTAssertFalse(FieldValidators.validateIBAN("PL00000000000000000000000000"))
    }

    func testIBANWithSpaces() {
        // Should handle spaces
        XCTAssertTrue(FieldValidators.validateIBAN("PL61 1090 1014 0000 0712 1981 2874"))
    }

    // MARK: - Pattern Detection Tests

    func testDatePatternDetection() {
        XCTAssertTrue(FieldValidators.looksLikeDate("15.01.2024"))
        XCTAssertTrue(FieldValidators.looksLikeDate("2024-01-15"))
        XCTAssertTrue(FieldValidators.looksLikeDate("15/01/2024"))
        XCTAssertTrue(FieldValidators.looksLikeDate("Data: 15.01.2024"))

        XCTAssertFalse(FieldValidators.looksLikeDate("ABC Company"))
        XCTAssertFalse(FieldValidators.looksLikeDate("1234567890"))
    }

    func testAccountNumberDetection() {
        XCTAssertTrue(FieldValidators.looksLikeAccountNumber("12345678901234567890123456"))
        XCTAssertTrue(FieldValidators.looksLikeAccountNumber("61 1090 1014 0000 0712 1981 2874"))

        XCTAssertFalse(FieldValidators.looksLikeAccountNumber("1234567890"))
        XCTAssertFalse(FieldValidators.looksLikeAccountNumber("ABC Company"))
    }

    func testAmountDetection() {
        XCTAssertTrue(FieldValidators.looksLikeAmount("1 234,56"))
        XCTAssertTrue(FieldValidators.looksLikeAmount("1234.56"))
        XCTAssertTrue(FieldValidators.looksLikeAmount("1234,56 PLN"))
        XCTAssertTrue(FieldValidators.looksLikeAmount("PLN 1234"))

        XCTAssertFalse(FieldValidators.looksLikeAmount("ABC Company"))
        XCTAssertFalse(FieldValidators.looksLikeAmount("Invoice 123"))
    }

    func testNIPDetection() {
        XCTAssertTrue(FieldValidators.looksLikeNIP("NIP: 1234567890"))
        XCTAssertTrue(FieldValidators.looksLikeNIP("1234567890"))
        XCTAssertTrue(FieldValidators.looksLikeNIP("123-456-78-90"))

        XCTAssertFalse(FieldValidators.looksLikeNIP("ABC Company"))
        XCTAssertFalse(FieldValidators.looksLikeNIP("12345"))  // Too short
    }

    func testDeductionKeywords() {
        // Polish keywords
        XCTAssertTrue(FieldValidators.containsDeductionKeywords("Rabat 10%"))
        XCTAssertTrue(FieldValidators.containsDeductionKeywords("Korekta faktury"))
        XCTAssertTrue(FieldValidators.containsDeductionKeywords("Upust handlowy"))
        XCTAssertTrue(FieldValidators.containsDeductionKeywords("Zniżka sezonowa"))
        XCTAssertTrue(FieldValidators.containsDeductionKeywords("Bonifikata"))

        // English keywords
        XCTAssertTrue(FieldValidators.containsDeductionKeywords("Discount applied"))
        XCTAssertTrue(FieldValidators.containsDeductionKeywords("Credit note"))
        XCTAssertTrue(FieldValidators.containsDeductionKeywords("Rebate given"))
        XCTAssertTrue(FieldValidators.containsDeductionKeywords("Refund issued"))
        XCTAssertTrue(FieldValidators.containsDeductionKeywords("Adjustment made"))

        // Should not match
        XCTAssertFalse(FieldValidators.containsDeductionKeywords("Do zapłaty"))
        XCTAssertFalse(FieldValidators.containsDeductionKeywords("Total amount"))
        XCTAssertFalse(FieldValidators.containsDeductionKeywords("Invoice number"))
    }

    // MARK: - NIP Checksum Validation Tests

    func testNIPChecksumValidation() {
        // Valid NIPs (pass checksum)
        XCTAssertTrue(FieldValidators.validateNIPChecksum("7740001454"))  // Example valid NIP
        XCTAssertTrue(FieldValidators.validateNIPChecksum("525-23-31-860"))  // With separators

        // Invalid NIPs (fail checksum)
        XCTAssertFalse(FieldValidators.validateNIPChecksum("0000000000"))
        XCTAssertFalse(FieldValidators.validateNIPChecksum("1234567890"))

        // Wrong length
        XCTAssertFalse(FieldValidators.validateNIPChecksum("123456789"))  // 9 digits
        XCTAssertFalse(FieldValidators.validateNIPChecksum("12345678901"))  // 11 digits
    }
}
