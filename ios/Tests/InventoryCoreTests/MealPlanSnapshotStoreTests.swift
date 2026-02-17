import XCTest
@testable import InventoryCore

final class MealPlanSnapshotStoreTests: XCTestCase {
    func testTodayMenuSnapshotStoreRoundtripPreservesSourceMetadata() {
        let defaults = UserDefaults(suiteName: "MealPlanSnapshotStoreTests.today.roundtrip")!
        defaults.removePersistentDomain(forName: "MealPlanSnapshotStoreTests.today.roundtrip")

        let store = TodayMenuSnapshotStore(userDefaults: defaults, key: "today_menu")
        let snapshot = TodayMenuSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            items: [
                .init(mealType: "breakfast", title: "Омлет", kcal: 380)
            ],
            estimatedCost: 190,
            dataSource: .localFallback,
            dataSourceDetails: "Использован локальный каталог."
        )

        store.save(snapshot)
        let loaded = store.load()

        XCTAssertEqual(loaded?.items.count, 1)
        XCTAssertEqual(loaded?.dataSource, .localFallback)
        XCTAssertEqual(loaded?.dataSourceDetails, "Использован локальный каталог.")
    }

    func testTodayMenuSnapshotLegacyPayloadDecodesWithoutSourceMetadata() throws {
        let defaults = UserDefaults(suiteName: "MealPlanSnapshotStoreTests.today.legacy")!
        defaults.removePersistentDomain(forName: "MealPlanSnapshotStoreTests.today.legacy")

        let legacyJSON = """
        {
          "generatedAt": "2026-02-17T12:00:00Z",
          "items": [
            {
              "mealType": "lunch",
              "title": "Курица с рисом",
              "kcal": 520
            }
          ],
          "estimatedCost": 320
        }
        """

        defaults.set(legacyJSON.data(using: .utf8), forKey: "today_menu")
        let store = TodayMenuSnapshotStore(userDefaults: defaults, key: "today_menu")

        let loaded = store.load()

        XCTAssertEqual(loaded?.items.first?.title, "Курица с рисом")
        XCTAssertNil(loaded?.dataSource)
        XCTAssertNil(loaded?.dataSourceDetails)
    }

    func testMealPlanSnapshotStoreRoundtrip() {
        let defaults = UserDefaults(suiteName: "MealPlanSnapshotStoreTests.plan.roundtrip")!
        defaults.removePersistentDomain(forName: "MealPlanSnapshotStoreTests.plan.roundtrip")

        let store = MealPlanSnapshotStore(userDefaults: defaults, key: "plan_snapshot")
        let snapshot = MealPlanSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            rangeRawValue: "week",
            dataSource: .serverSmart,
            dataSourceDetails: "План собран smart-оптимизатором сервера.",
            plan: samplePlan()
        )

        store.save(snapshot)
        let loaded = store.load()

        XCTAssertEqual(loaded?.rangeRawValue, "week")
        XCTAssertEqual(loaded?.dataSource, .serverSmart)
        XCTAssertEqual(loaded?.plan.days.count, 1)
        XCTAssertEqual(loaded?.plan.days.first?.entries.first?.recipe.title, "Омлет")
    }

    private func samplePlan() -> MealPlanGenerateResponse {
        let recipe = Recipe(
            id: "r_1",
            sourceURL: URL(string: "https://example.com/r1")!,
            sourceName: "Test",
            title: "Омлет",
            imageURL: URL(string: "https://example.com/r1.jpg")!,
            videoURL: nil,
            ingredients: ["яйца", "молоко"],
            instructions: ["Взбить", "Обжарить"],
            totalTimeMinutes: 10,
            servings: 2,
            cuisine: "домашняя",
            tags: ["завтрак"],
            nutrition: .init(kcal: 380, protein: 24, fat: 22, carbs: 13)
        )

        let day = MealPlanGenerateResponse.Day(
            date: "2026-02-17",
            entries: [
                .init(mealType: "breakfast", recipe: recipe, score: 0.91, estimatedCost: 180, kcal: 380)
            ],
            totals: .init(kcal: 380, estimatedCost: 180),
            targets: .init(kcal: 1_900, perMealKcal: 633),
            missingIngredients: ["яйца"]
        )

        return MealPlanGenerateResponse(
            days: [day],
            shoppingList: ["яйца"],
            estimatedTotalCost: 180,
            warnings: []
        )
    }
}
