import SwiftUI

struct SettingsView: View {
    let settingsService: any SettingsServiceProtocol
    let inventoryService: any InventoryServiceProtocol
    let healthKitService: HealthKitService
    @EnvironmentObject private var appSettingsStore: AppSettingsStore

    @AppStorage("preferredColorScheme") private var storedColorScheme: Int = 0
    @AppStorage("enableAnimations") private var storedAnimationsEnabled: Bool = true
    @AppStorage("motionLevel") private var storedMotionLevel: String = AppSettings.MotionLevel.full.rawValue
    @AppStorage("hapticsEnabled") private var storedHapticsEnabled: Bool = true
    @AppStorage("showHealthCardOnHome") private var storedShowHealthCardOnHome: Bool = true

    @State private var settings: AppSettings = .default
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isHydratingSettings = false
    @State private var autoSaveTask: Task<Void, Never>?

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
                settingRow(icon: "paintpalette.fill", color: .vayAccent, label: "Тема") {
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
                settingRow(icon: "sparkles", color: .vaySecondary, label: "Движение интерфейса") {
                    Picker("Движение интерфейса", selection: $motionLevel) {
                        ForEach(AppSettings.MotionLevel.allCases, id: \.rawValue) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                        .tint(Color.vayPrimary)
                }

                settingRow(icon: "iphone.radiowaves.left.and.right", color: .vayInfo, label: "Тактильная отдача") {
                    Toggle("", isOn: $hapticsEnabled)
                        .labelsHidden()
                        .tint(Color.vayPrimary)
                }

                settingRow(icon: "heart.text.square.fill", color: .vaySuccess, label: "Здоровье на главной") {
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
                settingRow(icon: "heart.fill", color: .vayDanger, label: "Читать данные") {
                    Toggle("", isOn: $healthKitReadEnabled)
                        .labelsHidden()
                        .tint(Color.vayPrimary)
                }

                settingRow(icon: "heart.text.square.fill", color: .vaySuccess, label: "Записывать калории") {
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
                Picker("Период бюджета", selection: $budgetInputPeriod) {
                    ForEach(AppSettings.BudgetInputPeriod.allCases, id: \.rawValue) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: budgetInputPeriod) { previous, current in
                    convertBudgetPrimaryInput(from: previous, to: current)
                }

                settingRow(icon: "rublesign.circle.fill", color: .vaySuccess, label: budgetPrimaryLabel) {
                    TextField(budgetPrimaryPlaceholder, text: $budgetPrimaryText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                ForEach(readOnlyBudgetRows, id: \.period.rawValue) { rowData in
                    settingRow(icon: rowData.icon, color: rowData.color, label: rowData.label) {
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
                settingRow(icon: "sunrise.fill", color: .vayAccent, label: "Завтрак") {
                    DatePicker("", selection: $breakfastDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                settingRow(icon: "sun.max.fill", color: .vayWarning, label: "Обед") {
                    DatePicker("", selection: $lunchDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                settingRow(icon: "moon.stars.fill", color: .vaySecondary, label: "Ужин") {
                    DatePicker("", selection: $dinnerDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            } header: {
                sectionHeader(icon: "clock.fill", title: "Расписание приёмов пищи")
            }

            Section {
                settingRow(icon: "moon.zzz.fill", color: .vaySecondary, label: "Начало") {
                    DatePicker("", selection: $quietStartDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                settingRow(icon: "alarm.fill", color: .vayAccent, label: "Конец") {
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
        }
        .listStyle(.insetGrouped)
        .dismissKeyboardOnTap()
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: VayLayout.tabBarOverlayInset)
        }
        .navigationTitle("Настройки")
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
        .onChange(of: selectedTheme) { _, newValue in
            storedColorScheme = newValue
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: motionLevel) { _, newValue in
            storedMotionLevel = newValue.rawValue
            storedAnimationsEnabled = newValue != .off
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: hapticsEnabled) { _, newValue in
            storedHapticsEnabled = newValue
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: showHealthCardOnHome) { _, _ in
            storedShowHealthCardOnHome = showHealthCardOnHome
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
            applyLoadedSettings(updated)
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

    private func settingRow<Content: View>(
        icon: String,
        color: Color,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(label)
                .font(VayFont.body(15))

            Spacer()

            content()
        }
    }

    private func navigationRow(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(title)
                .font(VayFont.body(15))

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
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
        isHydratingSettings = true
        defer { isHydratingSettings = false }

        settings = loaded

        quietStartDate = DateComponents.from(minutes: loaded.quietStartMinute).asDate
        quietEndDate = DateComponents.from(minutes: loaded.quietEndMinute).asDate
        breakfastDate = DateComponents.from(minutes: loaded.mealSchedule.breakfastMinute).asDate
        lunchDate = DateComponents.from(minutes: loaded.mealSchedule.lunchMinute).asDate
        dinnerDate = DateComponents.from(minutes: loaded.mealSchedule.dinnerMinute).asDate

        selectedTheme = loaded.preferredColorScheme ?? 0
        healthKitReadEnabled = loaded.healthKitReadEnabled
        healthKitWriteEnabled = loaded.healthKitWriteEnabled
        motionLevel = loaded.motionLevel
        hapticsEnabled = loaded.hapticsEnabled
        showHealthCardOnHome = loaded.showHealthCardOnHome

        budgetInputPeriod = loaded.budgetInputPeriod
        budgetPrimaryText = formatBudgetValue(
            budgetPrimaryValue(from: loaded, period: loaded.budgetInputPeriod)
        )

        appSettingsStore.update(loaded)
        syncAppearanceStorage(from: loaded)
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

    private func saveSettingsIfValid() async {
        guard !isHydratingSettings else { return }
        autoSaveTask?.cancel()
        autoSaveTask = nil

        let updated = makeDraftSettings()

        do {
            let saved = try await settingsService.saveSettings(updated)
            settings = saved
            appSettingsStore.update(saved)
            syncAppearanceStorage(from: saved)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func publishLiveSettingsDraft() {
        guard !isHydratingSettings else { return }
        let draft = makeDraftSettings()
        appSettingsStore.update(draft)
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

        if let budgetBreakdown = parsedBudgetBreakdown {
            updated.budgetInputPeriod = budgetInputPeriod
            updated.budgetDay = budgetBreakdown.day
            updated.budgetWeek = budgetBreakdown.week
            updated.budgetMonth = budgetBreakdown.month
        }

        return updated.normalized()
    }

    private func syncAppearanceStorage(from settings: AppSettings) {
        storedColorScheme = settings.preferredColorScheme ?? 0
        storedAnimationsEnabled = settings.enableAnimations
        storedMotionLevel = settings.motionLevel.rawValue
        storedHapticsEnabled = settings.hapticsEnabled
        storedShowHealthCardOnHome = settings.showHealthCardOnHome
    }

    private func convertBudgetPrimaryInput(
        from previous: AppSettings.BudgetInputPeriod,
        to current: AppSettings.BudgetInputPeriod
    ) {
        guard previous != current else { return }

        let sourceValue: Decimal
        if let parsed = parseBudgetValue(budgetPrimaryText) {
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
            let fallbackWeek = (max(0, settings.budgetDay) * 7).rounded(scale: 2)
            return AppSettings.monthlyBudget(fromWeekly: fallbackWeek)
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
