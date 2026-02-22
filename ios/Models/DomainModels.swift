import Foundation

enum InventoryLocation: String, Codable, CaseIterable, Identifiable {
    case fridge
    case freezer
    case pantry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fridge: return "Холодильник"
        case .freezer: return "Морозилка"
        case .pantry: return "Шкаф"
        }
    }
}

enum UnitType: String, Codable, CaseIterable, Identifiable {
    case pcs
    case g
    case ml

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pcs: return "шт"
        case .g: return "г"
        case .ml: return "мл"
        }
    }
}

enum Store: String, Codable, CaseIterable, Identifiable {
    case pyaterochka
    case perekrestok
    case magnit
    case lenta
    case auchan
    case okay
    case vkusvill
    case metro
    case dixy
    case fixPrice = "fix_price"
    case samokat
    case yandexLavka = "yandex_lavka"
    case ozonfresh = "ozon_fresh"
    case chizhik
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pyaterochka:  return "Пятёрочка"
        case .perekrestok:  return "Перекрёсток"
        case .magnit:       return "Магнит"
        case .lenta:        return "Лента"
        case .auchan:       return "Ашан"
        case .okay:         return "О'Кей"
        case .vkusvill:     return "ВкусВилл"
        case .metro:        return "METRO"
        case .dixy:         return "Дикси"
        case .fixPrice:     return "Fix Price"
        case .samokat:      return "Самокат"
        case .yandexLavka:  return "Яндекс Лавка"
        case .ozonfresh:    return "Ozon Fresh"
        case .chizhik:      return "Чижик"
        case .custom:       return "Другой"
        }
    }

    /// SF Symbol or asset name for the store logo placeholder.
    var iconSystemName: String {
        switch self {
        case .pyaterochka:  return "basket.fill"
        case .perekrestok:  return "cart.fill"
        case .magnit:       return "bag.fill"
        case .lenta:        return "cart.badge.plus"
        case .auchan:       return "storefront.fill"
        case .okay:         return "cart.circle.fill"
        case .vkusvill:     return "leaf.fill"
        case .metro:        return "building.2.fill"
        case .dixy:         return "basket"
        case .fixPrice:     return "tag.fill"
        case .samokat:      return "bicycle"
        case .yandexLavka:  return "bolt.fill"
        case .ozonfresh:    return "shippingbox.fill"
        case .chizhik:      return "bird.fill"
        case .custom:       return "ellipsis.circle.fill"
        }
    }

    var assetName: String? {
        switch self {
        case .pyaterochka:  return "store_pyaterochka"
        case .perekrestok:  return "store_perekrestok"
        case .magnit:       return "store_magnit"
        case .lenta:        return "store_lenta"
        case .okay:         return "store_okey"
        case .vkusvill:     return "store_vkusvill"
        case .metro:        return "store_metro"
        case .dixy:         return "store_dixy"
        case .fixPrice:     return "store_fixprice"
        case .samokat:      return "store_samokat"
        case .yandexLavka:  return "store_yandexlavka"
        case .auchan:       return "store_auchan"
        case .ozonfresh:    return "store_ozonfresh"
        default: return nil
        }
    }
}

struct Nutrition: Codable, Equatable {
    var kcal: Double?
    var protein: Double?
    var fat: Double?
    var carbs: Double?

    static let empty = Nutrition(kcal: nil, protein: nil, fat: nil, carbs: nil)
}

