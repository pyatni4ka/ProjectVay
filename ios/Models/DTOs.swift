import Foundation

struct BarcodeLookupPayload: Codable, Equatable {
    var barcode: String
    var name: String
    var brand: String?
    var category: String
    var nutrition: Nutrition
    var imageURL: URL?
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
    let diets: [String]
    let maxPrepTime: Int?
    let difficulty: [String]
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

struct SubstituteRequest: Codable {
    let ingredients: [String]
    let limit: Int?
}

struct SubstituteResponse: Codable {
    struct Substitution: Codable, Hashable {
        let ingredient: String
        let substitute: String
        let reason: String
        let estimatedSavingsRub: Double?
    }
    
    let substitutions: [Substitution]
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
    let diets: [String]
    let maxPrepTime: Int?
    let difficulty: [String]
}

struct SmartMealPlanGenerateRequest: Codable {
    struct Budget: Codable {
        let perDay: Double?
        let perMeal: Double?
    }

    struct IngredientPriceHint: Codable {
        let ingredient: String
        let priceRub: Double
        let confidence: Double?
        let source: String?
        let capturedAt: String?
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
    let diets: [String]
    let maxPrepTime: Int?
    let difficulty: [String]
    let objective: String?
    let optimizerProfile: String?
    let macroTolerancePercent: Double?
    let ingredientPriceHints: [IngredientPriceHint]?
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

struct SmartMealPlanGenerateResponse: Codable {
    let days: [MealPlanGenerateResponse.Day]
    let shoppingList: [String]
    let estimatedTotalCost: Double
    let warnings: [String]
    let objective: String
    let optimizerProfile: String?
    let costConfidence: Double
    let priceExplanation: [String]
}

struct RecipeParseRequest: Codable {
    let url: String
}

struct RecipeParseResponse: Codable {
    struct NormalizedIngredient: Codable {
        let raw: String
        let normalizedKey: String
        let name: String
        let quantity: Double?
        let unit: String?
    }

    struct Quality: Codable {
        let hasImage: Bool
        let hasNutrition: Bool
        let hasServings: Bool
        let hasTotalTime: Bool
        let ingredientCount: Int
        let instructionCount: Int
        let score: Double
        let missingFields: [String]
    }

    let recipe: Recipe
    let normalizedIngredients: [NormalizedIngredient]
    let quality: Quality
    let diagnostics: [String]
}

struct PriceEstimateRequest: Codable {
    struct Hint: Codable {
        let ingredient: String
        let priceRub: Double
        let confidence: Double?
        let source: String?
        let capturedAt: String?
    }

    let ingredients: [String]
    let hints: [Hint]?
    let region: String?
    let currency: String?
}

struct PriceEstimateResponse: Codable {
    struct Item: Codable {
        let ingredient: String
        let estimatedPriceRub: Double
        let confidence: Double
        let source: String
    }

    let items: [Item]
    let totalEstimatedRub: Double
    let confidence: Double
    let missingIngredients: [String]
}

enum MealPlanDataSource: String, Codable, Equatable {
    case serverSmart
    case serverBasic
    case localFallback
    case unknown
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
    let dataSource: MealPlanDataSource?
    let dataSourceDetails: String?
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

struct MealPlanSnapshot: Codable {
    let generatedAt: Date
    let rangeRawValue: String
    let dataSource: MealPlanDataSource
    let dataSourceDetails: String?
    let plan: MealPlanGenerateResponse
}

final class MealPlanSnapshotStore {
    private let userDefaults: UserDefaults
    private let key: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "vay_last_meal_plan_snapshot"
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

    func save(_ snapshot: MealPlanSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        userDefaults.set(data, forKey: key)
    }

    func load() -> MealPlanSnapshot? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? decoder.decode(MealPlanSnapshot.self, from: data)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }
}

// MARK: - Weekly Autopilot DTOs

struct WeeklyAutopilotRequest: Codable {
    struct Budget: Codable {
        let perDay: Double?
        let perMeal: Double?
        let perWeek: Double?
        let perMonth: Double?
        let strictness: String?
        let softLimitPct: Double?
    }

    struct Constraints: Codable {
        let diets: [String]?
        let allergies: [String]?
        let dislikes: [String]?
        let favorites: [String]?
    }

    struct IngredientPriceHint: Codable {
        let ingredient: String
        let priceRub: Double
        let confidence: Double?
        let source: String?
        let capturedAt: String?
    }

