import Foundation

final class HealthKitService {
    struct UserMetrics {
        var heightCM: Double?
        var weightKG: Double?
        var bodyFatPercent: Double?
        var activeEnergyKcal: Double?
        var age: Int?
        var sex: String?
    }

    func requestReadAccess() async throws {
        // TODO: HKHealthStore authorization
    }

    func fetchLatestMetrics() async throws -> UserMetrics {
        // TODO: Read HKQuantityType for weight/body fat/height/active energy
        return UserMetrics()
    }

    func calculateDailyCalories(metrics: UserMetrics, targetLossPerWeek: Double = 0.5) -> Int {
        guard
            let weight = metrics.weightKG,
            let height = metrics.heightCM,
            let age = metrics.age
        else { return 2100 }

        let base: Double
        if metrics.sex == "male" {
            base = 10 * weight + 6.25 * height - 5 * Double(age) + 5
        } else {
            base = 10 * weight + 6.25 * height - 5 * Double(age) - 161
        }

        let active = metrics.activeEnergyKcal ?? 300
        let tdee = base + active
        let deficit = targetLossPerWeek * 7700.0 / 7.0
        let adjusted = max(1500, min(3200, tdee - deficit))
        return Int(adjusted.rounded())
    }
}
