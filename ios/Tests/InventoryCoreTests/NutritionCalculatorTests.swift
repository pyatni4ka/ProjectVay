import XCTest
@testable import InventoryCore

final class NutritionCalculatorTests: XCTestCase {

    // MARK: - BMR (Mifflin–St Jeor)

    func testBMR_Male_80kg_180cm_30yo() {
        let input = NutritionCalculator.Input(
            weightKg: 80,
            heightCm: 180,
            ageYears: 30,
            isMale: true,
            activityLevel: .sedentary,
            goal: .maintain
        )
        let result = NutritionCalculator.calculate(input: input)!
        // BMR = 10*80 + 6.25*180 - 5*30 + 5 = 800 + 1125 - 150 + 5 = 1780
        XCTAssertEqual(result.bmr, 1780, accuracy: 1)
    }

    func testBMR_Female_60kg_165cm_25yo() {
        let input = NutritionCalculator.Input(
            weightKg: 60,
            heightCm: 165,
            ageYears: 25,
            isMale: false,
            activityLevel: .sedentary,
            goal: .maintain
        )
        let result = NutritionCalculator.calculate(input: input)!
        // BMR = 10*60 + 6.25*165 - 5*25 - 161 = 600 + 1031.25 - 125 - 161 = 1345.25
        XCTAssertEqual(result.bmr, 1345, accuracy: 1)
    }

    // MARK: - TDEE

    func testTDEE_SedentaryMale() {
        let input = NutritionCalculator.Input(
            weightKg: 80, heightCm: 180, ageYears: 30,
            isMale: true, activityLevel: .sedentary, goal: .maintain
        )
        let result = NutritionCalculator.calculate(input: input)!
        // TDEE = 1780 * 1.2 = 2136
        XCTAssertEqual(result.tdee, 2136, accuracy: 1)
    }

    func testTDEE_ModeratelyActiveFemale() {
        let input = NutritionCalculator.Input(
            weightKg: 60, heightCm: 165, ageYears: 25,
            isMale: false, activityLevel: .moderatelyActive, goal: .maintain
        )
        let result = NutritionCalculator.calculate(input: input)!
        // TDEE = 1345.25 * 1.55 ≈ 2085
        XCTAssertEqual(result.tdee, 2085, accuracy: 2)
    }

    // MARK: - Target Calories

    func testTargetKcal_Lose_500Deficit() {
        let input = NutritionCalculator.Input(
            weightKg: 80, heightCm: 180, ageYears: 30,
            isMale: true, activityLevel: .moderatelyActive, goal: .lose
        )
        let result = NutritionCalculator.calculate(input: input)!
        // TDEE = 1780 * 1.55 = 2759, target = 2759 - 500 = 2259
        XCTAssertEqual(result.tdee, 2759, accuracy: 1)
        XCTAssertEqual(result.targetKcal, 2259, accuracy: 1)
        XCTAssertEqual(result.deficitKcal, -500, accuracy: 1)
    }

    func testTargetKcal_LoseFloor_NeverBelowBMR_1_1() {
        // Light female with sedentary lifestyle — deficit could push below BMR*1.1
        let input = NutritionCalculator.Input(
            weightKg: 45, heightCm: 155, ageYears: 50,
            isMale: false, activityLevel: .sedentary, goal: .lose
        )
        let result = NutritionCalculator.calculate(input: input)!
        // BMR = 10*45 + 6.25*155 - 5*50 - 161 = 450 + 968.75 - 250 - 161 = 1007.75
        // BMR*1.1 = 1108.5
        // TDEE = 1007.75 * 1.2 = 1209.3
        // rawTarget = 1209 - 500 = 709 → floor is BMR*1.1 ≈ 1109
        XCTAssertGreaterThanOrEqual(result.targetKcal, result.bmr * 1.1 - 1)
    }

    func testTargetKcal_Maintain_EqualsTDEE() {
        let input = NutritionCalculator.Input(
            weightKg: 70, heightCm: 175, ageYears: 35,
            isMale: true, activityLevel: .lightlyActive, goal: .maintain
        )
        let result = NutritionCalculator.calculate(input: input)!
        XCTAssertEqual(result.targetKcal, result.tdee, accuracy: 1)
    }

    func testTargetKcal_Gain_Plus400() {
        let input = NutritionCalculator.Input(
            weightKg: 70, heightCm: 175, ageYears: 25,
            isMale: true, activityLevel: .moderatelyActive, goal: .gain
        )
        let result = NutritionCalculator.calculate(input: input)!
        XCTAssertEqual(result.targetKcal, result.tdee + 400, accuracy: 1)
    }

    // MARK: - Macros (ISSN 2017)