struct Product: Identifiable, Codable, Equatable {
    let id: UUID
    var barcode: String?
    var name: String
    var brand: String?
    var category: String
    var imageURL: URL?
    var localImagePath: String?
    var defaultUnit: UnitType
    var store: Store?
    var nutrition: Nutrition
    var disliked: Bool
    var mayContainBones: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        barcode: String? = nil,
        name: String,
        brand: String? = nil,
        category: String,
        imageURL: URL? = nil,
        localImagePath: String? = nil,
        defaultUnit: UnitType = .pcs,
        store: Store? = nil,
        nutrition: Nutrition = .empty,
        disliked: Bool = false,
        mayContainBones: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.category = category
        self.imageURL = imageURL
        self.localImagePath = localImagePath
        self.defaultUnit = defaultUnit
        self.store = store
        self.nutrition = nutrition
        self.disliked = disliked
        self.mayContainBones = mayContainBones
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct Batch: Identifiable, Codable, Equatable {
    let id: UUID
    let productId: UUID
    var location: InventoryLocation
    var quantity: Double
    var unit: UnitType
    var expiryDate: Date?
    var purchasePriceMinor: Int64?
    var isOpened: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        productId: UUID,
        location: InventoryLocation,
        quantity: Double,
        unit: UnitType,
        expiryDate: Date? = nil,
        purchasePriceMinor: Int64? = nil,
        isOpened: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.productId = productId
        self.location = location
        self.quantity = quantity
        self.unit = unit
        self.expiryDate = expiryDate
        self.purchasePriceMinor = purchasePriceMinor
        self.isOpened = isOpened
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum InventoryRemovalIntent: String, Codable {
    case consumed
    case writeOff
}

enum InventoryEventReason: String, Codable {
    case consumed
    case writeOff
    case expired
    case unknown
}

struct PriceEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let productId: UUID
    var store: Store
    var price: Decimal
    var currency: String
    var date: Date

    init(
        id: UUID = UUID(),
        productId: UUID,
        store: Store,
        price: Decimal,
        currency: String = "RUB",
        date: Date = Date()
    ) {
        self.id = id
        self.productId = productId
        self.store = store
        self.price = price
        self.currency = currency
        self.date = date
    }
}

struct InventoryEvent: Identifiable, Codable, Equatable {
    enum EventType: String, Codable {
        case add
        case remove
        case adjust
        case open
        case close
    }

    let id: UUID
    var type: EventType
    var productId: UUID
    var batchId: UUID?
    var quantityDelta: Double
    var reason: InventoryEventReason
    var estimatedValueMinor: Int64?
    var timestamp: Date
    var note: String?

    init(
        id: UUID = UUID(),
        type: EventType,
        productId: UUID,
        batchId: UUID? = nil,
        quantityDelta: Double,
        reason: InventoryEventReason = .unknown,
        estimatedValueMinor: Int64? = nil,
        timestamp: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.type = type
        self.productId = productId
        self.batchId = batchId
        self.quantityDelta = quantityDelta
        self.reason = reason
        self.estimatedValueMinor = estimatedValueMinor
        self.timestamp = timestamp
        self.note = note
    }
}

extension InventoryEvent {
    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case productId
        case batchId
        case quantityDelta
        case reason
        case estimatedValueMinor
        case timestamp
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(EventType.self, forKey: .type)
        productId = try container.decode(UUID.self, forKey: .productId)
        batchId = try container.decodeIfPresent(UUID.self, forKey: .batchId)
        quantityDelta = try container.decode(Double.self, forKey: .quantityDelta)
        reason = try container.decodeIfPresent(InventoryEventReason.self, forKey: .reason) ?? .unknown
        estimatedValueMinor = try container.decodeIfPresent(Int64.self, forKey: .estimatedValueMinor)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(productId, forKey: .productId)
        try container.encodeIfPresent(batchId, forKey: .batchId)
        try container.encode(quantityDelta, forKey: .quantityDelta)
        try container.encode(reason, forKey: .reason)
        try container.encodeIfPresent(estimatedValueMinor, forKey: .estimatedValueMinor)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

struct AppSettings: Codable, Equatable {
    enum MacroGoalSource: String, Codable, CaseIterable {
        case automatic
        case manual

        var title: String {
            switch self {
            case .automatic: return "Авто"
            case .manual: return "Вручную"
            }
        }
    }

    enum BudgetInputPeriod: String, Codable, CaseIterable {
        case day
        case week
        case month

        var title: String {
            switch self {
            case .day:
                return "День"
            case .week:
                return "Неделя"
            case .month:
                return "Месяц"
            }
        }
    }

    enum DietProfile: String, Codable, CaseIterable {
        case light
        case medium
        case extreme

        var title: String {
            switch self {
            case .light:
                return "Лайт"
            case .medium:
                return "Медиум"
            case .extreme:
                return "Экстрим"
            }
        }

        var targetLossPerWeek: Double {
            switch self {
            case .light:
                return 0.3
            case .medium:
                return 0.5
            case .extreme:
                return 0.8
            }
        }
    }

