import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

final class HealthKitService {
    enum ReadAuthorizationRequestStatus: Equatable {
        case unavailable
        case shouldRequest
        case unnecessary
        case unknown
    }

    enum ReadAccessState: Equatable {
        case readDisabled
        case unavailable
        case needsRequest
        case denied
        case authorizedNoData
        case authorizedWithData
    }

    enum DataAvailabilityDiagnosis: Equatable {
        case unavailableDevice
        case readDisabledInSettings
        case accessNotRequested
        case accessDenied
        case noRecords
        case available
        case unknown

        var message: String {
            switch self {
            case .unavailableDevice:
                return "Apple Health недоступен на этом устройстве."
            case .readDisabledInSettings:
                return "Чтение Apple Health отключено в настройках."
            case .accessNotRequested:
                return "Доступ к Apple Health ещё не запрошен."
            case .accessDenied:
                return "Доступ к данным Apple Health не выдан."
            case .noRecords:
                return "В Apple Health пока нет записей веса/жира."
            case .available:
                return "Данные Apple Health доступны."
            case .unknown:
                return "Статус данных Apple Health пока не определён."
            }
        }
    }

    struct SamplePoint: Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let value: Double
    }

    struct DailyNutritionSample: Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let nutrition: Nutrition
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
    func requestAccess() async throws -> Bool {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        guard let readTypes = makeReadTypes() else {
            return false
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestAuthorization(toShare: makeWriteTypes(), read: readTypes) { granted, error in
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

    func logNutrition(_ nutrition: Nutrition, date: Date) async throws {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let end = date
        let start = Calendar.current.date(byAdding: .second, value: -1, to: end) ?? end
        var samples: [HKQuantitySample] = []

        if let kcal = nutrition.kcal, kcal > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal), start: start, end: end))
        }
        if let protein = nutrition.protein, protein > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryProtein) {
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: .gram(), doubleValue: protein), start: start, end: end))
        }
        if let fat = nutrition.fat, fat > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal) {
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: .gram(), doubleValue: fat), start: start, end: end))
        }
        if let carbs = nutrition.carbs, carbs > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: .gram(), doubleValue: carbs), start: start, end: end))
        }

        guard !samples.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(samples) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #endif
    }

    func readAccessRequestStatus() async -> ReadAuthorizationRequestStatus {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }

        guard let readTypes = makeReadTypes() else {
            return .unavailable
        }

        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: makeWriteTypes() ?? [], read: readTypes) { status, _ in
                switch status {
                case .shouldRequest:
                    continuation.resume(returning: .shouldRequest)
                case .unnecessary:
                    continuation.resume(returning: .unnecessary)
                case .unknown:
                    continuation.resume(returning: .unknown)
                @unknown default:
                    continuation.resume(returning: .unknown)
                }
            }
        }
        #else
        return .unavailable
        #endif
    }

    func readAccessState(
        readEnabledInSettings: Bool,
        hasAnyData: Bool? = nil
    ) async -> ReadAccessState {
        #if canImport(HealthKit)
        let available = HKHealthStore.isHealthDataAvailable()
        let requestStatus = available ? await readAccessRequestStatus() : .unavailable
        let denied = available ? isReadAccessDenied() : false

        let resolvedHasData: Bool
        if let hasAnyData {
            resolvedHasData = hasAnyData
        } else if available {
            let weight = (try? await fetchWeightHistory(days: 0)) ?? []
            let fat = (try? await fetchBodyFatHistory(days: 0)) ?? []
            resolvedHasData = !weight.isEmpty || !fat.isEmpty
        } else {
            resolvedHasData = false
        }

        return Self.resolveReadAccessState(
            readEnabledInSettings: readEnabledInSettings,
            isHealthDataAvailable: available,
            requestStatus: requestStatus,
            isDenied: denied,
            hasAnyData: resolvedHasData
        )
        #else
        return Self.resolveReadAccessState(
            readEnabledInSettings: readEnabledInSettings,
            isHealthDataAvailable: false,
            requestStatus: .unavailable,
            isDenied: false,
            hasAnyData: hasAnyData ?? false
        )
        #endif
    }

    static func resolveReadAccessState(
        readEnabledInSettings: Bool,
        isHealthDataAvailable: Bool,
        requestStatus: ReadAuthorizationRequestStatus,
        isDenied: Bool,
        hasAnyData: Bool
    ) -> ReadAccessState {
        guard readEnabledInSettings else {
            return .readDisabled
        }

        guard isHealthDataAvailable else {
            return .unavailable
        }

        switch requestStatus {
        case .unavailable:
            return .unavailable
        case .shouldRequest, .unknown:
            return .needsRequest
        case .unnecessary:
            break
        }

        if isDenied {
            return .denied
        }

        return hasAnyData ? .authorizedWithData : .authorizedNoData
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

    func fetchConsumedNutritionHistory(days: Int = 14) async throws -> [DailyNutritionSample] {
        #if canImport(HealthKit)
        let safeDays = max(1, min(days, 90))
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        var result: [DailyNutritionSample] = []
        result.reserveCapacity(safeDays)

        for offset in (0..<safeDays).reversed() {
            guard
                let dayStart = calendar.date(byAdding: .day, value: -offset, to: todayStart),
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            else {
                continue
            }

            let dayNutrition = Nutrition(
                kcal: try await cumulativeValue(
                    for: .dietaryEnergyConsumed,
                    unit: .kilocalorie(),
                    start: dayStart,
                    end: dayEnd
                ),
                protein: try await cumulativeValue(
                    for: .dietaryProtein,
                    unit: .gram(),
                    start: dayStart,
                    end: dayEnd
                ),
                fat: try await cumulativeValue(
                    for: .dietaryFatTotal,
                    unit: .gram(),
                    start: dayStart,
                    end: dayEnd
                ),
                carbs: try await cumulativeValue(
                    for: .dietaryCarbohydrates,
                    unit: .gram(),
                    start: dayStart,
                    end: dayEnd
                )
            )

            let hasValues =
                (dayNutrition.kcal ?? 0) > 0 ||
                (dayNutrition.protein ?? 0) > 0 ||
                (dayNutrition.fat ?? 0) > 0 ||
                (dayNutrition.carbs ?? 0) > 0

            if hasValues {
                result.append(.init(date: dayStart, nutrition: dayNutrition))
            }
        }

        return result.sorted(by: { $0.date < $1.date })
        #else
        return []
        #endif
    }

    func diagnoseDataAvailability(readEnabledInSettings: Bool) async -> DataAvailabilityDiagnosis {
        guard readEnabledInSettings else { return .readDisabledInSettings }

        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailableDevice
        }

        let requestStatus = await readAccessRequestStatus()
        switch requestStatus {
        case .shouldRequest:
            return .accessNotRequested
        case .unavailable:
            return .unavailableDevice
        case .unknown:
            break
        case .unnecessary:
            break
        }

        if
            let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass),
            store.authorizationStatus(for: bodyMass) == .sharingDenied
        {
            return .accessDenied
        }

        if
            let bodyFat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage),
            store.authorizationStatus(for: bodyFat) == .sharingDenied
        {
            return .accessDenied
        }

        let weight = (try? await fetchWeightHistory(days: 0)) ?? []
        let fat = (try? await fetchBodyFatHistory(days: 0)) ?? []

        if !weight.isEmpty || !fat.isEmpty {
            return .available
        }

        return requestStatus == .unknown ? .unknown : .noRecords
        #else
        return .unavailableDevice
        #endif
    }

    #if canImport(HealthKit)
    private func makeWriteTypes() -> Set<HKSampleType>? {
        guard
            let dietaryEnergy = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed),
            let dietaryProtein = HKObjectType.quantityType(forIdentifier: .dietaryProtein),
            let dietaryFatTotal = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal),
            let dietaryCarbohydrates = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)
        else {
            return nil
        }
        return [dietaryEnergy, dietaryProtein, dietaryFatTotal, dietaryCarbohydrates]
    }

    private func makeReadTypes() -> Set<HKObjectType>? {
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
            return nil
        }

        return [
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
    }

    private func quantityHistory(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int
    ) async throws -> [SamplePoint] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return []
        }

        let predicate: NSPredicate?
        if days > 0 {
            let calendar = Calendar.current
            let safeDays = max(1, min(days, 3650))
            let end = Date()
            let start = calendar.date(byAdding: .day, value: -safeDays, to: end) ?? end
            predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        } else {
            predicate = nil
        }
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
        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()
        return try await cumulativeValue(for: identifier, unit: unit, start: start, end: end)
    }

    private func cumulativeValue(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

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

    private func isReadAccessDenied() -> Bool {
        guard
            let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass),
            let bodyFat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)
        else {
            return false
        }

        let deniedTypes = [
            store.authorizationStatus(for: bodyMass),
            store.authorizationStatus(for: bodyFat)
        ]

        return deniedTypes.contains(.sharingDenied)
    }
    #endif
}
