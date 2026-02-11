import SwiftUI

struct OnboardingView: View {
    var body: some View {
        Form {
            Section("Разрешения") {
                Text("Apple Health (чтение)")
                Text("Уведомления")
            }
            Section("Цели") {
                Text("Похудение: -0.5 кг/нед")
            }
            Section("Тихие часы") {
                Text("01:00–06:00")
            }
            Section("Бюджет") {
                Text("500–1000 ₽/день")
            }
        }
        .navigationTitle("Онбординг")
    }
}