    enum SmartOptimizerProfile: String, Codable, CaseIterable {
        case economyAggressive = "economy_aggressive"
        case balanced
        case macroPrecision = "macro_precision"
        case inventoryFirst = "inventory_first"

        var title: String {
            switch self {
            case .economyAggressive:
                return "Экономия"
            case .balanced:
                return "Баланс"
            case .macroPrecision:
                return "Макро"
            case .inventoryFirst:
                return "Мои запасы"
            }
        }
    }

    enum DietGoalMode: String, Codable, CaseIterable {
        case lose
        case maintain
        case gain

        var title: String {
            switch self {
            case .lose:
                return "Похудение"
            case .maintain:
                return "Поддержание"
            case .gain:
                return "Набор"
            }
        }

        func targetWeightDeltaPerWeek(for profile: DietProfile) -> Double {
            switch self {
            case .lose:
                return profile.targetLossPerWeek
            case .maintain:
                return 0
            case .gain:
                return -profile.targetLossPerWeek
            }
        }
    }

    enum MotionLevel: String, Codable, CaseIterable {
        case off
        case reduced
        case full

        var title: String {
            switch self {
            case .off:
                return "Выкл"
            case .reduced:
                return "Меньше"
            case .full:
                return "Полный"
            }
        }
    }

    enum BodyMetricsRangeMode: String, Codable, CaseIterable {
        case lastMonths
        case year
        case sinceYear

        var title: String {
            switch self {
            case .lastMonths:
                return "N месяцев"
            case .year:
                return "Год"
            case .sinceYear:
                return "С года"
            }
        }
    }

    enum AIDataCollectionMode: String, Codable, CaseIterable {
        case conservative
        case balanced
        case maximal

        var title: String {
            switch self {
            case .conservative:
                return "Минимальный"
            case .balanced:
                return "Сбалансированный"
            case .maximal:
                return "Максимальный"
            }
        }
    }

    struct MealSchedule: Codable, Equatable {
        var breakfastMinute: Int
        var lunchMinute: Int
        var dinnerMinute: Int

        static let `default` = MealSchedule(
            breakfastMinute: 8 * 60,
            lunchMinute: 13 * 60,
            dinnerMinute: 19 * 60
        )

        func normalized() -> MealSchedule {
            let breakfast = AppSettings.clampMinute(breakfastMinute)
            let lunch = AppSettings.clampMinute(lunchMinute)
            let dinner = AppSettings.clampMinute(dinnerMinute)

            let minimumGap = 60
            if breakfast + minimumGap >= lunch || lunch + minimumGap >= dinner {
                return .default
            }

            return MealSchedule(
                breakfastMinute: breakfast,
                lunchMinute: lunch,
                dinnerMinute: dinner
            )
        }
    }

    var quietStartMinute: Int
    var quietEndMinute: Int
    var expiryAlertsDays: [Int]
    var budgetPrimaryValue: Decimal
    var budgetInputPeriod: BudgetInputPeriod = .week
    var stores: [Store]

    var budgetDay: Decimal {
        AppSettings.budgetBreakdown(input: budgetPrimaryValue, period: budgetInputPeriod).day
    }
    var budgetWeek: Decimal {
        AppSettings.budgetBreakdown(input: budgetPrimaryValue, period: budgetInputPeriod).week
    }
    var budgetMonth: Decimal {
        AppSettings.budgetBreakdown(input: budgetPrimaryValue, period: budgetInputPeriod).month
    }

    var dislikedList: [String]
    var preferredCuisines: [String]
    var diets: [String]
    var maxPrepTime: Int?
    var difficultyTargets: [String]
    var avoidBones: Bool
    var mealSchedule: MealSchedule = .default
    var strictMacroTracking: Bool = true
    var macroTolerancePercent: Double = 25
    var macroGoalSource: MacroGoalSource = .automatic

    // Nutrition goals
    var kcalGoal: Double?
    var proteinGoalGrams: Double?
    var fatGoalGrams: Double?
    var carbsGoalGrams: Double?
    var weightGoalKg: Double?

