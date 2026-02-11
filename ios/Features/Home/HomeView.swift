import SwiftUI

struct HomeView: View {
    enum TimeFilter: String, CaseIterable, Identifiable {
        case any
        case upTo15
        case upTo30
        case upTo60

        var id: String { rawValue }

        var title: String {
            switch self {
            case .any: return "Любое"
            case .upTo15: return "до 15 мин"
            case .upTo30: return "до 30 мин"
            case .upTo60: return "до 60 мин"
            }
        }

        var maxMinutes: Int? {
            switch self {
            case .any: return nil
            case .upTo15: return 15
            case .upTo30: return 30
            case .upTo60: return 60
            }
        }
    }

    let inventoryService: any InventoryServiceProtocol
    let settingsService: any SettingsServiceProtocol
    let recipeServiceClient: RecipeServiceClient?

    @State private var expiringSoon: [Batch] = []
    @State private var productsByID: [UUID: Product] = [:]
    @State private var ingredientKeywords: [String] = []
    @State private var settings: AppSettings = .default

    @State private var recommended: [RecommendResponse.RankedRecipe] = []
    @State private var searchedRecipes: [Recipe] = []

    @State private var searchText = ""
    @State private var onlyInStock = false
    @State private var hideBones = false
    @State private var selectedTimeFilter: TimeFilter = .any

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            urgentSection
            filtersSection
            recipesSection
            if let errorMessage {
                Section("Статус") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Что приготовить")
        .searchable(text: $searchText, prompt: "Поиск рецептов")
        .task {
            await loadInitialData()
        }
        .onChange(of: searchText) { _, newValue in
            Task {
                await handleSearchChange(newValue)
            }
        }
        .onChange(of: onlyInStock) { _, _ in
            Task { await refreshRecommendations() }
        }
        .onChange(of: hideBones) { _, _ in
            Task { await refreshRecommendations() }
        }
        .onChange(of: selectedTimeFilter) { _, _ in
            Task { await refreshRecommendations() }
        }
        .refreshable {
            await loadInitialData()
        }
    }

    @ViewBuilder
    private var urgentSection: some View {
        Section("Срочно использовать") {
            if expiringSoon.isEmpty {
                Text("Нет продуктов с близким сроком")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(expiringSoon) { batch in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(productsByID[batch.productId]?.name ?? "Продукт")
                            .font(.headline)
                        if let expiryDate = batch.expiryDate {
                            Text("Срок: \(expiryDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var filtersSection: some View {
        Section("Фильтры") {
            Toggle("Только из того, что есть", isOn: $onlyInStock)
            Toggle("Без костей", isOn: $hideBones)

            Picker("Время", selection: $selectedTimeFilter) {
                ForEach(TimeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
        }
    }

    @ViewBuilder
    private var recipesSection: some View {
        Section(sectionTitle) {
            if isLoading {
                HStack {
                    SwiftUI.ProgressView()
                    Text("Обновляем рекомендации...")
                }
            }

            if displayedRecipes.isEmpty, !isLoading {
                Text("Пока нет подходящих рецептов")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedRecipes) { item in
                    NavigationLink {
                        RecipeView(recipe: item.recipe, availableIngredients: Set(ingredientKeywords))
                    } label: {
                        RecipeCardView(recipe: item.recipe, score: item.score)
                    }
                }
            }
        }
    }

    private var sectionTitle: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Рекомендации" : "Результаты поиска"
    }

    private var displayedRecipes: [RankedRecipeItem] {
        let rawItems: [RankedRecipeItem]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawItems = recommended.map { .init(recipe: $0.recipe, score: $0.score) }
        } else {
            rawItems = searchedRecipes.map { .init(recipe: $0, score: nil) }
        }

        return rawItems.filter { item in
            guard let maxTime = selectedTimeFilter.maxMinutes else { return true }
            guard let recipeMinutes = item.recipe.totalTimeMinutes else { return true }
            return recipeMinutes <= maxTime
        }
    }

    private func loadInitialData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let productsTask = inventoryService.listProducts(location: nil, search: nil)
            async let expiringTask = inventoryService.expiringBatches(horizonDays: 5)
            async let settingsTask = settingsService.loadSettings()

            let products = try await productsTask
            let expiring = try await expiringTask
            let loadedSettings = try await settingsTask

            productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            ingredientKeywords = Array(Set(products.map { normalize($0.name) })).sorted()
            expiringSoon = expiring
            settings = loadedSettings
            hideBones = loadedSettings.avoidBones

            await refreshRecommendations()
        } catch {
            errorMessage = "Не удалось загрузить данные: \(error.localizedDescription)"
        }
    }

    private func handleSearchChange(_ query: String) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            searchedRecipes = []
            await refreshRecommendations()
            return
        }

        guard let recipeServiceClient else {
            errorMessage = "Сервис рецептов недоступен"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            searchedRecipes = try await recipeServiceClient.search(query: normalized)
            errorMessage = nil
        } catch {
            errorMessage = "Ошибка поиска рецептов: \(error.localizedDescription)"
        }
    }

    private func refreshRecommendations() async {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        guard let recipeServiceClient else {
            errorMessage = "Сервис рецептов недоступен"
            return
        }

        let expiringKeywords = Array(Set(expiringSoon.compactMap { batch in
            productsByID[batch.productId].map { normalize($0.name) }
        })).sorted()

        guard !ingredientKeywords.isEmpty || !expiringKeywords.isEmpty else {
            recommended = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let budgetPerMeal = NSDecimalNumber(decimal: settings.budgetDay).doubleValue / 3.0
            let payload = RecommendRequest(
                ingredientKeywords: ingredientKeywords,
                expiringSoonKeywords: expiringKeywords,
                targets: .init(kcal: 650, protein: 40, fat: 22, carbs: 65),
                budget: .init(perMeal: budgetPerMeal > 0 ? budgetPerMeal : nil),
                exclude: settings.dislikedList,
                avoidBones: hideBones,
                cuisine: [],
                limit: 30
            )

            let response = try await recipeServiceClient.recommend(payload: payload)
            let items = response.items
                .filter { item in
                    if !onlyInStock { return true }
                    return item.recipe.ingredients.allSatisfy { ingredient in
                        ingredientKeywords.contains(normalize(ingredient))
                    }
                }

            recommended = items
            errorMessage = nil
        } catch {
            errorMessage = "Не удалось получить рекомендации: \(error.localizedDescription)"
        }
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct RankedRecipeItem: Identifiable {
    var id: String { recipe.id }
    let recipe: Recipe
    let score: Double?
}

private struct RecipeCardView: View {
    let recipe: Recipe
    let score: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: recipe.imageURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(.gray.opacity(0.15))
                    .overlay(SwiftUI.ProgressView())
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(recipe.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 10) {
                if let minutes = recipe.totalTimeMinutes {
                    Label("\(minutes) мин", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let kcal = recipe.nutrition?.kcal {
                    Label("\(Int(kcal.rounded())) ккал", systemImage: "flame")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let score {
                    Label(score.formatted(.number.precision(.fractionLength(2))), systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(recipe.sourceName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
