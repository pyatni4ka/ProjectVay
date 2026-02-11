import SwiftUI
import UIKit

struct RecipeView: View {
    let recipe: Recipe
    let availableIngredients: Set<String>

    @State private var copiedMissing = false

    private var missingIngredients: [String] {
        recipe.ingredients.filter { ingredient in
            !availableIngredients.contains(normalize(ingredient))
        }
    }

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
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(recipe.title)
                    .font(.title2.bold())

                HStack(spacing: 12) {
                    if let minutes = recipe.totalTimeMinutes {
                        Label("\(minutes) мин", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let servings = recipe.servings {
                        Label("\(servings) порц", systemImage: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Link("Источник: \(recipe.sourceName)", destination: recipe.sourceURL)
                if let videoURL = recipe.videoURL {
                    Link("Открыть видео", destination: videoURL)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ингредиенты")
                        .font(.headline)

                    ForEach(recipe.ingredients, id: \.self) { ingredient in
                        let isAvailable = availableIngredients.contains(normalize(ingredient))
                        HStack(spacing: 8) {
                            Image(systemName: isAvailable ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isAvailable ? .green : .secondary)
                            Text(ingredient)
                            Spacer()
                            Text(isAvailable ? "есть" : "нет")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Шаги")
                        .font(.headline)

                    ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Button(missingIngredients.isEmpty ? "Все ингредиенты есть" : "Скопировать недостающее") {
                    guard !missingIngredients.isEmpty else { return }
                    UIPasteboard.general.string = missingIngredients.joined(separator: "\n")
                    copiedMissing = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(missingIngredients.isEmpty)

                if copiedMissing {
                    Text("Недостающие ингредиенты скопированы в буфер обмена")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button("Готовлю") {}
                    .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Рецепт")
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
