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
    @State private var budgetInputPeriod: AppSettings.BudgetInputPeriod = .week
    @State private var budgetPrimaryText = AppSettings.default.budgetWeek?.formattedSimple ?? "5600"
    @State private var dislikedText = "кускус"
    @State private var avoidBones = true
    @State private var strictMacroTracking = true
    @State private var macroTolerancePercent = 25.0
    @State private var selectedStores = Set(AppSettings.default.stores)
    @State private var notificationsGranted: Bool?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var loadedSettings: AppSettings = .default

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
                Picker("Период бюджета", selection: $budgetInputPeriod) {
                    ForEach(AppSettings.BudgetInputPeriod.allCases, id: \.rawValue) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: budgetInputPeriod) { previous, current in
                    convertBudgetPrimaryInput(from: previous, to: current)
                }

                row("rublesign.circle.fill", .vaySuccess) {
                    TextField(budgetPrimaryPlaceholder, text: $budgetPrimaryText)
                        .keyboardType(.decimalPad)
                }

                ForEach(readOnlyBudgetRows, id: \.period.rawValue) { rowData in
                    row(rowData.icon, rowData.color) {
                        Text("\(rowData.label): \(rowData.value)")
                            .font(VayFont.body(14))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                secHead("banknote", "Бюджет")
            } footer: {
                Text("Введите бюджет за выбранный период. Остальные периоды считаются автоматически.")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
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
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
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

    private var budgetPrimaryPlaceholder: String {
        switch budgetInputPeriod {
        case .day:
            return "₽/день"
        case .week:
            return "₽/нед"
        case .month:
            return "₽/мес"
        }
    }

    private var displayBudgetBreakdown: (day: Decimal, week: Decimal, month: Decimal) {
        if let parsedBudgetBreakdown {
            return parsedBudgetBreakdown
        }

        let primary = budgetPrimaryValue(from: loadedSettings, period: budgetInputPeriod)
        return AppSettings.budgetBreakdown(input: primary, period: budgetInputPeriod)
    }

    private var readOnlyBudgetRows: [(period: AppSettings.BudgetInputPeriod, icon: String, color: Color, label: String, value: String)] {
        let breakdown = displayBudgetBreakdown
        let allRows: [(AppSettings.BudgetInputPeriod, String, Color, String, String)] = [
            (.day, "calendar", .vayInfo, "Рассчитано в день", "\(breakdown.day.formattedSimple) ₽"),
            (.week, "calendar.badge.clock", .vayWarning, "Рассчитано в неделю", "\(breakdown.week.formattedSimple) ₽"),
            (.month, "calendar.badge.plus", .vayPrimary, "Рассчитано в месяц", "\(breakdown.month.formattedSimple) ₽")
        ]

        return allRows.filter { $0.0 != budgetInputPeriod }
            .map { (period: $0.0, icon: $0.1, color: $0.2, label: $0.3, value: $0.4) }
    }

    private func selectedBudgetPeriodTitle() -> String {
        switch budgetInputPeriod {
        case .day:
            return "день"
        case .week:
            return "неделю"
        case .month:
            return "месяц"
        }
    }

    private var parsedBudgetBreakdown: (day: Decimal, week: Decimal, month: Decimal)? {
        guard let primaryBudget = parseBudgetValue(budgetPrimaryText) else {
            return nil
        }

        return AppSettings.budgetBreakdown(
            input: primaryBudget,
            period: budgetInputPeriod
        )
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
            loadedSettings = s
            quietStartDate = DateComponents.from(minutes: s.quietStartMinute).asDate
            quietEndDate = DateComponents.from(minutes: s.quietEndMinute).asDate
            breakfastDate = DateComponents.from(minutes: s.mealSchedule.breakfastMinute).asDate
            lunchDate = DateComponents.from(minutes: s.mealSchedule.lunchMinute).asDate
            dinnerDate = DateComponents.from(minutes: s.mealSchedule.dinnerMinute).asDate
            expiryDaysText = s.expiryAlertsDays.map(String.init).joined(separator: ",")
            budgetInputPeriod = s.budgetInputPeriod
            budgetPrimaryText = budgetPrimaryValue(
                from: s,
                period: s.budgetInputPeriod
            ).formattedSimple
            dislikedText = s.dislikedList.joined(separator: ", ")
            avoidBones = s.avoidBones
            strictMacroTracking = s.strictMacroTracking
            macroTolerancePercent = s.macroTolerancePercent
            selectedStores = Set(s.stores)
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveOnboarding() async {
        guard let budgetBreakdown = parsedBudgetBreakdown else {
            errorMessage = "Некорректный бюджет за \(selectedBudgetPeriodTitle())"
            return
        }

        let days = expiryDaysText.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let disliked = dislikedText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let settings = AppSettings(
            quietStartMinute: minuteOfDay(quietStartDate),
            quietEndMinute: minuteOfDay(quietEndDate),
            expiryAlertsDays: days,
            budgetDay: budgetBreakdown.day,
            budgetWeek: budgetBreakdown.week,
            budgetMonth: budgetBreakdown.month,
            budgetInputPeriod: budgetInputPeriod,
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

    private func convertBudgetPrimaryInput(
        from previous: AppSettings.BudgetInputPeriod,
        to current: AppSettings.BudgetInputPeriod
    ) {
        guard previous != current else { return }

        let sourceValue: Decimal
        if let primaryBudget = parseBudgetValue(budgetPrimaryText) {
            sourceValue = primaryBudget
        } else {
            sourceValue = budgetPrimaryValue(from: loadedSettings, period: previous)
        }

        let previousBreakdown = AppSettings.budgetBreakdown(
            input: sourceValue,
            period: previous
        )

        let converted: Decimal
        switch current {
        case .day:
            converted = previousBreakdown.day
        case .week:
            converted = previousBreakdown.week
        case .month:
            converted = previousBreakdown.month
        }
        budgetPrimaryText = converted.formattedSimple
    }

    private func budgetPrimaryValue(
        from settings: AppSettings,
        period: AppSettings.BudgetInputPeriod
    ) -> Decimal {
        switch period {
        case .day:
            if settings.budgetDay > 0 {
                return settings.budgetDay.rounded(scale: 2)
            }
            if let budgetWeek = settings.budgetWeek {
                return AppSettings.dailyBudget(fromWeekly: budgetWeek)
            }
            if let budgetMonth = settings.budgetMonth {
                return AppSettings.dailyBudget(fromMonthly: budgetMonth)
            }
            return 0
        case .week:
            if let budgetWeek = settings.budgetWeek {
                return budgetWeek.rounded(scale: 2)
            }
            if let budgetMonth = settings.budgetMonth {
                return AppSettings.weeklyBudget(fromMonthly: budgetMonth)
            }
            return (max(0, settings.budgetDay) * 7).rounded(scale: 2)
        case .month:
            if let budgetMonth = settings.budgetMonth {
                return budgetMonth.rounded(scale: 2)
            }
            if let budgetWeek = settings.budgetWeek {
                return AppSettings.monthlyBudget(fromWeekly: budgetWeek)
            }
            return (max(0, settings.budgetDay) * 365 / 12).rounded(scale: 2)
        }
    }

    private func parseBudgetValue(_ value: String) -> Decimal? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let decimal = Decimal(string: normalized), decimal >= 0 else { return nil }
        return decimal.rounded(scale: 2)
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
