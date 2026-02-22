import Foundation

/// Evidence-based nutrition target calculator.
/// Formulas: Mifflin–St Jeor BMR, TDEE via activity factor, macros per ISSN/WHO guidelines.
/// All results are informational — not medical advice.
enum NutritionCalculator {

    // MARK: - Input / Output

    struct Input {
        var weightKg: Double
        var heightCm: Double
        var ageYears: Int
        var isMale: Bool
        var activityLevel: ActivityLevel
        var goal: Goal
        /// Overrides computed protein target if non-nil.
        var customProteinGPerKg: Double? = nil
        /// Overrides computed fat fraction if non-nil (0.0–1.0).
        var customFatFraction: Double? = nil
    }

    struct Output {
        let bmr: Double          // ккал/сут
        let tdee: Double         // ккал/сут
        let targetKcal: Double   // ккал/сут (с учётом цели)
        let proteinGrams: Double
        let fatGrams: Double
        let carbsGrams: Double
        let deficitKcal: Double  // < 0 значит дефицит
        let explanation: Explanation
    }

    struct Explanation {
        let bmrFormula: String       // e.g. "Mifflin–St Jeor"
        let activityLabel: String
        let goalLabel: String
        let proteinBasis: String
        let disclaimer: String
    }

    // MARK: - Enums

    enum ActivityLevel: String, CaseIterable, Identifiable {
        case sedentary       // desk job, no exercise
        case lightlyActive   // 1-3 days/week
        case moderatelyActive // 3-5 days/week
        case veryActive      // 6-7 days/week
        case extraActive     // twice/day or heavy labour

        var id: String { rawValue }

        var factor: Double {
            switch self {
            case .sedentary:        return 1.2
            case .lightlyActive:    return 1.375
            case .moderatelyActive: return 1.55
            case .veryActive:       return 1.725
            case .extraActive:      return 1.9
            }
        }

        var label: String {
            switch self {
            case .sedentary:        return "Сидячий образ жизни"
            case .lightlyActive:    return "Лёгкая активность (1–3 дня/нед)"
            case .moderatelyActive: return "Умеренная активность (3–5 дней/нед)"
            case .veryActive:       return "Высокая активность (6–7 дней/нед)"
            case .extraActive:      return "Очень высокая (спорт 2 раза/день)"
            }
        }
    }

    enum Goal: String, CaseIterable, Identifiable {
        case lose
        case maintain
        case gain

        var id: String { rawValue }

        var label: String {
            switch self {
            case .lose:     return "Похудение"
            case .maintain: return "Поддержание веса"
            case .gain:     return "Набор массы"
            }
        }

        /// Kcal adjustment relative to TDEE. Negative = deficit.
        func kcalAdjustment(forTDEE tdee: Double) -> Double {
            switch self {
            case .lose:
                return -500
            case .maintain:
                return 0
            case .gain:
                return 400  // Midpoint of 300–500 surplus
            }
        }
    }

    // MARK: - Validation bounds

    private static let minWeight: Double = 30
    private static let maxWeight: Double = 300
    private static let minHeight: Double = 120
    private static let maxHeight: Double = 250
    private static let minAge = 10
    private static let maxAge = 110

    // MARK: - Main calculate function

    static func calculate(input: Input) -> Output? {
        // Sanity guards
        guard (minWeight...maxWeight).contains(input.weightKg),
              (minHeight...maxHeight).contains(input.heightCm),
              (minAge...maxAge).contains(input.ageYears) else {
            return nil
        }

        // Mifflin–St Jeor BMR
        let bmr: Double
        if input.isMale {
            bmr = 10 * input.weightKg + 6.25 * input.heightCm - 5 * Double(input.ageYears) + 5
        } else {
            bmr = 10 * input.weightKg + 6.25 * input.heightCm - 5 * Double(input.ageYears) - 161
        }

        let tdee = (bmr * input.activityLevel.factor).rounded()
        let adjustment = input.goal.kcalAdjustment(forTDEE: tdee)
        let rawTarget = tdee + adjustment
        // Safety floor: never below BMR × 1.1 (ISSN recommendation)
        let kcalFloor = (bmr * 1.1).rounded()
        let targetKcal = max(kcalFloor, rawTarget).rounded()

        // Protein (ISSN 2017): cut 2.0, maintain 1.6, gain 1.8 g/kg
        let proteinPerKg: Double
        if let custom = input.customProteinGPerKg, custom > 0 {
            proteinPerKg = min(3.0, custom)
        } else {
            switch input.goal {
            case .lose:     proteinPerKg = 2.0
            case .maintain: proteinPerKg = 1.6
            case .gain:     proteinPerKg = 1.8
            }
        }
        let proteinGrams = (proteinPerKg * input.weightKg).rounded()
        let proteinKcal = proteinGrams * 4

        // Fat: 25–35% of target kcal, minimum 0.5 g/kg (ISSN)
        let fatFraction: Double
        if let custom = input.customFatFraction, (0.15...0.45).contains(custom) {
            fatFraction = custom
        } else {
            fatFraction = 0.30
        }
        let fatFromFraction = (targetKcal * fatFraction / 9).rounded()
        let fatMinGrams = (0.5 * input.weightKg).rounded()
        let fatGrams = max(fatFromFraction, fatMinGrams)
        let fatKcal = fatGrams * 9

        // Carbs: remainder
        let carbsKcal = max(0, targetKcal - proteinKcal - fatKcal)
        let carbsGrams = (carbsKcal / 4).rounded()

        let explanation = Explanation(
            bmrFormula: "Mifflin–St Jeor",
            activityLabel: input.activityLevel.label,
            goalLabel: input.goal.label,
            proteinBasis: "\(String(format: "%.1f", proteinPerKg)) г/кг массы тела",
            disclaimer: "Это информационные рекомендации, не медицинская консультация."
        )

        return Output(
            bmr: bmr.rounded(),
            tdee: tdee,
            targetKcal: targetKcal,
            proteinGrams: proteinGrams,
            fatGrams: fatGrams,
            carbsGrams: carbsGrams,
            deficitKcal: adjustment,
            explanation: explanation
        )
    }
}
