import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    let settingsService: any SettingsServiceProtocol
    let inventoryService: any InventoryServiceProtocol
    let shoppingListService: any ShoppingListServiceProtocol
    let healthKitService: HealthKitService
    @Environment(AppSettingsStore.self) private var appSettingsStore

    @State private var settings: AppSettings = .default
    @State private var lastPersistedSettings: AppSettings = .default
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isHydratingSettings = false
    @State private var autoSaveTask: Task<Void, Never>?

    @State private var showResetInventoryAlert = false
    @State private var showResetShoppingListAlert = false
    @State private var showResetAllAlert = false

    @State private var quietStartDate = Date()
    @State private var quietEndDate = Date()
    @State private var breakfastDate = Date()
    @State private var lunchDate = Date()
    @State private var dinnerDate = Date()

    @State private var selectedTheme: Int = 0
    @State private var healthKitReadEnabled: Bool = true
    @State private var healthKitWriteEnabled: Bool = false
    @State private var motionLevel: AppSettings.MotionLevel = .full
    @State private var hapticsEnabled: Bool = true
    @State private var showHealthCardOnHome: Bool = true

    @State private var budgetInputPeriod: AppSettings.BudgetInputPeriod = .week
    @State private var budgetPrimaryText = ""
    @FocusState private var isBudgetFieldFocused: Bool
    /// True while applyLoadedSettings is populating state — prevents spurious period conversion.
    @State private var isBudgetHydrating = false

    private let themeOptions = ["Системный", "Светлый", "Тёмный"]

    private struct AutoSaveState: Equatable {
        let selectedTheme: Int
        let healthKitReadEnabled: Bool
        let healthKitWriteEnabled: Bool
        let motionLevel: AppSettings.MotionLevel
        let hapticsEnabled: Bool
        let showHealthCardOnHome: Bool
        let budgetInputPeriod: AppSettings.BudgetInputPeriod
        let budgetPrimaryText: String
        let quietStartMinute: Int
        let quietEndMinute: Int
        let breakfastMinute: Int
        let lunchMinute: Int
        let dinnerMinute: Int
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack(spacing: VaySpacing.sm) {
                        ProgressView()
                        Text("Загружаем настройки...")
                            .font(VayFont.body(14))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                SettingsRowView(icon: "paintpalette.fill", color: .vayAccent, title: "Тема") {
                    Picker("Тема", selection: $selectedTheme) {
                        ForEach(0..<themeOptions.count, id: \.self) { index in
                            Text(themeOptions[index]).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.vayPrimary)
                }
            } header: {
                sectionHeader(icon: "paintbrush.fill", title: "Внешний вид")
            }

            Section {
                SettingsRowView(icon: "sparkles", color: .vaySecondary, title: "Движение интерфейса") {
                    Picker("Движение интерфейса", selection: $motionLevel) {
                        ForEach(AppSettings.MotionLevel.allCases, id: \.rawValue) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                        .tint(Color.vayPrimary)
                }

                SettingsRowView(icon: "iphone.radiowaves.left.and.right", color: .vayInfo, title: "Тактильная отдача") {
                    Toggle("", isOn: $hapticsEnabled)
                        .labelsHidden()
                        .tint(Color.vayPrimary)
                }

                SettingsRowView(icon: "heart.text.square.fill", color: .vaySuccess, title: "Здоровье на главной") {
                    Toggle("", isOn: $showHealthCardOnHome)
                        .labelsHidden()
                        .tint(Color.vayPrimary)
                }
            } header: {
                sectionHeader(icon: "wand.and.stars", title: "Интерфейс и отклик")
            } footer: {
                Text("Полный режим — максимум плавности. Меньше — сокращённые эффекты. Выкл — без анимаций.")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }

            Section {
                SettingsRowView(icon: "heart.fill", color: .vayDanger, title: "Читать данные") {
                    Toggle("", isOn: $healthKitReadEnabled)
                        .labelsHidden()
                        .tint(Color.vayPrimary)
                }

                SettingsRowView(icon: "heart.text.square.fill", color: .vaySuccess, title: "Записывать калории") {
                    Toggle("", isOn: $healthKitWriteEnabled)
                        .labelsHidden()
                        .tint(Color.vayPrimary)
                }
            } header: {
                sectionHeader(icon: "apple.logo", title: "Apple Health")
            } footer: {
                Text("Разрешить чтение данных о весе, составе тела и активности из Apple Health.")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Период бюджета", selection: Binding(
                    get: { budgetInputPeriod },
                    set: { newPeriod in
                        guard newPeriod != budgetInputPeriod, !isBudgetHydrating else {
                            budgetInputPeriod = newPeriod
                            return
                        }
                        let old = budgetInputPeriod
                        budgetInputPeriod = newPeriod
                        convertBudgetPrimaryInput(from: old, to: newPeriod)
                    }
                )) {
                    ForEach(AppSettings.BudgetInputPeriod.allCases, id: \.rawValue) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                SettingsRowView(icon: "rublesign.circle.fill", color: .vaySuccess, title: budgetPrimaryLabel) {
                    TextField(budgetPrimaryPlaceholder, text: $budgetPrimaryText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isBudgetFieldFocused)
                }

                ForEach(readOnlyBudgetRows, id: \.period.rawValue) { rowData in
                    SettingsRowView(icon: rowData.icon, color: rowData.color, title: rowData.label) {
                        Text(rowData.value)
                            .font(VayFont.label(14))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                sectionHeader(icon: "banknote.fill", title: "Бюджет")
            } footer: {
                Text("Введите бюджет за выбранный период. Остальные периоды рассчитываются автоматически.")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }

            Section {
                SettingsRowView(icon: "sunrise.fill", color: .vayAccent, title: "Завтрак") {
                    DatePicker("", selection: $breakfastDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                SettingsRowView(icon: "sun.max.fill", color: .vayWarning, title: "Обед") {
                    DatePicker("", selection: $lunchDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                SettingsRowView(icon: "moon.stars.fill", color: .vaySecondary, title: "Ужин") {
                    DatePicker("", selection: $dinnerDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            } header: {
                sectionHeader(icon: "clock.fill", title: "Расписание приёмов пищи")
            }

            Section {
                SettingsRowView(icon: "moon.zzz.fill", color: .vaySecondary, title: "Начало") {
                    DatePicker("", selection: $quietStartDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                SettingsRowView(icon: "alarm.fill", color: .vayAccent, title: "Конец") {
                    DatePicker("", selection: $quietEndDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            } header: {
                sectionHeader(icon: "bell.slash.fill", title: "Тихие часы")
            }

            Section {
                NavigationLink {
                    SettingsStatisticsView(inventoryService: inventoryService)
                } label: {
                    navigationRow(icon: "chart.bar.fill", color: .vayInfo, title: "Статистика")
                }

                NavigationLink {
                    SettingsAchievementsView()
                } label: {
                    navigationRow(icon: "trophy.fill", color: .vayWarning, title: "Достижения")
                }

                NavigationLink {
                    BodyMetricsView(
                        settingsService: settingsService,
                        healthKitService: healthKitService
                    )
                } label: {
                    navigationRow(icon: "figure.walk", color: .vayPrimary, title: "Моё тело")
                }

                NavigationLink {
                    DietSettingsView(settingsService: settingsService)
                } label: {
                    navigationRow(icon: "leaf.circle.fill", color: .vaySuccess, title: "Диета")
                }
            } header: {
                sectionHeader(icon: "square.grid.2x2.fill", title: "Разделы")
            }

            Section {
                VStack(alignment: .leading, spacing: VaySpacing.xs) {
                    Text("ДомИнвентарь")
                        .font(VayFont.label(14))
                    Text("Версия \(appVersionText)")
                        .font(VayFont.caption(12))
                        .foregroundStyle(.secondary)
                    Text("© 2026 ProjectVay")
                        .font(VayFont.caption(11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, VaySpacing.xs)
            } header: {
                sectionHeader(icon: "info.circle", title: "О приложении")
            }
            Section {
                Button(role: .destructive) {
                    showResetInventoryAlert = true
                } label: {
                    Text("Очистить инвентарь")
                }

                Button(role: .destructive) {
                    showResetShoppingListAlert = true
                } label: {
                    Text("Очистить список покупок")
                }

                Button(role: .destructive) {
                    showResetAllAlert = true
                } label: {
                    Text("Обнулить всё (Сброс приложения)")
                }
            } header: {
                sectionHeader(icon: "trash.fill", title: "Управление данными")
            } footer: {
                Text("Эти действия необратимы. Будьте осторожны.")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: VayLayout.tabBarOverlayInset)
        }
        .navigationTitle("Настройки")
        .alert("Очистить инвентарь?", isPresented: $showResetInventoryAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Очистить", role: .destructive) {
                Task {
                    do {
                        try await inventoryService.deleteAllInventoryData()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Вы уверены? Все ваши продукты будут удалены.")
        }
        .alert("Очистить список покупок?", isPresented: $showResetShoppingListAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Очистить", role: .destructive) {
                Task {
                    do {
                        try await shoppingListService.deleteAllItems()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Вы уверены? Все элементы в списке покупок будут удалены.")
        }
        .alert("Обнулить настройки и данные?", isPresented: $showResetAllAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Сброс", role: .destructive) {
                Task {
                    do {
                        try await shoppingListService.deleteAllItems()
                        try await settingsService.deleteAllLocalData(resetOnboarding: true)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Приложение вернётся к начальным настройкам.")
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
        .task {
            await loadSettings()
        }
        .onChange(of: autoSaveState) { _, _ in
            publishLiveSettingsDraft()
            scheduleAutoSave()
        }
        .onChange(of: selectedTheme) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: motionLevel) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: hapticsEnabled) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: showHealthCardOnHome) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: healthKitReadEnabled) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: healthKitWriteEnabled) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsDidChange)) { notification in
            guard let updated = notification.object as? AppSettings else { return }
            guard updated != settings else { return }
            guard !isBudgetFieldFocused else { return }
            applyLoadedSettings(updated)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isBudgetFieldFocused = false
        }
        .onDisappear {
            autoSaveTask?.cancel()
            Task { await saveSettingsIfValid() }
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var autoSaveState: AutoSaveState {
        AutoSaveState(
            selectedTheme: selectedTheme,
            healthKitReadEnabled: healthKitReadEnabled,
            healthKitWriteEnabled: healthKitWriteEnabled,
            motionLevel: motionLevel,
            hapticsEnabled: hapticsEnabled,
            showHealthCardOnHome: showHealthCardOnHome,
            budgetInputPeriod: budgetInputPeriod,
            budgetPrimaryText: budgetPrimaryText,
            quietStartMinute: Calendar.current.minuteOfDay(from: quietStartDate),
            quietEndMinute: Calendar.current.minuteOfDay(from: quietEndDate),
            breakfastMinute: Calendar.current.minuteOfDay(from: breakfastDate),
            lunchMinute: Calendar.current.minuteOfDay(from: lunchDate),
            dinnerMinute: Calendar.current.minuteOfDay(from: dinnerDate)
        )
    }

    private var budgetPrimaryLabel: String {
        switch budgetInputPeriod {
        case .day:
            return "Бюджет дня"
        case .week:
            return "Бюджет недели"
        case .month:
            return "Бюджет месяца"
        }
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

    private var parsedBudgetBreakdown: (day: Decimal, week: Decimal, month: Decimal)? {
        guard let primaryBudget = parseBudgetValue(budgetPrimaryText) else {
            return nil
        }

        return AppSettings.budgetBreakdown(
            input: primaryBudget,
            period: budgetInputPeriod
        )
    }

    private var displayBudgetBreakdown: (day: Decimal, week: Decimal, month: Decimal) {
        if let parsedBudgetBreakdown {
            return parsedBudgetBreakdown
        }

        let primary = budgetPrimaryValue(from: settings, period: budgetInputPeriod)
        return AppSettings.budgetBreakdown(input: primary, period: budgetInputPeriod)
    }

    private var readOnlyBudgetRows: [(period: AppSettings.BudgetInputPeriod, icon: String, color: Color, label: String, value: String)] {
        let breakdown = displayBudgetBreakdown
        let allRows: [(AppSettings.BudgetInputPeriod, String, Color, String, String)] = [
            (.day, "calendar", .vayInfo, "Рассчитано в день", "\(formatBudgetValue(breakdown.day)) ₽"),
            (.week, "calendar.badge.clock", .vayWarning, "Рассчитано в неделю", "\(formatBudgetValue(breakdown.week)) ₽"),
            (.month, "calendar.badge.plus", .vayPrimary, "Рассчитано в месяц", "\(formatBudgetValue(breakdown.month)) ₽")
        ]

        return allRows.filter { $0.0 != budgetInputPeriod }
            .map { (period: $0.0, icon: $0.1, color: $0.2, label: $0.3, value: $0.4) }
    }

    private func navigationRow(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: icon)
                .font(VayFont.label(13))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(title)
                .font(VayFont.body(15))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: icon)
                .font(VayFont.caption(11))
            Text(title)
        }
        .font(VayFont.caption(12))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    private func loadSettings() async {
        defer { isLoading = false }

        do {
            let loaded = try await settingsService.loadSettings()
            applyLoadedSettings(loaded)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyLoadedSettings(_ loaded: AppSettings) {
        let normalized = loaded.normalized()
        isHydratingSettings = true
        isBudgetHydrating = true

        settings = normalized
        lastPersistedSettings = normalized

        quietStartDate = DateComponents.from(minutes: normalized.quietStartMinute).asDate
        quietEndDate = DateComponents.from(minutes: normalized.quietEndMinute).asDate
        breakfastDate = DateComponents.from(minutes: normalized.mealSchedule.breakfastMinute).asDate
        lunchDate = DateComponents.from(minutes: normalized.mealSchedule.lunchMinute).asDate
        dinnerDate = DateComponents.from(minutes: normalized.mealSchedule.dinnerMinute).asDate

        selectedTheme = normalized.preferredColorScheme ?? 0
        healthKitReadEnabled = normalized.healthKitReadEnabled
        healthKitWriteEnabled = normalized.healthKitWriteEnabled
        motionLevel = normalized.motionLevel
        hapticsEnabled = normalized.hapticsEnabled
        showHealthCardOnHome = normalized.showHealthCardOnHome

        // Set text BEFORE period so the Binding setter sees isBudgetHydrating=true.
        budgetPrimaryText = formatBudgetValue(
            budgetPrimaryValue(from: normalized, period: normalized.budgetInputPeriod)
        )
        budgetInputPeriod = normalized.budgetInputPeriod

        appSettingsStore.update(normalized)

        // Reset flags after SwiftUI has processed state changes (next run-loop turn).
        Task { @MainActor in
            isHydratingSettings = false
            isBudgetHydrating = false
        }
    }

    private func scheduleAutoSave() {
        guard !isHydratingSettings else { return }

        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await saveSettingsIfValid()
        }
    }

    @MainActor
    private func saveSettingsIfValid() async {
        guard !isHydratingSettings else { return }
        autoSaveTask?.cancel()
        autoSaveTask = nil

        let updated = makeDraftSettings()

        do {
            let saved = try await settingsService.saveSettings(updated)
            settings = saved
            lastPersistedSettings = saved
            appSettingsStore.update(saved)
        } catch {
            rollbackToLastPersisted(with: error)
        }
    }

    @MainActor
    private func publishLiveSettingsDraft() {
        guard !isHydratingSettings else { return }
        let draft = makeDraftSettings()
        appSettingsStore.publishDraft(draft)
    }

    private func makeDraftSettings() -> AppSettings {
        var updated = settings
        updated.preferredColorScheme = selectedTheme
        updated.healthKitReadEnabled = healthKitReadEnabled
        updated.healthKitWriteEnabled = healthKitWriteEnabled
        updated.motionLevel = motionLevel
        updated.enableAnimations = motionLevel != .off
        updated.hapticsEnabled = hapticsEnabled
        updated.showHealthCardOnHome = showHealthCardOnHome

        updated.quietStartMinute = Calendar.current.minuteOfDay(from: quietStartDate)
        updated.quietEndMinute = Calendar.current.minuteOfDay(from: quietEndDate)
        updated.mealSchedule.breakfastMinute = Calendar.current.minuteOfDay(from: breakfastDate)
        updated.mealSchedule.lunchMinute = Calendar.current.minuteOfDay(from: lunchDate)
        updated.mealSchedule.dinnerMinute = Calendar.current.minuteOfDay(from: dinnerDate)

        if let primaryBudget = parseBudgetValue(budgetPrimaryText) {
            updated.budgetInputPeriod = budgetInputPeriod
            
            // If the text matches the current high-precision value (formatted), keep the high-precision value.
            // Otherwise, the user likely edited the text, so use the parsed (lower precision) value.
            let currentFormatted = formatBudgetValue(updated.budgetPrimaryValue)
            if currentFormatted != budgetPrimaryText {
                updated.budgetPrimaryValue = primaryBudget
            }
        }

        return updated.normalized()
    }

    @MainActor
    private func rollbackToLastPersisted(with error: Error) {
        errorMessage = error.localizedDescription
        applyLoadedSettings(lastPersistedSettings)
    }

    private func convertBudgetPrimaryInput(
        from previous: AppSettings.BudgetInputPeriod,
        to current: AppSettings.BudgetInputPeriod
    ) {
        guard previous != current else { return }

        let sourceValue: Decimal
        // Check if the text matches the stored value (formatted). If so, use high precision.
        let storedFormatted = formatBudgetValue(budgetPrimaryValue(from: settings, period: previous))
        if storedFormatted == budgetPrimaryText {
            sourceValue = budgetPrimaryValue(from: settings, period: previous)
        } else if let parsed = parseBudgetValue(budgetPrimaryText) {
            sourceValue = parsed
        } else {
            sourceValue = budgetPrimaryValue(from: settings, period: previous)
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

        budgetPrimaryText = formatBudgetValue(converted)
        
        // Update local state to preserve high precision immediately
        settings.budgetPrimaryValue = converted
        settings.budgetInputPeriod = current
    }

    private func budgetPrimaryValue(
        from settings: AppSettings,
        period: AppSettings.BudgetInputPeriod
    ) -> Decimal {
        switch period {
        case .day:
            return settings.budgetDay
        case .week:
            return settings.budgetWeek
        case .month:
            return settings.budgetMonth
        }
    }

    private func parseBudgetValue(_ value: String) -> Decimal? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let decimal = Decimal(string: normalized), decimal >= 0 else {
            return nil
        }

        return decimal.rounded(scale: 2)
    }

    private func formatBudgetValue(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = ","
        return formatter.string(from: NSDecimalNumber(decimal: value.rounded(scale: 2))) ?? "0"
    }
}

extension Calendar {
    func minuteOfDay(from date: Date) -> Int {
        let components = dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
