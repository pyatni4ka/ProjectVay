import XCTest
@testable import InventoryCore

final class LocalRecipeCatalogTests: XCTestCase {
    func testDefaultCatalogLoadsSeedDatasetWhenAvailable() {
        let catalog = LocalRecipeCatalog()

        XCTAssertGreaterThan(catalog.recipes.count, 100)
    }

    func testSearchMatchesByTitleAndIngredient() {
        let catalog = LocalRecipeCatalog(recipes: [
            makeRecipe(
                id: "r1",
                title: "Курица с рисом",
                ingredients: ["куриное филе", "рис", "морковь"],
                nutrition: Nutrition(kcal: 520, protein: 35, fat: 14, carbs: 58)
            ),
            makeRecipe(
                id: "r2",
                title: "Овсяная каша",
                ingredients: ["овсянка", "молоко"],
                nutrition: Nutrition(kcal: 320, protein: 14, fat: 9, carbs: 44)
            )
        ], sourceLabel: "test")

        let byTitle = catalog.search(query: "каша")
        let byIngredient = catalog.search(query: "морковь")

        XCTAssertEqual(byTitle.first?.id, "r2")
        XCTAssertEqual(byIngredient.first?.id, "r1")
    }

    func testRecommendRespectsExcludeAndLimit() {
        let catalog = LocalRecipeCatalog(recipes: [
            makeRecipe(
                id: "r1",
                title: "Паста с сыром",
                ingredients: ["макароны", "сыр"],
                nutrition: Nutrition(kcal: 610, protein: 22, fat: 24, carbs: 72)
            ),
            makeRecipe(
                id: "r2",
                title: "Гречка с индейкой",
                ingredients: ["гречка", "индейка", "лук"],
                nutrition: Nutrition(kcal: 470, protein: 33, fat: 12, carbs: 49)
            )
        ], sourceLabel: "test")

        let response = catalog.recommend(payload: RecommendRequest(
            ingredientKeywords: ["гречка", "индейка"],
            expiringSoonKeywords: [],
            targets: Nutrition(kcal: 500, protein: 30, fat: 15, carbs: 55),
            budget: .init(perMeal: 300),
            exclude: ["сыр"],
            avoidBones: false,
            cuisine: [],
            limit: 1,
            strictNutrition: true,
            macroTolerancePercent: 40
        ))

        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items.first?.recipe.id, "r2")
    }

    func testGenerateMealPlanBuildsDaysAndShoppingList() {
        let catalog = LocalRecipeCatalog(recipes: [
            makeRecipe(
                id: "r1",
                title: "Завтрак",
                ingredients: ["яйца", "хлеб"],
                nutrition: Nutrition(kcal: 380, protein: 24, fat: 15, carbs: 34)
            ),
            makeRecipe(
                id: "r2",
                title: "Обед",
                ingredients: ["курица", "рис"],
                nutrition: Nutrition(kcal: 560, protein: 40, fat: 17, carbs: 61)
            ),
            makeRecipe(
                id: "r3",
                title: "Ужин",
                ingredients: ["творог", "яблоко"],
                nutrition: Nutrition(kcal: 430, protein: 29, fat: 16, carbs: 42)
            )
        ], sourceLabel: "test")

        let plan = catalog.generateMealPlan(payload: MealPlanGenerateRequest(
            days: 2,
            ingredientKeywords: ["яйца", "рис"],
            expiringSoonKeywords: ["яйца"],
            targets: Nutrition(kcal: 1800, protein: 120, fat: 60, carbs: 180),
            beveragesKcal: 120,
            budget: .init(perDay: 1_000, perMeal: nil),
            exclude: [],
            avoidBones: false,
            cuisine: []
        ))

        XCTAssertEqual(plan.days.count, 2)
        XCTAssertTrue(plan.days.allSatisfy { !$0.entries.isEmpty })
        XCTAssertGreaterThan(plan.estimatedTotalCost, 0)
        XCTAssertTrue(plan.warnings.contains { $0.contains("локально") })
        XCTAssertFalse(plan.shoppingList.isEmpty)
    }

    func testGenerateSmartPlanContainsPriceExplanation() {
        let catalog = LocalRecipeCatalog(recipes: [
            makeRecipe(
                id: "r1",
                title: "Чаша с курицей",
                ingredients: ["курица", "рис", "овощи"],
                nutrition: Nutrition(kcal: 520, protein: 35, fat: 15, carbs: 57)
            )
        ], sourceLabel: "test")

        let smart = catalog.generateSmartMealPlan(payload: SmartMealPlanGenerateRequest(
            days: 1,
            ingredientKeywords: ["курица"],
            expiringSoonKeywords: [],
            targets: Nutrition(kcal: 1700, protein: 110, fat: 60, carbs: 170),
            beveragesKcal: 0,
            budget: .init(perDay: 900, perMeal: nil),
            exclude: [],
            avoidBones: false,
            cuisine: [],
            objective: "cost_macro",
            optimizerProfile: "balanced",
            macroTolerancePercent: 25,
            ingredientPriceHints: nil
        ))

        XCTAssertFalse(smart.days.isEmpty)
        XCTAssertFalse(smart.priceExplanation.isEmpty)
        XCTAssertEqual(smart.objective, "cost_macro")
    }

    func testMergingAdditionalRecipesPrefersAdditionalVersionAndDeduplicatesByID() {
        let base = LocalRecipeCatalog(recipes: [
            makeRecipe(
                id: "r1",
                title: "База: Омлет",
                ingredients: ["яйца", "молоко"],
                nutrition: Nutrition(kcal: 300, protein: 19, fat: 21, carbs: 4)
            ),
            makeRecipe(
                id: "r2",
                title: "База: Суп",
                ingredients: ["курица", "лук"],
                nutrition: Nutrition(kcal: 350, protein: 26, fat: 17, carbs: 12)
            )
        ], sourceLabel: "base")

        let merged = base.merging(additionalRecipes: [
            makeRecipe(
                id: "r1",
                title: "Сеть: Омлет с зеленью",
                ingredients: ["яйца", "молоко", "укроп"],
                nutrition: Nutrition(kcal: 320, protein: 20, fat: 23, carbs: 5)
            ),
            makeRecipe(
                id: "r3",
                title: "Сеть: Тост с авокадо",
                ingredients: ["хлеб", "авокадо"],
                nutrition: Nutrition(kcal: 410, protein: 10, fat: 20, carbs: 43)
            )
        ], sourceLabel: "merged")

        XCTAssertEqual(merged.recipes.count, 3)
        XCTAssertEqual(merged.sourceLabel, "merged")
        XCTAssertEqual(merged.recipes.first(where: { $0.id == "r1" })?.title, "Сеть: Омлет с зеленью")
        XCTAssertEqual(merged.search(query: "авокадо").first?.id, "r3")
    }

    private func makeRecipe(
        id: String,
        title: String,
        ingredients: [String],
        nutrition: Nutrition
    ) -> Recipe {
        Recipe(
            id: id,
            sourceURL: URL(string: "https://example.com/\(id)")!,
            sourceName: "test",
            title: title,
            imageURL: URL(string: "https://example.com/\(id).jpg")!,
            videoURL: nil,
            ingredients: ingredients,
            instructions: ["Шаг 1", "Шаг 2"],
            totalTimeMinutes: 20,
            servings: 2,
            cuisine: "домашняя",
            tags: ["тест"],
            nutrition: nutrition
        )
    }
}
