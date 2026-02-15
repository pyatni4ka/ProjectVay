import Foundation

struct MacroRecommendationFilterResult {
    let items: [RecommendResponse.RankedRecipe]
    let note: String?
}

struct MacroRecommendationFilterUseCase {
    func execute(
        items: [RecommendResponse.RankedRecipe],
        target: Nutrition,
        strictTracking: Bool,
        tolerancePercent: Double,
        strictAppliedNote: String,
        fallbackNote: String,
        fallbackLimit: Int
    ) -> MacroRecommendationFilterResult {
        guard !items.isEmpty else {
            return MacroRecommendationFilterResult(items: items, note: nil)
        }

        guard strictTracking else {
            return MacroRecommendationFilterResult(items: items, note: nil)
        }

        let tolerance = min(max(tolerancePercent, 5), 60) / 100
        let sortedByMacroDistance = items.sorted {
            macroDistance(recipeNutrition: $0.recipe.nutrition, target: target) <
                macroDistance(recipeNutrition: $1.recipe.nutrition, target: target)
        }

        let strict = sortedByMacroDistance.filter {
            isWithinTolerance(recipeNutrition: $0.recipe.nutrition, target: target, tolerance: tolerance)
        }

        if !strict.isEmpty {
            return MacroRecommendationFilterResult(items: strict, note: strictAppliedNote)
        }

        let safeLimit = max(1, fallbackLimit)
        return MacroRecommendationFilterResult(
            items: Array(sortedByMacroDistance.prefix(safeLimit)),
            note: fallbackNote
        )
    }

    private func isWithinTolerance(recipeNutrition: Nutrition?, target: Nutrition, tolerance: Double) -> Bool {
        guard let recipeNutrition else { return false }

        let checks: [(Double?, Double?)] = [
            (target.kcal, recipeNutrition.kcal),
            (target.protein, recipeNutrition.protein),
            (target.fat, recipeNutrition.fat),
            (target.carbs, recipeNutrition.carbs)
        ]

        for (targetValue, actualValue) in checks {
            guard let targetValue, targetValue > 0 else {
                continue
            }
            guard let actualValue, actualValue >= 0 else {
                return false
            }

            let deviation = abs(actualValue - targetValue) / max(targetValue, 1)
            if deviation > tolerance {
                return false
            }
        }

        return true
    }

    private func macroDistance(recipeNutrition: Nutrition?, target: Nutrition) -> Double {
        guard let recipeNutrition else {
            return 10
        }

        let checks: [(Double?, Double?)] = [
            (target.kcal, recipeNutrition.kcal),
            (target.protein, recipeNutrition.protein),
            (target.fat, recipeNutrition.fat),
            (target.carbs, recipeNutrition.carbs)
        ]

        var sum = 0.0
        var count = 0.0
        for (targetValue, actualValue) in checks {
            guard let targetValue, targetValue > 0 else {
                continue
            }
            guard let actualValue else {
                return 9
            }
            let deviation = abs(actualValue - targetValue) / max(targetValue, 1)
            sum += deviation
            count += 1
        }

        guard count > 0 else { return 8 }
        return sum / count
    }
}
