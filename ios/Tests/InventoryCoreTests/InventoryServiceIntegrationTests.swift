import XCTest
import GRDB
@testable import InventoryCore

final class InventoryServiceIntegrationTests: XCTestCase {
    func testAddUpdateRemoveBatchRecordsEventsAndNotificationCalls() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let repository = InventoryRepository(dbQueue: dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let scheduler = NotificationSchedulerSpy()
        let service = InventoryService(
            repository: repository,
            settingsRepository: settingsRepository,
            notificationScheduler: scheduler
        )

        let product = try await service.createProduct(
            Product(
                barcode: "4601234567890",
                name: "Молоко",
                brand: "Пример",
                category: "Молочные продукты",
                defaultUnit: .pcs,
                disliked: false,
                mayContainBones: false
            )
        )

        let firstExpiry = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        var batch = try await service.addBatch(
            Batch(
                productId: product.id,
                location: .fridge,
                quantity: 2,
                unit: .pcs,
                expiryDate: firstExpiry,
                isOpened: false
            )
        )

        let secondExpiry = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        batch.expiryDate = secondExpiry
        _ = try await service.updateBatch(batch)
        try await service.removeBatch(id: batch.id, quantity: nil, intent: .writeOff, note: nil)

        let calls = await scheduler.snapshot()
        XCTAssertEqual(calls.scheduledBatchIDs, [batch.id])
        XCTAssertEqual(calls.rescheduledBatchIDs, [batch.id])
        XCTAssertEqual(calls.canceledBatchIDs, [batch.id])

        XCTAssertEqual(try countEvents(dbQueue, type: "add"), 1)
        XCTAssertEqual(try countEvents(dbQueue, type: "adjust"), 1)
        XCTAssertEqual(try countEvents(dbQueue, type: "remove"), 1)
    }

    func testPartialConsumeUpdatesBatchAndWritesProportionalValue() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let repository = InventoryRepository(dbQueue: dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let scheduler = NotificationSchedulerSpy()
        let service = InventoryService(
            repository: repository,
            settingsRepository: settingsRepository,
            notificationScheduler: scheduler
        )

        let product = try await service.createProduct(
            Product(
                barcode: nil,
                name: "Творог",
                brand: nil,
                category: "Молочные продукты",
                defaultUnit: .pcs,
                disliked: false,
                mayContainBones: false
            )
        )

        let batch = try await service.addBatch(
            Batch(
                productId: product.id,
                location: .fridge,
                quantity: 4,
                unit: .pcs,
                expiryDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                purchasePriceMinor: 20000,
                isOpened: false
            )
        )

        try await service.removeBatch(
            id: batch.id,
            quantity: 1,
            intent: .consumed,
            note: nil
        )

        let updatedBatch = try repository.listBatches(productId: product.id).first
        XCTAssertNotNil(updatedBatch)
        XCTAssertEqual(updatedBatch?.quantity ?? 0, 3, accuracy: 0.000_1)
        XCTAssertEqual(updatedBatch?.purchasePriceMinor, 15000)

        let removeEvent = try repository.listInventoryEvents(productId: product.id)
            .first(where: { $0.type == .remove })
        XCTAssertEqual(removeEvent?.reason, .consumed)
        XCTAssertEqual(removeEvent?.estimatedValueMinor, 5000)

        let calls = await scheduler.snapshot()
        XCTAssertEqual(calls.scheduledBatchIDs, [batch.id])
        XCTAssertEqual(calls.rescheduledBatchIDs, [batch.id])
        XCTAssertTrue(calls.canceledBatchIDs.isEmpty)
    }

