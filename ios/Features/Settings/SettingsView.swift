import SwiftUI

struct SettingsView: View {
    let settingsService: any SettingsServiceProtocol

    @State private var quietStartDate = DateComponents.from(minutes: AppSettings.default.quietStartMinute).asSettingsDate
    @State private var quietEndDate = DateComponents.from(minutes: AppSettings.default.quietEndMinute).asSettingsDate
    @State private var breakfastDate = DateComponents.from(minutes: AppSettings.default.mealSchedule.breakfastMinute).asSettingsDate
    @State private var lunchDate = DateComponents.from(minutes: AppSettings.default.mealSchedule.lunchMinute).asSettingsDate
    @State private var dinnerDate = DateComponents.from(minutes: AppSettings.default.mealSchedule.dinnerMinute).asSettingsDate
    @State private var expiryDaysText = "5,3,1"
    @State private var budgetDayText = "800"
    @State private var budgetWeekText = ""
    @State private var dislikedText = "кускус"
    @State private var avoidBones = true
    @State private var selectedStores = Set(AppSettings.default.stores)

    @State private var isSaving = false
    @State private var errorMessage: String?

    private let calendar = Calendar.current

    var body: some View {
        Form {
            Section("Уведомления") {
                DatePicker("Тихие часы: начало", selection: $quietStartDate, displayedComponents: [.hourAndMinute])
                DatePicker("Тихие часы: конец", selection: $quietEndDate, displayedComponents: [.hourAndMinute])
                TextField("Дни напоминаний (5,3,1)", text: $expiryDaysText)
            }

            Section("Питание") {
                TextField("Бюджет ₽/день", text: $budgetDayText)
                    .keyboardType(.decimalPad)
                TextField("Бюджет ₽/неделя", text: $budgetWeekText)
                    .keyboardType(.decimalPad)
                TextField("Нелюбимые продукты", text: $dislikedText)
                Toggle("Кости допустимы редко", isOn: $avoidBones)
            }

            Section("Расписание приёмов") {
                DatePicker("Завтрак", selection: $breakfastDate, displayedComponents: [.hourAndMinute])
                DatePicker("Обед", selection: $lunchDate, displayedComponents: [.hourAndMinute])
                DatePicker("Ужин", selection: $dinnerDate, displayedComponents: [.hourAndMinute])
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
                Button(isSaving ? "Сохраняем..." : "Сохранить настройки") {
                    Task { await save() }
                }
                .disabled(isSaving)
            }

            Section("Данные") {
                Button("Экспорт данных") {}
                Button("Удалить локальные данные", role: .destructive) {}
            }
        }
        .navigationTitle("Настройки")
        .task {
            await load()
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

    private func load() async {
        do {
            let settings = try await settingsService.loadSettings()
            quietStartDate = DateComponents.from(minutes: settings.quietStartMinute).asSettingsDate
            quietEndDate = DateComponents.from(minutes: settings.quietEndMinute).asSettingsDate
            breakfastDate = DateComponents.from(minutes: settings.mealSchedule.breakfastMinute).asSettingsDate
            lunchDate = DateComponents.from(minutes: settings.mealSchedule.lunchMinute).asSettingsDate
            dinnerDate = DateComponents.from(minutes: settings.mealSchedule.dinnerMinute).asSettingsDate
            expiryDaysText = settings.expiryAlertsDays.map(String.init).joined(separator: ",")
            budgetDayText = settings.budgetDay.formattedSimple
            budgetWeekText = settings.budgetWeek?.formattedSimple ?? ""
            dislikedText = settings.dislikedList.joined(separator: ", ")
            avoidBones = settings.avoidBones
            selectedStores = Set(settings.stores)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard let budgetDay = Decimal(string: budgetDayText.replacingOccurrences(of: ",", with: ".")), budgetDay >= 0 else {
            errorMessage = "Введите корректный дневной бюджет"
            return
        }

        var budgetWeek: Decimal?
        if !budgetWeekText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let week = Decimal(string: budgetWeekText.replacingOccurrences(of: ",", with: ".")), week >= 0 else {
                errorMessage = "Введите корректный недельный бюджет"
                return
            }
            budgetWeek = week
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
            )
        ).normalized()

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await settingsService.saveSettings(settings)
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
    var asSettingsDate: Date {
        let calendar = Calendar.current
        let now = Date()
        let day = calendar.dateComponents([.year, .month, .day], from: now)
        var comps = DateComponents()
        comps.year = day.year
        comps.month = day.month
        comps.day = day.day
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps) ?? now
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
