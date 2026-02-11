import Foundation

enum InventoryLocation: String, Codable, CaseIterable {
    case fridge
    case freezer
    case pantry
}

enum UnitType: String, Codable, CaseIterable {
    case pcs
    case g
    case ml
}

struct Nutrition: Codable, Equatable {
    var kcal: Double?
    var protein: Double?
    var fat: Double?
    var carbs: Double?
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
}

struct PriceEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let productId: UUID
    var store: String
    var price: Decimal
    var currency: String
    var date: Date
}

struct InventoryEvent: Identifiable, Codable, Equatable {
    enum EventType: String, Codable {
        case add, remove, adjust, open, close
    }

    let id: UUID
    var type: EventType
    var productId: UUID
    var batchId: UUID?
    var quantityDelta: Double
    var timestamp: Date
    var note: String?
}

struct AppSettings: Codable, Equatable {
    var quietHoursStart: DateComponents
    var quietHoursEnd: DateComponents
    var expiryAlertsDays: [Int]
    var budgetDay: Decimal
    var budgetWeek: Decimal?
    var stores: [String]
    var dislikedList: [String]
    var avoidBones: Bool
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
