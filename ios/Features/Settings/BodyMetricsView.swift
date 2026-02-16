import Charts
import SwiftUI

struct BodyMetricsView: View {
    let settingsService: any SettingsServiceProtocol
    let healthKitService: HealthKitService

    @State private var settings: AppSettings = .default
    @State private var isHydratingSettings = false
    @State private var autoSaveTask: Task<Void, Never>?

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

    @State private var desiredWeightText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: VaySpacing.lg) {
                desiredWeightCard
                healthOverviewCard
                todayNutritionCard
                chartCard(
                    title: "Вес за 30 дней",
                    icon: "scalemass.fill",
                    points: weightHistory,
                    valueSuffix: "кг",
                    lineColor: .vayPrimary
                )
                chartCard(
                    title: "Жир за 30 дней",
                    icon: "drop.fill",
                    points: bodyFatHistory,
                    valueSuffix: "%",
                    lineColor: .vaySecondary
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
            let previous = settings
            settings = updated
            desiredWeightText = formatDesiredWeight(updated.weightGoalKg)
            Task {
                await recalculateAutoGoalNutrition(for: updated)
                if shouldReloadHealthData(previous: previous, next: updated) {
                    await loadHealthData()
                }
            }
        }
        .onChange(of: desiredWeightText) { _, _ in
            scheduleAutoSave()
        }
        .onDisappear {
            autoSaveTask?.cancel()
            Task { await saveDesiredWeightIfValid() }
        }
    }

    private var desiredWeightCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack {
                sectionHeader(icon: "target", title: "Желаемый вес")
                Spacer()
            }

            HStack(spacing: VaySpacing.sm) {
                TextField("кг", text: $desiredWeightText)
                    .keyboardType(.decimalPad)
                    .font(VayFont.title(24))
                Text("кг")
                    .font(VayFont.label(14))
                    .foregroundStyle(.secondary)
            }

            if let currentWeight = metrics.weightKG {
                let delta = currentWeight - (parseDesiredWeight().value ?? currentWeight)
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

                    if let healthStatusMessage {
                        Text(healthStatusMessage)
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

    private func chartCard(
        title: String,
        icon: String,
        points: [HealthKitService.SamplePoint],
        valueSuffix: String,
        lineColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: icon, title: title)

            if points.count >= 2 {
                Chart(points) { point in
                    LineMark(
                        x: .value("Дата", point.date),
                        y: .value("Значение", point.value)
                    )
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Дата", point.date),
                        y: .value("Значение", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [lineColor.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 140)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(VayFont.caption(9))
                    }
                }
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
            } else {
                Text("Недостаточно данных для графика.")
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.vayPrimary)
            Text(title)
                .font(VayFont.heading(16))
        }
    }

    private func loadInitialData() async {
        await loadSettings()
        await loadHealthData()
        await recalculateAutoGoalNutrition(for: settings)
    }

    private func loadSettings() async {
        isHydratingSettings = true
        defer { isHydratingSettings = false }

        do {
            let loaded = try await settingsService.loadSettings()
            settings = loaded
            desiredWeightText = formatDesiredWeight(loaded.weightGoalKg)
        } catch {
            healthStatusMessage = "Не удалось загрузить настройки: \(error.localizedDescription)"
        }
    }

    private func loadHealthData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let metricsTask = healthKitService.fetchLatestMetrics()
            async let nutritionTask = healthKitService.fetchTodayConsumedNutrition()
            async let weightTask = healthKitService.fetchWeightHistory(days: 30)
            async let bodyFatTask = healthKitService.fetchBodyFatHistory(days: 30)

            metrics = try await metricsTask
            todayNutrition = try await nutritionTask
            let loadedWeightHistory = try await weightTask
            let loadedBodyFatHistory = try await bodyFatTask
            weightHistory = loadedWeightHistory.sorted(by: { $0.date < $1.date })
            bodyFatHistory = loadedBodyFatHistory.sorted(by: { $0.date < $1.date })
            healthStatusMessage = nil
        } catch {
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
            healthStatusMessage = "Нет доступа к данным Apple Health или данные отсутствуют."
        }

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
            let granted = try await healthKitService.requestReadAccess()
            if granted {
                var updated = settings
                updated.healthKitReadEnabled = true
                settings = try await settingsService.saveSettings(updated)
                desiredWeightText = formatDesiredWeight(settings.weightGoalKg)
                await loadHealthData()
                await recalculateAutoGoalNutrition(for: settings)
                healthStatusMessage = "Доступ к Apple Health предоставлен."
            } else {
                healthStatusMessage = "Доступ к Apple Health не предоставлен. Проверьте разрешения в приложении Здоровье и настройках iOS."
            }
        } catch {
            healthStatusMessage = "Не удалось запросить доступ: \(error.localizedDescription)"
        }
    }

    private func scheduleAutoSave() {
        guard !isHydratingSettings else { return }

        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await saveDesiredWeightIfValid()
        }
    }

    private func saveDesiredWeightIfValid() async {
        guard !isHydratingSettings else { return }
        autoSaveTask?.cancel()
        autoSaveTask = nil
        let parsed = parseDesiredWeight()
        guard parsed.valid else { return }

        var updated = settings
        updated.weightGoalKg = parsed.value

        do {
            settings = try await settingsService.saveSettings(updated)
            healthStatusMessage = nil
        } catch {
            healthStatusMessage = "Не удалось сохранить целевой вес: \(error.localizedDescription)"
        }
    }

    private func recalculateAutoGoalNutrition(for settings: AppSettings) async {
        var automaticDailyCalories: Double?
        var weightKG: Double?

        if settings.macroGoalSource == .automatic, settings.healthKitReadEnabled {
            if metrics.weightKG != nil, metrics.heightCM != nil, metrics.age != nil {
                automaticDailyCalories = Double(
                    healthKitService.calculateDailyCalories(
                        metrics: metrics,
                        targetLossPerWeek: settings.dietProfile.targetLossPerWeek
                    )
                )
                weightKG = metrics.weightKG
            } else if let loadedMetrics = try? await healthKitService.fetchLatestMetrics() {
                automaticDailyCalories = Double(
                    healthKitService.calculateDailyCalories(
                        metrics: loadedMetrics,
                        targetLossPerWeek: settings.dietProfile.targetLossPerWeek
                    )
                )
                weightKG = loadedMetrics.weightKG
            }
        }

        let output = AdaptiveNutritionUseCase().execute(
            .init(
                settings: settings,
                range: .day,
                automaticDailyCalories: automaticDailyCalories,
                weightKG: weightKG,
                consumedNutrition: nil,
                consumedFetchFailed: false,
                healthIntegrationEnabled: settings.healthKitReadEnabled
            )
        )
        autoGoalNutrition = output.baselineDayTarget
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
