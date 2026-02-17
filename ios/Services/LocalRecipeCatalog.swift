import Foundation

struct LocalRecipeCatalog {
    private struct SeedPayload: Decodable {
        let items: [Recipe]
    }

    let recipes: [Recipe]
    let sourceLabel: String

    init(datasetPathOverride: String? = nil, fileManager: FileManager = .default) {
        let loaded = Self.loadRecipes(datasetPathOverride: datasetPathOverride, fileManager: fileManager)
        recipes = loaded.items
        sourceLabel = loaded.source
    }

    init(recipes: [Recipe], sourceLabel: String = "memory") {
        let hydrated = recipes.map(Self.hydrateRecipe)
        if hydrated.isEmpty {
            self.recipes = Self.builtinFallbackRecipes
            self.sourceLabel = "builtin"
        } else {
            self.recipes = hydrated
            self.sourceLabel = sourceLabel
        }
    }

    var hasRecipes: Bool {
        !recipes.isEmpty
    }

    func merging(additionalRecipes: [Recipe], sourceLabel: String? = nil) -> LocalRecipeCatalog {
        let hydratedAdditional = additionalRecipes.map(Self.hydrateRecipe)
        guard !hydratedAdditional.isEmpty else {
            return self
        }

        var merged: [Recipe] = []
        var seen = Set<String>()

        for recipe in hydratedAdditional + recipes {
            if seen.insert(recipe.id).inserted {
                merged.append(recipe)
            }
        }

        let mergedSourceLabel = sourceLabel ?? "\(self.sourceLabel)+cached"
        return LocalRecipeCatalog(recipes: merged, sourceLabel: mergedSourceLabel)
    }

    func search(query: String, limit: Int = 50) -> [Recipe] {
        let cappedLimit = max(1, min(limit, 120))
        let normalizedQuery = Self.normalizeToken(query)

        guard !normalizedQuery.isEmpty else {
            return Array(recipes.prefix(cappedLimit))
        }

        let matched = recipes.filter { recipe in
            let haystack = ([recipe.title, recipe.sourceName, recipe.cuisine ?? ""] + recipe.tags + recipe.ingredients)
                .map(Self.normalizeToken)
                .joined(separator: " ")
            return haystack.contains(normalizedQuery)
        }

        return Array(matched.prefix(cappedLimit))
    }

    func recommend(payload: RecommendRequest) -> RecommendResponse {
        let ingredientKeywords = Set(payload.ingredientKeywords.map(Self.normalizeToken).filter { !$0.isEmpty })
        let expiringKeywords = Set(payload.expiringSoonKeywords.map(Self.normalizeToken).filter { !$0.isEmpty })
        let dislikedKeywords = Set(payload.exclude.map(Self.normalizeToken).filter { !$0.isEmpty })
        let cuisineFilter = Set(payload.cuisine.map(Self.normalizeToken).filter { !$0.isEmpty })

        let filteredRecipes = recipes.filter { recipe in
            if payload.avoidBones, Self.recipeLikelyContainsBones(recipe) {
                return false
            }

            if !cuisineFilter.isEmpty, !Self.matchesCuisine(recipe, allowedCuisine: cuisineFilter) {
                return false
            }

            if Self.containsDislikedIngredient(recipe, disliked: dislikedKeywords) {
                return false
            }

            return true
        }

        let candidates = filteredRecipes.isEmpty ? recipes : filteredRecipes
        let perMealBudget = payload.budget?.perMeal

        var ranked = candidates.map { recipe -> RecommendResponse.RankedRecipe in
            let normalizedRecipe = Self.hydrateRecipe(recipe)
            let inStockScore = Self.overlapScore(ingredients: normalizedRecipe.ingredients, keywords: ingredientKeywords)
            let expiringScore = Self.overlapScore(ingredients: normalizedRecipe.ingredients, keywords: expiringKeywords)
            let nutrition = Self.resolvedNutrition(for: normalizedRecipe)
            let macroDeviation = Self.averageMacroDeviation(target: payload.targets, actual: nutrition)
            let macroScore = max(0, 1 - min(1.4, macroDeviation))
            let budgetScore = Self.budgetScore(recipe: normalizedRecipe, perMealBudget: perMealBudget)
            let diversityNoise = Double(abs(normalizedRecipe.id.hashValue % 7)) * 0.01

            let totalScore = (inStockScore * 0.34)
                + (expiringScore * 0.14)
                + (macroScore * 0.37)
                + (budgetScore * 0.15)
                + diversityNoise

            let scoreBreakdown: [String: Double] = [
                "inStock": Self.round2(inStockScore),
                "expiring": Self.round2(expiringScore),
                "nutrition": Self.round2(macroScore),
                "budget": Self.round2(budgetScore),
                "macroDeviation": Self.round2(macroDeviation)
            ]

            return .init(
                recipe: normalizedRecipe,
                score: Self.round2(totalScore),
                scoreBreakdown: scoreBreakdown
            )
        }

        ranked.sort { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.recipe.title.localizedCaseInsensitiveCompare(rhs.recipe.title) == .orderedAscending
            }
            return lhs.score > rhs.score
        }

