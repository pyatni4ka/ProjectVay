import XCTest
@testable import InventoryCore

final class ScannerServiceTests: XCTestCase {
    func testParseEAN13() {
        let service = ScannerService()
        let payload = service.parse(code: "4601234567890")

        guard case .ean13(let value) = payload else {
            XCTFail("Expected EAN-13 payload")
            return
        }

        XCTAssertEqual(value, "4601234567890")
    }

    func testParseDataMatrixExtractsGTINAndExpiry() {
        let service = ScannerService()
        let payload = service.parse(code: "010460123456789017260228")

        guard case .dataMatrix(_, let gtin, let expiry) = payload else {
            XCTFail("Expected DataMatrix payload")
            return
        }

        XCTAssertEqual(gtin, "04601234567890")
        XCTAssertNotNil(expiry)
    }

    func testParseInternalCodeWeightBestEffort() {
        let service = ScannerService()
        let payload = service.parse(code: "22-12345")

        guard case .internalCode(_, let grams) = payload else {
            XCTFail("Expected internal code payload")
            return
        }

        XCTAssertEqual(grams, 345)
    }
}