    func testRemoveBatchFallbacksToLatestPriceWhenBatchPriceMissing() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let repository = InventoryRepository(dbQueue: dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let scheduler = NotificationSchedulerSpy()
        let service = InventoryService(
            repository: repository,
            settingsRepository: settingsRepository,
            notificationScheduler: scheduler
        )

        let product = try await service.createProduct(
            Product(
                barcode: nil,
                name: "Кефир",
                brand: nil,
                category: "Молочные продукты",
                defaultUnit: .pcs,
                disliked: false,
                mayContainBones: false
            )
        )
        let batch = try await service.addBatch(
            Batch(
                productId: product.id,
                location: .fridge,
                quantity: 2,
                unit: .pcs,
                expiryDate: Calendar.current.date(byAdding: .day, value: 4, to: Date()),
                isOpened: false
            )
        )

        try await service.savePriceEntry(
            PriceEntry(
                productId: product.id,
                store: .pyaterochka,
                price: 123
            )
        )

        try await service.removeBatch(
            id: batch.id,
            quantity: nil,
            intent: .writeOff,
            note: nil
        )

        let removeEvent = try repository.listInventoryEvents(productId: product.id)
            .first(where: { $0.type == .remove })
        XCTAssertEqual(removeEvent?.reason, .writeOff)
        XCTAssertEqual(removeEvent?.estimatedValueMinor, 24600)
    }

    func testSavePriceEntryPublishesInventoryDidChangeNotification() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let repository = InventoryRepository(dbQueue: dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let scheduler = NotificationSchedulerSpy()
        let service = InventoryService(
            repository: repository,
            settingsRepository: settingsRepository,
            notificationScheduler: scheduler
        )

        let product = Product(
            barcode: nil,
            name: "Бананы",
            brand: nil,
            category: "Фрукты",
            defaultUnit: .g,
            disliked: false,
            mayContainBones: false
        )
        try repository.upsertProduct(product)

        let notification = XCTNSNotificationExpectation(name: .inventoryDidChange)

        try await service.savePriceEntry(
            PriceEntry(
                productId: product.id,
                store: .pyaterochka,
                price: 199
            )
        )

        await fulfillment(of: [notification], timeout: 1.0)
    }

    func testRecordEventPublishesInventoryDidChangeNotification() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let repository = InventoryRepository(dbQueue: dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let scheduler = NotificationSchedulerSpy()
        let service = InventoryService(
            repository: repository,
            settingsRepository: settingsRepository,
            notificationScheduler: scheduler
        )

        let product = Product(
            barcode: nil,
            name: "Хлеб",
            brand: nil,
            category: "Хлебобулочные",
            defaultUnit: .pcs,
            disliked: false,
            mayContainBones: false
        )
        try repository.upsertProduct(product)

        let notification = XCTNSNotificationExpectation(name: .inventoryDidChange)

        try await service.recordEvent(
            InventoryEvent(
                type: .adjust,
                productId: product.id,
                quantityDelta: 1,
                reason: .unknown,
                note: "Тестовая корректировка"
            )
        )

        await fulfillment(of: [notification], timeout: 1.0)
    }

    func testWriteOffExpiredBatchMarksExpiredReason() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let repository = InventoryRepository(dbQueue: dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let scheduler = NotificationSchedulerSpy()
        let service = InventoryService(
            repository: repository,
            settingsRepository: settingsRepository,
            notificationScheduler: scheduler
        )

        let product = try await service.createProduct(
            Product(
                barcode: nil,
                name: "Салат",
                brand: nil,
                category: "Овощи",
                defaultUnit: .pcs,
                disliked: false,
                mayContainBones: false
            )
        )

        let expiredBatch = try await service.addBatch(
            Batch(
                productId: product.id,
                location: .fridge,
                quantity: 1,
                unit: .pcs,
                expiryDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
                purchasePriceMinor: 4500,
                isOpened: false
            )
        )

        try await service.removeBatch(
            id: expiredBatch.id,
            quantity: nil,
            intent: .writeOff,
            note: nil
        )

        let removeEvent = try repository.listInventoryEvents(productId: product.id)
            .first(where: { $0.type == .remove })
        XCTAssertEqual(removeEvent?.reason, .expired)
        XCTAssertEqual(removeEvent?.estimatedValueMinor, 4500)
    }