        if payload.strictNutrition == true {
            let tolerance = max(0.05, min(0.60, (payload.macroTolerancePercent ?? 25) / 100))
            let strictMatches = ranked.filter { item in
                (item.scoreBreakdown["macroDeviation"] ?? 1) <= tolerance
            }
            if !strictMatches.isEmpty {
                ranked = strictMatches
            }
        }

        let cappedLimit = max(1, min(payload.limit, 120))
        return .init(items: Array(ranked.prefix(cappedLimit)))
    }

    func generateMealPlan(payload: MealPlanGenerateRequest, startDate: Date = Date()) -> MealPlanGenerateResponse {
        let daysCount = max(1, min(payload.days, 7))
        let mealTypes = ["breakfast", "lunch", "dinner"]
        let ingredientKeywords = Set(payload.ingredientKeywords.map(Self.normalizeToken).filter { !$0.isEmpty })
        let dislikedKeywords = payload.exclude
        let perMealTargets = Self.divideNutrition(payload.targets, by: Double(mealTypes.count))
        let perMealBudget = Self.resolvePerMealBudget(payload.budget)

        var usedRecipeCount: [String: Int] = [:]
        var days: [MealPlanGenerateResponse.Day] = []
        var shoppingList = Set<String>()
        var estimatedTotalCost = 0.0

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        for dayOffset in 0..<daysCount {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate

            var entries: [MealPlanGenerateResponse.Day.Entry] = []
            var dayMissing = Set<String>()
            var dayKcal = 0.0
            var dayCost = 0.0
            var usedToday = Set<String>()

            for mealType in mealTypes {
                let recommendPayload = RecommendRequest(
                    ingredientKeywords: payload.ingredientKeywords,
                    expiringSoonKeywords: payload.expiringSoonKeywords,
                    targets: perMealTargets,
                    budget: .init(perMeal: perMealBudget),
                    exclude: dislikedKeywords,
                    avoidBones: payload.avoidBones,
                    cuisine: payload.cuisine,
                    limit: min(max(recipes.count, 12), 120),
                    strictNutrition: true,
                    macroTolerancePercent: 35
                )

                let ranked = recommend(payload: recommendPayload).items
                guard let selected = Self.pickForMeal(ranked: ranked, usedToday: usedToday, usedCount: usedRecipeCount) else {
                    continue
                }

                let recipe = selected.recipe
                let nutrition = Self.resolvedNutrition(for: recipe)
                let kcal = nutrition.kcal ?? 0
                let cost = Self.estimatedMealCost(for: recipe)

                entries.append(
                    .init(
                        mealType: mealType,
                        recipe: recipe,
                        score: selected.score,
                        estimatedCost: cost,
                        kcal: kcal
                    )
                )

                usedToday.insert(recipe.id)
                usedRecipeCount[recipe.id, default: 0] += 1
                dayKcal += kcal
                dayCost += cost

                let missing = recipe.ingredients
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .filter { ingredient in
                        !Self.ingredientCovered(ingredient, keywords: ingredientKeywords)
                    }

                for ingredient in missing {
                    dayMissing.insert(ingredient)
                    shoppingList.insert(ingredient)
                }
            }

            estimatedTotalCost += dayCost

            days.append(
                .init(
                    date: formatter.string(from: date),
                    entries: entries,
                    totals: .init(kcal: Self.round2(dayKcal), estimatedCost: Self.round2(dayCost)),
                    targets: .init(
                        kcal: payload.targets.kcal.map(Self.round2),
                        perMealKcal: perMealTargets.kcal.map(Self.round2)
                    ),
                    missingIngredients: Array(dayMissing).sorted()
                )
            )
        }

        var warnings = [
            "План собран локально (\(recipes.count) рецептов, источник: \(sourceLabel))."
        ]
        if days.contains(where: { $0.entries.count < 3 }) {
            warnings.append("В каталоге не хватило разнообразия, некоторые приёмы пищи пропущены.")
        }

        return .init(
            days: days,
            shoppingList: Array(shoppingList).sorted(),
            estimatedTotalCost: Self.round2(estimatedTotalCost),
            warnings: warnings
        )
    }

    func generateSmartMealPlan(payload: SmartMealPlanGenerateRequest, startDate: Date = Date()) -> SmartMealPlanGenerateResponse {
        let basePayload = MealPlanGenerateRequest(
            days: payload.days,
            ingredientKeywords: payload.ingredientKeywords,
            expiringSoonKeywords: payload.expiringSoonKeywords,
            targets: payload.targets,
            beveragesKcal: payload.beveragesKcal,
            budget: .init(perDay: payload.budget?.perDay, perMeal: payload.budget?.perMeal),
            exclude: payload.exclude,
            avoidBones: payload.avoidBones,
            cuisine: payload.cuisine
        )

        let basePlan = generateMealPlan(payload: basePayload, startDate: startDate)

        let explanation = [
            "Локальный smart-режим использует приближённую оценку цены по ингредиентам.",
            "Для более точной оптимизации подключите backend рецептов."
        ]

        return .init(
            days: basePlan.days,
            shoppingList: basePlan.shoppingList,
            estimatedTotalCost: basePlan.estimatedTotalCost,
            warnings: basePlan.warnings,
            objective: payload.objective ?? "cost_macro",
            optimizerProfile: payload.optimizerProfile,
            costConfidence: 0.42,
            priceExplanation: explanation
        )
    }
}

