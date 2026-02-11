import SwiftUI

struct RecipeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Rectangle()
                    .fill(.gray.opacity(0.2))
                    .frame(height: 220)
                    .overlay(Text("Фото рецепта"))

                Text("Омлет с овощами")
                    .font(.title2.bold())

                Link("Источник: example.ru", destination: URL(string: "https://example.ru")!)
                Link("Открыть видео", destination: URL(string: "https://youtube.com")!)

                VStack(alignment: .leading) {
                    Text("Ингредиенты").font(.headline)
                    Text("• Яйца (есть дома)")
                    Text("• Помидоры (нет дома)")
                }

                VStack(alignment: .leading) {
                    Text("Шаги").font(.headline)
                    Text("1. Взбить яйца")
                    Text("2. Добавить овощи")
                    Text("3. Готовить 7 минут")
                }

                Button("Добавить недостающее в список покупок") {}
                    .buttonStyle(.borderedProminent)

                Button("Готовлю") {}
                    .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Рецепт")
    }
}
