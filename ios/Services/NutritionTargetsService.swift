import Foundation

/// Single source of truth for nutrition targets (KCAL/P/F/C).
/// Wraps NutritionCalculator and maps AppSettings → consistent targets.
/// All screens must use this service instead of computing targets independently.
enum NutritionTargetsService {

    struct BodyMetrics {
        var weightKg: Double
        var heightCm: Double
        var ageYears: Int
        var isMale: Bool
    }

    struct Targets {
        let kcal: Double
        let proteinGrams: Double
        let fatGrams: Double
        let carbsGrams: Double
        let bmr: Double
        let tdee: Double
        let deficitKcal: Double
        let explanation: NutritionCalculator.Explanation

        var asNutrition: Nutrition {
            Nutrition(kcal: kcal, protein: proteinGrams, fat: fatGrams, carbs: carbsGrams)
        }
    }

    /// Compute nutrition targets from settings and body metrics.
    /// Returns nil if body metrics are insufficient for calculation.
    static func computeTargets(
        settings: AppSettings,
        metrics: BodyMetrics?
    ) -> Targets? {
        guard let metrics else { return nil }

        let goal = mapGoal(settings.dietGoalMode)

        let input = NutritionCalculator.Input(
            weightKg: metrics.weightKg,
            heightCm: metrics.heightCm,
            ageYears: metrics.ageYears,
            isMale: metrics.isMale,
            activityLevel: settings.activityLevel,
            goal: goal
        )

        guard let output = NutritionCalculator.calculate(input: input) else {
            return nil
        }

        return Targets(
            kcal: output.targetKcal,
            proteinGrams: output.proteinGrams,
            fatGrams: output.fatGrams,
            carbsGrams: output.carbsGrams,
            bmr: output.bmr,
            tdee: output.tdee,
            deficitKcal: output.deficitKcal,
            explanation: output.explanation
        )
    }

    /// Compute targets from HealthKit UserMetrics (convenience).
    static func computeTargets(
        settings: AppSettings,
        healthMetrics: HealthKitService.UserMetrics
    ) -> Targets? {
        guard let weight = healthMetrics.weightKG,
              let height = healthMetrics.heightCM,
              let age = healthMetrics.age else { return nil }
        let isMale = healthMetrics.sex?.lowercased().contains("male") ?? true

        return computeTargets(
            settings: settings,
            metrics: BodyMetrics(
                weightKg: weight,
                heightCm: height,
                ageYears: age,
                isMale: isMale
            )
        )
    }

    /// Resolve daily calorie target for the adaptive nutrition pipeline.
    /// Used by AdaptiveNutritionUseCase as the canonical calorie source.
    static func resolveAutomaticDailyCalories(
        settings: AppSettings,
        healthMetrics: HealthKitService.UserMetrics?
    ) -> (kcal: Double, weightKg: Double?) {
        if let healthMetrics,
           let targets = computeTargets(settings: settings, healthMetrics: healthMetrics) {
            return (targets.kcal, healthMetrics.weightKG)
        }

        // Fallback when no HealthKit data: use DietProfile-based estimate.
        let mediumDeficit = 0.5 * 7700.0 / 7.0
        let profileDeficit = settings.targetWeightDeltaPerWeek * 7700.0 / 7.0
        let fallback = max(900, 2100 + (mediumDeficit - profileDeficit))
        return (fallback, nil)
    }

    /// Resolve the fully unified daily nutrition target, acting as the absolute single source of truth.
    /// Used by AdaptiveNutritionUseCase and any UI views that need to display the user's daily goal.
    static func resolveTargetNutrition(
        settings: AppSettings,
        healthMetrics: HealthKitService.UserMetrics?
    ) -> Nutrition {
        switch settings.macroGoalSource {
        case .manual:
            return resolveManualTargets(settings: settings)
        case .automatic:
            if let healthMetrics, let targets = computeTargets(settings: settings, healthMetrics: healthMetrics) {
                return targets.asNutrition
            }
            return computeFallbackNutrition(for: settings)
        }
    }

    /// Map manual goals from settings to Nutrition.
    static func resolveManualTargets(settings: AppSettings) -> Nutrition {
        let kcal = max(900, settings.kcalGoal ?? 2000)
        let protein = max(0, settings.proteinGoalGrams ?? 110)
        let fat = max(0, settings.fatGoalGrams ?? 65)
        let carbsRemainder = max(80, (kcal - protein * 4 - fat * 9) / 4)
        let carbs = settings.carbsGoalGrams.map { max(0, $0) } ?? carbsRemainder
        return Nutrition(kcal: kcal, protein: protein, fat: fat, carbs: carbs)
    }

    private static func computeFallbackNutrition(for settings: AppSettings) -> Nutrition {
        let mediumDeficit = 0.5 * 7700.0 / 7.0
        let profileDeficit = settings.targetWeightDeltaPerWeek * 7700.0 / 7.0
        let baseKcal = max(900, 2100 + (mediumDeficit - profileDeficit))

        let protein = max(90, (baseKcal * 0.28 / 4).rounded())
        
        let fatFromFraction = (baseKcal * 0.30 / 9).rounded()
        let fatMinGrams = (0.5 * 70.0).rounded() // default weight 70kg
        let fat = max(fatFromFraction, fatMinGrams)
        
        let carbsKcal = max(0, baseKcal - protein * 4 - fat * 9)
        let carbs = max(80, (carbsKcal / 4).rounded())
        
        let requiredKcal = protein * 4 + fat * 9 + carbs * 4
        let adjustedKcal = max(baseKcal, requiredKcal)
        
        return Nutrition(kcal: adjustedKcal, protein: protein, fat: fat, carbs: carbs)
    }

    // MARK: - Private

    private static func mapGoal(_ mode: AppSettings.DietGoalMode) -> NutritionCalculator.Goal {
        switch mode {
        case .lose: return .lose
        case .maintain: return .maintain
        case .gain: return .gain
        }
    }
}
