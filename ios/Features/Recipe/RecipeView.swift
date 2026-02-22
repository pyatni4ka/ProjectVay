import SwiftUI
import UIKit
import Nuke
import NukeUI

struct RecipeView: View {
    let recipe: Recipe
    let availableIngredients: Set<String>
    let recipeServiceClient: RecipeServiceClient?
    let inventoryService: any InventoryServiceProtocol
    let onInventoryChanged: () async -> Void

    @Environment(\.vayMotion) private var motion

    @State private var statusText: String?
    @State private var pendingWriteOffPlan: RecipeWriteOffPlan?
    @State private var showWriteOffConfirmation = false
    @State private var isPreparingWriteOff = false
    @State private var isApplyingWriteOff = false
    @State private var checkedIngredients: Set<String> = []
    
    // Cooking Mode
    @State private var showCookingMode = false
    
    // Substitutions
    @State private var showSubstitutions = false
    @State private var selectedIngredientForSub: String? = nil
    @State private var substitutionsResult: [SubstituteResponse.Substitution] = []
    @State private var isLoadingSubstitutions = false
    @State private var substitutionError: String? = nil

    init(
        recipe: Recipe,
        availableIngredients: Set<String>,
        recipeServiceClient: RecipeServiceClient?,
        inventoryService: any InventoryServiceProtocol,
        onInventoryChanged: @escaping () async -> Void = {}
    ) {
        self.recipe = recipe
        self.availableIngredients = availableIngredients
        self.recipeServiceClient = recipeServiceClient
        self.inventoryService = inventoryService
        self.onInventoryChanged = onInventoryChanged
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VaySpacing.lg) {
                heroCard
                linksCard

                if let nutrition = recipe.nutrition {
                    nutritionCard(nutrition)
                }

                ingredientsCard
                stepsCard
                actionsCard

                if let statusText {
                    statusBanner(statusText)
                }


            }
            .padding(.horizontal, VaySpacing.lg)
            .padding(.top, VaySpacing.md)
        }
        .background(Color.vayBackground)
        .navigationTitle("Рецепт")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkedIngredients = Set(
                recipe.ingredients.filter { ingredient in
                    availableIngredients.contains(normalize(ingredient))
                }
            )
        }
        .alert(
            "Списать ингредиенты?",
            isPresented: $showWriteOffConfirmation,
            presenting: pendingWriteOffPlan
        ) { plan in
            Button(isApplyingWriteOff ? "Списываем..." : "Списать", role: .destructive) {
                Task { await applyWriteOff(plan: plan) }
            }
            .disabled(isApplyingWriteOff)

            Button("Отмена", role: .cancel) {}
        } message: { plan in
            Text(plan.summaryText)
        }
        .sheet(isPresented: $showSubstitutions) {
            substitutionSheet
        }
        .fullScreenCover(isPresented: $showCookingMode) {
            CookingModeView(recipe: recipe)
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            LazyImage(url: recipe.imageURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else if state.error != nil {
                    Rectangle()
                        .fill(Color.vayCardBackground)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                        )
                } else {
                    Rectangle()
                        .fill(Color.vayCardBackground)
                        .overlay(SwiftUI.ProgressView())
                }
            }
            .processors([
                ImageProcessors.Resize(
                    size: CGSize(width: 1200, height: 720),
                    contentMode: .aspectFill
                )
            ])
            .priority(.high)
            .pipeline(ImagePipeline.shared)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous))

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous))

            Text(recipe.title)
                .font(VayFont.title(24))
                .foregroundStyle(.white)
                .padding(VaySpacing.lg)
        }
        .vayShadow(.card)
        .vayAccessibilityLabel("Рецепт: \(recipe.title)")
    }

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            Link("Источник: \(recipe.sourceName)", destination: recipe.sourceURL)
                .font(VayFont.body(14))
                .foregroundStyle(Color.vayPrimary)

            if let videoURL = recipe.videoURL {
                Link("Открыть видео", destination: videoURL)
                    .font(VayFont.body(14))
                    .foregroundStyle(Color.vayPrimary)
            }
        }
        .vayCard()
    }

    private func nutritionCard(_ nutrition: Nutrition) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            Text("КБЖУ")
                .font(VayFont.heading(16))

            HStack(spacing: VaySpacing.sm) {
                nutritionChip("К", numberText(nutrition.kcal), color: .vayCalories)
                nutritionChip("Б", numberText(nutrition.protein), color: .vayProtein)
                nutritionChip("Ж", numberText(nutrition.fat), color: .vayFat)
                nutritionChip("У", numberText(nutrition.carbs), color: .vayCarbs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .vayCard()
        .vayAccessibilityLabel("КБЖУ: \(nutritionSummary(nutrition))")
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            Text("Ингредиенты")
                .font(VayFont.heading(16))

            ForEach(recipe.ingredients, id: \.self) { ingredient in
                ingredientRow(ingredient)
            }
        }
        .vayCard()
    }

    private func ingredientRow(_ ingredient: String) -> some View {
        let inStock = availableIngredients.contains(normalize(ingredient))
        let checked = checkedIngredients.contains(ingredient)

        return Button {
            withAnimation(motion.springSnappy) {
                if checkedIngredients.contains(ingredient) {
                    checkedIngredients.remove(ingredient)
                } else {
                    checkedIngredients.insert(ingredient)
                }
            }
        } label: {
            HStack(alignment: .center, spacing: VaySpacing.sm) {
                Image(systemName: checked ? "checkmark.circle.fill" : (inStock ? "circle.fill" : "circle"))
                    .foregroundStyle(checked ? Color.vaySuccess : (inStock ? Color.vayPrimary : Color.secondary))
                    .font(VayFont.body(18))

                Text(ingredient)
                    .font(VayFont.body(14))
                    .foregroundStyle(checked ? .secondary : .primary)
                    .strikethrough(checked)

                Spacer()
                
                if !inStock && !checked {
                    Button {
                        selectedIngredientForSub = ingredient
                        showSubstitutions = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.vayWarning)
                            .padding(6)
                            .background(Color.vayWarning.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .vayAccessibilityLabel("Подобрать замену для \(ingredient)")
                }

                if inStock {
                    Text("Есть дома")
                        .font(VayFont.caption(10))
                        .foregroundStyle(Color.vaySuccess)
                        .padding(.horizontal, VaySpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.vaySuccess.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(VaySpacing.sm)
            .background((checked ? Color.vaySuccess.opacity(0.08) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .vayAccessibilityLabel(
            "\(ingredient)",
            hint: checked ? "Отмечено как выполненное" : "Дважды нажмите, чтобы отметить"
        )
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            Text("Шаги")
                .font(VayFont.heading(16))

            ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: VaySpacing.sm) {
                    Text("\(index + 1)")
                        .font(VayFont.label(12))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.vayPrimary)
                        .clipShape(Circle())

                    Text(step)
                        .font(VayFont.body(14))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(VaySpacing.sm)
                .background(Color.vayCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
                .vayAccessibilityLabel("Шаг \(index + 1): \(step)")
            }
        }
        .vayCard()
    }

    private var actionsCard: some View {
        VStack(spacing: VaySpacing.sm) {
            if !recipe.instructions.isEmpty {
                Button(action: { showCookingMode = true }) {
                    Label("Начать готовить", systemImage: "play.fill")
                        .font(VayFont.label(16))
                        .frame(maxWidth: .infinity)
                        .vayPillButton(color: .vaySuccess)
                }
                .buttonStyle(.plain)
                .vayAccessibilityLabel("Начать готовить", hint: "Открыть пошаговые инструкции на полный экран")
            }

            Button(action: copyMissingIngredients) {
                Text("Добавить недостающее в список покупок")
                    .frame(maxWidth: .infinity)
                    .vayPillButton(color: .vayPrimary)
            }
            .buttonStyle(.plain)
            .vayAccessibilityLabel("Добавить недостающее в список покупок")

            Button(action: { Task { await prepareWriteOffPlan() } }) {
                Text(isPreparingWriteOff ? "Подготовка..." : (isApplyingWriteOff ? "Списание..." : "Готовлю"))
                    .frame(maxWidth: .infinity)
                    .vayPillButton(color: .secondary)
            }
            .buttonStyle(.plain)
            .disabled(isPreparingWriteOff || isApplyingWriteOff)
            .vayAccessibilityLabel("Готовлю", hint: "Подготовить списание ингредиентов")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vayCard()
    }
    
    private var substitutionSheet: some View {
        NavigationStack {
            Group {
                if let error = substitutionError {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Ошибка",
                        subtitle: error,
                        actionTitle: "Повторить",
                        action: {
                            Task { await fetchSubstitutions() }
                        }
                    )
                } else if isLoadingSubstitutions {
                    VStack(spacing: VaySpacing.md) {
                        SwiftUI.ProgressView()
                        Text("ИИ ищет замены...")
                            .font(VayFont.body(14))
                            .foregroundStyle(.secondary)
                    }
                } else if substitutionsResult.isEmpty {
                    EmptyStateView(
                        icon: "wand.and.stars",
                        title: "Нет вариантов",
                        subtitle: "Не удалось найти подходящих замен для «\(selectedIngredientForSub ?? "")».",
                        actionTitle: "Закрыть",
                        action: { showSubstitutions = false }
                    )
                } else {
                    List {
                        ForEach(substitutionsResult, id: \.self) { sub in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(sub.substitute)
                                    .font(VayFont.heading(16))
                                
                                HStack(spacing: VaySpacing.xs) {
                                    if sub.reason == "price" {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundStyle(Color.vaySuccess)
                                        Text("Дешевле")
                                    } else {
                                        Image(systemName: "cart.fill")
                                            .foregroundStyle(Color.vayInfo)
                                        Text("Доступнее")
                                    }
                                }
                                .font(VayFont.caption(12))
                                
                                if let savings = sub.estimatedSavingsRub, savings > 0 {
                                    Text("Экономия ~\(Int(savings)) ₽")
                                        .font(VayFont.caption(12))
                                        .foregroundStyle(Color.vaySuccess)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Замены")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        showSubstitutions = false
                    }
                }
            }
            .task {
                await fetchSubstitutions()
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func fetchSubstitutions() async {
        guard let ingredient = selectedIngredientForSub, let client = recipeServiceClient else { return }
        
        isLoadingSubstitutions = true
        substitutionError = nil
        substitutionsResult = []
        
        do {
            let response = try await client.getSubstitute(ingredients: [ingredient])
            substitutionsResult = response.substitutions
        } catch {
            substitutionError = error.localizedDescription
        }
        
        isLoadingSubstitutions = false
    }

    private func statusBanner(_ text: String) -> some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.vayInfo)
            Text(text)
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)
        }
        .padding(VaySpacing.md)
        .background(Color.vayInfo.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
        .vayAccessibilityLabel(text)
    }

    private func nutritionChip(_ shortTitle: String, _ value: String, color: Color) -> some View {
        HStack(spacing: VaySpacing.xs) {
            Text(shortTitle)
                .font(VayFont.caption(11))
                .foregroundStyle(color)
            Text(value)
                .font(VayFont.label(12))
        }
        .padding(.horizontal, VaySpacing.sm)
        .padding(.vertical, VaySpacing.xs)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func copyMissingIngredients() {
        let missing = recipe.ingredients.filter { ingredient in
            !availableIngredients.contains(normalize(ingredient))
        }

        guard !missing.isEmpty else {
            statusText = "Все ингредиенты есть дома."
            return
        }

        UIPasteboard.general.string = missing.joined(separator: "\n")
        statusText = "Список недостающих ингредиентов скопирован."
    }

    private func prepareWriteOffPlan() async {
        guard !isPreparingWriteOff && !isApplyingWriteOff else { return }
        isPreparingWriteOff = true
        defer { isPreparingWriteOff = false }

        do {
            let plan = try await BuildRecipeWriteOffPlanUseCase(inventoryService: inventoryService)
                .execute(recipe: recipe)

            guard !plan.entries.isEmpty else {
                statusText = "Не удалось найти подходящие партии для списания."
                pendingWriteOffPlan = nil
                showWriteOffConfirmation = false
                return
            }

            pendingWriteOffPlan = plan
            showWriteOffConfirmation = true
        } catch {
            statusText = "Не удалось подготовить списание: \(error.localizedDescription)"
        }
    }

    private func applyWriteOff(plan: RecipeWriteOffPlan) async {
        guard !isApplyingWriteOff else { return }
        isApplyingWriteOff = true
        defer { isApplyingWriteOff = false }

        do {
            let result = try await ApplyRecipeWriteOffUseCase(inventoryService: inventoryService)
                .execute(plan: plan)

            let removed = result.removedBatches
            let updated = result.updatedBatches
            statusText = "Списание выполнено. Партии удалены: \(removed), обновлены: \(updated)."
            pendingWriteOffPlan = nil
            await onInventoryChanged()
        } catch {
            statusText = "Ошибка списания: \(error.localizedDescription)"
        }
    }

    private func nutritionSummary(_ nutrition: Nutrition) -> String {
        "К \(numberText(nutrition.kcal)) · Б \(numberText(nutrition.protein)) · Ж \(numberText(nutrition.fat)) · У \(numberText(nutrition.carbs))"
    }

    private func numberText(_ value: Double?) -> String {
        max(0, value ?? 0).formatted(.number.precision(.fractionLength(0)))
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct RecipeImportView: View {
    let recipeServiceClient: RecipeServiceClient?

    @State private var recipeURL = ""
    @State private var isLoading = false
    @State private var parseResponse: RecipeParseResponse?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                TextField("https://...", text: $recipeURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Button(isLoading ? "Парсим..." : "Импортировать рецепт") {
                    Task { await parseRecipe() }
                }
                .disabled(isLoading || recipeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Ссылка на рецепт")
            }

            if let parsed = parseResponse {
                Section("Качество парсинга") {
                    qualityRow("Скор", "\(Int((parsed.quality.score * 100).rounded()))%")
                    qualityRow("Ингредиенты", "\(parsed.quality.ingredientCount)")
                    qualityRow("Шаги", "\(parsed.quality.instructionCount)")
                    qualityRow("КБЖУ", parsed.quality.hasNutrition ? "Да" : "Нет")
                }

                Section("Нормализованные ингредиенты") {
                    ForEach(parsed.normalizedIngredients, id: \.normalizedKey) { ingredient in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ingredient.raw)
                                .font(VayFont.body(14))
                            Text("Ключ: \(ingredient.normalizedKey)")
                                .font(VayFont.caption(11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(VayFont.caption(12))
                        .foregroundStyle(Color.vayDanger)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: VayLayout.tabBarOverlayInset)
        }
        .navigationTitle("Импорт рецепта")
    }

    private func parseRecipe() async {
        guard let recipeServiceClient else {
            errorMessage = "Сервис рецептов недоступен."
            return
        }

        let trimmed = recipeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            parseResponse = try await recipeServiceClient.parseRecipe(url: trimmed)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func qualityRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
