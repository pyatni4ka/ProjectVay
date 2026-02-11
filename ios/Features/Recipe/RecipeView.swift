import SwiftUI
import UIKit

struct RecipeView: View {
    let recipe: Recipe
    let availableIngredients: Set<String>

    @State private var copyStatus: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: recipe.imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(.gray.opacity(0.2))
                        .overlay(SwiftUI.ProgressView())
                }
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

                Button("Готовлю") {}
                    .buttonStyle(.bordered)

                if let copyStatus {
                    Text(copyStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Рецепт")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func copyMissingIngredients() {
        let missing = recipe.ingredients.filter { ingredient in
            !availableIngredients.contains(normalize(ingredient))
        }

        guard !missing.isEmpty else {
            copyStatus = "Все ингредиенты есть дома."
            return
        }

        UIPasteboard.general.string = missing.joined(separator: "\n")
        copyStatus = "Список недостающих ингредиентов скопирован."
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