    // App preferences
    var preferredColorScheme: Int?
    var healthKitReadEnabled: Bool = true
    var healthKitWriteEnabled: Bool = false
    var enableAnimations: Bool = true
    var motionLevel: MotionLevel = .full
    var hapticsEnabled: Bool = true
    var showHealthCardOnHome: Bool = true
    var aiPersonalizationEnabled: Bool = true
    var aiCloudAssistEnabled: Bool = true
    var aiRuOnlyStorage: Bool = true
    var aiDataConsentAcceptedAt: Date?
    var aiDataCollectionMode: AIDataCollectionMode = .maximal
    var bodyMetricsRangeMode: BodyMetricsRangeMode = .year
    var bodyMetricsRangeMonths: Int = 12
    var bodyMetricsRangeYear: Int = Calendar.current.component(.year, from: Date())
    var dietProfile: DietProfile = .medium
    var dietGoalMode: DietGoalMode = .lose
    var smartOptimizerProfile: SmartOptimizerProfile = .balanced
    var activityLevel: NutritionCalculator.ActivityLevel = .moderatelyActive
    var recipeServiceBaseURLOverride: String?

    static let defaultStores: [Store] = [.pyaterochka, .yandexLavka, .chizhik, .auchan]

    static let `default` = AppSettings(
        quietStartMinute: 60,
        quietEndMinute: 360,
        expiryAlertsDays: [5, 3, 1],
        budgetPrimaryValue: 5_600,
        budgetInputPeriod: .week,
        stores: defaultStores,
        dislikedList: ["кускус"],
        preferredCuisines: [],
        diets: [],
        maxPrepTime: nil,
        difficultyTargets: [],
        avoidBones: true,
        mealSchedule: .default,
        strictMacroTracking: true,
        macroTolerancePercent: 25,
        macroGoalSource: .automatic,
        preferredColorScheme: nil,
        healthKitReadEnabled: true,
        healthKitWriteEnabled: false,
        enableAnimations: true,
        motionLevel: .full,
        hapticsEnabled: true,
        showHealthCardOnHome: true,
        aiPersonalizationEnabled: true,
        aiCloudAssistEnabled: true,
        aiRuOnlyStorage: true,
        aiDataConsentAcceptedAt: nil,
        aiDataCollectionMode: .maximal,
        bodyMetricsRangeMode: .year,
        bodyMetricsRangeMonths: 12,
        bodyMetricsRangeYear: Calendar.current.component(.year, from: Date()),
        dietProfile: .medium,
        dietGoalMode: .lose,
        smartOptimizerProfile: .balanced,
        activityLevel: .moderatelyActive,
        recipeServiceBaseURLOverride: nil
    )

