import XCTest
@testable import InventoryCore

final class MacroRecommendationFilterUseCaseTests: XCTestCase {
    private let useCase = MacroRecommendationFilterUseCase()

    func testStrictTrackingReturnsOnlyMatchingRecipes() {
        let target = Nutrition(kcal: 600, protein: 40, fat: 20, carbs: 60)
        let items = [
            rankedRecipe(id: "close", nutrition: Nutrition(kcal: 590, protein: 38, fat: 20, carbs: 62)),
            rankedRecipe(id: "far", nutrition: Nutrition(kcal: 900, protein: 10, fat: 50, carbs: 120))
        ]

        let result = useCase.execute(
            items: items,
            target: target,
            strictTracking: true,
            tolerancePercent: 25,
            strictAppliedNote: "strict",
            fallbackNote: "fallback",
            fallbackLimit: 10
        )

        XCTAssertEqual(result.items.map(\.recipe.id), ["close"])
        XCTAssertEqual(result.note, "strict")
    }

    func testStrictTrackingFallsBackToClosestWhenNoMatches() {
        let target = Nutrition(kcal: 500, protein: 30, fat: 15, carbs: 55)
        let items = [
            rankedRecipe(id: "medium", nutrition: Nutrition(kcal: 650, protein: 26, fat: 24, carbs: 70)),
            rankedRecipe(id: "far", nutrition: Nutrition(kcal: 900, protein: 12, fat: 48, carbs: 130))
        ]

        let result = useCase.execute(
            items: items,
            target: target,
            strictTracking: true,
            tolerancePercent: 10,
            strictAppliedNote: "strict",
            fallbackNote: "fallback",
            fallbackLimit: 1
        )

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.recipe.id, "medium")
        XCTAssertEqual(result.note, "fallback")
    }

    func testNonStrictTrackingKeepsOriginalOrder() {
        let items = [
            rankedRecipe(id: "first", nutrition: Nutrition(kcal: 750, protein: 25, fat: 28, carbs: 80)),
            rankedRecipe(id: "second", nutrition: Nutrition(kcal: 500, protein: 35, fat: 14, carbs: 55))
        ]

        let result = useCase.execute(
            items: items,
            target: Nutrition(kcal: 550, protein: 35, fat: 16, carbs: 55),
            strictTracking: false,
            tolerancePercent: 5,
            strictAppliedNote: "strict",
            fallbackNote: "fallback",
            fallbackLimit: 1
        )

        XCTAssertEqual(result.items.map(\.recipe.id), ["first", "second"])
        XCTAssertNil(result.note)
    }

    private func rankedRecipe(id: String, nutrition: Nutrition) -> RecommendResponse.RankedRecipe {
        .init(
            recipe: Recipe(
                id: id,
                sourceURL: URL(string: "https://example.com/\(id)")!,
                sourceName: "example",
                title: id,
                imageURL: URL(string: "https://example.com/\(id).jpg")!,
                videoURL: nil,
                ingredients: ["ингредиент"],
                instructions: ["шаг"],
                totalTimeMinutes: 20,
                servings: 1,
                cuisine: nil,
                tags: [],
                nutrition: nutrition
            ),
            score: 0.5,
            scoreBreakdown: [:]
        )
    }
}
