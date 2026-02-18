import SwiftUI

/// Main Weekly Autopilot screen — shows 7-day plan list.
/// Supports: Generate, Replace (1 tap), Repeat, Why?, Ate-Something-Else.
struct WeeklyAutopilotView: View {
    let inventoryService: any InventoryServiceProtocol
    let settingsService: any SettingsServiceProtocol
    let healthKitService: HealthKitService
    let recipeServiceClient: RecipeServiceClient?
    var onOpenScanner: () -> Void = {}

    @EnvironmentObject private var appSettingsStore: AppSettingsStore

    @State private var autopilotPlan: WeeklyAutopilotResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedDayId: String?

    // Replace flow
    @State private var replaceContext: ReplaceContext?
    @State private var replaceResponse: ReplaceMealResponse?
    @State private var isReplaceLoading = false

    // Deviation flow
    @State private var deviationContext: DeviationContext?

    // Expanded "Why?" entries
    @State private var expandedWhyIds: Set<String> = []

    // HealthKit access guard (request once per session)
    @State private var hasRequestedHealthAccess = false

    // Shopping list toggle
    @State private var showShoppingList = false

    var body: some View {
        ScrollView {
            VStack(spacing: VaySpacing.lg) {
                // Header controls
                controlsSection

                // Loading / error
                if isLoading {
                    loadingCard
                }

                if let errorMessage {
                    errorCard(errorMessage)
                }

                // Plan
                if let plan = autopilotPlan {
                    budgetSummaryCard(plan)

                    ForEach(plan.days) { day in
                        dayCard(day, plan: plan)
                    }

                    shoppingListSection(plan)
                }

                Color.clear.frame(height: VayLayout.tabBarOverlayInset)
            }
            .padding(.horizontal, VaySpacing.lg)
        }
        .background(Color.vayBackground)
        .navigationTitle("Автопилот недели")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if autopilotPlan != nil {
                    Button {
                        showShoppingList.toggle()
                    } label: {
                        Image(systemName: "cart")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.vayPrimary)
                    }
                }

