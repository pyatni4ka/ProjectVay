import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Уведомления") {
                Text("Шаблон: 5/3/1")
                Text("Тихие часы: 01:00–06:00")
            }
            Section("Питание") {
                Text("Бюджет: 500–1000 ₽/день")
                Text("Нелюбимые: кускус")
                Text("Кости: редко")
            }
            Section("Источники") {
                Text("White-list рецептов")
            }
            Section("Данные") {
                Button("Экспорт данных") {}
                Button("Удалить локальные данные", role: .destructive) {}
            }
        }
        .navigationTitle("Настройки")
    }
}
