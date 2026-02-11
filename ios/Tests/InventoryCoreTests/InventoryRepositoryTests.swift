import XCTest
@testable import InventoryCore

final class InventoryRepositoryTests: XCTestCase {
    func testCRUDProductAndBatchAndSearch() throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let repository = InventoryRepository(dbQueue: dbQueue)

        var product = Product(
            barcode: "4601234567890",
            name: "Молоко 2.5%",
            brand: "Пример",
            category: "Молочные продукты",
            defaultUnit: .pcs,
            disliked: false,
            mayContainBones: false
        )
        product.updatedAt = product.createdAt
        try repository.upsertProduct(product)

        let found = try repository.findProduct(byBarcode: "4601234567890")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Молоко 2.5%")

        let batch = Batch(
            productId: product.id,
            location: .fridge,
            quantity: 2,
            unit: .pcs,
            expiryDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
            isOpened: false
        )
        try repository.addBatch(batch)

        let filteredProducts = try repository.listProducts(location: .fridge, search: "мол")
        XCTAssertEqual(filteredProducts.count, 1)

        let batches = try repository.listBatches(productId: product.id)
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.location, .fridge)

        let expiring = try repository.expiringBatches(until: Calendar.current.date(byAdding: .day, value: 5, to: Date())!)
        XCTAssertEqual(expiring.count, 1)

        try repository.removeBatch(id: batch.id)
        XCTAssertTrue(try repository.listBatches(productId: product.id).isEmpty)

        try repository.deleteProduct(id: product.id)
        XCTAssertNil(try repository.fetchProduct(id: product.id))
    }

    func testSavePriceAndHistoryOrder() throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let repository = InventoryRepository(dbQueue: dbQueue)

        let product = Product(
            barcode: nil,
            name: "Творог",
            brand: nil,
            category: "Молочные продукты",
            defaultUnit: .pcs,
            disliked: false,
            mayContainBones: false
        )
        try repository.upsertProduct(product)

        let older = PriceEntry(productId: product.id, store: .auchan, price: 150, date: Date().addingTimeInterval(-3600))
        let newer = PriceEntry(productId: product.id, store: .pyaterochka, price: 170, date: Date())

        try repository.savePriceEntry(older)
        try repository.savePriceEntry(newer)

        let history = try repository.listPriceHistory(productId: product.id)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.price, 170)
    }
}
