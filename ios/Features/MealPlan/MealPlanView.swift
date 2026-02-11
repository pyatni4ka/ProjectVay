import SwiftUI

struct MealPlanView: View {
    enum PlanRange: String, CaseIterable, Identifiable {
        case day
        case week

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day:
                return "День"
            case .week:
                return "Неделя"
            }
        }

        var daysCount: Int {
            switch self {
            case .day:
                return 1
            case .week:
                return 7
            }
        }
    }

    let inventoryService: any InventoryServiceProtocol
    let settingsService: any SettingsServiceProtocol
    let recipeServiceClient: RecipeServiceClient?

    @State private var selectedRange: PlanRange = .day
    @State private var mealPlan: MealPlanGenerateResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastGeneratedAt: Date?

    var body: some View {
        List {
            Section {
                Picker("Период", selection: $selectedRange) {
                    ForEach(PlanRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
            }

            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Генерируем план...")
                    }
                }
            }

            if let mealPlan {
                ForEach(mealPlan.days) { day in
                    Section(day.date) {
                        ForEach(day.entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(mealTypeTitle(entry.mealType)): \(entry.recipe.title)")
                                    .font(.headline)
                                Text("\(entry.kcal.formatted(.number.precision(.fractionLength(0)))) ккал · ~\(entry.estimatedCost.formatted(.number.precision(.fractionLength(0)))) ₽")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !day.missingIngredients.isEmpty {
                            Text("Не хватает: \(day.missingIngredients.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !mealPlan.shoppingList.isEmpty {
                    Section("Покупки") {
                        ForEach(mealPlan.shoppingList, id: \.self) { item in
                            Text(item)
                        }
                    }
                }

                Section("Итоги") {
                    Text("Оценка стоимости: \(mealPlan.estimatedTotalCost.formatted(.number.precision(.fractionLength(0)))) ₽")
                    if let lastGeneratedAt {
                        Text("Обновлено: \(lastGeneratedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !mealPlan.warnings.isEmpty {
                        ForEach(mealPlan.warnings, id: \.self) { warning in
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if let errorMessage {
                Section("Статус") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("План питания")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Сгенерировать") {
                    Task {
                        await generatePlan()
                    }
                }
                .disabled(isLoading)
            }
        }
        .task {
            await generatePlan()
        }
        .onChange(of: selectedRange) { _, _ in
            Task {
                await generatePlan()
            }
        }
    }

    private func generatePlan() async {
        guard let recipeServiceClient else {
            errorMessage = "Сервис рецептов недоступен. Укажите `RecipeServiceBaseURL` в конфиге приложения."
            return
        }

        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let productsTask = inventoryService.listProducts(location: nil, search: nil)
            async let expiringBatchesTask = inventoryService.expiringBatches(horizonDays: 5)
            async let settingsTask = settingsService.loadSettings()

            let products = try await productsTask
            let expiringBatches = try await expiringBatchesTask
            let settings = try await settingsTask

            let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            let ingredientKeywords = Array(Set(products.map { $0.name.lowercased() })).sorted()
            let expiringSoonKeywords = Array(
                Set(
                    expiringBatches.compactMap { batch in
                        productsByID[batch.productId]?.name.lowercased()
                    }
                )
            ).sorted()

            guard !ingredientKeywords.isEmpty else {
                mealPlan = nil
                errorMessage = "Добавьте продукты в инвентарь, чтобы сгенерировать план."
                return
            }

            let budgetPerDay = NSDecimalNumber(decimal: settings.budgetDay).doubleValue
            let payload = MealPlanGenerateRequest(
                days: selectedRange.daysCount,
                ingredientKeywords: ingredientKeywords,
                expiringSoonKeywords: expiringSoonKeywords,
                targets: Nutrition(kcal: 2200, protein: 150, fat: 70, carbs: 220),
                beveragesKcal: 120,
                budget: .init(perDay: budgetPerDay > 0 ? budgetPerDay : nil, perMeal: nil),
                exclude: settings.dislikedList,
                avoidBones: settings.avoidBones,
                cuisine: []
            )

            let generated = try await recipeServiceClient.generateMealPlan(payload: payload)
            mealPlan = generated
            errorMessage = nil
            lastGeneratedAt = Date()
        } catch {
            errorMessage = "Не удалось сгенерировать план: \(error.localizedDescription)"
        }
    }

    private func mealTypeTitle(_ raw: String) -> String {
        switch raw {
        case "breakfast":
            return "Завтрак"
        case "lunch":
            return "Обед"
        case "dinner":
            return "Ужин"
        default:
            return raw
        }
    }
}
