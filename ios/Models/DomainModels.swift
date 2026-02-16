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
    case yandexLavka
    case chizhik
    case auchan
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pyaterochka: return "Пятёрочка"
        case .yandexLavka: return "Яндекс Лавка"
        case .chizhik: return "Чижик"
        case .auchan: return "Ашан"
        case .custom: return "Другой"
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
    var budgetDay: Decimal
    var budgetWeek: Decimal?
    var stores: [Store]
    var dislikedList: [String]
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
    var recipeServiceBaseURLOverride: String?

    static let defaultStores: [Store] = [.pyaterochka, .yandexLavka, .chizhik, .auchan]

    static let `default` = AppSettings(
        quietStartMinute: 60,
        quietEndMinute: 360,
        expiryAlertsDays: [5, 3, 1],
        budgetDay: 800,
        budgetWeek: nil,
        stores: defaultStores,
        dislikedList: ["кускус"],
        avoidBones: true,
        mealSchedule: .default,
        strictMacroTracking: true,
        macroTolerancePercent: 25,
        macroGoalSource: .automatic,
        preferredColorScheme: nil,
        healthKitReadEnabled: true,
        healthKitWriteEnabled: false,
        enableAnimations: true,
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

        let normalizedStores = stores.isEmpty ? Self.defaultStores : stores

        var result = AppSettings(
            quietStartMinute: Self.clampMinute(quietStartMinute),
            quietEndMinute: Self.clampMinute(quietEndMinute),
            expiryAlertsDays: normalizedDays.isEmpty ? [5, 3, 1] : normalizedDays,
            budgetDay: max(0, budgetDay).rounded(scale: 2),
            budgetWeek: budgetWeek.map { max(0, $0).rounded(scale: 2) },
            stores: normalizedStores,
            dislikedList: normalizedDisliked,
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
        result.enableAnimations = enableAnimations
        result.recipeServiceBaseURLOverride = normalizedRecipeServiceURLOverride(recipeServiceBaseURLOverride)
        return result
    }

    var quietStartComponents: DateComponents { DateComponents.from(minutes: quietStartMinute) }

    var quietEndComponents: DateComponents { DateComponents.from(minutes: quietEndMinute) }

    static func clampMinute(_ minute: Int) -> Int {
        min(max(minute, 0), 23 * 60 + 59)
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
        case budgetDay
        case budgetWeek
        case stores
        case dislikedList
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
        case recipeServiceBaseURLOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quietStartMinute = try container.decode(Int.self, forKey: .quietStartMinute)
        quietEndMinute = try container.decode(Int.self, forKey: .quietEndMinute)
        expiryAlertsDays = try container.decode([Int].self, forKey: .expiryAlertsDays)
        budgetDay = try container.decode(Decimal.self, forKey: .budgetDay)
        budgetWeek = try container.decodeIfPresent(Decimal.self, forKey: .budgetWeek)
        stores = try container.decode([Store].self, forKey: .stores)
        dislikedList = try container.decode([String].self, forKey: .dislikedList)
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
        recipeServiceBaseURLOverride = try container.decodeIfPresent(String.self, forKey: .recipeServiceBaseURLOverride)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quietStartMinute, forKey: .quietStartMinute)
        try container.encode(quietEndMinute, forKey: .quietEndMinute)
        try container.encode(expiryAlertsDays, forKey: .expiryAlertsDays)
        try container.encode(budgetDay, forKey: .budgetDay)
        try container.encodeIfPresent(budgetWeek, forKey: .budgetWeek)
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
        try container.encodeIfPresent(recipeServiceBaseURLOverride, forKey: .recipeServiceBaseURLOverride)
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

    static func fromMinorUnits(_ value: Int64) -> Decimal {
        Decimal(value) / 100
    }
}