                Button(action: { Task { await generatePlan() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.vayPrimary)
                }
                .disabled(isLoading)
            }
        }
        .sheet(item: $replaceContext) { context in
            ReplaceSheetView(
                context: context,
                replaceResponse: replaceResponse,
                isLoading: isReplaceLoading,
                onSelect: { candidate in
                    applyReplacement(candidate: candidate, context: context)
                },
                onDismiss: {
                    replaceContext = nil
                    replaceResponse = nil
                }
            )
        }
        .sheet(item: $deviationContext) { context in
            DeviationSheetView(
                context: context,
                onConfirm: { eventType, impact in
                    Task { await adaptPlan(eventType: eventType, impact: impact) }
                    deviationContext = nil
                },
                onDismiss: { deviationContext = nil }
            )
        }
        .sheet(isPresented: $showShoppingList) {
            if let plan = autopilotPlan {
                ShoppingListView(plan: plan)
            }
        }
        .task {
            await generatePlan()
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            Button {
                Task { await generatePlan() }
            } label: {
                Label("Сгенерировать неделю", systemImage: "sparkles")
                    .font(VayFont.label(15))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VaySpacing.md)
                    .background(Color.vayPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
            }
            .disabled(isLoading)
        }
        .padding(.top, VaySpacing.sm)
    }

    // MARK: - Budget summary

    private func budgetSummaryCard(_ plan: WeeklyAutopilotResponse) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            HStack {
                Text("Бюджет недели")
                    .font(VayFont.heading(15))
                Spacer()
                Text("~\(plan.estimatedTotalCost.formatted(.number.precision(.fractionLength(0)))) ₽")
                    .font(VayFont.label(14))
                    .foregroundStyle(budgetColor(plan))
            }

            let bp = plan.budgetProjection
            HStack(spacing: VaySpacing.lg) {
                budgetPill("День", target: bp.day.target, actual: bp.day.actual)
                budgetPill("Неделя", target: bp.week.target, actual: bp.week.actual)
            }

            if !plan.warnings.isEmpty {
                ForEach(plan.warnings.prefix(2), id: \.self) { warning in
                    Text(warning)
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .vayCard()
    }

    private func budgetPill(_ label: String, target: Double, actual: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(VayFont.caption(11))
                .foregroundStyle(.secondary)
            Text("~\(actual.formatted(.number.precision(.fractionLength(0)))) / \(target.formatted(.number.precision(.fractionLength(0)))) ₽")
                .font(VayFont.label(13))
                .foregroundStyle(actual > target * 1.05 ? Color.vayWarning : Color.vaySuccess)
        }
    }

    private func budgetColor(_ plan: WeeklyAutopilotResponse) -> Color {
        let target = plan.budgetProjection.week.target
        let actual = plan.estimatedTotalCost
        if target <= 0 { return .primary }
        return actual > target * 1.05 ? Color.vayWarning : Color.vaySuccess
    }

    // MARK: - Day card

    private func dayCard(_ day: WeeklyAutopilotResponse.AutopilotDay, plan: WeeklyAutopilotResponse) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            // Day header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.dayOfWeek ?? day.date)
                        .font(VayFont.heading(15))
                    Text(day.date)
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("~\(day.totals.estimatedCost.formatted(.number.precision(.fractionLength(0)))) ₽")
                        .font(VayFont.label(13))
                        .foregroundStyle(.secondary)
                    Text("\(Int(day.totals.kcal)) ккал")
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, VaySpacing.xs)

            // Meals
            ForEach(day.entries) { entry in
                mealRow(entry: entry, day: day, plan: plan)
            }

            // "I ate something else" button
            Button {
                deviationContext = DeviationContext(plan: plan)
            } label: {
                Label("Съел другое / поел вне дома", systemImage: "fork.knife.circle")
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.top, VaySpacing.xs)
        }
        .vayCard()
    }

    // MARK: - Meal row

    private func mealRow(
        entry: WeeklyAutopilotResponse.DayEntry,
        day: WeeklyAutopilotResponse.AutopilotDay,
        plan: WeeklyAutopilotResponse
    ) -> some View {
        let entryId = "\(day.id)-\(entry.id)"
        return VStack(alignment: .leading, spacing: VaySpacing.xs) {
            HStack(alignment: .top, spacing: VaySpacing.sm) {
                // Meal type icon
                Image(systemName: mealIcon(entry.mealType))
                    .font(.system(size: 16))
                    .foregroundStyle(Color.vayPrimary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.recipe.title)
                        .font(VayFont.label(14))
                        .lineLimit(2)

                    HStack(spacing: VaySpacing.sm) {
                        Text(mealTypeLabel(entry.mealType))
                            .font(VayFont.caption(11))
                            .foregroundStyle(.secondary)

                        Text("·")
                            .foregroundStyle(.secondary)

                        Text("\(Int(entry.kcal)) ккал")
                            .font(VayFont.caption(11))
                            .foregroundStyle(.secondary)

                        Text("·")
                            .foregroundStyle(.secondary)

                        Text("~\(entry.estimatedCost.formatted(.number.precision(.fractionLength(0)))) ₽")
                            .font(VayFont.caption(11))
                            .foregroundStyle(.secondary)
                    }

                    // Explanation tags
                    if !entry.explanationTags.isEmpty {
                        HStack(spacing: VaySpacing.xs) {
                            ForEach(entry.explanationTags.prefix(3), id: \.self) { tag in
                                tagBadge(tag)
                            }
                        }
                    }
                }

                Spacer()

                // Replace button
                Button {
                    Task { await loadReplaceCandidates(entry: entry, day: day, plan: plan) }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.vayPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Заменить блюдо")
            }

            // Why? expandable
            Button {
                if expandedWhyIds.contains(entryId) {
                    expandedWhyIds.remove(entryId)
                } else {
                    expandedWhyIds.insert(entryId)
                }
            } label: {
                HStack(spacing: VaySpacing.xs) {
                    Text("Почему?")
                        .font(VayFont.caption(11))
                        .foregroundStyle(Color.vayPrimary)
                    Image(systemName: expandedWhyIds.contains(entryId) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.vayPrimary)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 32)

            if expandedWhyIds.contains(entryId) {
                whySection(entry: entry)
                    .padding(.leading, 32)
            }
        }
        .padding(.vertical, VaySpacing.xs)
    }

    private func whySection(entry: WeeklyAutopilotResponse.DayEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(explanationLines(entry), id: \.self) { line in
                HStack(alignment: .top, spacing: 4) {
                    Text("·")
                    Text(line)
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func explanationLines(_ entry: WeeklyAutopilotResponse.DayEntry) -> [String] {
        var lines: [String] = []
        for tag in entry.explanationTags {
            switch tag {
            case "cheap": lines.append("Дешевле среднего — укладывается в бюджет.")
            case "quick": lines.append("Быстро готовится — меньше 20 минут.")
            case "high_protein": lines.append("Высокое содержание белка для этого приёма.")
            case "uses_inventory": lines.append("Использует продукты из вашего холодильника.")
            case "expiring_soon": lines.append("Использует продукты с коротким сроком годности.")
            case "low_effort": lines.append("Простое в приготовлении.")
            default: lines.append(tag)
            }
        }
        if lines.isEmpty {
            let conf = entry.nutritionConfidence
            lines.append("Подобрано по целевому КБЖУ (точность: \(conf == "high" ? "высокая" : conf == "medium" ? "средняя" : "низкая")).")
        }
        return lines
    }

    // MARK: - Shopping list section

    private func shoppingListSection(_ plan: WeeklyAutopilotResponse) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            HStack {
                Text("Список покупок")
                    .font(VayFont.heading(15))
                Spacer()
                Text("\(plan.shoppingListWithQuantities.count) поз.")
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
            }

            Button {
                showShoppingList = true
            } label: {
                HStack {
                    Image(systemName: "cart.badge.plus")
                        .foregroundStyle(Color.vayPrimary)
                    Text("Открыть полный список")
                        .font(VayFont.label(14))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)

            // Preview: first 3 items
            ForEach(plan.shoppingListWithQuantities.prefix(3)) { item in
                shoppingItemRow(item)
            }

            if plan.shoppingListWithQuantities.count > 3 {
                Text("+ ещё \(plan.shoppingListWithQuantities.count - 3) позиций")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }
        }
        .vayCard()
    }

    private func shoppingItemRow(_ item: WeeklyAutopilotResponse.ShoppingItemQuantity) -> some View {
        HStack {
            Image(systemName: "circle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(item.ingredient.capitalized)
                .font(VayFont.body(13))
            Spacer()
            Text(item.approximate
                 ? "~\(item.amount.formatted(.number.precision(.fractionLength(0)))) \(item.unit)"
                 : "\(item.amount.formatted(.number.precision(.fractionLength(0)))) \(item.unit)")
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Load/generate actions

    private func generatePlan() async {
        guard let client = recipeServiceClient else {
            errorMessage = "Сервис рецептов недоступен."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let settings = appSettingsStore.settings
            let products = (try? await inventoryService.listProducts(location: nil, search: nil)) ?? []
            let batches = (try? await inventoryService.listBatches(productId: nil)) ?? []

            let ingredientKeywords = products.map { $0.name.lowercased() }
            let now = Date()
            let expiringSoonKeywords = batches
                .filter { batch in
                    guard let expiry = batch.expiryDate else { return false }
                    return expiry.timeIntervalSince(now) < 7 * 24 * 3600 && expiry > now
                }
                .compactMap { batch in products.first(where: { $0.id == batch.productId })?.name.lowercased() }

            let nutritionSnapshot = await computeBaselineNutrition(settings: settings)
            let budgetPerDay = NSDecimalNumber(decimal: settings.budgetDay).doubleValue

            let payload = WeeklyAutopilotRequest(
                days: 7,
                startDate: nil,
                mealsPerDay: 3,
                includeSnacks: false,
                ingredientKeywords: ingredientKeywords,
                expiringSoonKeywords: expiringSoonKeywords,
                targets: nutritionSnapshot,
                beveragesKcal: 120,
                budget: budgetPerDay > 0
                    ? WeeklyAutopilotRequest.Budget(
                        perDay: budgetPerDay,
                        perMeal: nil,
                        perWeek: nil,
                        perMonth: nil,
                        strictness: "soft",
                        softLimitPct: 5
                    )
                    : nil,
                exclude: settings.dislikedList,
                avoidBones: settings.avoidBones,
                cuisine: [],
                effortLevel: "standard",
                seed: nil,
                inventorySnapshot: ingredientKeywords,
                constraints: WeeklyAutopilotRequest.Constraints(
                    diets: nil,
                    allergies: nil,
                    dislikes: settings.dislikedList,
                    favorites: nil
                ),
                objective: "cost_macro",
                optimizerProfile: settings.smartOptimizerProfile.rawValue,
                macroTolerancePercent: settings.macroTolerancePercent,
                ingredientPriceHints: nil
            )

            let plan = try await client.generateWeeklyAutopilot(payload: payload)
            autopilotPlan = plan
        } catch {
            errorMessage = userFacingErrorMessage(error)
        }

        isLoading = false
    }

    private func loadReplaceCandidates(
        entry: WeeklyAutopilotResponse.DayEntry,
        day: WeeklyAutopilotResponse.AutopilotDay,
        plan: WeeklyAutopilotResponse
    ) async {
        guard let client = recipeServiceClient else { return }
        guard let dayIndex = plan.days.firstIndex(where: { $0.id == day.id }) else { return }

        replaceContext = ReplaceContext(plan: plan, dayIndex: dayIndex, mealSlot: entry.mealType, entry: entry)
        isReplaceLoading = true
        replaceResponse = nil

        let products = (try? await inventoryService.listProducts(location: nil, search: nil)) ?? []
        let inventoryKeywords = products.map { $0.name.lowercased() }

        do {
            let payload = ReplaceMealRequest(
                planId: plan.planId,
                currentPlan: plan,
                dayIndex: dayIndex,
                mealSlot: entry.mealType,
                sortMode: "cheap",
                topN: 5,
                inventorySnapshot: inventoryKeywords
            )
            replaceResponse = try await client.replaceMeal(payload: payload)
        } catch {
            // Replace sheet shows error inline
        }

        isReplaceLoading = false
    }

    private func applyReplacement(candidate: ReplaceMealResponse.Candidate, context: ReplaceContext) {
        guard let preview = replaceResponse?.updatedPlanPreview else { return }
        autopilotPlan = preview
        replaceContext = nil
        replaceResponse = nil
    }

    private func adaptPlan(eventType: String, impact: String) async {
        guard let client = recipeServiceClient, let plan = autopilotPlan else { return }

        isLoading = true
        do {
            let payload = AdaptPlanRequest(
                planId: plan.planId,
                currentPlan: plan,
                eventType: eventType,
                impactEstimate: impact,
                customMacros: nil,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                applyScope: "day"
            )
            let result = try await client.adaptPlan(payload: payload)
            autopilotPlan = result.updatedRemainingPlan
        } catch {
            errorMessage = userFacingErrorMessage(error)
        }
        isLoading = false
    }

    // MARK: - Helpers

    /// Returns the baseline daily nutrition target for building a 7-day plan.
    /// Mirrors MealPlanView.computeAdaptiveNutritionSnapshot but always runs in
    /// week (forward-planning) mode — no consumed-today tracking needed here.
    private func computeBaselineNutrition(settings: AppSettings) async -> Nutrition {
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

        let baseOutput = AdaptiveNutritionUseCase().execute(
            .init(
                settings: settings,
                range: .week,
                automaticDailyCalories: automaticDailyCalories,
                weightKG: weightKG,
                consumedNutrition: nil,
                consumedFetchFailed: false,
                healthIntegrationEnabled: settings.healthKitReadEnabled
            )
        )

        return baseOutput.baselineDayTarget
    }

    private func userFacingErrorMessage(_ error: Error) -> String {
        if let clientError = error as? RecipeServiceClientError {
            return clientError.errorDescription ?? error.localizedDescription
        }
        return "Не удалось загрузить план. Попробуйте ещё раз."
    }

    private func mealIcon(_ mealType: String) -> String {
        switch mealType {
        case "breakfast": return "sunrise"
        case "lunch": return "sun.max"
        case "dinner": return "moon.stars"
        case "snack": return "leaf"
        default: return "fork.knife"
        }
    }

    private func mealTypeLabel(_ mealType: String) -> String {
        switch mealType {
        case "breakfast": return "Завтрак"
        case "lunch": return "Обед"
        case "dinner": return "Ужин"
        case "snack": return "Перекус"
        default: return mealType.capitalized
        }
    }

    private func tagBadge(_ tag: String) -> some View {
        Text(tagLabel(tag))
            .font(VayFont.caption(10))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tagColor(tag).opacity(0.15))
            .foregroundStyle(tagColor(tag))
            .clipShape(Capsule())
    }

    private func tagLabel(_ tag: String) -> String {
        switch tag {
        case "cheap": return "Дёшево"
        case "quick": return "Быстро"
        case "high_protein": return "Белок"
        case "uses_inventory": return "Из холодильника"
        case "expiring_soon": return "Истекает"
        case "low_effort": return "Просто"
        default: return tag
        }
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "cheap": return .vaySuccess
        case "quick": return .vayInfo
        case "high_protein": return .vayProtein
        case "uses_inventory": return .vayPrimary
        case "expiring_soon": return .vayWarning
        case "low_effort": return .vaySecondary
        default: return .secondary
        }
    }

    // MARK: - Loading / Error

    private var loadingCard: some View {
        HStack(spacing: VaySpacing.sm) {
            SwiftUI.ProgressView()
            Text("Генерируем план на 7 дней...")
                .font(VayFont.body(14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VaySpacing.lg)
        .vayCard()
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.vayWarning)
            Text(message)
                .font(VayFont.body(13))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Повторить") {
                Task { await generatePlan() }
            }
            .font(VayFont.label(12))
            .buttonStyle(.borderedProminent)
            .tint(Color.vayPrimary)
        }
        .padding(VaySpacing.md)
        .background(Color.vayWarning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
    }
}

// MARK: - Context models

struct ReplaceContext: Identifiable {
    let id = UUID()
    let plan: WeeklyAutopilotResponse
    let dayIndex: Int
    let mealSlot: String
    let entry: WeeklyAutopilotResponse.DayEntry
}

struct DeviationContext: Identifiable {
    let id = UUID()
    let plan: WeeklyAutopilotResponse
}

// MARK: - Health metrics snapshot (lightweight bridge)

struct HealthMetricsSnapshot {
    let weightKg: Double?
    let bodyFatPercent: Double?
}

// MARK: - Replace Sheet

struct ReplaceSheetView: View {
    let context: ReplaceContext
    let replaceResponse: ReplaceMealResponse?
    let isLoading: Bool
    let onSelect: (ReplaceMealResponse.Candidate) -> Void
    let onDismiss: () -> Void

    @State private var selectedSortMode = "cheap"
    private let sortModes = [("cheap", "Дешевле"), ("fast", "Быстрее"), ("protein", "Белок"), ("expiry", "Срок")]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack {
                        SwiftUI.ProgressView()
                        Text("Ищем замены...")
                            .font(VayFont.body(14))
                            .padding(.top, VaySpacing.sm)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let response = replaceResponse, !response.candidates.isEmpty {
                    candidatesList(response)
                } else {
                    Text("Нет подходящих замен для этого слота.")
                        .font(VayFont.body(14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Заменить \(mealTypeLabel(context.mealSlot))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена", action: onDismiss)
                }
            }
        }
    }

    private func candidatesList(_ response: ReplaceMealResponse) -> some View {
        ScrollView {
            VStack(spacing: VaySpacing.md) {
                // Sort picker
                Picker("Сортировка", selection: $selectedSortMode) {
                    ForEach(sortModes, id: \.0) { mode in
                        Text(mode.1).tag(mode.0)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, VaySpacing.lg)

                // Why this search
                if !response.why.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(response.why, id: \.self) { why in
                            Text(why)
                                .font(VayFont.caption(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VaySpacing.lg)
                }

                // Candidates
                ForEach(response.candidates) { candidate in
                    Button {
                        onSelect(candidate)
                    } label: {
                        candidateRow(candidate)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, VaySpacing.lg)
                }

                Color.clear.frame(height: VaySpacing.xl)
            }
            .padding(.top, VaySpacing.md)
        }
    }

    private func candidateRow(_ candidate: ReplaceMealResponse.Candidate) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.recipe.title)
                        .font(VayFont.label(14))
                        .lineLimit(2)

                    HStack(spacing: VaySpacing.sm) {
                        if let kcal = candidate.recipe.nutrition?.kcal {
                            Text("\(Int(kcal)) ккал")
                                .font(VayFont.caption(11))
                                .foregroundStyle(.secondary)
                        }
                        if candidate.costDelta != 0 {
                            let sign = candidate.costDelta > 0 ? "+" : ""
                            Text("\(sign)\(Int(candidate.costDelta)) ₽")
                                .font(VayFont.caption(11))
                                .foregroundStyle(candidate.costDelta < 0 ? Color.vaySuccess : .secondary)
                        }
                        if let time = candidate.recipe.totalTimeMinutes {
                            Text("\(time) мин")
                                .font(VayFont.caption(11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Delta indicators
                    HStack(spacing: VaySpacing.sm) {
                        if candidate.costDelta < -10 {
                            Text("−\(Int(abs(candidate.costDelta))) ₽")
                                .font(VayFont.caption(10))
                                .foregroundStyle(Color.vaySuccess)
                        } else if candidate.costDelta > 10 {
                            Text("+\(Int(candidate.costDelta)) ₽")
                                .font(VayFont.caption(10))
                                .foregroundStyle(Color.vayWarning)
                        }
                        if let dProt = candidate.macroDelta.protein, abs(dProt) > 3 {
                            Text(dProt > 0 ? "+\(Int(dProt))г белка" : "\(Int(dProt))г белка")
                                .font(VayFont.caption(10))
                                .foregroundStyle(dProt > 0 ? Color.vayProtein : Color.secondary)
                        }
                    }
                }

                Spacer()

                // Tags
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(candidate.tags.prefix(2), id: \.self) { tag in
                        Text(tagLabel(tag))
                            .font(VayFont.caption(10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.vayPrimaryLight)
                            .foregroundStyle(Color.vayPrimary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(VaySpacing.md)
        .background(Color.vayCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
    }

    private func mealTypeLabel(_ mealType: String) -> String {
        switch mealType {
        case "breakfast": return "завтрак"
        case "lunch": return "обед"
        case "dinner": return "ужин"
        case "snack": return "перекус"
        default: return mealType
        }
    }

    private func tagLabel(_ tag: String) -> String {
        switch tag {
        case "cheap": return "Дёшево"
        case "quick": return "Быстро"
        case "high_protein": return "Белок"
        case "uses_inventory": return "Из холодильника"
        case "expiring_soon": return "Истекает"
        case "low_effort": return "Просто"
        default: return tag
        }
    }
}
