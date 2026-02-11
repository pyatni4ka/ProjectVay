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
        self.isOpened = isOpened
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
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
    var timestamp: Date
    var note: String?

    init(
        id: UUID = UUID(),
        type: EventType,
        productId: UUID,
        batchId: UUID? = nil,
        quantityDelta: Double,
        timestamp: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.type = type
        self.productId = productId
        self.batchId = batchId
        self.quantityDelta = quantityDelta
        self.timestamp = timestamp
        self.note = note
    }
}

struct AppSettings: Codable, Equatable {
    var quietStartMinute: Int
    var quietEndMinute: Int
    var expiryAlertsDays: [Int]
    var budgetDay: Decimal
    var budgetWeek: Decimal?
    var stores: [Store]
    var dislikedList: [String]
    var avoidBones: Bool

    static let defaultStores: [Store] = [.pyaterochka, .yandexLavka, .chizhik, .auchan]

    static let `default` = AppSettings(
        quietStartMinute: 60,
        quietEndMinute: 360,
        expiryAlertsDays: [5, 3, 1],
        budgetDay: 800,
        budgetWeek: nil,
        stores: defaultStores,
        dislikedList: ["кускус"],
        avoidBones: true
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

        return AppSettings(
            quietStartMinute: Self.clampMinute(quietStartMinute),
            quietEndMinute: Self.clampMinute(quietEndMinute),
            expiryAlertsDays: normalizedDays.isEmpty ? [5, 3, 1] : normalizedDays,
            budgetDay: max(0, budgetDay).rounded(scale: 2),
            budgetWeek: budgetWeek.map { max(0, $0).rounded(scale: 2) },
            stores: normalizedStores,
            dislikedList: normalizedDisliked,
            avoidBones: avoidBones
        )
    }

    var quietStartComponents: DateComponents { DateComponents.from(minutes: quietStartMinute) }

    var quietEndComponents: DateComponents { DateComponents.from(minutes: quietEndMinute) }

    static func clampMinute(_ minute: Int) -> Int {
        min(max(minute, 0), 23 * 60 + 59)
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
