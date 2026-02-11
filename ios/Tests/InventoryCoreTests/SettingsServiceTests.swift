import XCTest
@testable import InventoryCore

final class SettingsServiceTests: XCTestCase {
    func testSaveSettingsReschedulesOnlyBatchesWithExpiryDate() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let inventoryRepository = InventoryRepository(dbQueue: dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let scheduler = NotificationSchedulerSpy()

        let product = Product(
            barcode: "4600000000000",
            name: "Йогурт",
            brand: "Тест",
            category: "Молочные продукты"
        )
        try inventoryRepository.upsertProduct(product)

        let expiringBatch = Batch(
            productId: product.id,
            location: .fridge,
            quantity: 1,
            unit: .pcs,
            expiryDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
            isOpened: false
        )
        let noExpiryBatch = Batch(
            productId: product.id,
            location: .fridge,
            quantity: 1,
            unit: .pcs,
            expiryDate: nil,
            isOpened: false
        )
        try inventoryRepository.addBatch(expiringBatch)
        try inventoryRepository.addBatch(noExpiryBatch)

        let service = SettingsService(
            repository: settingsRepository,
            inventoryRepository: inventoryRepository,
            notificationScheduler: scheduler
        )

        let _ = try await service.saveSettings(
            AppSettings(
                quietStartMinute: 90,
                quietEndMinute: 360,
                expiryAlertsDays: [7, 3, 1, 3],
                budgetDay: 900,
                budgetWeek: 5_000,
                stores: [.pyaterochka, .auchan],
                dislikedList: ["Кускус", " кускус "],
                avoidBones: true
            )
        )

        let calls = await scheduler.snapshot()
        XCTAssertEqual(calls.rescheduledBatchIDs, [expiringBatch.id])
        XCTAssertEqual(calls.scheduledBatchIDs, [])
        XCTAssertEqual(calls.canceledBatchIDs, [])
    }

    func testOnboardingFlagRoundtrip() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let service = SettingsService(repository: settingsRepository)

        let before = try await service.isOnboardingCompleted()
        XCTAssertFalse(before)
        try await service.setOnboardingCompleted()
        let after = try await service.isOnboardingCompleted()
        XCTAssertTrue(after)
    }

    func testExportLocalDataWritesSnapshot() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let inventoryRepository = InventoryRepository(dbQueue: dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let exportsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InventoryCoreTests-\(UUID().uuidString)", isDirectory: true)

        let product = Product(
            barcode: "4600000000000",
            name: "Йогурт",
            brand: "Тест",
            category: "Молочные продукты"
        )
        try inventoryRepository.upsertProduct(product)
        try inventoryRepository.addBatch(
            Batch(
                productId: product.id,
                location: .fridge,
                quantity: 2,
                unit: .pcs,
                expiryDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                isOpened: false
            )
        )
        try inventoryRepository.savePriceEntry(
            PriceEntry(
                productId: product.id,
                store: .pyaterochka,
                price: 129
            )
        )
        try inventoryRepository.saveInventoryEvent(
            InventoryEvent(
                type: .add,
                productId: product.id,
                quantityDelta: 2,
                note: "seed"
            )
        )

        let service = SettingsService(
            repository: settingsRepository,
            inventoryRepository: inventoryRepository,
            exportsDirectoryURL: exportsDirectory
        )

        let fileURL = try await service.exportLocalData()
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LocalDataExportSnapshot.self, from: data)

        XCTAssertEqual(decoded.products.count, 1)
        XCTAssertEqual(decoded.batches.count, 1)
        XCTAssertEqual(decoded.priceEntries.count, 1)
        XCTAssertEqual(decoded.inventoryEvents.count, 1)
    }

    func testDeleteAllLocalDataClearsInventoryAndResetsOnboarding() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let inventoryRepository = InventoryRepository(dbQueue: dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let service = SettingsService(
            repository: settingsRepository,
            inventoryRepository: inventoryRepository
        )

        let product = Product(
            barcode: nil,
            name: "Молоко",
            brand: nil,
            category: "Молочные продукты"
        )
        try inventoryRepository.upsertProduct(product)
        try inventoryRepository.addBatch(
            Batch(
                productId: product.id,
                location: .fridge,
                quantity: 1,
                unit: .pcs
            )
        )
        try await service.setOnboardingCompleted()

        try await service.deleteAllLocalData(resetOnboarding: true)

        let products = try inventoryRepository.listProducts(location: nil, search: nil)
        let batches = try inventoryRepository.listBatches(productId: nil)
        let onboardingCompleted = try await service.isOnboardingCompleted()
        let settings = try await service.loadSettings()

        XCTAssertTrue(products.isEmpty)
        XCTAssertTrue(batches.isEmpty)
        XCTAssertFalse(onboardingCompleted)
        XCTAssertEqual(settings, .default)
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
}
