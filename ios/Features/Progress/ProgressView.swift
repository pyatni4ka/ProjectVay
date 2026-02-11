import SwiftUI

struct ProgressView: View {
    let healthKitService: HealthKitService

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var metrics = HealthKitService.UserMetrics()
    @State private var consumedNutrition = Nutrition.empty
    @State private var targetNutrition = Nutrition(kcal: 2200, protein: 140, fat: 70, carbs: 220)
    @State private var weightHistory: [HealthKitService.SamplePoint] = []
    @State private var bodyFatHistory: [HealthKitService.SamplePoint] = []
    @State private var hasRequestedHealthAccess = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        SwiftUI.ProgressView()
                        Text("Загружаем данные Health...")
                    }
                }
            }

            Section("Текущие метрики") {
                metricRow("Вес", valueText(metrics.weightKG, suffix: "кг"))
                metricRow("Жир", valueText(metrics.bodyFatPercent.map { $0 * 100 }, suffix: "%"))
                metricRow("Рост", valueText(metrics.heightCM, suffix: "см"))
                metricRow("Активная энергия", valueText(metrics.activeEnergyKcal, suffix: "ккал"))
            }

            Section("КБЖУ за сегодня (Apple Health / Yazio)") {
                nutritionRow("Цель", targetNutrition)
                nutritionRow("Съедено", consumedNutrition)
                nutritionRow("Остаток", subtractNutrition(targetNutrition, consumedNutrition))
            }

            Section("Тренд веса") {
                if let weeklyDelta = weightWeeklyDelta() {
                    Text("Тренд: \(weeklyDelta >= 0 ? "+" : "")\(weeklyDelta.formatted(.number.precision(.fractionLength(2)))) кг/нед")
                        .font(.subheadline)
                } else {
                    Text("Недостаточно данных для тренда.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(weightHistory.suffix(5).reversed()), id: \.id) { point in
                    HStack {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text("\(point.value.formatted(.number.precision(.fractionLength(1)))) кг")
                    }
                    .font(.caption)
                }
            }

            Section("Тренд процента жира") {
                if bodyFatHistory.isEmpty {
                    Text("Нет данных по проценту жира.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(bodyFatHistory.suffix(5).reversed()), id: \.id) { point in
                        HStack {
                            Text(point.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text("\((point.value * 100).formatted(.number.precision(.fractionLength(1)))) %")
                        }
                        .font(.caption)
                    }
                }
            }

            if let errorMessage {
                Section("Статус") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Прогресс")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Обновить") {
                    Task { await load() }
                }
                .disabled(isLoading)
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            if !hasRequestedHealthAccess {
                hasRequestedHealthAccess = true
                _ = try? await healthKitService.requestReadAccess()
            }

            async let metricsTask = healthKitService.fetchLatestMetrics()
            async let nutritionTask = healthKitService.fetchTodayConsumedNutrition()
            async let weightTask = healthKitService.fetchWeightHistory(days: 30)
            async let bodyFatTask = healthKitService.fetchBodyFatHistory(days: 30)

            let fetchedMetrics = try await metricsTask
            let fetchedNutrition = try await nutritionTask
            let fetchedWeight = try await weightTask
            let fetchedBodyFat = try await bodyFatTask

            metrics = fetchedMetrics
            consumedNutrition = normalizeNutrition(fetchedNutrition)
            targetNutrition = nutritionForTargetKcal(
                Double(healthKitService.calculateDailyCalories(metrics: fetchedMetrics, targetLossPerWeek: 0.5)),
                weightKG: fetchedMetrics.weightKG
            )
            weightHistory = fetchedWeight
            bodyFatHistory = fetchedBodyFat
            errorMessage = nil
        } catch {
            errorMessage = "Не удалось загрузить данные Health: \(error.localizedDescription)"
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func valueText(_ value: Double?, suffix: String) -> String {
        guard let value else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) \(suffix)"
    }

    private func nutritionRow(_ title: String, _ nutrition: Nutrition) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("К \(numberText(nutrition.kcal)) · Б \(numberText(nutrition.protein)) · Ж \(numberText(nutrition.fat)) · У \(numberText(nutrition.carbs))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func numberText(_ value: Double?) -> String {
        max(0, value ?? 0).formatted(.number.precision(.fractionLength(0)))
    }

    private func normalizeNutrition(_ value: Nutrition) -> Nutrition {
        Nutrition(
            kcal: max(0, value.kcal ?? 0),
            protein: max(0, value.protein ?? 0),
            fat: max(0, value.fat ?? 0),
            carbs: max(0, value.carbs ?? 0)
        )
    }

    private func subtractNutrition(_ left: Nutrition, _ right: Nutrition) -> Nutrition {
        Nutrition(
            kcal: max(0, (left.kcal ?? 0) - (right.kcal ?? 0)),
            protein: max(0, (left.protein ?? 0) - (right.protein ?? 0)),
            fat: max(0, (left.fat ?? 0) - (right.fat ?? 0)),
            carbs: max(0, (left.carbs ?? 0) - (right.carbs ?? 0))
        )
    }

    private func nutritionForTargetKcal(_ kcal: Double, weightKG: Double?) -> Nutrition {
        let baseKcal = max(900, kcal)

        let protein: Double
        if let weightKG {
            protein = min(max(weightKG * 1.8, 90), 220)
        } else {
            protein = max(90, baseKcal * 0.28 / 4)
        }

        let fat: Double
        if let weightKG {
            fat = min(max(weightKG * 0.8, 45), 120)
        } else {
            fat = max(45, baseKcal * 0.28 / 9)
        }

        let minCarbs = 80.0
        let minRequiredKcal = protein * 4 + fat * 9 + minCarbs * 4
        let adjustedKcal = max(baseKcal, minRequiredKcal)
        let carbs = max(minCarbs, (adjustedKcal - protein * 4 - fat * 9) / 4)

        return Nutrition(kcal: adjustedKcal, protein: protein, fat: fat, carbs: carbs)
    }

    private func weightWeeklyDelta() -> Double? {
        guard
            let first = weightHistory.first,
            let last = weightHistory.last,
            first.date < last.date
        else {
            return nil
        }

        let deltaWeight = last.value - first.value
        let deltaDays = last.date.timeIntervalSince(first.date) / 86_400
        guard deltaDays > 0 else { return nil }
        return deltaWeight / deltaDays * 7
    }
}
