import SwiftUI
import UIKit
import Nuke
import NukeUI

struct RecipeView: View {
    let recipe: Recipe
    let availableIngredients: Set<String>
    let inventoryService: any InventoryServiceProtocol
    let onInventoryChanged: () async -> Void

    @State private var statusText: String?
    @State private var pendingWriteOffPlan: RecipeWriteOffPlan?
    @State private var showWriteOffConfirmation = false
    @State private var isPreparingWriteOff = false
    @State private var isApplyingWriteOff = false

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
            VStack(alignment: .leading, spacing: 16) {
                LazyImage(source: recipe.imageURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(.gray.opacity(0.2))
                            .overlay(SwiftUI.ProgressView())
                    }
                }
                .processors([ImageProcessors.Resize(width: 900)])
                .priority(.high)
                .pipeline(ImagePipeline.shared)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.title)
                        .font(.title2.bold())

                    Link("Источник: \(recipe.sourceName)", destination: recipe.sourceURL)
                        .font(.subheadline)

                    if let videoURL = recipe.videoURL {
                        Link("Открыть видео", destination: videoURL)
                            .font(.subheadline)
                    }

                    if let nutrition = recipe.nutrition {
                        Text(nutritionSummary(nutrition))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ингредиенты")
                        .font(.headline)

                    ForEach(recipe.ingredients, id: \.self) { ingredient in
                        let inStock = availableIngredients.contains(normalize(ingredient))
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: inStock ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(inStock ? .green : .secondary)
                            Text(ingredient)
                        }
                        .font(.subheadline)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Шаги")
                        .font(.headline)

                    ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .font(.subheadline)
                    }
                }

                Button("Добавить недостающее в список покупок") {
                    copyMissingIngredients()
                }
                .buttonStyle(.borderedProminent)

                Button(isPreparingWriteOff ? "Подготовка..." : (isApplyingWriteOff ? "Списание..." : "Готовлю")) {
                    Task { await prepareWriteOffPlan() }
                }
                .buttonStyle(.bordered)
                .disabled(isPreparingWriteOff || isApplyingWriteOff)

                if let statusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Рецепт")
        .navigationBarTitleDisplayMode(.inline)
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