    func testDeleteProductCancelsNotificationsForAllBatches() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let repository = InventoryRepository(dbQueue: dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let scheduler = NotificationSchedulerSpy()
        let service = InventoryService(
            repository: repository,
            settingsRepository: settingsRepository,
            notificationScheduler: scheduler
        )

        let product = try await service.createProduct(
            Product(
                barcode: nil,
                name: "Курица",
                brand: nil,
                category: "Мясо",
                defaultUnit: .pcs,
                disliked: false,
                mayContainBones: true
            )
        )

        let batch1 = try await service.addBatch(
            Batch(
                productId: product.id,
                location: .freezer,
                quantity: 1,
                unit: .pcs,
                expiryDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
                isOpened: false
            )
        )
        let batch2 = try await service.addBatch(
            Batch(
                productId: product.id,
                location: .freezer,
                quantity: 2,
                unit: .pcs,
                expiryDate: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
                isOpened: false
            )
        )

        await scheduler.reset()
        try await service.deleteProduct(id: product.id)

        let calls = await scheduler.snapshot()
        XCTAssertEqual(calls.canceledBatchIDs.sorted(by: { $0.uuidString < $1.uuidString }),
                       [batch1.id, batch2.id].sorted(by: { $0.uuidString < $1.uuidString }))
        XCTAssertNil(try repository.fetchProduct(id: product.id))
    }

    func testBindInternalCodeAllowsLookupByInternalCode() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let repository = InventoryRepository(dbQueue: dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let scheduler = NotificationSchedulerSpy()
        let service = InventoryService(
            repository: repository,
            settingsRepository: settingsRepository,
            notificationScheduler: scheduler
        )

        let product = try await service.createProduct(
            Product(
                barcode: nil,
                name: "Яблоки",
                brand: nil,
                category: "Фрукты",
                defaultUnit: .g,
                disliked: false,
                mayContainBones: false
            )
        )

        try await service.bindInternalCode("AA12", productId: product.id, parsedWeightGrams: 350)

        let mapping = try await service.internalCodeMapping(for: "AA12")
        XCTAssertNotNil(mapping)
        XCTAssertEqual(mapping?.parsedWeightGrams, 350)

        let resolved = try await service.findProduct(byInternalCode: "AA12")
        XCTAssertEqual(resolved?.id, product.id)
    }

    private func countEvents(_ dbQueue: DatabaseQueue, type: String) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM inventory_events WHERE type = ?",
                arguments: [type]
            ) ?? 0
        }
    }
}

private actor NotificationSchedulerSpy: NotificationScheduling {
    struct Snapshot {
        let scheduledBatchIDs: [UUID]
        let rescheduledBatchIDs: [UUID]
        let canceledBatchIDs: [UUID]
    }

    private var scheduledBatchIDs: [UUID] = []
    private var rescheduledBatchIDs: [UUID] = []
    private var canceledBatchIDs: [UUID] = []

    func scheduleExpiryNotifications(for batch: Batch, product: Product, settings: AppSettings) async throws {
        scheduledBatchIDs.append(batch.id)
    }

    func cancelExpiryNotifications(batchId: UUID) async throws {
        canceledBatchIDs.append(batchId)
    }

    func rescheduleExpiryNotifications(for batch: Batch, product: Product, settings: AppSettings) async throws {
        rescheduledBatchIDs.append(batch.id)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            scheduledBatchIDs: scheduledBatchIDs,
            rescheduledBatchIDs: rescheduledBatchIDs,
            canceledBatchIDs: canceledBatchIDs
        )
    }

    func reset() {
        scheduledBatchIDs.removeAll()
        rescheduledBatchIDs.removeAll()
        canceledBatchIDs.removeAll()
    }
}