    func normalized() -> AppSettings {
        let normalizedDays = Array(Set(expiryAlertsDays.map { min(max($0, 1), 30) }))
            .sorted(by: >)

        let normalizedDisliked = dislikedList
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { partialResult, item in
                if !partialResult.contains(item) {
                    partialResult.append(item)
                }
            }

        let normalizedCuisines = preferredCuisines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { partialResult, item in
                if !partialResult.contains(item) {
                    partialResult.append(item)
                }
            }

        let normalizedDiets = diets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        let normalizedDifficulty = difficultyTargets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        let normalizedStores = stores.isEmpty ? Self.defaultStores : stores
        let normalizedBudgetPrimaryValue = max(0, budgetPrimaryValue).rounded(scale: 2)
        let currentYear = Calendar.current.component(.year, from: Date())

        let resolvedMotionLevel: MotionLevel
        if motionLevel == .full, !enableAnimations {
            resolvedMotionLevel = .off
        } else {
            resolvedMotionLevel = motionLevel
        }

        var result = AppSettings(
            quietStartMinute: Self.clampMinute(quietStartMinute),
            quietEndMinute: Self.clampMinute(quietEndMinute),
            expiryAlertsDays: normalizedDays.isEmpty ? [5, 3, 1] : normalizedDays,
            budgetPrimaryValue: normalizedBudgetPrimaryValue,
            budgetInputPeriod: budgetInputPeriod,
            stores: normalizedStores,
            dislikedList: normalizedDisliked,
            preferredCuisines: normalizedCuisines,
            diets: normalizedDiets,
            maxPrepTime: maxPrepTime.map { max($0, 5) },
            difficultyTargets: normalizedDifficulty,
            avoidBones: avoidBones,
            mealSchedule: mealSchedule.normalized(),
            strictMacroTracking: strictMacroTracking,
            macroTolerancePercent: min(max(macroTolerancePercent, 5), 60),
            macroGoalSource: macroGoalSource
        )
        result.kcalGoal = normalizedMacroValue(kcalGoal)
        result.proteinGoalGrams = normalizedMacroValue(proteinGoalGrams)
        result.fatGoalGrams = normalizedMacroValue(fatGoalGrams)
        result.carbsGoalGrams = normalizedMacroValue(carbsGoalGrams)
        result.weightGoalKg = normalizedMacroValue(weightGoalKg)
        result.preferredColorScheme = normalizedColorScheme(preferredColorScheme)
        result.healthKitReadEnabled = healthKitReadEnabled
        result.healthKitWriteEnabled = healthKitWriteEnabled
        result.enableAnimations = resolvedMotionLevel != .off
        result.motionLevel = resolvedMotionLevel
        result.hapticsEnabled = hapticsEnabled
        result.showHealthCardOnHome = showHealthCardOnHome
        result.aiPersonalizationEnabled = aiPersonalizationEnabled
        result.aiCloudAssistEnabled = aiCloudAssistEnabled
        result.aiRuOnlyStorage = aiRuOnlyStorage
        result.aiDataConsentAcceptedAt = aiDataConsentAcceptedAt
        result.aiDataCollectionMode = aiDataCollectionMode
        result.bodyMetricsRangeMode = bodyMetricsRangeMode
        result.bodyMetricsRangeMonths = min(max(bodyMetricsRangeMonths, 1), 60)
        result.bodyMetricsRangeYear = min(max(bodyMetricsRangeYear, 1970), currentYear)
        result.dietProfile = dietProfile
        result.dietGoalMode = dietGoalMode
        result.smartOptimizerProfile = smartOptimizerProfile
        result.activityLevel = activityLevel
        result.recipeServiceBaseURLOverride = normalizedRecipeServiceURLOverride(recipeServiceBaseURLOverride)
        return result
    }

    var quietStartComponents: DateComponents { DateComponents.from(minutes: quietStartMinute) }

    var quietEndComponents: DateComponents { DateComponents.from(minutes: quietEndMinute) }

    static func clampMinute(_ minute: Int) -> Int {
        min(max(minute, 0), 23 * 60 + 59)
    }

    static func budgetBreakdown(
        input value: Decimal,
        period: BudgetInputPeriod
    ) -> (day: Decimal, week: Decimal, month: Decimal) {
        let normalizedValue = max(0, value)

        switch period {
        case .day:
            let day = normalizedValue
            let week = (day * 7).rounded(scale: 2)
            let month = ((day * 365) / 12).rounded(scale: 2)
            return (day: day, week: week, month: month)
        case .week:
            let week = normalizedValue
            let month = monthlyBudget(fromWeekly: week)
            let day = dailyBudget(fromWeekly: week)
            return (day: day, week: week, month: month)
        case .month:
            let month = normalizedValue
            let week = weeklyBudget(fromMonthly: month)
            let day = dailyBudget(fromWeekly: week)
            return (day: day, week: week, month: month)
        }
    }

    static func weeklyBudget(fromMonthly monthlyBudget: Decimal) -> Decimal {
        ((max(0, monthlyBudget) * 84) / 365)
    }

    static func monthlyBudget(fromWeekly weeklyBudget: Decimal) -> Decimal {
        ((max(0, weeklyBudget) * 365) / 84)
    }

    static func dailyBudget(fromWeekly weeklyBudget: Decimal) -> Decimal {
        (max(0, weeklyBudget) / 7)
    }

    static func dailyBudget(fromMonthly monthlyBudget: Decimal) -> Decimal {
        ((max(0, monthlyBudget) * 12) / 365)
    }

    private func normalizedMacroValue(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return max(0, value)
    }

    private func normalizedColorScheme(_ value: Int?) -> Int? {
        guard let value, (0...2).contains(value) else { return nil }
        return value
    }

