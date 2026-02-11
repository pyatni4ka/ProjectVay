import SwiftUI

struct HomeView: View {
    var body: some View {
        List {
            Section("Срочно использовать") {
                Label("Творог 5% (1 день)", systemImage: "exclamationmark.triangle.fill")
                Label("Шампиньоны (2 дня)", systemImage: "clock.badge.exclamationmark")
            }

            Section("Рекомендации") {
                NavigationLink("Омлет с овощами") {
                    RecipeView()
                }
                NavigationLink("Творожная запеканка") {
                    RecipeView()
                }
            }
        }
        .navigationTitle("Что приготовить")
        .searchable(text: .constant(""), prompt: "Поиск рецептов")
    }
}
