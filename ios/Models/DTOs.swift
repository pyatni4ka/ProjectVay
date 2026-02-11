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
