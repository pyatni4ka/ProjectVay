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
        List {
            // Permissions
            Section {
                Button {
                    Task { await requestNotifications() }
                } label: {
                    row("bell.badge.fill", .vayPrimary) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Разрешить уведомления")
                                .font(VayFont.body(15))
                            if let notificationsGranted {
                                Text(notificationsGranted ? "✓ Разрешены" : "Отключены")
                                    .font(VayFont.caption(12))
                                    .foregroundStyle(notificationsGranted ? Color.vaySuccess : Color.secondary)
                            }
                        }
                    }
                }
            } header: {
                secHead("lock.shield", "Разрешения")
            }

            // Goal
            Section {
                row("target", .vayDanger) {
                    Text("Похудение: −0.5 кг/нед")
                        .font(VayFont.body(15))
                        .foregroundStyle(.secondary)
                }
            } header: {
                secHead("flag", "Цель")
            }

            // Quiet Hours
            Section {
                row("moon.fill", .indigo) {
                    DatePicker("Начало", selection: $quietStartDate, displayedComponents: [.hourAndMinute])
                }
                row("sunrise.fill", .orange) {
                    DatePicker("Конец", selection: $quietEndDate, displayedComponents: [.hourAndMinute])
                }
            } header: {
                secHead("moon.zzz", "Тихие часы")
            }

            // Meals
            Section {
                row("cup.and.saucer.fill", .vayWarning) {
                    DatePicker("Завтрак", selection: $breakfastDate, displayedComponents: [.hourAndMinute])
                }
                row("fork.knife", .vayPrimary) {
                    DatePicker("Обед", selection: $lunchDate, displayedComponents: [.hourAndMinute])
                }
                row("moon.stars.fill", .vaySecondary) {
                    DatePicker("Ужин", selection: $dinnerDate, displayedComponents: [.hourAndMinute])
                }
            } header: {
                secHead("clock", "Приёмы пищи")
            }

            // Expiry Alerts
            Section {
                row("exclamationmark.triangle.fill", .vayWarning) {
                    TextField("Дни (5,3,1)", text: $expiryDaysText)
                }
            } header: {
                secHead("bell", "Уведомления о сроке")
            }

            // Budget
            Section {
                row("rublesign.circle.fill", .vaySuccess) {
                    TextField("₽/день", text: $budgetDayText)
                        .keyboardType(.decimalPad)
                }
                row("calendar.circle.fill", .vayInfo) {
                    TextField("₽/нед (опц.)", text: $budgetWeekText)
                        .keyboardType(.decimalPad)
                }
            } header: {
                secHead("banknote", "Бюджет")
            }

            // Disliked
            Section {
                row("hand.thumbsdown.fill", .vayDanger) {
                    TextField("Через запятую", text: $dislikedText)
                }
                row("fish.fill", .vaySecondary) {
                    Toggle("Кости ОК", isOn: $avoidBones)
                }
            } header: {
                secHead("xmark.circle", "Нелюбимое")
            }

            // Macros
            Section {
                row("chart.bar.fill", .vayPrimary) {
                    Toggle("Строго по КБЖУ", isOn: $strictMacroTracking)
                }
                if strictMacroTracking {
                    VStack(alignment: .leading, spacing: VaySpacing.sm) {
                        HStack {
                            Text("Допуск").font(VayFont.body(14))
                            Spacer()
                            Text("±\(Int(macroTolerancePercent))%")
                                .font(VayFont.label(13))
                                .foregroundStyle(Color.vayPrimary)
                        }
                        Slider(value: $macroTolerancePercent, in: 5...60, step: 5)
                            .tint(.vayPrimary)
                    }
                }
            } header: {
                secHead("flame", "КБЖУ")
            }

            // Stores
            Section {
                ForEach(Store.allCases) { store in
                    Button { toggleStore(store) } label: {
                        HStack {
                            Image(systemName: "storefront.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(selectedStores.contains(store) ? Color.vayPrimary : .gray)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(store.title)
                                .font(VayFont.body(15))
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedStores.contains(store) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.vayPrimary)
                            }
                        }
                    }
                }
            } header: {
                secHead("cart", "Магазины")
            }

            // Save
            Section {
                Button {
                    Task { await saveOnboarding() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Завершить")
                        }
                        Spacer()
                    }
                    .font(VayFont.label())
                    .foregroundStyle(.white)
                    .padding(.vertical, VaySpacing.sm)
                    .background(Color.vayPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
                }
                .disabled(isSaving)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Настройка")
        .task { await loadSettings() }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Components

    private func row<C: View>(_ icon: String, _ color: Color, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            content()
        }
    }

    private func secHead(_ icon: String, _ title: String) -> some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: icon).font(.system(size: 11))
            Text(title)
        }
        .font(VayFont.caption(12))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    // MARK: - Logic (preserved)

    private func toggleStore(_ store: Store) {
        if selectedStores.contains(store) { selectedStores.remove(store) }
        else { selectedStores.insert(store) }
        VayHaptic.selection()
    }

    private func requestNotifications() async {
        do { notificationsGranted = try await settingsService.requestNotificationAuthorization() }
        catch { errorMessage = error.localizedDescription }
    }

    private func loadSettings() async {
        do {
            let s = try await settingsService.loadSettings()
            quietStartDate = DateComponents.from(minutes: s.quietStartMinute).asDate
            quietEndDate = DateComponents.from(minutes: s.quietEndMinute).asDate
            breakfastDate = DateComponents.from(minutes: s.mealSchedule.breakfastMinute).asDate
            lunchDate = DateComponents.from(minutes: s.mealSchedule.lunchMinute).asDate
            dinnerDate = DateComponents.from(minutes: s.mealSchedule.dinnerMinute).asDate
            expiryDaysText = s.expiryAlertsDays.map(String.init).joined(separator: ",")
            budgetDayText = s.budgetDay.formattedSimple
            budgetWeekText = s.budgetWeek?.formattedSimple ?? ""
            dislikedText = s.dislikedList.joined(separator: ", ")
            avoidBones = s.avoidBones
            strictMacroTracking = s.strictMacroTracking
            macroTolerancePercent = s.macroTolerancePercent
            selectedStores = Set(s.stores)
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveOnboarding() async {
        guard let bd = Decimal(string: budgetDayText.replacingOccurrences(of: ",", with: ".")), bd >= 0 else {
            errorMessage = "Некорректный бюджет в день"; return
        }
        var bw: Decimal?
        if !budgetWeekText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let v = Decimal(string: budgetWeekText.replacingOccurrences(of: ",", with: ".")), v >= 0 else {
                errorMessage = "Некорректный бюджет в неделю"; return
            }
            bw = v
        }
        let days = expiryDaysText.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let disliked = dislikedText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let settings = AppSettings(
            quietStartMinute: minuteOfDay(quietStartDate),
            quietEndMinute: minuteOfDay(quietEndDate),
            expiryAlertsDays: days, budgetDay: bd, budgetWeek: bw,
            stores: selectedStores.isEmpty ? AppSettings.default.stores : Array(selectedStores),
            dislikedList: disliked, avoidBones: avoidBones,
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
            VayHaptic.success()
            await onComplete()
        } catch { errorMessage = error.localizedDescription }
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

private extension Decimal {
    var formattedSimple: String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 2
        f.decimalSeparator = ","
        return f.string(from: NSDecimalNumber(decimal: self)) ?? "0"
    }
}
