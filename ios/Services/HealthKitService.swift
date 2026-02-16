import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

final class HealthKitService {
    struct SamplePoint: Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let value: Double
    }

    struct UserMetrics {
        var heightCM: Double?
        var weightKG: Double?
        var bodyFatPercent: Double?
        var activeEnergyKcal: Double?
        var age: Int?
        var sex: String?
    }

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif

    var isHealthDataAvailable: Bool {
        #if canImport(HealthKit)
        HKHealthStore.isHealthDataAvailable()
        #else
        false
        #endif
    }

    @MainActor
    func requestReadAccess() async throws -> Bool {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        guard
            let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass),
            let height = HKObjectType.quantityType(forIdentifier: .height),
            let bodyFat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage),
            let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            let dietaryEnergy = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed),
            let dietaryProtein = HKObjectType.quantityType(forIdentifier: .dietaryProtein),
            let dietaryFatTotal = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal),
            let dietaryCarbohydrates = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates),
            let dateOfBirth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth),
            let biologicalSex = HKObjectType.characteristicType(forIdentifier: .biologicalSex)
        else {
            return false
        }

        let readTypes: Set<HKObjectType> = [
            bodyMass,
            height,
            bodyFat,
            activeEnergy,
            dietaryEnergy,
            dietaryProtein,
            dietaryFatTotal,
            dietaryCarbohydrates,
            dateOfBirth,
            biologicalSex
        ]

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestAuthorization(toShare: nil, read: readTypes) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        #else
        return false
        #endif
    }

    func fetchLatestMetrics() async throws -> UserMetrics {
        #if canImport(HealthKit)
        let height = try await latestQuantityValue(for: .height, unit: .meterUnit(with: .centi))
        let weight = try await latestQuantityValue(for: .bodyMass, unit: .gramUnit(with: .kilo))
        let bodyFat = try await latestQuantityValue(for: .bodyFatPercentage, unit: .percent())
        let activeEnergy = try await latestQuantityValue(for: .activeEnergyBurned, unit: .kilocalorie())

        let age = try? ageFromHealthKit()
        let sex = try? biologicalSexFromHealthKit()

        return UserMetrics(
            heightCM: height,
            weightKG: weight,
            bodyFatPercent: bodyFat,
            activeEnergyKcal: activeEnergy,
            age: age,
            sex: sex
        )
        #else
        return UserMetrics()
        #endif
    }

    func fetchTodayConsumedEnergyKcal() async throws -> Double? {
        let nutrition = try await fetchTodayConsumedNutrition()
        return nutrition.kcal
    }

    func fetchTodayConsumedNutrition() async throws -> Nutrition {
        #if canImport(HealthKit)
        let kcal = try await todayCumulativeValue(for: .dietaryEnergyConsumed, unit: .kilocalorie())
        let protein = try await todayCumulativeValue(for: .dietaryProtein, unit: .gram())
        let fat = try await todayCumulativeValue(for: .dietaryFatTotal, unit: .gram())
        let carbs = try await todayCumulativeValue(for: .dietaryCarbohydrates, unit: .gram())

        return Nutrition(
            kcal: kcal,
            protein: protein,
            fat: fat,
            carbs: carbs
        )
        #else
        return .empty
        #endif
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

    func fetchWeightHistory(days: Int = 30) async throws -> [SamplePoint] {
        #if canImport(HealthKit)
        return try await quantityHistory(
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            days: days
        )
        #else
        return []
        #endif
    }

    func fetchBodyFatHistory(days: Int = 30) async throws -> [SamplePoint] {
        #if canImport(HealthKit)
        return try await quantityHistory(
            identifier: .bodyFatPercentage,
            unit: .percent(),
            days: days
        )
        #else
        return []
        #endif
    }

    #if canImport(HealthKit)
    private func quantityHistory(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int
    ) async throws -> [SamplePoint] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return []
        }

        let calendar = Calendar.current
        let safeDays = max(1, min(days, 365))
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -safeDays, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[SamplePoint], Error>) in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let points = (samples as? [HKQuantitySample] ?? [])
                    .map {
                        SamplePoint(
                            date: $0.endDate,
                            value: $0.quantity.doubleValue(for: unit)
                        )
                    }

                continuation.resume(returning: points)
            }

            store.execute(query)
        }
    }

    private func todayCumulativeValue(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double?, Error>) in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = result?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }

            store.execute(query)
        }
    }

    private func latestQuantityValue(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double?, Error>) in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let sample = samples?.first as? HKQuantitySample
                continuation.resume(returning: sample?.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func ageFromHealthKit() throws -> Int? {
        let components = try store.dateOfBirthComponents()
        guard let birthDate = Calendar.current.date(from: components) else {
            return nil
        }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    private func biologicalSexFromHealthKit() throws -> String? {
        let value = try store.biologicalSex().biologicalSex
        switch value {
        case .male:
            return "male"
        case .female:
            return "female"
        default:
            return nil
        }
    }
    #endif
}
