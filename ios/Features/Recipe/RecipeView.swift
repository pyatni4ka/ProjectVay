import SwiftUI
import UIKit

struct RecipeView: View {
    let recipe: Recipe
    let availableIngredients: Set<String>
    let inventoryService: any InventoryServiceProtocol
    let onInventoryChanged: () async -> Void

    @Environment(\.vayMotion) private var motion

    @State private var statusText: String?
    @State private var pendingWriteOffPlan: RecipeWriteOffPlan?
    @State private var showWriteOffConfirmation = false
    @State private var isPreparingWriteOff = false
    @State private var isApplyingWriteOff = false
    @State private var checkedIngredients: Set<String> = []

    init(
        recipe: Recipe,
        availableIngredients: Set<String>,
        inventoryService: any InventoryServiceProtocol,
        onInventoryChanged: @escaping () async -> Void = {}
    ) {
        self.recipe = recipe
        self.availableIngredients = availableIngredients
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
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: recipe.imageURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color.vayCardBackground)
                    .overlay(SwiftUI.ProgressView())
            }
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
                    .font(.system(size: 18, weight: .semibold))

                Text(ingredient)
                    .font(VayFont.body(14))
                    .foregroundStyle(checked ? .secondary : .primary)
                    .strikethrough(checked)

                Spacer()

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
            Button("Добавить недостающее в список покупок") {
                copyMissingIngredients()
            }
            .buttonStyle(.borderedProminent)
            .tint(.vayPrimary)
            .vayAccessibilityLabel("Добавить недостающее в список покупок")

            Button(isPreparingWriteOff ? "Подготовка..." : (isApplyingWriteOff ? "Списание..." : "Готовлю")) {
                Task { await prepareWriteOffPlan() }
            }
            .buttonStyle(.bordered)
            .disabled(isPreparingWriteOff || isApplyingWriteOff)
            .vayAccessibilityLabel("Готовлю", hint: "Подготовить списание ингредиентов")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vayCard()
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
