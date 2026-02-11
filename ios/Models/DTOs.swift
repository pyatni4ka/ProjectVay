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
    let ingredientKeywords: [String]
    let expiringSoonKeywords: [String]
    let targets: Nutrition
    let budgetPerMeal: Double
    let exclude: [String]
    let avoidBones: Bool
    let limit: Int
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