    private func normalizedRecipeServiceURLOverride(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return trimmed
    }
}

extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case quietStartMinute
        case quietEndMinute
        case expiryAlertsDays
        case budgetPrimaryValue
        case budgetDay
        case budgetWeek
        case budgetMonth
        case budgetInputPeriod
        case stores
        case dislikedList
        case preferredCuisines
        case diets
        case maxPrepTime
        case difficultyTargets
        case avoidBones
        case mealSchedule
        case strictMacroTracking
        case macroTolerancePercent
        case macroGoalSource
        case kcalGoal
        case proteinGoalGrams
        case fatGoalGrams
        case carbsGoalGrams
        case weightGoalKg
        case preferredColorScheme
        case healthKitReadEnabled
        case healthKitWriteEnabled
        case enableAnimations
        case motionLevel
        case hapticsEnabled
        case showHealthCardOnHome
        case aiPersonalizationEnabled
        case aiCloudAssistEnabled
        case aiRuOnlyStorage
        case aiDataConsentAcceptedAt
        case aiDataCollectionMode
        case bodyMetricsRangeMode
        case bodyMetricsRangeMonths
        case bodyMetricsRangeYear
        case dietProfile
        case dietGoalMode
        case smartOptimizerProfile
        case activityLevel
        case recipeServiceBaseURLOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quietStartMinute = try container.decode(Int.self, forKey: .quietStartMinute)
        quietEndMinute = try container.decode(Int.self, forKey: .quietEndMinute)
        expiryAlertsDays = try container.decode([Int].self, forKey: .expiryAlertsDays)

        if let budgetInputPeriodRaw = try container.decodeIfPresent(String.self, forKey: .budgetInputPeriod),
           let decodedPeriod = BudgetInputPeriod(rawValue: budgetInputPeriodRaw) {
            budgetInputPeriod = decodedPeriod
        } else {
            budgetInputPeriod = .week
        }

        if let primary = try container.decodeIfPresent(Decimal.self, forKey: .budgetPrimaryValue) {
            budgetPrimaryValue = primary
        } else {
            // Migration from old fields
            let oldDay = try container.decodeIfPresent(Decimal.self, forKey: .budgetDay) ?? 0
            let oldWeek = try container.decodeIfPresent(Decimal.self, forKey: .budgetWeek)
            let oldMonth = try container.decodeIfPresent(Decimal.self, forKey: .budgetMonth)

            switch budgetInputPeriod {
            case .day:
                budgetPrimaryValue = oldDay
            case .week:
                budgetPrimaryValue = oldWeek ?? (oldDay * 7)
            case .month:
                budgetPrimaryValue = oldMonth ?? Self.monthlyBudget(fromWeekly: oldWeek ?? (oldDay * 7))
            }
        }

