import XCTest
@testable import InventoryCore

final class BarcodeListRuParserTests: XCTestCase {
    func testParseExtractsCoffeeFromSearchResultsRow() {
        let html = """
        <html>
          <body>
            <table>
              <tr><td>1519</td><td>4607001771562</td><td>Кофе ЯКОБС МОНАРХ /JACOBS MONARCH/ РАСТВОРИМЫЙ СУБЛИМИРОВАННЫЙ ПАКЕТ</td><td>ШТ. 1</td></tr>
            </table>
          </body>
        </html>
        """

        let payload = BarcodeListRuParser.parse(barcode: "4607001771562", document: html)

        XCTAssertEqual(payload?.barcode, "4607001771562")
        XCTAssertEqual(payload?.name, "Кофе ЯКОБС МОНАРХ /JACOBS MONARCH/ РАСТВОРИМЫЙ СУБЛИМИРОВАННЫЙ ПАКЕТ")
        XCTAssertEqual(payload?.category, "Продукты")
        XCTAssertNil(payload?.brand)
    }

    func testParseExtractsCoffeeFromMirrorMarkdown() {
        let markdown = """
        Title: Кофе ЯКОБС Крема Сублмирован. 95гр

        | № | Штрих-код | Наименование | Единица измерения | Рейтинг* |
        | --- | --- | --- | --- | --- |
        | 1 | 4607001771562 | КОФЕ ЯКОБС КРЕМА СУБЛМИРОВАН. 95ГР | ШТ. | 114 |
        """

        let payload = BarcodeListRuParser.parse(barcode: "4607001771562", document: markdown)

        XCTAssertEqual(payload?.barcode, "4607001771562")
        XCTAssertEqual(payload?.name, "Кофе ЯКОБС Крема Сублмирован. 95гр")
        XCTAssertEqual(payload?.category, "Продукты")
    }

    func testParseSkipsGenericTitleAndExtractsMayonnaiseFromRows() {
        let markdown = """
        Title: 4601576009686 - Штрих-код: 4601576009686

        | № | Штрих-код | Наименование | Единица измерения | Рейтинг* |
        | --- | --- | --- | --- | --- |
        | 1 | 4601576009686 | 4601576009686 | ШТ. | 9 |
        | 2 | 4601576009686 | МАЙОНЕЗ МОСКОВСКИЙ ПРОВАНСАЛЬ КЛАССИЧЕСКИЙ МАССОВАЯ ДОЛЯ ЖИРА 67ПРЦ 390 МЛ ДОЙ-ПАК | ШТ | 3 |
        """

        let payload = BarcodeListRuParser.parse(barcode: "4601576009686", document: markdown)

        XCTAssertEqual(payload?.barcode, "4601576009686")
        XCTAssertEqual(payload?.name, "МАЙОНЕЗ МОСКОВСКИЙ ПРОВАНСАЛЬ КЛАССИЧЕСКИЙ МАССОВАЯ ДОЛЯ ЖИРА 67ПРЦ 390 МЛ ДОЙ-ПАК")
        XCTAssertEqual(payload?.category, "Продукты")
        XCTAssertNil(payload?.brand)
    }

    func testParseRejectsSearchPlaceholderTitle() {
        let markdown = """
        Title: Поиск:4680017928991

        Результаты поиска Штрих-код: 4680017928991
        """

        let payload = BarcodeListRuParser.parse(barcode: "4680017928991", document: markdown)
        XCTAssertNil(payload)
    }
}
