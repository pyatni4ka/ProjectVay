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

struct AdaptiveNutritionUseCase {
    enum PlanRange {
        case day
        case week
    }

    enum MealSlot: String, Codable {
        case breakfast
        case lunch
        case dinner

        var title: String {
            switch self {
            case .breakfast: return "Завтрак"
            case .lunch: return "Обед"
            case .dinner: return "Ужин"
            }
        }

        var remainingMealsCount: Int {
            switch self {
            case .breakfast: return 3
            case .lunch: return 2
            case .dinner: return 1
            }
        }

        static func next(for date: Date, schedule: AppSettings.MealSchedule) -> MealSlot {
            let calendar = Calendar.current
            let minute = (calendar.component(.hour, from: date) * 60) + calendar.component(.minute, from: date)
            let normalized = schedule.normalized()

            if minute < normalized.breakfastMinute {
                return .breakfast
            }
            if minute < normalized.lunchMinute {
                return .lunch
            }
            if minute < normalized.dinnerMinute {
                return .dinner
            }

            return .breakfast
        }
    }

    struct Input {
        var settings: AppSettings
        var range: PlanRange
        var now: Date = Date()
        var automaticDailyCalories: Double?
        var weightKG: Double?
        var consumedNutrition: Nutrition?
        var consumedFetchFailed: Bool
        var healthIntegrationEnabled: Bool = true
    }

    struct Output {
        let baselineDayTarget: Nutrition
        let planDayTarget: Nutrition
        let consumedToday: Nutrition
        let remainingToday: Nutrition
        let nextMealTarget: Nutrition
        let nextMealSlot: MealSlot
        let remainingMealsCount: Int
        let statusMessage: String
    }

    func execute(_ input: Input) -> Output {
        let nextMealSlot = MealSlot.next(for: input.now, schedule: input.settings.mealSchedule)
        let remainingMealsCount = max(1, nextMealSlot.remainingMealsCount)

        let baselineTarget: Nutrition
        let sourceMessage: String
        switch input.settings.macroGoalSource {
        case .automatic:
            let baselineKcal = max(900, input.automaticDailyCalories ?? 2100)
            baselineTarget = nutritionForTargetKcal(baselineKcal, weightKG: input.weightKG)
            sourceMessage = "Используется автоматический расчёт КБЖУ."
        case .manual:
            baselineTarget = manualGoal(from: input.settings)
            sourceMessage = "Используется ручная цель КБЖУ."
        }

        let consumedToday = normalizeNutrition(input.consumedNutrition ?? .empty)
        let hasConsumedData = [consumedToday.kcal, consumedToday.protein, consumedToday.fat, consumedToday.carbs]
            .contains { ($0 ?? 0) > 0 }

        let healthMessage: String
        if !input.healthIntegrationEnabled {
            healthMessage = "Доступ к Apple Health отключен в настройках."
        } else if hasConsumedData {
            healthMessage = "Учтено съеденное за сегодня из Apple Health."
        } else if input.consumedFetchFailed {
            healthMessage = "Не удалось получить КБЖУ за сегодня из Apple Health."
        } else {
            healthMessage = "Apple Health не вернул КБЖУ за сегодня."
        }

        let remainingToday = subtractNutrition(baselineTarget, consumedToday)
        let nextMealTarget = divideNutrition(remainingToday, by: Double(remainingMealsCount))
        let planDayTarget = input.range == .day ? remainingToday : baselineTarget

        return Output(
            baselineDayTarget: baselineTarget,
            planDayTarget: planDayTarget,
            consumedToday: consumedToday,
            remainingToday: remainingToday,
            nextMealTarget: nextMealTarget,
            nextMealSlot: nextMealSlot,
            remainingMealsCount: remainingMealsCount,
            statusMessage: "\(sourceMessage) \(healthMessage) Остаток делится на \(remainingMealsCount) приём(а)."
        )
    }

    private func manualGoal(from settings: AppSettings) -> Nutrition {
        var kcal = max(900, settings.kcalGoal ?? 2000)
        let protein = max(0, settings.proteinGoalGrams ?? 110)
        let fat = max(0, settings.fatGoalGrams ?? 65)

        let carbs: Double
        if let manualCarbs = settings.carbsGoalGrams {
            carbs = max(0, manualCarbs)
        } else {
            carbs = max(80, (kcal - protein * 4 - fat * 9) / 4)
        }

        let requiredKcal = protein * 4 + fat * 9 + carbs * 4
        kcal = max(kcal, requiredKcal)

        return Nutrition(kcal: kcal, protein: protein, fat: fat, carbs: carbs)
    }

    private func nutritionForTargetKcal(_ kcal: Double, weightKG: Double?) -> Nutrition {
        let baseKcal = max(900, kcal)

        let protein: Double
        if let weightKG {
            protein = min(max(weightKG * 1.8, 90), 220)
        } else {
            protein = max(90, baseKcal * 0.28 / 4)
        }

        let fat: Double
        if let weightKG {
            fat = min(max(weightKG * 0.8, 45), 120)
        } else {
            fat = max(45, baseKcal * 0.28 / 9)
        }

        let minCarbs = 80.0
        let minRequiredKcal = protein * 4 + fat * 9 + minCarbs * 4
        let adjustedKcal = max(baseKcal, minRequiredKcal)
        let carbs = max(minCarbs, (adjustedKcal - protein * 4 - fat * 9) / 4)

        return Nutrition(kcal: adjustedKcal, protein: protein, fat: fat, carbs: carbs)
    }

    private func normalizeNutrition(_ value: Nutrition) -> Nutrition {
        Nutrition(
            kcal: max(0, value.kcal ?? 0),
            protein: max(0, value.protein ?? 0),
            fat: max(0, value.fat ?? 0),
            carbs: max(0, value.carbs ?? 0)
        )
    }

    private func subtractNutrition(_ left: Nutrition, _ right: Nutrition) -> Nutrition {
        Nutrition(
            kcal: max(0, resolved(left.kcal) - resolved(right.kcal)),
            protein: max(0, resolved(left.protein) - resolved(right.protein)),
            fat: max(0, resolved(left.fat) - resolved(right.fat)),
            carbs: max(0, resolved(left.carbs) - resolved(right.carbs))
        )
    }

    private func divideNutrition(_ value: Nutrition, by divisor: Double) -> Nutrition {
        let safeDivisor = max(divisor, 1)
        return Nutrition(
            kcal: resolved(value.kcal) / safeDivisor,
            protein: resolved(value.protein) / safeDivisor,
            fat: resolved(value.fat) / safeDivisor,
            carbs: resolved(value.carbs) / safeDivisor
        )
    }

    private func resolved(_ value: Double?) -> Double {
        max(0, value ?? 0)
    }
}
