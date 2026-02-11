import Foundation

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
