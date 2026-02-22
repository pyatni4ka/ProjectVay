import XCTest
@testable import InventoryCore

final class AdaptiveNutritionUseCaseTests: XCTestCase {
    private let useCase = AdaptiveNutritionUseCase()

    func testAutomaticModeUsesHealthTargetsAndConsumedNutrition() {
        var settings = AppSettings.default
        settings.macroGoalSource = .automatic

        let output = useCase.execute(
            .init(
                settings: settings,
                range: .day,
                now: date(hour: 10, minute: 0),
                baselineTarget: Nutrition(kcal: 2400, protein: 120, fat: 80, carbs: 300),
                consumedNutrition: Nutrition(kcal: 500, protein: 40, fat: 15, carbs: 35),
                consumedFetchFailed: false
            )
        )

        XCTAssertEqual(output.nextMealSlot, .lunch)
        XCTAssertEqual(output.remainingMealsCount, 2)
        XCTAssertEqual(output.baselineDayTarget.kcal ?? 0, 2400, accuracy: 0.001)
        XCTAssertEqual(output.remainingToday.kcal ?? 0, 1900, accuracy: 0.001)
        XCTAssertEqual(output.planDayTarget.kcal ?? 0, 1900, accuracy: 0.001)
        XCTAssertEqual(output.nextMealTarget.kcal ?? 0, 950, accuracy: 0.001)
    }

    func testAutomaticModeFallsBackWhenHealthCaloriesUnavailable() {
        var settings = AppSettings.default
        settings.macroGoalSource = .automatic

        let output = useCase.execute(
            .init(
                settings: settings,
                range: .day,
                now: date(hour: 8, minute: 0),
                baselineTarget: Nutrition(kcal: 2100, protein: 100, fat: 70, carbs: 260),
                consumedNutrition: nil,
                consumedFetchFailed: true
            )
        )

        XCTAssertEqual(output.baselineDayTarget.kcal ?? 0, 2100, accuracy: 0.001)
        XCTAssertTrue(output.statusMessage.contains("автоматический расчёт"))
        XCTAssertTrue(output.statusMessage.contains("Не удалось получить КБЖУ"))
    }

    func testManualModeUsesManualGoals() {
        let settings = AppSettings(
            quietStartMinute: 60,
            quietEndMinute: 360,
            expiryAlertsDays: [5, 3, 1],
            budgetPrimaryValue: 5600,
            budgetInputPeriod: .week,
            stores: AppSettings.defaultStores,
            dislikedList: [],
            avoidBones: false,
            mealSchedule: .default,
            strictMacroTracking: true,
            macroTolerancePercent: 25,
            macroGoalSource: .manual,
            kcalGoal: 1800,
            proteinGoalGrams: 130,
            fatGoalGrams: 60,
            carbsGoalGrams: 140
        )

        let output = useCase.execute(
            .init(
                settings: settings,
                range: .week,
                now: date(hour: 20, minute: 30),
                baselineTarget: Nutrition(kcal: 1800, protein: 130, fat: 60, carbs: 140),
                consumedNutrition: Nutrition(kcal: 200, protein: 10, fat: 5, carbs: 10),
                consumedFetchFailed: false
            )
        )

        XCTAssertEqual(output.baselineDayTarget.kcal ?? 0, 1800, accuracy: 0.001)
        XCTAssertEqual(output.baselineDayTarget.protein ?? 0, 130, accuracy: 0.001)
        XCTAssertEqual(output.baselineDayTarget.fat ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(output.baselineDayTarget.carbs ?? 0, 140, accuracy: 0.001)
        XCTAssertEqual(output.planDayTarget.kcal ?? 0, 1800, accuracy: 0.001)
        XCTAssertTrue(output.statusMessage.contains("ручная цель"))
    }

    func testNextMealTargetIsCalculatedFromRemainingMeals() {
        var settings = AppSettings.default
        settings.macroGoalSource = .manual
        settings.kcalGoal = 2100
        settings.proteinGoalGrams = 120
        settings.fatGoalGrams = 70
        settings.carbsGoalGrams = 220

        let output = useCase.execute(
            .init(
                settings: settings,
                range: .day,
                now: date(hour: 7, minute: 30),
                baselineTarget: Nutrition(kcal: 2100, protein: 120, fat: 70, carbs: 220),
                consumedNutrition: Nutrition(kcal: 600, protein: 30, fat: 20, carbs: 60),
                consumedFetchFailed: false
            )
        )

        XCTAssertEqual(output.nextMealSlot, .breakfast)
        XCTAssertEqual(output.remainingMealsCount, 3)
        XCTAssertEqual(output.remainingToday.kcal ?? 0, 1500, accuracy: 0.001)
        XCTAssertEqual(output.nextMealTarget.kcal ?? 0, 500, accuracy: 0.001)
    }

    func testManualModeIgnoresAutomaticCaloriesEvenWithExtremeDietProfile() {
        var settings = AppSettings.default
        settings.macroGoalSource = .manual
        settings.dietProfile = .extreme
        settings.kcalGoal = 1750
        settings.proteinGoalGrams = 120
        settings.fatGoalGrams = 55
        settings.carbsGoalGrams = 150

        let output = useCase.execute(
            .init(
                settings: settings,
                range: .day,
                now: date(hour: 12, minute: 0),
                baselineTarget: Nutrition(kcal: 1750, protein: 120, fat: 55, carbs: 150),
                consumedNutrition: Nutrition(kcal: 300, protein: 20, fat: 10, carbs: 25),
                consumedFetchFailed: false
            )
        )

        XCTAssertEqual(output.baselineDayTarget.kcal ?? 0, 1750, accuracy: 0.001)
        XCTAssertEqual(output.planDayTarget.kcal ?? 0, 1450, accuracy: 0.001)
        XCTAssertTrue(output.statusMessage.contains("ручная цель"))
    }

    private func date(hour: Int, minute: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 15
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }
}
