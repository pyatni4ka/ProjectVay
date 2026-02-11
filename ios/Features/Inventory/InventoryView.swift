import SwiftUI

struct InventoryView: View {
    var body: some View {
        List {
            Section("Холодильник") {
                Text("Молоко — 2 шт")
                Text("Яйца — 10 шт")
            }
            Section("Морозилка") {
                Text("Курица — 1 кг")
            }
            Section("Шкаф") {
                Text("Гречка — 800 г")
            }
        }
        .navigationTitle("Инвентарь")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Сканировать") {}
                Button("Добавить") {}
            }
        }
    }
}