    func testProtein_Lose_2gPerKg() {
        let input = NutritionCalculator.Input(
            weightKg: 80, heightCm: 180, ageYears: 30,
            isMale: true, activityLevel: .moderatelyActive, goal: .lose
        )
        let result = NutritionCalculator.calculate(input: input)!
        // Protein = 2.0 * 80 = 160g
        XCTAssertEqual(result.proteinGrams, 160, accuracy: 1)
    }

    func testProtein_Maintain_1_6gPerKg() {
        let input = NutritionCalculator.Input(
            weightKg: 70, heightCm: 175, ageYears: 30,
            isMale: true, activityLevel: .moderatelyActive, goal: .maintain
        )
        let result = NutritionCalculator.calculate(input: input)!
        // Protein = 1.6 * 70 = 112g
        XCTAssertEqual(result.proteinGrams, 112, accuracy: 1)
    }

    func testProtein_Gain_1_8gPerKg() {
        let input = NutritionCalculator.Input(
            weightKg: 75, heightCm: 178, ageYears: 28,
            isMale: true, activityLevel: .veryActive, goal: .gain
        )
        let result = NutritionCalculator.calculate(input: input)!
        // Protein = 1.8 * 75 = 135g
        XCTAssertEqual(result.proteinGrams, 135, accuracy: 1)
    }

    func testFat_MinimumHalfGramPerKg() {
        // Very low calorie scenario where 30% fat could be less than 0.5 g/kg
        let input = NutritionCalculator.Input(
            weightKg: 100, heightCm: 170, ageYears: 40,
            isMale: true, activityLevel: .sedentary, goal: .lose
        )
        let result = NutritionCalculator.calculate(input: input)!
        // Fat should be at least 0.5 * 100 = 50g
        XCTAssertGreaterThanOrEqual(result.fatGrams, 50 - 1)
    }

    func testCarbs_AreRemainder() {
        let input = NutritionCalculator.Input(
            weightKg: 80, heightCm: 180, ageYears: 30,
            isMale: true, activityLevel: .moderatelyActive, goal: .maintain
        )
        let result = NutritionCalculator.calculate(input: input)!
        let reconstructed = result.proteinGrams * 4 + result.fatGrams * 9 + result.carbsGrams * 4
        XCTAssertEqual(reconstructed, result.targetKcal, accuracy: 15)
    }

    // MARK: - Validation

    func testReturnsNil_ForInvalidWeight() {
        let input = NutritionCalculator.Input(
            weightKg: 10, heightCm: 170, ageYears: 30,
            isMale: true, activityLevel: .sedentary, goal: .maintain
        )
        XCTAssertNil(NutritionCalculator.calculate(input: input))
    }

    func testReturnsNil_ForInvalidHeight() {
        let input = NutritionCalculator.Input(
            weightKg: 70, heightCm: 100, ageYears: 30,
            isMale: true, activityLevel: .sedentary, goal: .maintain
        )
        XCTAssertNil(NutritionCalculator.calculate(input: input))
    }

    func testReturnsNil_ForInvalidAge() {
        let input = NutritionCalculator.Input(
            weightKg: 70, heightCm: 170, ageYears: 5,
            isMale: true, activityLevel: .sedentary, goal: .maintain
        )
        XCTAssertNil(NutritionCalculator.calculate(input: input))
    }

    // MARK: - Custom Overrides

    func testCustomProtein_IsRespected() {
        let input = NutritionCalculator.Input(
            weightKg: 80, heightCm: 180, ageYears: 30,
            isMale: true, activityLevel: .moderatelyActive, goal: .lose,
            customProteinGPerKg: 2.5
        )
        let result = NutritionCalculator.calculate(input: input)!
        // Custom: 2.5 * 80 = 200g
        XCTAssertEqual(result.proteinGrams, 200, accuracy: 1)
    }

    func testCustomFatFraction_IsRespected() {
        let input = NutritionCalculator.Input(
            weightKg: 80, heightCm: 180, ageYears: 30,
            isMale: true, activityLevel: .moderatelyActive, goal: .maintain,
            customFatFraction: 0.25
        )
        let result = NutritionCalculator.calculate(input: input)!
        let expectedFatFromFraction = (result.targetKcal * 0.25 / 9).rounded()
        let fatMin = (0.5 * 80).rounded()
        XCTAssertEqual(result.fatGrams, max(expectedFatFromFraction, fatMin), accuracy: 1)
    }

    // MARK: - Explanation

    func testExplanation_ContainsMifflinStJeor() {
        let input = NutritionCalculator.Input(
            weightKg: 70, heightCm: 170, ageYears: 30,
            isMale: true, activityLevel: .sedentary, goal: .maintain
        )
        let result = NutritionCalculator.calculate(input: input)!
        XCTAssertTrue(result.explanation.bmrFormula.contains("Mifflin"))
    }
}
