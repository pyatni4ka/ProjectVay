import Foundation

struct BarcodeLookupPayload: Codable, Equatable {
    var barcode: String
    var name: String
    var brand: String?
    var category: String
    var nutrition: Nutrition
}

enum ScanResolution: Equatable {
    case found(product: Product, suggestedExpiry: Date?, parsedWeightGrams: Double?)
    case created(product: Product, suggestedExpiry: Date?, parsedWeightGrams: Double?, provider: String)
    case notFound(barcode: String?, internalCode: String?, parsedWeightGrams: Double?, suggestedExpiry: Date?)
}

struct RecommendRequest: Codable {
    struct Budget: Codable {
        let perMeal: Double?
    }

    let ingredientKeywords: [String]
    let expiringSoonKeywords: [String]
    let targets: Nutrition
    let budget: Budget?
    let exclude: [String]
    let avoidBones: Bool
    let cuisine: [String]
    let limit: Int
    let strictNutrition: Bool?
    let macroTolerancePercent: Double?
}

struct RecommendResponse: Codable {
    struct RankedRecipe: Codable {
        let recipe: Recipe
        let score: Double
        let scoreBreakdown: [String: Double]
    }

    let items: [RankedRecipe]
}

struct MealPlanGenerateRequest: Codable {
    struct Budget: Codable {
        let perDay: Double?
        let perMeal: Double?
    }

    let days: Int
    let ingredientKeywords: [String]
    let expiringSoonKeywords: [String]
    let targets: Nutrition
    let beveragesKcal: Double?
    let budget: Budget?
    let exclude: [String]
    let avoidBones: Bool
    let cuisine: [String]
}

struct MealPlanGenerateResponse: Codable {
    struct Day: Codable, Identifiable {
        struct Entry: Codable, Identifiable {
            var id: String { "\(mealType)-\(recipe.id)" }
            let mealType: String
            let recipe: Recipe
            let score: Double
            let estimatedCost: Double
            let kcal: Double
        }

        struct Totals: Codable {
            let kcal: Double
            let estimatedCost: Double
        }

        struct Targets: Codable {
            let kcal: Double?
            let perMealKcal: Double?
        }

        var id: String { date }
        let date: String
        let entries: [Entry]
        let totals: Totals
        let targets: Targets
        let missingIngredients: [String]
    }

    let days: [Day]
    let shoppingList: [String]
    let estimatedTotalCost: Double
    let warnings: [String]
}

struct TodayMenuSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable {
        let mealType: String
        let title: String
        let kcal: Double
    }

    let generatedAt: Date
    let items: [Item]
    let estimatedCost: Double?
}

final class TodayMenuSnapshotStore {
    private let userDefaults: UserDefaults
    private let key: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "vay_today_menu_snapshot"
    ) {
        self.userDefaults = userDefaults
        self.key = key

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save(_ snapshot: TodayMenuSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        userDefaults.set(data, forKey: key)
    }

    func load() -> TodayMenuSnapshot? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? decoder.decode(TodayMenuSnapshot.self, from: data)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }

    func isFreshForToday(_ snapshot: TodayMenuSnapshot) -> Bool {
        Calendar.current.isDate(snapshot.generatedAt, inSameDayAs: Date())
    }
}
