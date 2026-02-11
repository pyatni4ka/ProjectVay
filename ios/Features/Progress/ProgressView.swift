import SwiftUI

struct ProgressView: View {
    var body: some View {
        List {
            Section("Тренд веса") {
                Text("Текущий вес: 82.4 кг")
                Text("Тренд: -0.4 кг/нед")
            }
            Section("Корректировка калорий") {
                Text("Новая цель: 2150 ккал/день")
            }
        }
        .navigationTitle("Прогресс")
    }
}