private extension LocalRecipeCatalog {
    static func loadRecipes(datasetPathOverride: String?, fileManager: FileManager) -> (items: [Recipe], source: String) {
        let candidateURLs = datasetCandidateURLs(datasetPathOverride: datasetPathOverride)

        for candidateURL in candidateURLs {
            guard fileManager.fileExists(atPath: candidateURL.path) else {
                continue
            }

            guard let data = try? Data(contentsOf: candidateURL), let decoded = decodeRecipes(data) else {
                continue
            }

            let hydrated = decoded.map(hydrateRecipe)
            guard !hydrated.isEmpty else {
                continue
            }

            return (hydrated, candidateURL.lastPathComponent)
        }

        return (builtinFallbackRecipes, "builtin")
    }

    static func datasetCandidateURLs(datasetPathOverride: String?) -> [URL] {
        var urls: [URL] = []

        if let datasetPathOverride {
            let trimmed = datasetPathOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                urls.append(URL(fileURLWithPath: trimmed))
            }
        }

        guard let repositoryRootURL else {
            return urls
        }

        urls.append(repositoryRootURL.appendingPathComponent("ios/DataSources/External/index/recipe_catalog.json"))
        urls.append(repositoryRootURL.appendingPathComponent("ios/DataSources/Seed/recipes_seed.json"))
        return urls
    }

    static var repositoryRootURL: URL? {
        let fileURL = URL(fileURLWithPath: #filePath)
        let servicesURL = fileURL.deletingLastPathComponent()
        let iosURL = servicesURL.deletingLastPathComponent()
        return iosURL.deletingLastPathComponent()
    }

    static func decodeRecipes(_ data: Data) -> [Recipe]? {
        let decoder = JSONDecoder()

        if let payload = try? decoder.decode(SeedPayload.self, from: data), !payload.items.isEmpty {
            return payload.items
        }

        if let direct = try? decoder.decode([Recipe].self, from: data), !direct.isEmpty {
            return direct
        }

        return nil
    }

    static func hydrateRecipe(_ recipe: Recipe) -> Recipe {
        var hydrated = recipe

        if hydrated.ingredients.isEmpty {
            hydrated.ingredients = ["ингредиенты не указаны"]
        }
        if hydrated.instructions.isEmpty {
            hydrated.instructions = ["Смешайте ингредиенты и приготовьте до готовности."]
        }
        if hydrated.tags.isEmpty {
            hydrated.tags = []
        }
        if hydrated.totalTimeMinutes == nil {
            hydrated.totalTimeMinutes = max(12, min(90, hydrated.instructions.count * 6 + hydrated.ingredients.count * 2))
        }
        if hydrated.servings == nil {
            hydrated.servings = 2
        }

        let nutrition = resolvedNutrition(for: hydrated)
        hydrated.nutrition = nutrition

        return hydrated
    }

    static func resolvedNutrition(for recipe: Recipe) -> Nutrition {
        let existing = recipe.nutrition ?? .empty
        let estimated = estimatedNutrition(for: recipe)

        return Nutrition(
            kcal: existing.kcal ?? estimated.kcal,
            protein: existing.protein ?? estimated.protein,
            fat: existing.fat ?? estimated.fat,
            carbs: existing.carbs ?? estimated.carbs
        )
    }

    static func estimatedNutrition(for recipe: Recipe) -> Nutrition {
        let ingredientCount = Double(max(3, recipe.ingredients.count))
        let instructionsCount = Double(max(1, recipe.instructions.count))

        let protein = max(12, ingredientCount * 2.8 + instructionsCount)
        let fat = max(8, ingredientCount * 1.6 + (instructionsCount * 0.5))
        let kcal = max(300, ingredientCount * 95 + instructionsCount * 12)
        let carbs = max(18, (kcal - protein * 4 - fat * 9) / 4)

        return Nutrition(
            kcal: round2(kcal),
            protein: round2(protein),
            fat: round2(fat),
            carbs: round2(carbs)
        )
    }

    static func averageMacroDeviation(target: Nutrition, actual: Nutrition) -> Double {
        let pairs: [(Double?, Double?)] = [
            (target.kcal, actual.kcal),
            (target.protein, actual.protein),
            (target.fat, actual.fat),
            (target.carbs, actual.carbs)
        ]

        var deviations: [Double] = []
        for pair in pairs {
            guard let targetValue = pair.0, let actualValue = pair.1, targetValue > 0 else {
                continue
            }
            deviations.append(abs(actualValue - targetValue) / targetValue)
        }

        guard !deviations.isEmpty else {
            return 0.45
        }

        return deviations.reduce(0, +) / Double(deviations.count)
    }

    static func overlapScore(ingredients: [String], keywords: Set<String>) -> Double {
        guard !keywords.isEmpty, !ingredients.isEmpty else {
            return 0
        }

        let normalizedIngredients = ingredients.map(normalizeIngredient)
        let matched = normalizedIngredients.filter { ingredient in
            keywords.contains { keyword in
                ingredient.contains(keyword) || keyword.contains(ingredient)
            }
        }

        return Double(matched.count) / Double(normalizedIngredients.count)
    }

    static func containsDislikedIngredient(_ recipe: Recipe, disliked: Set<String>) -> Bool {
        guard !disliked.isEmpty else {
            return false
        }

        return recipe.ingredients
            .map(normalizeIngredient)
            .contains { ingredient in
                disliked.contains { disliked in
                    ingredient.contains(disliked)
                }
            }
    }

    static func matchesCuisine(_ recipe: Recipe, allowedCuisine: Set<String>) -> Bool {
        guard !allowedCuisine.isEmpty else {
            return true
        }

        let fields = [recipe.cuisine ?? ""] + recipe.tags
        let normalizedFields = fields.map(normalizeToken)

        return allowedCuisine.contains { cuisine in
            normalizedFields.contains { field in
                field.contains(cuisine)
            }
        }
    }

    static func recipeLikelyContainsBones(_ recipe: Recipe) -> Bool {
        let fields = recipe.ingredients + recipe.tags
        let normalized = fields.map(normalizeToken)

        return normalized.contains { item in
            item.contains("кост") || item.contains("bone")
        }
    }

    static func budgetScore(recipe: Recipe, perMealBudget: Double?) -> Double {
        guard let perMealBudget, perMealBudget > 0 else {
            return 0.55
        }

        let estimatedCost = estimatedMealCost(for: recipe)
        return max(0, 1 - (estimatedCost / perMealBudget))
    }

    static func estimatedMealCost(for recipe: Recipe) -> Double {
        let ingredientFactor = Double(max(1, recipe.ingredients.count)) * 32
        let macroFactor = (resolvedNutrition(for: recipe).protein ?? 0) * 0.9
        return round2(max(75, min(1_500, ingredientFactor + macroFactor)))
    }

    static func divideNutrition(_ value: Nutrition, by divisor: Double) -> Nutrition {
        let safe = max(1, divisor)
        return Nutrition(
            kcal: value.kcal.map { $0 / safe },
            protein: value.protein.map { $0 / safe },
            fat: value.fat.map { $0 / safe },
            carbs: value.carbs.map { $0 / safe }
        )
    }

    static func resolvePerMealBudget(_ budget: MealPlanGenerateRequest.Budget?) -> Double? {
        if let perMeal = budget?.perMeal, perMeal > 0 {
            return perMeal
        }
        if let perDay = budget?.perDay, perDay > 0 {
            return perDay / 3
        }
        return nil
    }

    static func pickForMeal(
        ranked: [RecommendResponse.RankedRecipe],
        usedToday: Set<String>,
        usedCount: [String: Int]
    ) -> RecommendResponse.RankedRecipe? {
        let sorted = ranked.sorted { lhs, rhs in
            let lhsCount = usedCount[lhs.recipe.id] ?? 0
            let rhsCount = usedCount[rhs.recipe.id] ?? 0

            if lhsCount == rhsCount {
                return lhs.score > rhs.score
            }
            return lhsCount < rhsCount
        }

        if let fresh = sorted.first(where: { !usedToday.contains($0.recipe.id) }) {
            return fresh
        }

        return sorted.first
    }

    static func ingredientCovered(_ ingredient: String, keywords: Set<String>) -> Bool {
        guard !keywords.isEmpty else {
            return false
        }

        let normalizedIngredient = normalizeIngredient(ingredient)
        return keywords.contains { keyword in
            normalizedIngredient.contains(keyword) || keyword.contains(normalizedIngredient)
        }
    }

    static func normalizeIngredient(_ value: String) -> String {
        let withoutDetails = value.components(separatedBy: "(").first ?? value
        return normalizeToken(withoutDetails)
    }

    static func normalizeToken(_ value: String) -> String {
        let lowered = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else {
            return ""
        }

        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let scalars = lowered.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : " "
        }

        let compact = String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        return compact
    }

    static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    static let builtinFallbackRecipes: [Recipe] = [
        Recipe(
            id: "local:omelet",
            sourceURL: URL(string: "https://example.com/omelet")!,
            sourceName: "Local",
            title: "Омлет с томатами",
            imageURL: URL(string: "https://images.unsplash.com/photo-1510693206972-df098062cb71")!,
            videoURL: nil,
            ingredients: ["яйца", "помидоры", "молоко"],
            instructions: ["Взбейте яйца с молоком.", "Добавьте томаты и обжарьте 5-7 минут."],
            totalTimeMinutes: 15,
            servings: 2,
            cuisine: "домашняя",
            tags: ["завтрак", "быстро"],
            nutrition: Nutrition(kcal: 390, protein: 24, fat: 24, carbs: 14)
        ),
        Recipe(
            id: "local:chicken-rice",
            sourceURL: URL(string: "https://example.com/chicken-rice")!,
            sourceName: "Local",
            title: "Курица с рисом",
            imageURL: URL(string: "https://images.unsplash.com/photo-1512058564366-18510be2db19")!,
            videoURL: nil,
            ingredients: ["куриное филе", "рис", "морковь", "лук"],
            instructions: ["Отварите рис.", "Обжарьте курицу с овощами.", "Смешайте и прогрейте."],
            totalTimeMinutes: 35,
            servings: 2,
            cuisine: "домашняя",
            tags: ["обед", "ужин"],
            nutrition: Nutrition(kcal: 560, protein: 39, fat: 16, carbs: 59)
        ),
        Recipe(
            id: "local:cottage-bowl",
            sourceURL: URL(string: "https://example.com/cottage-bowl")!,
            sourceName: "Local",
            title: "Творожная миска с ягодами",
            imageURL: URL(string: "https://images.unsplash.com/photo-1488477181946-6428a0291777")!,
            videoURL: nil,
            ingredients: ["творог", "ягоды", "мёд", "грецкий орех"],
            instructions: ["Смешайте творог с ягодами.", "Добавьте мёд и орехи."],
            totalTimeMinutes: 8,
            servings: 1,
            cuisine: "домашняя",
            tags: ["завтрак", "перекус"],
            nutrition: Nutrition(kcal: 430, protein: 31, fat: 18, carbs: 35)
        )
    ]
}
