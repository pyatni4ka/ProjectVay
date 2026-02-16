import XCTest
import GRDB
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

    func testImportLocalDataRestoresSnapshot() async throws {
        let sourceQueue = try AppDatabase.makeInMemoryQueue()
        let sourceInventoryRepository = InventoryRepository(dbQueue: sourceQueue)
        let sourceSettingsRepository = SettingsRepository(dbQueue: sourceQueue)
        let exportsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InventoryCoreImport-\(UUID().uuidString)", isDirectory: true)

        let sourceService = SettingsService(
            repository: sourceSettingsRepository,
            inventoryRepository: sourceInventoryRepository,
            exportsDirectoryURL: exportsDirectory
        )

        let sourceProduct = Product(
            barcode: "4601234567890",
            name: "Кефир",
            brand: "Тест",
            category: "Молочные продукты"
        )
        try sourceInventoryRepository.upsertProduct(sourceProduct)
        try sourceInventoryRepository.addBatch(
            Batch(
                productId: sourceProduct.id,
                location: .fridge,
                quantity: 3,
                unit: .pcs,
                expiryDate: Calendar.current.date(byAdding: .day, value: 4, to: Date())
            )
        )

        let exportURL = try await sourceService.exportLocalData()

        let targetQueue = try AppDatabase.makeInMemoryQueue()
        let targetInventoryRepository = InventoryRepository(dbQueue: targetQueue)
        let targetSettingsRepository = SettingsRepository(dbQueue: targetQueue)
        let targetService = SettingsService(
            repository: targetSettingsRepository,
            inventoryRepository: targetInventoryRepository
        )

        try await targetService.importLocalData(from: exportURL, replaceExisting: true)

        let importedProducts = try targetInventoryRepository.listProducts(location: nil, search: nil)
        let importedBatches = try targetInventoryRepository.listBatches(productId: nil)

        XCTAssertEqual(importedProducts.count, 1)
        XCTAssertEqual(importedProducts.first?.name, "Кефир")
        XCTAssertEqual(importedBatches.count, 1)
        XCTAssertEqual(importedBatches.first?.quantity ?? 0, 3, accuracy: 0.001)
    }

    func testDecodeLegacySettingsWithoutMacroFieldsUsesDefaults() throws {
        let legacyJSON = """
        {
          "quietStartMinute": 60,
          "quietEndMinute": 360,
          "expiryAlertsDays": [5,3,1],
          "budgetDay": 800,
          "budgetWeek": null,
          "stores": ["pyaterochka","yandexLavka"],
          "dislikedList": ["кускус"],
          "avoidBones": true,
          "mealSchedule": {
            "breakfastMinute": 480,
            "lunchMinute": 780,
            "dinnerMinute": 1140
          }
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertTrue(settings.strictMacroTracking)
        XCTAssertEqual(settings.macroTolerancePercent, 25)
        XCTAssertEqual(settings.macroGoalSource, .automatic)
        XCTAssertNil(settings.recipeServiceBaseURLOverride)
        XCTAssertNil(settings.budgetMonth)
        XCTAssertEqual(settings.budgetInputPeriod, .week)
        XCTAssertTrue(settings.hapticsEnabled)
        XCTAssertTrue(settings.showHealthCardOnHome)
        XCTAssertEqual(settings.dietProfile, .medium)
    }

    func testBudgetNormalizationConvertsDayToWeekAndMonth() {
        let settings = AppSettings(
            quietStartMinute: 60,
            quietEndMinute: 360,
            expiryAlertsDays: [5, 3, 1],
            budgetDay: 800,
            budgetWeek: nil,
            budgetMonth: nil,
            budgetInputPeriod: .day,
            stores: [.pyaterochka],
            dislikedList: [],
            avoidBones: true
        ).normalized()

        XCTAssertEqual(settings.budgetInputPeriod, .day)
        XCTAssertEqual(NSDecimalNumber(decimal: settings.budgetDay).doubleValue, 800, accuracy: 0.001)
        XCTAssertEqual(NSDecimalNumber(decimal: settings.budgetWeek ?? 0).doubleValue, 5_600, accuracy: 0.001)
        XCTAssertEqual(NSDecimalNumber(decimal: settings.budgetMonth ?? 0).doubleValue, 24_333.33, accuracy: 0.01)
    }

    func testBudgetNormalizationConvertsWeekToMonthAndDay() {
        let settings = AppSettings(
            quietStartMinute: 60,
            quietEndMinute: 360,
            expiryAlertsDays: [5, 3, 1],
            budgetDay: 0,
            budgetWeek: 5_600,
            budgetMonth: nil,
            budgetInputPeriod: .week,
            stores: [.pyaterochka],
            dislikedList: [],
            avoidBones: true
        ).normalized()

        XCTAssertEqual(settings.budgetInputPeriod, .week)
        XCTAssertEqual(NSDecimalNumber(decimal: settings.budgetDay).doubleValue, 800, accuracy: 0.001)
        XCTAssertEqual(NSDecimalNumber(decimal: settings.budgetWeek ?? 0).doubleValue, 5_600, accuracy: 0.001)
        XCTAssertEqual(NSDecimalNumber(decimal: settings.budgetMonth ?? 0).doubleValue, 24_333.33, accuracy: 0.01)
    }

    func testBudgetNormalizationConvertsMonthToWeekAndDay() {
        let settings = AppSettings(
            quietStartMinute: 60,
            quietEndMinute: 360,
            expiryAlertsDays: [5, 3, 1],
            budgetDay: 0,
            budgetWeek: nil,
            budgetMonth: 24_333.33,
            budgetInputPeriod: .month,
            stores: [.pyaterochka],
            dislikedList: [],
            avoidBones: true
        ).normalized()

        XCTAssertEqual(settings.budgetInputPeriod, .month)
        XCTAssertEqual(NSDecimalNumber(decimal: settings.budgetDay).doubleValue, 800, accuracy: 0.01)
        XCTAssertEqual(NSDecimalNumber(decimal: settings.budgetWeek ?? 0).doubleValue, 5_600, accuracy: 0.01)
        XCTAssertEqual(NSDecimalNumber(decimal: settings.budgetMonth ?? 0).doubleValue, 24_333.33, accuracy: 0.01)
    }

    func testSettingsNormalizationClampsMacroTolerance() {
        let settings = AppSettings(
            quietStartMinute: 60,
            quietEndMinute: 360,
            expiryAlertsDays: [5, 3, 1],
            budgetDay: 800,
            budgetWeek: nil,
            stores: [.pyaterochka],
            dislikedList: ["кускус"],
            avoidBones: true,
            mealSchedule: .default,
            strictMacroTracking: true,
            macroTolerancePercent: 1
        ).normalized()

        XCTAssertEqual(settings.macroTolerancePercent, 5)
    }

    func testInvalidPersistedDietProfileFallsBackToMedium() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let service = SettingsService(repository: SettingsRepository(dbQueue: dbQueue))

        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE app_settings SET diet_profile = ? WHERE id = ?",
                arguments: ["unsupported_profile", AppSettingsRecord.singletonID]
            )
        }

        let loaded = try await service.loadSettings()
        XCTAssertEqual(loaded.dietProfile, .medium)
    }

    func testExtendedSettingsRoundtrip() async throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let service = SettingsService(repository: settingsRepository)

        let source = AppSettings(
            quietStartMinute: 120,
            quietEndMinute: 420,
            expiryAlertsDays: [7, 3, 1],
            budgetDay: 950,
            budgetWeek: 5_500,
            stores: [.auchan, .pyaterochka],
            dislikedList: ["корица"],
            avoidBones: false,
            mealSchedule: .init(breakfastMinute: 9 * 60, lunchMinute: 14 * 60, dinnerMinute: 20 * 60),
            strictMacroTracking: false,
            macroTolerancePercent: 30,
            macroGoalSource: .manual,
            kcalGoal: 1800,
            proteinGoalGrams: 135,
            fatGoalGrams: 55,
            carbsGoalGrams: 160,
            weightGoalKg: 72,
            preferredColorScheme: 2,
            healthKitReadEnabled: false,
            healthKitWriteEnabled: true,
            enableAnimations: false,
            hapticsEnabled: false,
            showHealthCardOnHome: false,
            dietProfile: .extreme,
            recipeServiceBaseURLOverride: "http://192.168.0.15:8080"
        )

        _ = try await service.saveSettings(source)
        let loaded = try await service.loadSettings()

        XCTAssertEqual(loaded.macroGoalSource, .manual)
        XCTAssertEqual(loaded.kcalGoal, 1800)
        XCTAssertEqual(loaded.proteinGoalGrams, 135)
        XCTAssertEqual(loaded.fatGoalGrams, 55)
        XCTAssertEqual(loaded.carbsGoalGrams, 160)
        XCTAssertEqual(loaded.weightGoalKg, 72)
        XCTAssertEqual(loaded.preferredColorScheme, 2)
        XCTAssertFalse(loaded.healthKitReadEnabled)
        XCTAssertTrue(loaded.healthKitWriteEnabled)
        XCTAssertFalse(loaded.enableAnimations)
        XCTAssertFalse(loaded.hapticsEnabled)
        XCTAssertFalse(loaded.showHealthCardOnHome)
        XCTAssertEqual(loaded.dietProfile, .extreme)
        XCTAssertEqual(loaded.recipeServiceBaseURLOverride, "http://192.168.0.15:8080")
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
