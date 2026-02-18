import SwiftUI

/// Quick "Cook Now" screen — shows what the user can cook right now from their inventory.
/// No plan needed. Sorted by inventory availability + expiry priority.
struct CookNowView: View {
    let inventoryService: any InventoryServiceProtocol
    let recipeServiceClient: RecipeServiceClient?

    @State private var recipes: [CookNowResponse.CookNowRecipe] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var inventoryCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: VaySpacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: VaySpacing.sm) {
                    HStack {
                        Image(systemName: "refrigerator")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.vayPrimary)
                        Text("Из того, что есть")
                            .font(VayFont.heading(18))
                    }

                    if inventoryCount > 0 {
                        Text("Нашли \(inventoryCount) продукт\(inventoryCount == 1 ? "" : inventoryCount < 5 ? "а" : "ов") в инвентаре")
                            .font(VayFont.caption(12))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, VaySpacing.sm)

                if isLoading {
                    loadingCard
                }

                if let errorMessage {
                    errorCard(errorMessage)
                }

                if !recipes.isEmpty {
                    recipesList
                } else if !isLoading {
                    emptyState
                }

                Color.clear.frame(height: VayLayout.tabBarOverlayInset)
            }
            .padding(.horizontal, VaySpacing.lg)
        }
        .background(Color.vayBackground)
        .navigationTitle("Что приготовить?")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { Task { await loadRecipes() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.vayPrimary)
                }
                .disabled(isLoading)
            }
        }
        .task {
            await loadRecipes()
        }
    }

    // MARK: - Recipes list

    private var recipesList: some View {
        VStack(spacing: VaySpacing.md) {
            ForEach(recipes) { item in
                NavigationLink {
                    // Navigate to recipe detail (reuse existing RecipeView)
                    recipeDetailPlaceholder(item)
                } label: {
                    cookNowRow(item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cookNowRow(_ item: CookNowResponse.CookNowRecipe) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.recipe.title)
                        .font(VayFont.label(15))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: VaySpacing.sm) {
                        // Availability ratio
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.vaySuccess)
                            Text("\(item.availabilityRatio)% из холодильника")
                                .font(VayFont.caption(11))
                                .foregroundStyle(.secondary)
                        }

                        if let kcal = item.recipe.nutrition?.kcal {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text("\(Int(kcal)) ккал")
                                .font(VayFont.caption(11))
                                .foregroundStyle(.secondary)
                        }

                        if let time = item.recipe.totalTimeMinutes {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text("\(time) мин")
                                .font(VayFont.caption(11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Matched filter tags
                    if !item.matchedFilters.isEmpty {
                        HStack(spacing: VaySpacing.xs) {
                            ForEach(item.matchedFilters.prefix(3), id: \.self) { filter in
                                filterBadge(filter)
                            }
                        }
                    }
                }

                Spacer()

                // Availability indicator circle
                availabilityCircle(ratio: item.availabilityRatio)
            }
        }
        .padding(VaySpacing.md)
        .background(Color.vayCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
    }

    private func availabilityCircle(ratio: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.vayPrimaryLight, lineWidth: 3)
                .frame(width: 40, height: 40)

            Circle()
                .trim(from: 0, to: CGFloat(ratio) / 100)
                .stroke(
                    ratio >= 70 ? Color.vaySuccess : ratio >= 40 ? Color.vayWarning : Color.vayDanger,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 40, height: 40)

            Text("\(ratio)%")
                .font(VayFont.caption(9))
                .foregroundStyle(.secondary)
        }
    }

    private func filterBadge(_ filter: String) -> some View {
        let label: String
        let color: Color
        switch filter {
        case "expiring": label = "Истекает"; color = .vayWarning
        case "in_stock": label = "Есть дома"; color = .vaySuccess
        default: label = filter; color = .secondary
        }
        return Text(label)
            .font(VayFont.caption(10))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // Placeholder for recipe detail — existing RecipeView handles this
    @ViewBuilder
    private func recipeDetailPlaceholder(_ item: CookNowResponse.CookNowRecipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VaySpacing.md) {
                Text(item.recipe.title)
                    .font(VayFont.title())
                    .padding(.horizontal, VaySpacing.lg)

                if !item.recipe.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: VaySpacing.sm) {
                        Text("Ингредиенты")
                            .font(VayFont.heading(16))
                        ForEach(item.recipe.ingredients.prefix(15), id: \.self) { ingredient in
                            HStack(spacing: VaySpacing.sm) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(Color.vayPrimary)
                                Text(ingredient)
                                    .font(VayFont.body(14))
                            }
                        }
                    }
                    .vayCard()
                    .padding(.horizontal, VaySpacing.lg)
                }

                if !item.recipe.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: VaySpacing.sm) {
                        Text("Инструкция")
                            .font(VayFont.heading(16))
                        ForEach(Array(item.recipe.instructions.prefix(10).enumerated()), id: \.offset) { idx, step in
                            HStack(alignment: .top, spacing: VaySpacing.sm) {
                                Text("\(idx + 1)")
                                    .font(VayFont.label(13))
                                    .foregroundStyle(Color.vayPrimary)
                                    .frame(width: 20)
                                Text(step)
                                    .font(VayFont.body(14))
                            }
                        }
                    }
                    .vayCard()
                    .padding(.horizontal, VaySpacing.lg)
                }

                Color.clear.frame(height: VayLayout.tabBarOverlayInset)
            }
            .padding(.top, VaySpacing.md)
        }
        .background(Color.vayBackground)
        .navigationTitle("Рецепт")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        VStack(spacing: VaySpacing.md) {
            Image(systemName: "refrigerator")
                .font(.system(size: 40))
                .foregroundStyle(Color.vayPrimaryLight)

            Text("Нет подходящих рецептов")
                .font(VayFont.heading(16))

            Text("Добавьте больше продуктов в инвентарь, и мы подберём что-нибудь вкусное.")
                .font(VayFont.body(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var loadingCard: some View {
        HStack(spacing: VaySpacing.sm) {
            SwiftUI.ProgressView()
            Text("Ищем рецепты из вашего инвентаря...")
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
                Task { await loadRecipes() }
            }
            .font(VayFont.label(12))
            .buttonStyle(.borderedProminent)
            .tint(Color.vayPrimary)
        }
        .padding(VaySpacing.md)
        .background(Color.vayWarning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
    }

    // MARK: - Data loading

    private func loadRecipes() async {
        guard let client = recipeServiceClient else {
            errorMessage = "Сервис рецептов недоступен."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let products = (try? await inventoryService.listProducts(location: nil, search: nil)) ?? []
            let batches = (try? await inventoryService.listBatches(productId: nil)) ?? []

            let inventoryKeywords = products.map { $0.name.lowercased() }
            let now = Date()
            let expiringSoonKeywords = batches
                .filter { batch in
                    guard let expiry = batch.expiryDate else { return false }
                    return expiry.timeIntervalSince(now) < 5 * 24 * 3600 && expiry > now
                }
                .compactMap { batch in products.first(where: { $0.id == batch.productId })?.name.lowercased() }

            inventoryCount = products.count

            let payload = CookNowRequest(
                inventoryKeywords: inventoryKeywords,
                expiringSoonKeywords: expiringSoonKeywords,
                maxPrepTime: 45,
                limit: 7,
                exclude: nil
            )

            let response = try await client.cookNow(payload: payload)
            recipes = response.recipes
            inventoryCount = response.inventoryCount
        } catch {
            errorMessage = "Не удалось загрузить рецепты. Проверьте подключение."
        }

        isLoading = false
    }
}
