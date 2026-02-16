import XCTest
@testable import InventoryCore

final class RecipeServiceClientTests: XCTestCase {
    func testMapsURLNotConnectedErrorToNoConnection() {
        let mapped = RecipeServiceClientError.from(URLError(.notConnectedToInternet))
        XCTAssertEqual(mapped, .noConnection)
    }

    func testReturnsSameDomainErrorWhenAlreadyMapped() {
        let source: RecipeServiceClientError = .offlineMode
        let mapped = RecipeServiceClientError.from(source)
        XCTAssertEqual(mapped, .offlineMode)
    }

    func testLocalizedDescriptionsAreRussianAndHumanReadable() {
        XCTAssertEqual(RecipeServiceClientError.noConnection.errorDescription, "Нет подключения к серверу рецептов.")
        XCTAssertEqual(RecipeServiceClientError.offlineMode.errorDescription, "Сеть недоступна. Работаем в офлайн-режиме.")
        XCTAssertEqual(
            RecipeServiceClientError.httpError(statusCode: 503, body: "upstream down").errorDescription,
            "Сервер рецептов временно недоступен. Попробуйте позже."
        )
    }
}