        stores = try container.decode([Store].self, forKey: .stores)
        dislikedList = try container.decode([String].self, forKey: .dislikedList)
        preferredCuisines = try container.decodeIfPresent([String].self, forKey: .preferredCuisines) ?? []
        diets = try container.decodeIfPresent([String].self, forKey: .diets) ?? []
        maxPrepTime = try container.decodeIfPresent(Int.self, forKey: .maxPrepTime)
        difficultyTargets = try container.decodeIfPresent([String].self, forKey: .difficultyTargets) ?? []
        avoidBones = try container.decode(Bool.self, forKey: .avoidBones)
        mealSchedule = try container.decodeIfPresent(MealSchedule.self, forKey: .mealSchedule) ?? .default
        strictMacroTracking = try container.decodeIfPresent(Bool.self, forKey: .strictMacroTracking) ?? true
        macroTolerancePercent = try container.decodeIfPresent(Double.self, forKey: .macroTolerancePercent) ?? 25
        macroGoalSource = try container.decodeIfPresent(MacroGoalSource.self, forKey: .macroGoalSource) ?? .automatic
        kcalGoal = try container.decodeIfPresent(Double.self, forKey: .kcalGoal)
        proteinGoalGrams = try container.decodeIfPresent(Double.self, forKey: .proteinGoalGrams)
        fatGoalGrams = try container.decodeIfPresent(Double.self, forKey: .fatGoalGrams)
        carbsGoalGrams = try container.decodeIfPresent(Double.self, forKey: .carbsGoalGrams)
        weightGoalKg = try container.decodeIfPresent(Double.self, forKey: .weightGoalKg)
        preferredColorScheme = try container.decodeIfPresent(Int.self, forKey: .preferredColorScheme)
        healthKitReadEnabled = try container.decodeIfPresent(Bool.self, forKey: .healthKitReadEnabled) ?? true
        healthKitWriteEnabled = try container.decodeIfPresent(Bool.self, forKey: .healthKitWriteEnabled) ?? false
        enableAnimations = try container.decodeIfPresent(Bool.self, forKey: .enableAnimations) ?? true
        motionLevel = try container.decodeIfPresent(MotionLevel.self, forKey: .motionLevel) ?? (enableAnimations ? .full : .off)
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        showHealthCardOnHome = try container.decodeIfPresent(Bool.self, forKey: .showHealthCardOnHome) ?? true
        aiPersonalizationEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiPersonalizationEnabled) ?? true
        aiCloudAssistEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiCloudAssistEnabled) ?? true
        aiRuOnlyStorage = try container.decodeIfPresent(Bool.self, forKey: .aiRuOnlyStorage) ?? true
        aiDataConsentAcceptedAt = try container.decodeIfPresent(Date.self, forKey: .aiDataConsentAcceptedAt)
        if
            let aiDataCollectionModeRaw = try container.decodeIfPresent(String.self, forKey: .aiDataCollectionMode),
            let decodedMode = AIDataCollectionMode(rawValue: aiDataCollectionModeRaw)
        {
            aiDataCollectionMode = decodedMode
        } else {
            aiDataCollectionMode = .maximal
        }
        if
            let bodyMetricsRangeModeRaw = try container.decodeIfPresent(String.self, forKey: .bodyMetricsRangeMode),
            let decodedMode = BodyMetricsRangeMode(rawValue: bodyMetricsRangeModeRaw)
        {
            bodyMetricsRangeMode = decodedMode
        } else {
            bodyMetricsRangeMode = .year
        }
        bodyMetricsRangeMonths = try container.decodeIfPresent(Int.self, forKey: .bodyMetricsRangeMonths) ?? 12
        bodyMetricsRangeYear = try container.decodeIfPresent(Int.self, forKey: .bodyMetricsRangeYear) ?? Calendar.current.component(.year, from: Date())
        dietProfile = try container.decodeIfPresent(DietProfile.self, forKey: .dietProfile) ?? .medium
        dietGoalMode = try container.decodeIfPresent(DietGoalMode.self, forKey: .dietGoalMode) ?? .lose
        smartOptimizerProfile = try container.decodeIfPresent(SmartOptimizerProfile.self, forKey: .smartOptimizerProfile) ?? .balanced
        if let activityRaw = try container.decodeIfPresent(String.self, forKey: .activityLevel),
           let parsed = NutritionCalculator.ActivityLevel(rawValue: activityRaw) {
            activityLevel = parsed
        } else {
            activityLevel = .moderatelyActive
        }
        recipeServiceBaseURLOverride = try container.decodeIfPresent(String.self, forKey: .recipeServiceBaseURLOverride)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quietStartMinute, forKey: .quietStartMinute)
        try container.encode(quietEndMinute, forKey: .quietEndMinute)
        try container.encode(expiryAlertsDays, forKey: .expiryAlertsDays)
        try container.encode(budgetPrimaryValue, forKey: .budgetPrimaryValue)
        try container.encode(budgetDay, forKey: .budgetDay)
        try container.encode(budgetWeek, forKey: .budgetWeek)
        try container.encode(budgetMonth, forKey: .budgetMonth)
        try container.encode(budgetInputPeriod.rawValue, forKey: .budgetInputPeriod)
        try container.encode(stores, forKey: .stores)
        try container.encode(dislikedList, forKey: .dislikedList)
        try container.encode(avoidBones, forKey: .avoidBones)
        try container.encode(mealSchedule, forKey: .mealSchedule)
        try container.encode(strictMacroTracking, forKey: .strictMacroTracking)
        try container.encode(macroTolerancePercent, forKey: .macroTolerancePercent)
        try container.encode(macroGoalSource, forKey: .macroGoalSource)
        try container.encodeIfPresent(kcalGoal, forKey: .kcalGoal)
        try container.encodeIfPresent(proteinGoalGrams, forKey: .proteinGoalGrams)
        try container.encodeIfPresent(fatGoalGrams, forKey: .fatGoalGrams)
        try container.encodeIfPresent(carbsGoalGrams, forKey: .carbsGoalGrams)
        try container.encodeIfPresent(weightGoalKg, forKey: .weightGoalKg)
        try container.encodeIfPresent(preferredColorScheme, forKey: .preferredColorScheme)
        try container.encode(healthKitReadEnabled, forKey: .healthKitReadEnabled)
        try container.encode(healthKitWriteEnabled, forKey: .healthKitWriteEnabled)
        try container.encode(enableAnimations, forKey: .enableAnimations)
        try container.encode(motionLevel, forKey: .motionLevel)
        try container.encode(hapticsEnabled, forKey: .hapticsEnabled)
        try container.encode(showHealthCardOnHome, forKey: .showHealthCardOnHome)
        try container.encode(aiPersonalizationEnabled, forKey: .aiPersonalizationEnabled)
        try container.encode(aiCloudAssistEnabled, forKey: .aiCloudAssistEnabled)
        try container.encode(aiRuOnlyStorage, forKey: .aiRuOnlyStorage)
        try container.encodeIfPresent(aiDataConsentAcceptedAt, forKey: .aiDataConsentAcceptedAt)
        try container.encode(aiDataCollectionMode, forKey: .aiDataCollectionMode)
        try container.encode(bodyMetricsRangeMode, forKey: .bodyMetricsRangeMode)
        try container.encode(bodyMetricsRangeMonths, forKey: .bodyMetricsRangeMonths)
        try container.encode(bodyMetricsRangeYear, forKey: .bodyMetricsRangeYear)
        try container.encode(dietProfile, forKey: .dietProfile)
        try container.encode(dietGoalMode, forKey: .dietGoalMode)
        try container.encode(smartOptimizerProfile, forKey: .smartOptimizerProfile)
        try container.encode(activityLevel.rawValue, forKey: .activityLevel)
        try container.encodeIfPresent(recipeServiceBaseURLOverride, forKey: .recipeServiceBaseURLOverride)
    }
}

