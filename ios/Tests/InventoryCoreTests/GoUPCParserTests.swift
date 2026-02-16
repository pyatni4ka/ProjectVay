import XCTest
@testable import InventoryCore

final class GoUPCParserTests: XCTestCase {
    func testParseExtractsCoffeeNameAndBrand() {
        let html = """
        <html>
          <head><title>Jacobs Кофе Растворимый &quot;Monarch — EAN 4607001771562 — Go-UPC</title></head>
          <body>
            <div class="product-details">
              <h1 class="product-name">Jacobs Кофе Растворимый &quot;Monarch</h1>
            </div>
            <table class="table table-striped">
              <tr><td class="metadata-label">EAN</td><td>4607001771562</td></tr>
              <tr><td class="metadata-label">Brand</td><td>Jacobs</td></tr>
              <tr><td class="metadata-label">Category</td><td></td></tr>
            </table>
          </body>
        </html>
        """

        let payload = GoUPCParser.parse(barcode: "4607001771562", document: html)

        XCTAssertEqual(payload?.barcode, "4607001771562")
        XCTAssertEqual(payload?.name, "Jacobs Кофе Растворимый \"Monarch")
        XCTAssertEqual(payload?.brand, "Jacobs")
        XCTAssertEqual(payload?.category, "Продукты")
    }

    func testParseReturnsNilForInvalidPage() {
        let html = """
        <html>
          <head><title>Invalid Value — Go-UPC</title></head>
          <body><p>Invalid Value</p></body>
        </html>
        """

        let payload = GoUPCParser.parse(barcode: "9999999999999", document: html)
        XCTAssertNil(payload)
    }
}
