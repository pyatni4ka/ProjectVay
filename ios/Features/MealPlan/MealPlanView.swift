import SwiftUI

struct MealPlanView: View {
    enum PlanRange: String, CaseIterable, Identifiable {
        case day
        case week

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: return "День"
            case .week: return "Неделя"
            }
        }

        var daysCount: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            }
        }
    }

    let inventoryService: any InventoryServiceProtocol
    let settingsService: any SettingsServiceProtocol
    let healthKitService: HealthKitService
    let recipeServiceClient: RecipeServiceClient?
    var onOpenScanner: () -> Void = {}

    @State private var selectedRange: PlanRange = .day
    @State private var mealPlan: MealPlanGenerateResponse?
    @State private var macroGoalSource: AppSettings.MacroGoalSource = .automatic
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastGeneratedAt: Date?
    @State private var dayTargetNutrition = Nutrition(kcal: 2200, protein: 140, fat: 70, carbs: 220)
    @State private var consumedTodayNutrition = Nutrition(kcal: 0, protein: 0, fat: 0, carbs: 0)
    @State private var remainingTodayNutrition = Nutrition(kcal: 2200, protein: 140, fat: 70, carbs: 220)
    @State private var nextMealTargetNutrition = Nutrition(kcal: 730, protein: 47, fat: 23, carbs: 73)
    @State private var nextMealSlot: AdaptiveNutritionUseCase.MealSlot = .breakfast
    @State private var nextMealRecommendations: [RecommendResponse.RankedRecipe] = []
    @State private var healthStatusMessage: String?
    @State private var offlineStatusMessage: String?
    @State private var hasRequestedHealthAccess = false
    @State private var hasInventoryProducts = true
    @State private var availableIngredients: Set<String> = []
    private let todayMenuSnapshotStore = TodayMenuSnapshotStore()

    var body: some View {
        ScrollView {
            VStack(spacing: VaySpacing.lg) {
                periodCard
                nutritionCard
                if let offlineStatusMessage {
                    offlineBanner(offlineStatusMessage)
                }

                if isLoading {
                    loadingCard
                }

                if !hasInventoryProducts, !isLoading {
                    EmptyStateView(
                        icon: "fork.knife",
                        title: "Нет продуктов для генерации плана",
                        subtitle: "Добавьте хотя бы один продукт в инвентарь, чтобы построить персональный план.",
                        actionTitle: "Сканировать товар",
                        action: onOpenScanner
                    )
                } else {
                    if !nextMealRecommendations.isEmpty {
                        recommendationsSection
                    }

                    if let mealPlan {
                        mealPlanSection(mealPlan)
                    }
                }

                if let errorMessage {
                    errorCard(errorMessage)
                }


                Color.clear.frame(height: VayLayout.tabBarOverlayInset)
            }
            .padding(.horizontal, VaySpacing.lg)
        }
        .background(Color.vayBackground)
        .navigationTitle("План питания")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: onOpenScanner) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.vayPrimary)
                }
                .vayAccessibilityLabel("Открыть сканер", hint: "Добавить продукты для плана")

                Button("Сгенерировать") {
                    Task { await generatePlan() }
                }
                .disabled(isLoading)
            }
        }
        .task {
            await generatePlan()
        }
        .onChange(of: selectedRange) { _, _ in
            Task { await generatePlan() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsDidChange)) { _ in
            Task { await generatePlan() }
        }
    }

    private var periodCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            Text("Период")
                .font(VayFont.heading(16))

            Picker("Период", selection: $selectedRange) {
                ForEach(PlanRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .vayAccessibilityLabel("Выбор периода плана", hint: "День или неделя")
        }
        .vayCard()
    }

    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack {
                Text(nutritionCardTitle)
                    .font(VayFont.heading(16))
                Spacer()
                Text(nextMealSlot.title)
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
            }

            NutritionRingGroup(
                kcal: resolved(consumedTodayNutrition.kcal),
                protein: resolved(consumedTodayNutrition.protein),
                fat: resolved(consumedTodayNutrition.fat),
                carbs: resolved(consumedTodayNutrition.carbs),
                kcalGoal: resolved(dayTargetNutrition.kcal),
                proteinGoal: resolved(dayTargetNutrition.protein),
                fatGoal: resolved(dayTargetNutrition.fat),
                carbsGoal: resolved(dayTargetNutrition.carbs)
            )
            .frame(maxWidth: .infinity)
            .vayAccessibilityLabel("Кольца КБЖУ: съедено сегодня относительно цели")

            nutritionRow(title: "Цель на день", nutrition: dayTargetNutrition)
            nutritionRow(title: "Съедено сегодня", nutrition: consumedTodayNutrition)
            nutritionRow(title: "Остаток на сегодня", nutrition: remainingTodayNutrition)
            nutritionRow(title: "Таргет на \(nextMealSlot.title.lowercased())", nutrition: nextMealTargetNutrition)

            if let healthStatusMessage {
                Text(healthStatusMessage)
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }
        }
        .vayCard()
    }

    private var loadingCard: some View {
        HStack(spacing: VaySpacing.sm) {
            SwiftUI.ProgressView()
            Text("Генерируем план...")
                .font(VayFont.body(14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VaySpacing.lg)
        .vayCard()
    }

    private var nutritionCardTitle: String {
        switch macroGoalSource {
        case .automatic:
            return "КБЖУ (Apple Health / Yazio)"
        case .manual:
            return "КБЖУ (ручная цель)"
        }
    }

    private func offlineBanner(_ text: String) -> some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(Color.vayWarning)
            Text(text)
                .font(VayFont.body(13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Повторить") {
                Task { await generatePlan() }
            }
            .font(VayFont.label(12))
            .buttonStyle(.borderedProminent)
            .tint(Color.vayPrimary)
        }
        .padding(VaySpacing.md)
        .background(Color.vayPrimaryLight.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
        .vayAccessibilityLabel("Оффлайн-режим: \(text)")
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            Text("Рекомендации на \(nextMealSlot.title.lowercased())")
                .font(VayFont.heading(16))

            ForEach(Array(nextMealRecommendations.prefix(5)), id: \.recipe.id) { item in
                NavigationLink {
                    RecipeView(
                        recipe: item.recipe,
                        availableIngredients: availableIngredients,
                        inventoryService: inventoryService,
                        onInventoryChanged: {}
                    )
                } label: {
                    recommendationRow(item)
                }
                .buttonStyle(.plain)
            }
        }
        .vayCard()
    }

    private func mealPlanSection(_ mealPlan: MealPlanGenerateResponse) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            ForEach(mealPlan.days) { day in
                VStack(alignment: .leading, spacing: VaySpacing.md) {
                    HStack {
                        Text(day.date)
                            .font(VayFont.heading(16))
                        Spacer()
                        Text("~\(day.totals.estimatedCost.formatted(.number.precision(.fractionLength(0)))) ₽")
                            .font(VayFont.caption(12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(VaySpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(VayGradient.cool.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))

                    ForEach(day.entries) { entry in
                        NavigationLink {
                            RecipeView(
                                recipe: entry.recipe,
                                availableIngredients: availableIngredients,
                                inventoryService: inventoryService,
                                onInventoryChanged: {}
                            )
                        } label: {
                            mealEntryCard(entry)
                        }
                        .buttonStyle(.plain)
                    }

                    if !day.missingIngredients.isEmpty {
                        Text("Не хватает: \(day.missingIngredients.joined(separator: ", "))")
                            .font(VayFont.caption(11))
                            .foregroundStyle(.secondary)
                            .vayAccessibilityLabel("Не хватает ингредиентов: \(day.missingIngredients.joined(separator: ", "))")
                    }
                }
                .padding(VaySpacing.md)
                .background(Color.vayCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous))
            }

            if !mealPlan.shoppingList.isEmpty {
                VStack(alignment: .leading, spacing: VaySpacing.sm) {
                    Text("Покупки")
                        .font(VayFont.heading(15))
                    ForEach(mealPlan.shoppingList, id: \.self) { item in
                        Label(item, systemImage: "cart")
                            .font(VayFont.body(14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(VaySpacing.md)
                .background(Color.vayPrimaryLight.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
            }

            VStack(alignment: .leading, spacing: VaySpacing.xs) {
                Text("Оценка стоимости: \(mealPlan.estimatedTotalCost.formatted(.number.precision(.fractionLength(0)))) ₽")
                    .font(VayFont.body(14))
                if let lastGeneratedAt {
                    Text("Обновлено: \(lastGeneratedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                }
                if !mealPlan.warnings.isEmpty {
                    ForEach(mealPlan.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(VayFont.caption(11))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .vayAccessibilityLabel("Итоги плана и предупреждения")
        }
        .vayCard()
    }

    private func errorCard(_ text: String) -> some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.vayDanger)
            Text(text)
                .font(VayFont.body(14))
                .foregroundStyle(Color.vayDanger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VaySpacing.md)
        .background(Color.vayDanger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
        .vayAccessibilityLabel("Ошибка генерации плана: \(text)")
    }

    private func nutritionRow(title: String, nutrition: Nutrition) -> some View {
        HStack {
            Text(title)
                .font(VayFont.body(14))
            Spacer()
            Text(nutritionSummary(nutrition))
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)
        }
        .vayAccessibilityLabel("\(title): \(nutritionSummary(nutrition))")
    }

    private func recommendationRow(_ item: RecommendResponse.RankedRecipe) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            HStack {
                Text(item.recipe.title)
                    .font(VayFont.heading(15))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(item.score.formatted(.number.precision(.fractionLength(2))))")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }

            Text(nutritionSummary(item.recipe.nutrition ?? .empty))
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)
        }
        .padding(VaySpacing.md)
        .background(Color.vayCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous)
                .stroke(Color.vayPrimary.opacity(0.15), lineWidth: 1)
        )
        .vayAccessibilityLabel("\(item.recipe.title), \(nutritionSummary(item.recipe.nutrition ?? .empty))")
    }

    private func mealEntryCard(_ entry: MealPlanGenerateResponse.Day.Entry) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            HStack {
                Text(mealTypeTitle(entry.mealType))
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.kcal.formatted(.number.precision(.fractionLength(0)))) ккал")
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
            }

            Text(entry.recipe.title)
                .font(VayFont.heading(15))

            Text("~\(entry.estimatedCost.formatted(.number.precision(.fractionLength(0)))) ₽")
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)
        }
        .padding(VaySpacing.md)
        .background(
            LinearGradient(
                colors: [Color.vayPrimaryLight.opacity(0.55), Color.vayCardBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
        .vayAccessibilityLabel("\(mealTypeTitle(entry.mealType)): \(entry.recipe.title), \(entry.kcal.formatted(.number.precision(.fractionLength(0)))) ккал")
    }

    private func generatePlan() async {
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
            macroGoalSource = settings.macroGoalSource

            let nutritionSnapshot = await computeAdaptiveNutritionSnapshot(settings: settings)

            dayTargetNutrition = selectedRange == .day ? nutritionSnapshot.planDayTarget : nutritionSnapshot.baselineDayTarget
            consumedTodayNutrition = nutritionSnapshot.consumedToday
            remainingTodayNutrition = nutritionSnapshot.remainingToday
            nextMealTargetNutrition = nutritionSnapshot.nextMealTarget
            nextMealSlot = nutritionSnapshot.nextMealSlot
            healthStatusMessage = nutritionSnapshot.statusMessage

            let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            let ingredientKeywords = Array(Set(products.map { $0.name.lowercased() })).sorted()
            availableIngredients = Set(ingredientKeywords)
            let expiringSoonKeywords = Array(
                Set(
                    expiringBatches.compactMap { batch in
                        productsByID[batch.productId]?.name.lowercased()
                    }
                )
            ).sorted()

            guard !ingredientKeywords.isEmpty else {
                hasInventoryProducts = false
                mealPlan = nil
                nextMealRecommendations = []
                offlineStatusMessage = nil
                errorMessage = nil
                return
            }

            hasInventoryProducts = true

            guard let recipeServiceClient else {
                offlineStatusMessage = "Сервис рецептов сейчас недоступен."
                errorMessage = nil
                return
            }

            let budgetPerDay = NSDecimalNumber(decimal: settings.budgetDay).doubleValue
            let payload = MealPlanGenerateRequest(
                days: selectedRange.daysCount,
                ingredientKeywords: ingredientKeywords,
                expiringSoonKeywords: expiringSoonKeywords,
                targets: selectedRange == .day ? nutritionSnapshot.planDayTarget : nutritionSnapshot.baselineDayTarget,
                beveragesKcal: 120,
                budget: .init(perDay: budgetPerDay > 0 ? budgetPerDay : nil, perMeal: nil),
                exclude: settings.dislikedList,
                avoidBones: settings.avoidBones,
                cuisine: []
            )

            let generated = try await recipeServiceClient.generateMealPlan(payload: payload)
            mealPlan = generated
            offlineStatusMessage = nil
            persistTodayMenuSnapshot(from: generated)

            let nextMealBudget = budgetPerDay > 0 ? budgetPerDay / Double(max(1, nutritionSnapshot.remainingMealsCount)) : nil
            do {
                let recommendPayload = RecommendRequest(
                    ingredientKeywords: ingredientKeywords,
                    expiringSoonKeywords: expiringSoonKeywords,
                    targets: nutritionSnapshot.nextMealTarget,
                    budget: .init(perMeal: nextMealBudget),
                    exclude: settings.dislikedList,
                    avoidBones: settings.avoidBones,
                    cuisine: [],
                    limit: 25,
                    strictNutrition: settings.strictMacroTracking,
                    macroTolerancePercent: settings.macroTolerancePercent
                )
                let recommended = try await recipeServiceClient.recommend(payload: recommendPayload)
                let macroFiltered = MacroRecommendationFilterUseCase().execute(
                    items: recommended.items,
                    target: nutritionSnapshot.nextMealTarget,
                    strictTracking: settings.strictMacroTracking,
                    tolerancePercent: settings.macroTolerancePercent,
                    strictAppliedNote: "Рекомендации отфильтрованы строго по КБЖУ (±\(Int(settings.macroTolerancePercent))%).",
                    fallbackNote: "Строгий фильтр КБЖУ не дал точных совпадений, показаны ближайшие блюда.",
                    fallbackLimit: 10
                )
                nextMealRecommendations = macroFiltered.items

                if let note = macroFiltered.note {
                    if let current = healthStatusMessage, !current.isEmpty {
                        healthStatusMessage = "\(current) \(note)"
                    } else {
                        healthStatusMessage = note
                    }
                }
            } catch {
                nextMealRecommendations = []
                let fallback = "Не удалось обновить рекомендации на следующий приём."
                if let current = healthStatusMessage, !current.isEmpty {
                    healthStatusMessage = "\(current) \(fallback)"
                } else {
                    healthStatusMessage = fallback
                }
                if let offlineMessage = offlineMessage(for: error, hasCachedPlan: mealPlan != nil) {
                    offlineStatusMessage = offlineMessage
                }
            }

            errorMessage = nil
            lastGeneratedAt = Date()
        } catch {
            if let offlineMessage = offlineMessage(for: error, hasCachedPlan: mealPlan != nil) {
                offlineStatusMessage = offlineMessage
                errorMessage = nil
            } else {
                offlineStatusMessage = nil
                errorMessage = "Не удалось сгенерировать план: \(userFacingErrorMessage(error))"
            }
        }
    }

    private func persistTodayMenuSnapshot(from plan: MealPlanGenerateResponse) {
        guard let firstDay = plan.days.first, !firstDay.entries.isEmpty else {
            return
        }

        let items = firstDay.entries.map { entry in
            TodayMenuSnapshot.Item(
                mealType: entry.mealType,
                title: entry.recipe.title,
                kcal: entry.kcal
            )
        }

        let snapshot = TodayMenuSnapshot(
            generatedAt: Date(),
            items: items,
            estimatedCost: firstDay.totals.estimatedCost
        )
        todayMenuSnapshotStore.save(snapshot)
    }

    private func computeAdaptiveNutritionSnapshot(settings: AppSettings) async -> AdaptiveNutritionUseCase.Output {
        if settings.healthKitReadEnabled, !hasRequestedHealthAccess {
            hasRequestedHealthAccess = true
            _ = try? await healthKitService.requestReadAccess()
        }

        var automaticDailyCalories: Double?
        var weightKG: Double?
        if settings.healthKitReadEnabled, settings.macroGoalSource == .automatic {
            do {
                let metrics = try await healthKitService.fetchLatestMetrics()
                automaticDailyCalories = Double(
                    healthKitService.calculateDailyCalories(
                        metrics: metrics,
                        targetLossPerWeek: settings.dietProfile.targetLossPerWeek
                    )
                )
                weightKG = metrics.weightKG
            } catch {
                automaticDailyCalories = nil
                weightKG = nil
            }
        }

        var consumedNutrition: Nutrition?
        var consumedFetchFailed = false
        if settings.healthKitReadEnabled {
            do {
                consumedNutrition = try await healthKitService.fetchTodayConsumedNutrition()
            } catch {
                consumedFetchFailed = true
            }
        }

        return AdaptiveNutritionUseCase().execute(
            .init(
                settings: settings,
                range: selectedRange == .day ? .day : .week,
                automaticDailyCalories: automaticDailyCalories,
                weightKG: weightKG,
                consumedNutrition: consumedNutrition,
                consumedFetchFailed: consumedFetchFailed,
                healthIntegrationEnabled: settings.healthKitReadEnabled
            )
        )
    }

    private func offlineMessage(for error: Error, hasCachedPlan: Bool) -> String? {
        guard let clientError = RecipeServiceClientError.from(error) else {
            return nil
        }

        guard clientError == .noConnection || clientError == .offlineMode else {
            return nil
        }

        let baseText = clientError.errorDescription ?? "Нет подключения к серверу рецептов."
        if hasCachedPlan {
            return "\(baseText) Показываем последний доступный план."
        }
        return "\(baseText) Сохранённый план пока недоступен."
    }

    private func userFacingErrorMessage(_ error: Error) -> String {
        if let clientError = RecipeServiceClientError.from(error) {
            return clientError.errorDescription ?? "Ошибка сервера рецептов."
        }
        return error.localizedDescription
    }

    private func resolved(_ value: Double?) -> Double {
        max(0, value ?? 0)
    }

    private func nutritionSummary(_ nutrition: Nutrition) -> String {
        "К \(numberText(nutrition.kcal)) · Б \(numberText(nutrition.protein)) · Ж \(numberText(nutrition.fat)) · У \(numberText(nutrition.carbs))"
    }

    private func numberText(_ value: Double?) -> String {
        resolved(value).formatted(.number.precision(.fractionLength(0)))
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
