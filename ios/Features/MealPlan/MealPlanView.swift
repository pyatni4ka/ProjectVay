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
    @EnvironmentObject private var appSettingsStore: AppSettingsStore

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
    @State private var mealPlanDataSource: MealPlanDataSource = .unknown
    @State private var mealPlanDataSourceDetails: String?
    @State private var lastSavedMealPlan: MealPlanSnapshot?
    @State private var suppressAutoGenerate = false
    @State private var hasRequestedHealthAccess = false
    @State private var hasInventoryProducts = true
    @State private var availableIngredients: Set<String> = []
    private let todayMenuSnapshotStore = TodayMenuSnapshotStore()
    private let mealPlanSnapshotStore = MealPlanSnapshotStore()

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
                // Weekly Autopilot — 7-day plan with Replace / Deviation flow
                NavigationLink {
                    WeeklyAutopilotView(
                        inventoryService: inventoryService,
                        settingsService: settingsService,
                        healthKitService: healthKitService,
                        recipeServiceClient: recipeServiceClient,
                        onOpenScanner: onOpenScanner
                    )
                } label: {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.vayPrimary)
                }
                .vayAccessibilityLabel("Автопилот недели — план на 7 дней")

                // Cook Now — quick meal from current inventory
                NavigationLink {
                    CookNowView(
                        inventoryService: inventoryService,
                        recipeServiceClient: recipeServiceClient
                    )
                } label: {
                    Image(systemName: "refrigerator")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.vayPrimary)
                }
                .vayAccessibilityLabel("Что приготовить сейчас из запасов")

                NavigationLink {
                    RecipeImportView(recipeServiceClient: recipeServiceClient)
                } label: {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.vayPrimary)
                }
                .vayAccessibilityLabel("Импортировать рецепт по ссылке")

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
            refreshLastSavedPlan()
            await generatePlan()
        }
        .onChange(of: selectedRange) { _, _ in
            if suppressAutoGenerate { return }
            Task { await generatePlan() }
        }
        .onChange(of: appSettingsStore.settings) { _, _ in
            if suppressAutoGenerate { return }
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

            if let lastSavedMealPlan {
                Button {
                    applySavedMealPlan(lastSavedMealPlan)
                } label: {
                    HStack(spacing: VaySpacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Повторить последний план")
                                .font(VayFont.label(13))
                            Text(
                                "\(lastSavedMealPlan.generatedAt.formatted(date: .abbreviated, time: .shortened)) · \(mealPlanDataSourceTitle(lastSavedMealPlan.dataSource))"
                            )
                            .font(VayFont.caption(11))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.clockwise.circle")
                            .foregroundStyle(Color.vayPrimary)
                    }
                    .padding(VaySpacing.sm)
                    .background(Color.vayCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .vayAccessibilityLabel("Повторить последний план питания")
            }
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
                HStack(spacing: VaySpacing.xs) {
                    Image(systemName: mealPlanDataSourceIcon(mealPlanDataSource))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.vayPrimary)
                    Text("Источник: \(mealPlanDataSourceTitle(mealPlanDataSource))")
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                }
                if let mealPlanDataSourceDetails, !mealPlanDataSourceDetails.isEmpty {
                    Text(mealPlanDataSourceDetails)
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                }
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

            let products = try await productsTask
            let expiringBatches = try await expiringBatchesTask
            let settings = appSettingsStore.settings
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
                mealPlanDataSource = .unknown
                mealPlanDataSourceDetails = nil
                nextMealRecommendations = []
                offlineStatusMessage = nil
                errorMessage = nil
                return
            }

            hasInventoryProducts = true

            guard let recipeServiceClient else {
                offlineStatusMessage = "Сервис рецептов сейчас недоступен."
                mealPlanDataSource = .unknown
                mealPlanDataSourceDetails = "Подключите backend или используйте сохранённый план."
                errorMessage = nil
                return
            }

            var allPriceEntries: [PriceEntry] = []
            for product in products {
                if let history = try? await inventoryService.listPriceHistory(productId: product.id) {
                    allPriceEntries.append(contentsOf: history)
                }
            }

            let ingredientPriceHints = IngredientPriceResolverUseCase().execute(
                ingredients: ingredientKeywords,
                products: products,
                priceEntries: allPriceEntries
            )

            let budgetPerDay = NSDecimalNumber(decimal: settings.budgetDay).doubleValue
            let smartPayload = SmartMealPlanGenerateRequest(
                days: selectedRange.daysCount,
                ingredientKeywords: ingredientKeywords,
                expiringSoonKeywords: expiringSoonKeywords,
                targets: selectedRange == .day ? nutritionSnapshot.planDayTarget : nutritionSnapshot.baselineDayTarget,
                beveragesKcal: 120,
                budget: .init(perDay: budgetPerDay > 0 ? budgetPerDay : nil, perMeal: nil),
                exclude: settings.dislikedList,
                avoidBones: settings.avoidBones,
                cuisine: [],
                objective: "cost_macro",
                optimizerProfile: settings.smartOptimizerProfile.rawValue,
                macroTolerancePercent: settings.macroTolerancePercent,
                ingredientPriceHints: ingredientPriceHints
            )

            var smartExplanation: [String] = []
            var smartFallbackReason: String?
            var usedSmartGenerator = false
            let generated: MealPlanGenerateResponse
            do {
                let generatedSmart = try await recipeServiceClient.generateSmartMealPlan(payload: smartPayload)
                generated = MealPlanGenerateResponse(
                    days: generatedSmart.days,
                    shoppingList: generatedSmart.shoppingList,
                    estimatedTotalCost: generatedSmart.estimatedTotalCost,
                    warnings: generatedSmart.warnings
                )
                usedSmartGenerator = true
                smartExplanation = generatedSmart.priceExplanation
            } catch {
                smartFallbackReason = userFacingErrorMessage(error)
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
                generated = try await recipeServiceClient.generateMealPlan(payload: payload)
            }

            let source = resolvePlanDataSource(for: generated, usedSmartGenerator: usedSmartGenerator)
            let sourceDetails = resolvePlanDataSourceDetails(
                source: source,
                smartFallbackReason: smartFallbackReason
            )

            mealPlanDataSource = source
            mealPlanDataSourceDetails = sourceDetails
            mealPlan = generated
            offlineStatusMessage = source == .localFallback
                ? (sourceDetails ?? "Сервер рецептов недоступен, использован локальный каталог.")
                : nil
            persistTodayMenuSnapshot(from: generated, dataSource: source, dataSourceDetails: sourceDetails)
            persistMealPlanSnapshot(from: generated, dataSource: source, dataSourceDetails: sourceDetails)
            await MainActor.run {
                GamificationService.shared.trackMealPlanGenerated()
                GamificationService.shared.trackMacroModeDay(source: settings.macroGoalSource)
            }

            if !smartExplanation.isEmpty {
                let explanation = smartExplanation.joined(separator: " ")
                if let current = healthStatusMessage, !current.isEmpty {
                    healthStatusMessage = "\(current) \(explanation)"
                } else {
                    healthStatusMessage = explanation
                }
            }

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
            mealPlanDataSource = .unknown
            mealPlanDataSourceDetails = nil
        }
    }

    private func persistTodayMenuSnapshot(
        from plan: MealPlanGenerateResponse,
        dataSource: MealPlanDataSource,
        dataSourceDetails: String?
    ) {
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
            estimatedCost: firstDay.totals.estimatedCost,
            dataSource: dataSource,
            dataSourceDetails: dataSourceDetails
        )
        todayMenuSnapshotStore.save(snapshot)
    }

    private func persistMealPlanSnapshot(
        from plan: MealPlanGenerateResponse,
        dataSource: MealPlanDataSource,
        dataSourceDetails: String?
    ) {
        let snapshot = MealPlanSnapshot(
            generatedAt: Date(),
            rangeRawValue: selectedRange.rawValue,
            dataSource: dataSource,
            dataSourceDetails: dataSourceDetails,
            plan: plan
        )
        mealPlanSnapshotStore.save(snapshot)
        lastSavedMealPlan = snapshot
    }

    private func refreshLastSavedPlan() {
        lastSavedMealPlan = mealPlanSnapshotStore.load()
    }

    private func applySavedMealPlan(_ snapshot: MealPlanSnapshot) {
        suppressAutoGenerate = true
        if let range = PlanRange(rawValue: snapshot.rangeRawValue) {
            selectedRange = range
        }
        mealPlan = snapshot.plan
        mealPlanDataSource = snapshot.dataSource
        mealPlanDataSourceDetails = snapshot.dataSourceDetails
        lastGeneratedAt = snapshot.generatedAt
        offlineStatusMessage = "Показан сохранённый план."
        errorMessage = nil
        DispatchQueue.main.async {
            suppressAutoGenerate = false
        }
    }

    private func resolvePlanDataSource(
        for plan: MealPlanGenerateResponse,
        usedSmartGenerator: Bool
    ) -> MealPlanDataSource {
        if isLocalGeneratedPlan(plan) {
            return .localFallback
        }
        return usedSmartGenerator ? .serverSmart : .serverBasic
    }

    private func resolvePlanDataSourceDetails(
        source: MealPlanDataSource,
        smartFallbackReason: String?
    ) -> String? {
        switch source {
        case .localFallback:
            return "Сервер рецептов недоступен, используется локальный каталог."
        case .serverSmart:
            return "План собран smart-оптимизатором сервера."
        case .serverBasic:
            if let smartFallbackReason, !smartFallbackReason.isEmpty {
                return "Smart-режим недоступен (\(smartFallbackReason)). Использован базовый серверный генератор."
            }
            return "План собран базовым серверным генератором."
        case .unknown:
            return nil
        }
    }

    private func isLocalGeneratedPlan(_ plan: MealPlanGenerateResponse) -> Bool {
        plan.warnings.contains { warning in
            warning.localizedCaseInsensitiveContains("план собран локально")
        }
    }

    private func mealPlanDataSourceTitle(_ source: MealPlanDataSource) -> String {
        switch source {
        case .localFallback:
            return "Локальный каталог"
        case .serverSmart:
            return "Сервер (smart)"
        case .serverBasic:
            return "Сервер (базовый)"
        case .unknown:
            return "Не определён"
        }
    }

    private func mealPlanDataSourceIcon(_ source: MealPlanDataSource) -> String {
        switch source {
        case .localFallback:
            return "internaldrive.fill"
        case .serverSmart:
            return "sparkles"
        case .serverBasic:
            return "network"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func computeAdaptiveNutritionSnapshot(settings: AppSettings) async -> AdaptiveNutritionUseCase.Output {
        if settings.healthKitReadEnabled, !hasRequestedHealthAccess {
            hasRequestedHealthAccess = true
            _ = try? await healthKitService.requestReadAccess()
        }

        var automaticDailyCalories: Double?
        var weightKG: Double?
        if settings.macroGoalSource == .automatic {
            automaticDailyCalories = healthKitService.fallbackAutomaticDailyCalories(
                targetLossPerWeek: settings.targetWeightDeltaPerWeek
            )
        }

        if settings.healthKitReadEnabled, settings.macroGoalSource == .automatic {
            if let metrics = try? await healthKitService.fetchLatestMetrics() {
                automaticDailyCalories = Double(
                    healthKitService.calculateDailyCalories(
                        metrics: metrics,
                        targetLossPerWeek: settings.targetWeightDeltaPerWeek
                    )
                )
                weightKG = metrics.weightKG
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

        let baseOutput = AdaptiveNutritionUseCase().execute(
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

        guard settings.macroGoalSource == .automatic else {
            return baseOutput
        }

        let weightHistory = (try? await healthKitService.fetchWeightHistory(days: 14)) ?? []
        let bodyFatHistory = (try? await healthKitService.fetchBodyFatHistory(days: 14)) ?? []
        let nutritionHistory = (try? await healthKitService.fetchConsumedNutritionHistory(days: 7)) ?? []

        let coachOutput = DietCoachUseCase().execute(
            .init(
                settings: settings,
                baselineTarget: baseOutput.baselineDayTarget,
                weightHistory: weightHistory,
                bodyFatHistory: bodyFatHistory,
                nutritionHistory: nutritionHistory
            )
        )

        let adjustedBaseline = coachOutput.adjustedTarget
        let remaining = subtractNutrition(adjustedBaseline, baseOutput.consumedToday)
        let nextMeal = divideNutrition(remaining, by: Double(baseOutput.remainingMealsCount))
        let planDayTarget = selectedRange == .day ? remaining : adjustedBaseline

        let statusMessage: String
        if let note = coachOutput.note, !note.isEmpty {
            statusMessage = "\(baseOutput.statusMessage) \(note)"
        } else {
            statusMessage = baseOutput.statusMessage
        }

        return .init(
            baselineDayTarget: adjustedBaseline,
            planDayTarget: planDayTarget,
            consumedToday: baseOutput.consumedToday,
            remainingToday: remaining,
            nextMealTarget: nextMeal,
            nextMealSlot: baseOutput.nextMealSlot,
            remainingMealsCount: baseOutput.remainingMealsCount,
            statusMessage: statusMessage
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

    private func subtractNutrition(_ left: Nutrition, _ right: Nutrition) -> Nutrition {
        Nutrition(
            kcal: max(0, (left.kcal ?? 0) - (right.kcal ?? 0)),
            protein: max(0, (left.protein ?? 0) - (right.protein ?? 0)),
            fat: max(0, (left.fat ?? 0) - (right.fat ?? 0)),
            carbs: max(0, (left.carbs ?? 0) - (right.carbs ?? 0))
        )
    }

    private func divideNutrition(_ value: Nutrition, by divisor: Double) -> Nutrition {
        let safe = max(1, divisor)
        return Nutrition(
            kcal: (value.kcal ?? 0) / safe,
            protein: (value.protein ?? 0) / safe,
            fat: (value.fat ?? 0) / safe,
            carbs: (value.carbs ?? 0) / safe
        )
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