extension AppSettings {
    var targetWeightDeltaPerWeek: Double {
        dietGoalMode.targetWeightDeltaPerWeek(for: dietProfile)
    }
}

struct Recipe: Identifiable, Codable, Equatable {
    let id: String
    var sourceURL: URL
    var sourceName: String
    var title: String
    var imageURL: URL
    var videoURL: URL?
    var ingredients: [String]
    var instructions: [String]
    var totalTimeMinutes: Int?
    var servings: Int?
    var cuisine: String?
    var tags: [String]
    var nutrition: Nutrition? = nil
}

struct MealEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var recipeId: String
    var mealType: String
}

struct MealPlanDay: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var entries: [MealEntry]
    var beverages: [BeverageLog]
    var targetKcal: Double
    var totalKcal: Double
}

struct BeverageLog: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var volumeML: Int
    var kcal: Double
}

struct InternalCodeMapping: Identifiable, Codable, Equatable {
    var id: String { code }
    var code: String
    var productId: UUID
    var parsedWeightGrams: Double?
    var createdAt: Date
}

extension DateComponents {
    static func from(minutes: Int) -> DateComponents {
        DateComponents(hour: minutes / 60, minute: minutes % 60)
    }

    var asDate: Date {
        let cal = Calendar.current
        let now = Date()
        let today = cal.dateComponents([.year, .month, .day], from: now)
        var c = DateComponents()
        c.year = today.year
        c.month = today.month
        c.day = today.day
        c.hour = hour
        c.minute = minute
        return cal.date(from: c) ?? now
    }
}

extension Decimal {
    func rounded(scale: Int = 2) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .bankers)
        return result
    }

    var asMinorUnits: Int64 {
        let value = (self.rounded(scale: 2) * 100).rounded(scale: 0)
        return NSDecimalNumber(decimal: value).int64Value
    }

    var asHighPrecisionMinorUnits: Int64 {
        // Scale 4 (e.g. 100.0123 -> 1000123)
        let value = (self.rounded(scale: 4) * 10000).rounded(scale: 0)
        return NSDecimalNumber(decimal: value).int64Value
    }

    static func fromMinorUnits(_ value: Int64) -> Decimal {
        Decimal(value) / 100
    }

    static func fromHighPrecisionMinorUnits(_ value: Int64) -> Decimal {
        Decimal(value) / 10000
    }
}