    let days: Int?
    let startDate: String?
    let mealsPerDay: Int?
    let includeSnacks: Bool?
    let ingredientKeywords: [String]
    let expiringSoonKeywords: [String]
    let targets: Nutrition
    let beveragesKcal: Double?
    let budget: Budget?
    let exclude: [String]?
    let avoidBones: Bool?
    let cuisine: [String]?
    let effortLevel: String?
    let seed: Int?
    let inventorySnapshot: [String]?
    let constraints: Constraints?
    let objective: String?
    let optimizerProfile: String?
    let macroTolerancePercent: Double?
    let ingredientPriceHints: [IngredientPriceHint]?
}

struct WeeklyAutopilotResponse: Codable {
    struct BudgetProjectionItem: Codable {
        let target: Double
        let actual: Double
        let delta: Double
    }

    struct BudgetProjection: Codable {
        let day: BudgetProjectionItem
        let week: BudgetProjectionItem
        let month: BudgetProjectionItem
        let strictness: String
        let softLimitPct: Double
    }

    struct ShoppingItemQuantity: Codable, Identifiable {
        var id: String { ingredient }
        let ingredient: String
        let amount: Double
        let unit: String
        let approximate: Bool
    }

    struct MealSlotTarget: Codable {
        let mealSlotKey: String
        let kcal: Double?
        let protein: Double?
        let fat: Double?
        let carbs: Double?
    }

    struct DayEntry: Codable, Identifiable {
        var id: String { "\(mealSlotKey)-\(recipe.id)" }
        let mealType: String
        let recipe: Recipe
        let score: Double
        let estimatedCost: Double
        let kcal: Double
        let protein: Double
        let fat: Double
        let carbs: Double
        let mealSlotKey: String
        let explanationTags: [String]
        let nutritionConfidence: String
    }

    struct DayTotals: Codable {
        let kcal: Double
        let protein: Double
        let fat: Double
        let carbs: Double
        let estimatedCost: Double
    }

    struct AutopilotDay: Codable, Identifiable {
        var id: String { date }
        let date: String
        let dayOfWeek: String?
        let entries: [DayEntry]
        let totals: DayTotals
        let dayTargets: Nutrition
        let dayBudget: BudgetProjectionItem
        let missingIngredients: [String]
    }

    let planId: String
    let startDate: String
    let days: [AutopilotDay]
    let shoppingListWithQuantities: [ShoppingItemQuantity]
    let shoppingListGrouped: [String: [String]]
    let budgetProjection: BudgetProjection
    let estimatedTotalCost: Double
    let warnings: [String]
    let nutritionConfidence: String
    let explanationTags: [String]
}

// MARK: - Replace Meal DTOs

struct ReplaceMealRequest: Codable {
    let planId: String?
    let currentPlan: WeeklyAutopilotResponse
    let dayIndex: Int
    let mealSlot: String
    let sortMode: String?
    let topN: Int?
    let inventorySnapshot: [String]?
}

struct ReplaceMealResponse: Codable {
    struct Candidate: Codable, Identifiable {
        var id: String { recipe.id }
        let recipe: Recipe
        let mealSlotKey: String
        let macroDelta: MacroDelta
        let costDelta: Double
        let timeDelta: Double
        let tags: [String]
        let nutritionConfidence: String
    }

    struct MacroDelta: Codable {
        let kcal: Double?
        let protein: Double?
        let fat: Double?
        let carbs: Double?
    }

    let candidates: [Candidate]
    let updatedPlanPreview: WeeklyAutopilotResponse
    let why: [String]
}

// MARK: - Adapt Plan DTOs

struct AdaptPlanRequest: Codable {
    let planId: String?
    let currentPlan: WeeklyAutopilotResponse
    let eventType: String
    let impactEstimate: String
    let customMacros: Nutrition?
    let timestamp: String?
    let applyScope: String?
}

struct AdaptPlanResponse: Codable {
    let updatedRemainingPlan: WeeklyAutopilotResponse
    let disruptionScore: Double
    let newBudgetProjection: WeeklyAutopilotResponse.BudgetProjection
    let gentleMessage: String
    let why: [String]
}

// MARK: - Cook Now DTOs

struct CookNowRequest: Codable {
    let inventoryKeywords: [String]
    let expiringSoonKeywords: [String]?
    let maxPrepTime: Int?
    let limit: Int?
    let exclude: [String]?
}

struct CookNowResponse: Codable {
    struct CookNowRecipe: Codable, Identifiable {
        var id: String { recipe.id }
        let recipe: Recipe
        let score: Double
        let availabilityRatio: Int
        let matchedFilters: [String]
    }

    let recipes: [CookNowRecipe]
    let inventoryCount: Int
}
