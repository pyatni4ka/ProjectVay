import SwiftUI

struct OnboardingFlowView: View {
    let settingsService: any SettingsServiceProtocol
    let onComplete: () async -> Void

    @State private var quietStartDate = DateComponents.from(minutes: AppSettings.default.quietStartMinute).asDate
    @State private var quietEndDate = DateComponents.from(minutes: AppSettings.default.quietEndMinute).asDate
    @State private var breakfastDate = DateComponents.from(minutes: AppSettings.default.mealSchedule.breakfastMinute).asDate
    @State private var lunchDate = DateComponents.from(minutes: AppSettings.default.mealSchedule.lunchMinute).asDate
    @State private var dinnerDate = DateComponents.from(minutes: AppSettings.default.mealSchedule.dinnerMinute).asDate
    @State private var expiryDaysText = "5,3,1"
    @State private var budgetDayText = "800"
    @State private var budgetWeekText = ""
    @State private var dislikedText = "кускус"
    @State private var avoidBones = true
    @State private var strictMacroTracking = true
    @State private var macroTolerancePercent = 25.0
    @State private var selectedStores = Set(AppSettings.default.stores)

    @State private var notificationsGranted: Bool?
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let calendar = Calendar.current

    var body: some View {
        Form {
            Section("Разрешения") {
                Button("Разрешить уведомления") {
                    Task { await requestNotifications() }
                }

                if let notificationsGranted {
                    Text(notificationsGranted ? "Уведомления разрешены" : "Уведомления отключены")
                        .foregroundStyle(notificationsGranted ? .green : .secondary)
                }
            }

            Section("Цель") {
                Text("Похудение: -0.5 кг/нед")
                    .foregroundStyle(.secondary)
            }

            Section("Тихие часы") {
                DatePicker("Начало", selection: $quietStartDate, displayedComponents: [.hourAndMinute])
                DatePicker("Конец", selection: $quietEndDate, displayedComponents: [.hourAndMinute])
            }

            Section("Время приёмов пищи") {
                DatePicker("Завтрак", selection: $breakfastDate, displayedComponents: [.hourAndMinute])
                DatePicker("Обед", selection: $lunchDate, displayedComponents: [.hourAndMinute])
                DatePicker("Ужин", selection: $dinnerDate, displayedComponents: [.hourAndMinute])
            }

            Section("Уведомления о сроке") {
                TextField("Дни до срока (например: 5,3,1)", text: $expiryDaysText)
            }

            Section("Бюджет") {
                TextField("₽/день", text: $budgetDayText)
                    .keyboardType(.decimalPad)
                TextField("₽/неделя (опционально)", text: $budgetWeekText)
                    .keyboardType(.decimalPad)
            }

            Section("Нелюбимые продукты") {
                TextField("Список через запятую", text: $dislikedText)
                Toggle("Кости допустимы редко", isOn: $avoidBones)
            }

            Section("КБЖУ на следующий приём") {
                Toggle("Строго подбирать блюда по КБЖУ", isOn: $strictMacroTracking)
                if strictMacroTracking {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Допуск")
                            Spacer()
                            Text("±\(Int(macroTolerancePercent))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $macroTolerancePercent, in: 5...60, step: 5)
                    }
                }
            }

            Section("Магазины") {
                ForEach(Store.allCases) { store in
                    Button {
                        toggleStore(store)
                    } label: {
                        HStack {
                            Text(store.title)
                            Spacer()
                            if selectedStores.contains(store) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section {
                Button(isSaving ? "Сохраняем..." : "Завершить онбординг") {
                    Task { await saveOnboarding() }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Онбординг")
        .task {
            await loadSettings()
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
    }

    private func toggleStore(_ store: Store) {
        if selectedStores.contains(store) {
            selectedStores.remove(store)
        } else {
            selectedStores.insert(store)
        }
    }

    private func requestNotifications() async {
        do {
            notificationsGranted = try await settingsService.requestNotificationAuthorization()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSettings() async {
        do {
            let settings = try await settingsService.loadSettings()
            quietStartDate = DateComponents.from(minutes: settings.quietStartMinute).asDate
            quietEndDate = DateComponents.from(minutes: settings.quietEndMinute).asDate
            breakfastDate = DateComponents.from(minutes: settings.mealSchedule.breakfastMinute).asDate
            lunchDate = DateComponents.from(minutes: settings.mealSchedule.lunchMinute).asDate
            dinnerDate = DateComponents.from(minutes: settings.mealSchedule.dinnerMinute).asDate
            expiryDaysText = settings.expiryAlertsDays.map(String.init).joined(separator: ",")
            budgetDayText = settings.budgetDay.formattedSimple
            budgetWeekText = settings.budgetWeek?.formattedSimple ?? ""
            dislikedText = settings.dislikedList.joined(separator: ", ")
            avoidBones = settings.avoidBones
            strictMacroTracking = settings.strictMacroTracking
            macroTolerancePercent = settings.macroTolerancePercent
            selectedStores = Set(settings.stores)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveOnboarding() async {
        guard let budgetDay = Decimal(string: budgetDayText.replacingOccurrences(of: ",", with: ".")), budgetDay >= 0 else {
            errorMessage = "Некорректный бюджет в день"
            return
        }

        var budgetWeek: Decimal?
        if !budgetWeekText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let value = Decimal(string: budgetWeekText.replacingOccurrences(of: ",", with: ".")), value >= 0 else {
                errorMessage = "Некорректный бюджет в неделю"
                return
            }
            budgetWeek = value
        }

        let days = expiryDaysText
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        let disliked = dislikedText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        let settings = AppSettings(
            quietStartMinute: minuteOfDay(quietStartDate),
            quietEndMinute: minuteOfDay(quietEndDate),
            expiryAlertsDays: days,
            budgetDay: budgetDay,
            budgetWeek: budgetWeek,
            stores: selectedStores.isEmpty ? AppSettings.default.stores : Array(selectedStores),
            dislikedList: disliked,
            avoidBones: avoidBones,
            mealSchedule: .init(
                breakfastMinute: minuteOfDay(breakfastDate),
                lunchMinute: minuteOfDay(lunchDate),
                dinnerMinute: minuteOfDay(dinnerDate)
            ),
            strictMacroTracking: strictMacroTracking,
            macroTolerancePercent: macroTolerancePercent
        ).normalized()

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await settingsService.saveSettings(settings)
            try await settingsService.setOnboardingCompleted()
            await onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

private extension DateComponents {
    var asDate: Date {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        var composed = DateComponents()
        composed.year = today.year
        composed.month = today.month
        composed.day = today.day
        composed.hour = hour
        composed.minute = minute
        return calendar.date(from: composed) ?? now
    }
}

private extension Decimal {
    var formattedSimple: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = ","
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? "0"
    }
}
