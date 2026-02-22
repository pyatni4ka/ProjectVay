import Charts
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct BodyMetricsView: View {
    let settingsService: any SettingsServiceProtocol
    let healthKitService: HealthKitService
    @Environment(AppSettingsStore.self) private var appSettingsStore

    @State private var settings: AppSettings = .default
    @State private var isHydratingSettings = false

    @State private var isLoading = true
    @State private var metrics = HealthKitService.UserMetrics(
        heightCM: nil,
        weightKG: nil,
        bodyFatPercent: nil,
        activeEnergyKcal: nil,
        age: nil,
        sex: nil
    )
    @State private var todayNutrition = Nutrition.empty
    @State private var autoGoalNutrition = Nutrition.empty
    @State private var weightHistory: [HealthKitService.SamplePoint] = []
    @State private var bodyFatHistory: [HealthKitService.SamplePoint] = []
    @State private var healthStatusMessage: String?
    @State private var isRequestingHealthAccess = false
    @State private var healthReadAccessState: HealthKitService.ReadAccessState = .unavailable

    @State private var desiredWeightText = ""
    @State private var isEditingDesiredWeight = false
    @State private var selectedWeightDate: Date?
    @State private var selectedBodyFatDate: Date?
    @State private var chartRangeMode: AppSettings.BodyMetricsRangeMode = .year
    @State private var chartRangeMonths = 12
    @State private var chartRangeYear = Calendar.current.component(.year, from: Date())
    @State private var isHydratingChartRange = false

    // КБЖУ калькулятор — synced with settings for consistency
    @State private var calcActivityLevel: NutritionCalculator.ActivityLevel = .moderatelyActive
    @State private var calcGoal: NutritionCalculator.Goal = .lose
    @State private var isSyncingCalcPickers = false

    var body: some View {
        ScrollView {
            VStack(spacing: VaySpacing.lg) {
                desiredWeightCard
                healthOverviewCard
                todayNutritionCard
                nutritionPlanCard
                chartRangeCard
                chartCard(
                    title: "Вес (доступные данные)",
                    icon: "scalemass.fill",
                    points: filteredWeightHistory,
                    valueSuffix: "кг",
                    lineColor: .vayPrimary,
                    metricKind: .weightKg,
                    hasRawData: !weightHistory.isEmpty,
                    selectedDate: $selectedWeightDate
                )
                chartCard(
                    title: "Жир (доступные данные)",
                    icon: "drop.fill",
                    points: filteredBodyFatHistory,
                    valueSuffix: "%",
                    lineColor: .vaySecondary,
                    metricKind: .bodyFatPercent,
                    hasRawData: !bodyFatHistory.isEmpty,
                    selectedDate: $selectedBodyFatDate
                )

                if let healthStatusMessage {
                    Text(healthStatusMessage)
                        .font(VayFont.caption(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, VaySpacing.lg)
            .padding(.bottom, VaySpacing.huge)
        }
        .background(Color.vayBackground)
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: VayLayout.tabBarOverlayInset)
        }
        .navigationTitle("Моё тело")
        .task {
            await loadInitialData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsDidChange)) { notification in
            guard let updated = notification.object as? AppSettings else { return }
            handleSettingsUpdate(updated)
        }
        .onChange(of: appSettingsStore.settings) { _, updated in
            handleSettingsUpdate(updated)
        }
        .onChange(of: chartRangeMode) { _, _ in
            guard !isHydratingSettings, !isHydratingChartRange else { return }
            selectedWeightDate = nil
            selectedBodyFatDate = nil
            Task { await saveChartRangeIfNeeded() }
        }
        .onChange(of: chartRangeMonths) { _, _ in
            guard !isHydratingSettings, !isHydratingChartRange else { return }
            selectedWeightDate = nil
            selectedBodyFatDate = nil
            Task { await saveChartRangeIfNeeded() }
        }
        .onChange(of: chartRangeYear) { _, _ in
            guard !isHydratingSettings, !isHydratingChartRange else { return }
            selectedWeightDate = nil
            selectedBodyFatDate = nil
            Task { await saveChartRangeIfNeeded() }
        }
        .onChange(of: calcActivityLevel) { _, newValue in
            guard !isSyncingCalcPickers, !isHydratingSettings else { return }
            Task { await saveCalcPickerChanges(activityLevel: newValue, goal: calcGoal) }
        }
        .onChange(of: calcGoal) { _, newValue in
            guard !isSyncingCalcPickers, !isHydratingSettings else { return }
            Task { await saveCalcPickerChanges(activityLevel: calcActivityLevel, goal: newValue) }
        }
        .onDisappear {
            guard isEditingDesiredWeight else { return }
            Task { _ = await saveDesiredWeightIfValid() }
        }
    }

    private var desiredWeightCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack {
                sectionHeader(icon: "target", title: "Желаемый вес")
                Spacer()
                if isEditingDesiredWeight {
                    Button("Отмена") {
                        cancelDesiredWeightEditing()
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.vayPrimary)
                    .font(VayFont.label(13))
                } else {
                    Button("Изменить") {
                        beginDesiredWeightEditing()
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.vayPrimary)
                    .font(VayFont.label(13))
                }
            }

            if isEditingDesiredWeight {
                HStack(spacing: VaySpacing.sm) {
                    TextField("кг", text: $desiredWeightText)
                        .keyboardType(.decimalPad)
                        .font(VayFont.title(24))
                    Text("кг")
                        .font(VayFont.label(14))
                        .foregroundStyle(.secondary)
                }

                let parsed = parseDesiredWeight()
                if !parsed.valid {
                    Text("Введите корректный вес от 0 до 500 кг.")
                        .font(VayFont.caption(12))
                        .foregroundStyle(Color.vayWarning)
                }

                HStack(spacing: VaySpacing.sm) {
                    Button("Сохранить") {
                        Task { _ = await saveDesiredWeightIfValid() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.vayPrimary)

                    Button("Очистить") {
                        Task { await clearDesiredWeight() }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.vayPrimary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: VaySpacing.xs) {
                    if let goal = settings.weightGoalKg {
                        Text(metricText(goal, digits: 1))
                            .font(VayFont.title(24))
                        Text("кг")
                            .font(VayFont.label(14))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Не задан")
                            .font(VayFont.title(24))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let currentWeight = metrics.weightKG {
                let delta = currentWeight - (resolvedDesiredWeightForDelta ?? currentWeight)
                Text("Текущий вес: \(metricText(currentWeight, digits: 1)) кг · Дельта до цели: \(signedText(delta, digits: 1)) кг")
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Текущий вес появится после чтения данных Apple Health.")
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
            }
        }
        .vayCard()
    }

    private var healthOverviewCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack {
                sectionHeader(icon: "heart.text.square.fill", title: "Показатели Apple Health")
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if hasAnyHealthData {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: VaySpacing.sm) {
                    metricPill(title: "Рост", value: metricOrDash(metrics.heightCM, suffix: "см"))
                    metricPill(title: "Вес", value: metricOrDash(metrics.weightKG, suffix: "кг"))
                    metricPill(title: "Жир", value: metricOrDash(metrics.bodyFatPercent.map { $0 * 100 }, suffix: "%"))
                    metricPill(title: "Активная энергия", value: metricOrDash(metrics.activeEnergyKcal, suffix: "ккал"))
                    metricPill(title: "Возраст", value: metrics.age.map { "\($0)" } ?? "—")
                    metricPill(title: "Пол", value: sexLabel(metrics.sex))
                }
            } else {
                VStack(alignment: .leading, spacing: VaySpacing.sm) {
                    Text("Данные из Apple Health пока недоступны.")
                        .font(VayFont.body(14))
                        .foregroundStyle(.secondary)

                    if shouldShowHealthRequestButton {
                        Button {
                            Task { await requestHealthAccess() }
                        } label: {
                            if isRequestingHealthAccess {
                                HStack(spacing: VaySpacing.sm) {
                                    ProgressView()
                                    Text("Запрашиваем доступ...")
                                        .font(VayFont.label(13))
                                }
                            } else {
                                Label("Разрешить доступ к Apple Health", systemImage: "apple.logo")
                                    .font(VayFont.label(13))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.vayPrimary)
                        .disabled(isRequestingHealthAccess)
                    }

                    if shouldShowOpenSettingsButton {
                        Button {
                            openSystemSettings()
                        } label: {
                            Label("Открыть настройки iOS", systemImage: "gearshape")
                                .font(VayFont.label(13))
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.vayPrimary)
                    }

                    if let healthStatusMessage {
                        Text(healthStatusMessage)
                            .font(VayFont.caption(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let infoMessage = healthAccessInfoMessage {
                        Text(infoMessage)
                            .font(VayFont.caption(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .vayCard()
    }

    private var todayNutritionCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: "fork.knife", title: "КБЖУ за сегодня")

            HStack(spacing: VaySpacing.sm) {
                metricPill(title: "К", value: metricOrDash(todayNutrition.kcal, suffix: "ккал", digits: 0))
                metricPill(title: "Б", value: metricOrDash(todayNutrition.protein, suffix: "г", digits: 0))
                metricPill(title: "Ж", value: metricOrDash(todayNutrition.fat, suffix: "г", digits: 0))
                metricPill(title: "У", value: metricOrDash(todayNutrition.carbs, suffix: "г", digits: 0))
            }

            if settings.macroGoalSource == .manual {
                Text(
                    "Цель: К \(goalValueText(settings.kcalGoal)) · Б \(goalValueText(settings.proteinGoalGrams)) · Ж \(goalValueText(settings.fatGoalGrams)) · У \(goalValueText(settings.carbsGoalGrams))"
                )
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)
            } else {
                Text(
                    "Авто-цель (\(settings.dietProfile.title)): К \(goalValueText(autoGoalNutrition.kcal)) · Б \(goalValueText(autoGoalNutrition.protein)) · Ж \(goalValueText(autoGoalNutrition.fat)) · У \(goalValueText(autoGoalNutrition.carbs))"
                )
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)
            }
        }
        .vayCard()
    }

    // MARK: - Mifflin–St Jeor КБЖУ-калькулятор

    private var nutritionPlanCard: some View {
        let calcResult = computeNutritionPlan()
        return VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: "flame.fill", title: "Рекомендация по КБЖУ")

            if let result = calcResult {
                VStack(spacing: VaySpacing.sm) {
                    HStack {
                        macroBox(label: "Ккал", value: result.kcal, unit: "ккал", color: .vayCalories)
                        macroBox(label: "Белок", value: result.proteinGrams, unit: "г", color: .vayProtein)
                        macroBox(label: "Жиры", value: result.fatGrams, unit: "г", color: .vayFat)
                        macroBox(label: "Углев", value: result.carbsGrams, unit: "г", color: .vayCarbs)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ОО (BMR): \(Int(result.bmr)) ккал")
                                .font(VayFont.caption(11))
                                .foregroundStyle(.secondary)
                            Text("TDEE: \(Int(result.tdee)) ккал")
                                .font(VayFont.caption(11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        let deficit = result.deficitKcal
                        Text(deficit < 0 ? "Дефицит: \(Int(abs(deficit))) ккал" : deficit > 0 ? "Профицит: \(Int(deficit)) ккал" : "Поддержание")
                            .font(VayFont.caption(11))
                            .foregroundStyle(deficit < 0 ? Color.vayWarning : deficit > 0 ? Color.vaySuccess : .secondary)
                    }
                }

                Picker("Активность", selection: $calcActivityLevel) {
                    ForEach(NutritionCalculator.ActivityLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.vayPrimary)
                .font(VayFont.body(14))

                Picker("Цель", selection: $calcGoal) {
                    ForEach(NutritionCalculator.Goal.allCases) { goal in
                        Text(goal.label).tag(goal)
                    }
                }
                .pickerStyle(.segmented)

                Text(result.explanation.disclaimer)
                    .font(VayFont.caption(10))
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                Text("Для расчёта КБЖУ необходимы данные Apple Health: рост, вес, возраст и пол.")
                    .font(VayFont.body(14))
                    .foregroundStyle(.secondary)
            }
        }
        .vayCard()
    }

    private func computeNutritionPlan() -> NutritionTargetsService.Targets? {
        guard let weight = metrics.weightKG,
              let height = metrics.heightCM,
              let age = metrics.age else { return nil }
        let isMale = metrics.sex?.lowercased().contains("male") ?? true

        var tempSettings = settings
        tempSettings.activityLevel = calcActivityLevel
        switch calcGoal {
        case .lose: tempSettings.dietGoalMode = .lose
        case .maintain: tempSettings.dietGoalMode = .maintain
        case .gain: tempSettings.dietGoalMode = .gain
        }

        let bodyMetrics = NutritionTargetsService.BodyMetrics(
            weightKg: weight,
            heightCm: height,
            ageYears: age,
            isMale: isMale
        )
        return NutritionTargetsService.computeTargets(settings: tempSettings, metrics: bodyMetrics)
    }

    private func macroBox(label: String, value: Double, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(VayFont.caption(10))
                .foregroundStyle(.secondary)
            Text("\(Int(value))")
                .font(VayFont.label(16))
                .foregroundStyle(color)
            Text(unit)
                .font(VayFont.caption(9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, VaySpacing.sm)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.sm, style: .continuous))
    }

    private var chartRangeCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: "calendar", title: "Период графиков")

            Picker("Режим периода", selection: $chartRangeMode) {
                ForEach(AppSettings.BodyMetricsRangeMode.allCases, id: \.rawValue) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch chartRangeMode {
            case .lastMonths:
                Stepper(value: $chartRangeMonths, in: 1...60) {
                    Text("Последние \(chartRangeMonths) мес.")
                        .font(VayFont.body(14))
                }
            case .year, .sinceYear:
                Picker("Год", selection: $chartRangeYear) {
                    ForEach(availableChartYears, id: \.self) { year in
                        Text("\(year)").tag(year)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.vayPrimary)
            }

            Text(activeChartRange.fullLabel)
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)
        }
        .vayCard()
    }

    private struct ChartDisplayPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let originalValue: Double
        let plottedValue: Double
        let isLowerOutlier: Bool
        let isUpperOutlier: Bool

        var hasOutlier: Bool {
            isLowerOutlier || isUpperOutlier
        }
    }

    private var activeChartRange: BodyMetricsTimeRange {
        BodyMetricsTimeRange(
            mode: chartRangeMode,
            months: chartRangeMonths,
            year: chartRangeYear
        )
    }

    private var filteredWeightHistory: [HealthKitService.SamplePoint] {
        activeChartRange.filter(points: weightHistory)
    }

    private var filteredBodyFatHistory: [HealthKitService.SamplePoint] {
        activeChartRange.filter(points: bodyFatHistory)
    }

    private var availableChartYears: [Int] {
        BodyMetricsTimeRange.availableYears(
            from: [weightHistory, bodyFatHistory],
            selectedYear: chartRangeYear
        )
    }

    private func chartCard(
        title: String,
        icon: String,
        points: [HealthKitService.SamplePoint],
        valueSuffix: String,
        lineColor: Color,
        metricKind: DynamicChartMetricKind,
        hasRawData: Bool,
        selectedDate: Binding<Date?>
    ) -> some View {
        let scale = DynamicChartScaleDomain.resolve(
            values: points.map(\.value),
            metric: metricKind
        )
        let displayedPoints = chartDisplayPoints(points: points, scale: scale)
        let selectedPoint = selectedChartPoint(
            points: displayedPoints,
            selectedDate: selectedDate.wrappedValue
        )

        return VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: icon, title: title)

            if let selectedPoint {
                Text(
                    "Выбрано: \(metricText(selectedPoint.originalValue, digits: 1)) \(valueSuffix) · \(chartSelectionDateText(selectedPoint.date))"
                    + (selectedPoint.hasOutlier ? " · выброс" : "")
                )
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)
            } else if let latestPoint = displayedPoints.last {
                Text(
                    "Последнее: \(metricText(latestPoint.originalValue, digits: 1)) \(valueSuffix) · \(chartSelectionDateText(latestPoint.date))"
                )
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)
            }

            if displayedPoints.count >= 2 {
                let baseChart = Chart(displayedPoints) { point in
                    LineMark(
                        x: .value("Дата", point.date),
                        y: .value("Значение", point.plottedValue)
                    )
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)

                    AreaMark(
                        x: .value("Дата", point.date),
                        y: .value("Значение", point.plottedValue)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [lineColor.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    if point.hasOutlier {
                        PointMark(
                            x: .value("Дата", point.date),
                            y: .value("Значение", point.plottedValue)
                        )
                        .foregroundStyle(lineColor)
                        .symbolSize(52)
                        .annotation(position: point.isUpperOutlier ? .top : .bottom, alignment: .center) {
                            Image(systemName: point.isUpperOutlier ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(VayFont.caption(9))
                                .foregroundStyle(lineColor)
                        }
                    }

                    if let selectedPoint, selectedPoint.date == point.date {
                        RuleMark(x: .value("Выбор", point.date))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(lineColor.opacity(0.55))

                        PointMark(
                            x: .value("Дата", point.date),
                            y: .value("Значение", point.plottedValue)
                        )
                        .foregroundStyle(.white)
                        .symbolSize(86)

                        PointMark(
                            x: .value("Дата", point.date),
                            y: .value("Значение", point.plottedValue)
                        )
                        .foregroundStyle(lineColor)
                        .symbolSize(38)
                    }
                }
                applyScale(
                    to: baseChart,
                    scale: scale,
                    valueSuffix: valueSuffix
                )
                .frame(height: 140)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(VayFont.caption(9))
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        updateSelectionDate(
                                            location: value.location,
                                            proxy: proxy,
                                            geometry: geometry,
                                            points: displayedPoints,
                                            selection: selectedDate
                                        )
                                    }
                            )
                    }
                }
            } else if let point = displayedPoints.last {
                VStack(alignment: .leading, spacing: VaySpacing.xs) {
                    Text("\(point.originalValue.formatted(.number.precision(.fractionLength(0...1)))) \(valueSuffix)")
                        .font(VayFont.title(24))
                        .foregroundStyle(lineColor)
                    Text(point.date.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(hasRawData ? "Нет данных за выбранный период." : "Недостаточно данных для графика.")
                    .font(VayFont.body(14))
                    .foregroundStyle(.secondary)
            }
        }
        .vayCard()
    }

    private var hasAnyHealthData: Bool {
        metrics.heightCM != nil
            || metrics.weightKG != nil
            || metrics.bodyFatPercent != nil
            || metrics.activeEnergyKcal != nil
            || metrics.age != nil
            || metrics.sex != nil
            || !weightHistory.isEmpty
            || !bodyFatHistory.isEmpty
            || todayNutrition.kcal != nil
            || todayNutrition.protein != nil
            || todayNutrition.fat != nil
            || todayNutrition.carbs != nil
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.xs) {
            Text(title)
                .font(VayFont.caption(11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(VayFont.label(14))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VaySpacing.sm)
        .background(Color.vayPrimaryLight.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: icon)
                .font(VayFont.label(14))
                .foregroundStyle(Color.vayPrimary)
            Text(title)
                .font(VayFont.heading(16))
        }
    }

    private func loadInitialData() async {
        await loadSettings()
        await loadHealthData()
    }

    private func loadSettings() async {
        isHydratingSettings = true
        defer { isHydratingSettings = false }

        do {
            let loaded = try await settingsService.loadSettings()
            settings = loaded.normalized()
            applyChartRangeFromSettings(settings)
            syncCalcPickersFromSettings(settings)
            desiredWeightText = formatDesiredWeight(settings.weightGoalKg)
            isEditingDesiredWeight = false
            appSettingsStore.update(settings)
        } catch {
            healthStatusMessage = "Не удалось загрузить настройки: \(error.localizedDescription)"
        }
    }

    private func syncCalcPickersFromSettings(_ settings: AppSettings) {
        isSyncingCalcPickers = true
        defer { isSyncingCalcPickers = false }

        calcActivityLevel = settings.activityLevel

        switch settings.dietGoalMode {
        case .lose: calcGoal = .lose
        case .maintain: calcGoal = .maintain
        case .gain: calcGoal = .gain
        }
    }

    private func saveCalcPickerChanges(
        activityLevel: NutritionCalculator.ActivityLevel,
        goal: NutritionCalculator.Goal
    ) async {
        var updated = settings
        updated.activityLevel = activityLevel
        switch goal {
        case .lose: updated.dietGoalMode = .lose
        case .maintain: updated.dietGoalMode = .maintain
        case .gain: updated.dietGoalMode = .gain
        }

        do {
            settings = try await settingsService.saveSettings(updated)
            appSettingsStore.update(settings)
            await recalculateAutoGoalNutrition(for: settings)
        } catch {
            healthStatusMessage = "Не удалось сохранить настройки: \(error.localizedDescription)"
        }
    }

    private func loadHealthData() async {
        isLoading = true
        defer { isLoading = false }

        guard settings.healthKitReadEnabled else {
            metrics = HealthKitService.UserMetrics(
                heightCM: nil,
                weightKG: nil,
                bodyFatPercent: nil,
                activeEnergyKcal: nil,
                age: nil,
                sex: nil
            )
            todayNutrition = .empty
            weightHistory = []
            bodyFatHistory = []
            selectedWeightDate = nil
            selectedBodyFatDate = nil
            healthStatusMessage = "Чтение Apple Health отключено в настройках."
            await refreshHealthReadAccessState(hasAnyData: false)
            await recalculateAutoGoalNutrition(for: settings)
            return
        }

        async let metricsTask = try? healthKitService.fetchLatestMetrics()
        async let nutritionTask = try? healthKitService.fetchTodayConsumedNutrition()
        async let weightTask = try? healthKitService.fetchWeightHistory(days: 0)
        async let bodyFatTask = try? healthKitService.fetchBodyFatHistory(days: 0)

        let loadedMetrics = await metricsTask
        let loadedNutrition = await nutritionTask
        let loadedWeightHistory = await weightTask
        let loadedBodyFatHistory = await bodyFatTask

        metrics = loadedMetrics ?? HealthKitService.UserMetrics(
            heightCM: nil,
            weightKG: nil,
            bodyFatPercent: nil,
            activeEnergyKcal: nil,
            age: nil,
            sex: nil
        )
        todayNutrition = loadedNutrition ?? .empty
        weightHistory = (loadedWeightHistory ?? []).sorted(by: { $0.date < $1.date })
        bodyFatHistory = (loadedBodyFatHistory ?? [])
            .map { .init(date: $0.date, value: $0.value * 100) }
            .sorted(by: { $0.date < $1.date })

        if weightHistory.isEmpty, let latestWeight = metrics.weightKG {
            weightHistory = [.init(date: Date(), value: latestWeight)]
        }
        if bodyFatHistory.isEmpty, let latestBodyFat = metrics.bodyFatPercent {
            bodyFatHistory = [.init(date: Date(), value: latestBodyFat * 100)]
        }
        selectedWeightDate = nil
        selectedBodyFatDate = nil

        let hasMetricsData =
            metrics.heightCM != nil
            || metrics.weightKG != nil
            || metrics.bodyFatPercent != nil
            || metrics.activeEnergyKcal != nil
            || metrics.age != nil
            || metrics.sex != nil
        let hasNutritionData =
            (todayNutrition.kcal ?? 0) > 0
            || (todayNutrition.protein ?? 0) > 0
            || (todayNutrition.fat ?? 0) > 0
            || (todayNutrition.carbs ?? 0) > 0
        let hasHistoryData = !weightHistory.isEmpty || !bodyFatHistory.isEmpty

        if hasMetricsData || hasNutritionData || hasHistoryData {
            var notes: [String] = []
            if loadedMetrics == nil {
                notes.append("Часть метрик тела недоступна.")
            }
            if loadedNutrition == nil {
                notes.append("КБЖУ за сегодня недоступно.")
            }
            healthStatusMessage = notes.isEmpty ? nil : notes.joined(separator: " ")
        } else {
            let diagnosis = await healthKitService.diagnoseDataAvailability(
                readEnabledInSettings: settings.healthKitReadEnabled
            )
            healthStatusMessage = diagnosis.message
        }

        await refreshHealthReadAccessState(hasAnyData: hasAnyHealthData)
        await recalculateAutoGoalNutrition(for: settings)
    }

    private func requestHealthAccess() async {
        guard healthKitService.isHealthDataAvailable else {
            healthStatusMessage = "Apple Health недоступен на этом устройстве."
            return
        }

        isRequestingHealthAccess = true
        healthStatusMessage = "Запрашиваем доступ к Apple Health..."
        defer { isRequestingHealthAccess = false }

        do {
            let granted = try await healthKitService.requestAccess()
            if granted {
                var updated = settings
                updated.healthKitReadEnabled = true
                settings = try await settingsService.saveSettings(updated)
                appSettingsStore.update(settings)
                if !isEditingDesiredWeight {
                    desiredWeightText = formatDesiredWeight(settings.weightGoalKg)
                }
                await loadHealthData()
                await recalculateAutoGoalNutrition(for: settings)
                healthStatusMessage = "Доступ к Apple Health предоставлен."
            } else {
                healthStatusMessage = "Доступ к Apple Health не предоставлен. Проверьте разрешения в приложении Здоровье и настройках iOS."
            }
        } catch {
            healthStatusMessage = "Не удалось запросить доступ: \(error.localizedDescription)"
        }

        await refreshHealthReadAccessState(hasAnyData: hasAnyHealthData)
    }

    private var shouldShowHealthRequestButton: Bool {
        guard !hasAnyHealthData else { return false }
        return healthReadAccessState == .needsRequest
    }

    private var shouldShowOpenSettingsButton: Bool {
        guard !hasAnyHealthData else { return false }
        return healthReadAccessState == .denied
    }

    private var healthAccessInfoMessage: String? {
        switch healthReadAccessState {
        case .authorizedNoData:
            return "Доступ к Apple Health уже настроен. Добавьте записи веса или процента жира в приложении Здоровье."
        case .denied:
            return "Доступ к Apple Health запрещён. Разрешите чтение веса и состава тела в настройках iOS."
        case .unavailable:
            return "Apple Health недоступен на этом устройстве."
        case .readDisabled:
            return "Чтение Apple Health отключено в настройках."
        case .needsRequest, .authorizedWithData:
            return nil
        }
    }

    private func refreshHealthReadAccessState(hasAnyData: Bool? = nil) async {
        healthReadAccessState = await healthKitService.readAccessState(
            readEnabledInSettings: settings.healthKitReadEnabled,
            hasAnyData: hasAnyData
        )
    }

    private func handleSettingsUpdate(_ updated: AppSettings) {
        let normalized = updated.normalized()
        guard normalized != settings else { return }
        let previous = settings
        settings = normalized
        applyChartRangeFromSettings(normalized)
        syncCalcPickersFromSettings(normalized)
        if !isEditingDesiredWeight {
            desiredWeightText = formatDesiredWeight(normalized.weightGoalKg)
        }

        Task {
            if shouldReloadHealthData(previous: previous, next: normalized) {
                await loadHealthData()
            } else {
                await refreshHealthReadAccessState(hasAnyData: hasAnyHealthData)
                await recalculateAutoGoalNutrition(for: normalized)
            }
        }
    }

    private func applyChartRangeFromSettings(_ settings: AppSettings) {
        let range = BodyMetricsTimeRange(settings: settings)
        let needsUpdate =
            chartRangeMode != range.mode
            || chartRangeMonths != range.months
            || chartRangeYear != range.year
        guard needsUpdate else { return }

        isHydratingChartRange = true
        chartRangeMode = range.mode
        chartRangeMonths = range.months
        chartRangeYear = range.year
        isHydratingChartRange = false
    }

    private func saveChartRangeIfNeeded() async {
        guard !isHydratingSettings, !isHydratingChartRange else { return }

        let range = BodyMetricsTimeRange(
            mode: chartRangeMode,
            months: chartRangeMonths,
            year: chartRangeYear
        )

        if chartRangeMonths != range.months {
            chartRangeMonths = range.months
        }
        if chartRangeYear != range.year {
            chartRangeYear = range.year
        }

        var updated = settings
        updated.bodyMetricsRangeMode = range.mode
        updated.bodyMetricsRangeMonths = range.months
        updated.bodyMetricsRangeYear = range.year

        let noChanges =
            updated.bodyMetricsRangeMode == settings.bodyMetricsRangeMode
            && updated.bodyMetricsRangeMonths == settings.bodyMetricsRangeMonths
            && updated.bodyMetricsRangeYear == settings.bodyMetricsRangeYear
        guard !noChanges else { return }

        do {
            settings = try await settingsService.saveSettings(updated)
            appSettingsStore.update(settings)
            healthStatusMessage = nil
        } catch {
            applyChartRangeFromSettings(settings)
            healthStatusMessage = "Не удалось сохранить период графиков: \(error.localizedDescription)"
        }
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private var resolvedDesiredWeightForDelta: Double? {
        if isEditingDesiredWeight {
            return parseDesiredWeight().value ?? settings.weightGoalKg
        }
        return settings.weightGoalKg
    }

    private func beginDesiredWeightEditing() {
        desiredWeightText = formatDesiredWeight(settings.weightGoalKg)
        isEditingDesiredWeight = true
    }

    private func cancelDesiredWeightEditing() {
        desiredWeightText = formatDesiredWeight(settings.weightGoalKg)
        isEditingDesiredWeight = false
    }

    private func clearDesiredWeight() async {
        desiredWeightText = ""
        _ = await saveDesiredWeightIfValid()
    }

    @discardableResult
    private func saveDesiredWeightIfValid() async -> Bool {
        guard !isHydratingSettings else { return false }
        let parsed = parseDesiredWeight()
        guard parsed.valid else {
            healthStatusMessage = "Введите корректный вес от 0 до 500 кг."
            return false
        }

        let previousWeightGoal = settings.weightGoalKg
        if previousWeightGoal == parsed.value {
            desiredWeightText = formatDesiredWeight(settings.weightGoalKg)
            isEditingDesiredWeight = false
            healthStatusMessage = nil
            return true
        }

        var updated = settings
        updated.weightGoalKg = parsed.value

        do {
            settings = try await settingsService.saveSettings(updated)
            appSettingsStore.update(settings)
            desiredWeightText = formatDesiredWeight(settings.weightGoalKg)
            isEditingDesiredWeight = false
            if previousWeightGoal != settings.weightGoalKg, settings.weightGoalKg != nil {
                GamificationService.shared.trackBodyGoalSet()
            }
            healthStatusMessage = nil
            return true
        } catch {
            healthStatusMessage = "Не удалось сохранить целевой вес: \(error.localizedDescription)"
            return false
        }
    }

    @ViewBuilder
    private func applyScale<ChartContent: View>(
        to chart: ChartContent,
        scale: DynamicChartScaleDomain?,
        valueSuffix: String
    ) -> some View {
        if let scale {
            chart
                .chartYScale(domain: scale.domain, range: .plotDimension(padding: 15))
                .chartXScale(range: .plotDimension(padding: 15))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .stride(by: scale.step)) { value in
                        AxisValueLabel {
                            if let axisValue = value.as(Double.self) {
                                Text("\(axisValue.formatted(.number.precision(.fractionLength(0...1)))) \(valueSuffix)")
                            }
                        }
                        .font(VayFont.caption(9))
                    }
                }
        } else {
            chart
                .chartYScale(range: .plotDimension(padding: 15))
                .chartXScale(range: .plotDimension(padding: 15))
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let axisValue = value.as(Double.self) {
                                Text("\(axisValue.formatted(.number.precision(.fractionLength(0...1)))) \(valueSuffix)")
                            }
                        }
                        .font(VayFont.caption(9))
                    }
                }
        }
    }

    private func chartDisplayPoints(
        points: [HealthKitService.SamplePoint],
        scale: DynamicChartScaleDomain?
    ) -> [ChartDisplayPoint] {
        points.map { point in
            ChartDisplayPoint(
                date: point.date,
                originalValue: point.value,
                plottedValue: scale?.displayValue(for: point.value) ?? point.value,
                isLowerOutlier: scale?.isLowerOutlier(point.value) ?? false,
                isUpperOutlier: scale?.isUpperOutlier(point.value) ?? false
            )
        }
    }

    private func selectedChartPoint(points: [ChartDisplayPoint], selectedDate: Date?) -> ChartDisplayPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private func updateSelectionDate(
        location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [ChartDisplayPoint],
        selection: Binding<Date?>
    ) {
        guard !points.isEmpty, let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        guard frame.contains(location) else { return }

        let xPosition = location.x - frame.origin.x
        guard let resolvedDate: Date = proxy.value(atX: xPosition) else { return }

        guard let nearestPoint = points.min(by: {
            abs($0.date.timeIntervalSince(resolvedDate)) < abs($1.date.timeIntervalSince(resolvedDate))
        }) else {
            return
        }

        if selection.wrappedValue != nearestPoint.date {
            selection.wrappedValue = nearestPoint.date
        }
    }

    private func chartSelectionDateText(_ date: Date) -> String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let valueYear = calendar.component(.year, from: date)
        if currentYear == valueYear {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func recalculateAutoGoalNutrition(for settings: AppSettings) async {
        let healthMetrics: HealthKitService.UserMetrics?
        if settings.macroGoalSource == .automatic, settings.healthKitReadEnabled {
            if metrics.weightKG != nil, metrics.heightCM != nil, metrics.age != nil {
                healthMetrics = metrics
            } else {
                healthMetrics = try? await healthKitService.fetchLatestMetrics()
            }
        } else {
            healthMetrics = nil
        }
        
        let baselineTarget = NutritionTargetsService.resolveTargetNutrition(
            settings: settings, 
            healthMetrics: healthMetrics
        )

        let output = AdaptiveNutritionUseCase().execute(
            .init(
                settings: settings,
                range: .day,
                baselineTarget: baselineTarget,
                consumedNutrition: nil,
                consumedFetchFailed: false,
                healthIntegrationEnabled: settings.healthKitReadEnabled
            )
        )

        guard settings.macroGoalSource == .automatic else {
            autoGoalNutrition = output.baselineDayTarget
            return
        }

        let nutritionHistory = (try? await healthKitService.fetchConsumedNutritionHistory(days: 7)) ?? []
        let coachOutput = DietCoachUseCase().execute(
            .init(
                settings: settings,
                baselineTarget: output.baselineDayTarget,
                weightHistory: weightHistory,
                bodyFatHistory: bodyFatHistory,
                nutritionHistory: nutritionHistory
            )
        )
        autoGoalNutrition = coachOutput.adjustedTarget
    }

    private func shouldReloadHealthData(previous: AppSettings, next: AppSettings) -> Bool {
        previous.healthKitReadEnabled != next.healthKitReadEnabled
            || previous.healthKitWriteEnabled != next.healthKitWriteEnabled
            || previous.macroGoalSource != next.macroGoalSource
            || previous.dietProfile != next.dietProfile
    }

    private func parseDesiredWeight() -> (value: Double?, valid: Bool) {
        let trimmed = desiredWeightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (nil, true)
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0, value <= 500 else {
            return (nil, false)
        }

        return (value, true)
    }

    private func metricOrDash(_ value: Double?, suffix: String, digits: Int = 1) -> String {
        guard let value else { return "—" }
        return "\(metricText(value, digits: digits)) \(suffix)"
    }

    private func metricText(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)))
    }

    private func signedText(_ value: Double, digits: Int) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(metricText(value, digits: digits))"
    }

    private func sexLabel(_ value: String?) -> String {
        switch value {
        case "male":
            return "Мужской"
        case "female":
            return "Женский"
        default:
            return "—"
        }
    }

    private func formatDesiredWeight(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func goalValueText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
