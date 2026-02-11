import SwiftUI

struct MealPlanView: View {
    var body: some View {
        List {
            Section("Сегодня") {
                Text("Завтрак: Омлет")
                Text("Обед: Курица с рисом")
                Text("Ужин: Творожная запеканка")
            }
            Section("Покупки") {
                Text("Помидоры")
                Text("Творог")
            }
        }
        .navigationTitle("План питания")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Сгенерировать") {}
            }
        }
    }
}
