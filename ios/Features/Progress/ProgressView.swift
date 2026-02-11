import SwiftUI

struct ProgressView: View {
    let healthKitService: HealthKitService

    @State private var latestMetrics = HealthKitService.UserMetrics()
    @State private var consumedNutrition: Nutrition = .empty
    @State private var weightHistory: [HealthKitService.SamplePoint] = []
    @State private var bodyFatHistory: [HealthKitService.SamplePoint] = []

    @State private var targetKcal: Int = 2100
    @State private var statusMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if let statusMessage {
                Section("Статус") {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Текущие метрики") {
                metricRow("Вес", value: latestMetrics.weightKG.map { "\($0.formatted(.number.precision(.fractionLength(1)))) кг" })
                metricRow("Жир", value: latestMetrics.bodyFatPercent.map { "\(($0 * 100).formatted(.number.precision(.fractionLength(1)))) %" })
                metricRow("Рост", value: latestMetrics.heightCM.map { "\($0.formatted(.number.precision(.fractionLength(1)))) см" })
                metricRow("Активная энергия", value: latestMetrics.activeEnergyKcal.map { "\($0.formatted(.number.precision(.fractionLength(0)))) ккал" })
            }

            Section("Питание сегодня") {
                metricRow("Цель калорий", value: "\(targetKcal) ккал")
                metricRow("Съедено", value: nutritionText(consumedNutrition))
            }

            Section("Тренд веса") {
                metricRow("Тренд", value: weightTrendText)
                if weightHistory.isEmpty {
                    Text("Недостаточно данных веса в Apple Health")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(weightHistory.suffix(7)) { point in
                        HStack {
                            Text(point.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text("\(point.value.formatted(.number.precision(.fractionLength(1)))) кг")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !bodyFatHistory.isEmpty {
                Section("Тренд процента жира") {
                    let recent = Array(bodyFatHistory.suffix(7))
                    ForEach(recent) { point in
                        HStack {
                            Text(point.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text("\((point.value * 100).formatted(.number.precision(.fractionLength(1)))) %")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Прогресс")
        .task {
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    private var weightTrendText: String {
        guard let first = weightHistory.first, let last = weightHistory.last, weightHistory.count >= 2 else {
            return "недостаточно данных"
        }

        let days = max(1, Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 1)
        let delta = last.value - first.value
        let perWeek = delta / Double(days) * 7

        if abs(perWeek) < 0.05 {
            return "стабильно"
        }

        let direction = perWeek < 0 ? "снижение" : "рост"
        return "\(direction) \(abs(perWeek).formatted(.number.precision(.fractionLength(2)))) кг/нед"
    }

    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await healthKitService.requestReadAccess()
            async let metricsTask = healthKitService.fetchLatestMetrics()
            async let nutritionTask = healthKitService.fetchTodayConsumedNutrition()
            async let weightTask = healthKitService.fetchWeightHistory(days: 30)
            async let bodyFatTask = healthKitService.fetchBodyFatHistory(days: 30)

            let metrics = try await metricsTask
            let nutrition = try await nutritionTask
            let weight = try await weightTask
            let bodyFat = try await bodyFatTask

            latestMetrics = metrics
            consumedNutrition = normalizeNutrition(nutrition)
            weightHistory = weight
            bodyFatHistory = bodyFat
            targetKcal = healthKitService.calculateDailyCalories(metrics: metrics, targetLossPerWeek: 0.5)
            statusMessage = nil
        } catch {
            statusMessage = "Не удалось загрузить данные HealthKit: \(error.localizedDescription)"
        }
    }

    private func metricRow(_ title: String, value: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value ?? "—")
                .foregroundStyle(.secondary)
        }
    }

    private func nutritionText(_ value: Nutrition) -> String {
        let kcal = Int((value.kcal ?? 0).rounded())
        let protein = Int((value.protein ?? 0).rounded())
        let fat = Int((value.fat ?? 0).rounded())
        let carbs = Int((value.carbs ?? 0).rounded())
        return "\(kcal) ккал · Б \(protein) · Ж \(fat) · У \(carbs)"
    }

    private func normalizeNutrition(_ value: Nutrition) -> Nutrition {
        Nutrition(
            kcal: max(0, value.kcal ?? 0),
            protein: max(0, value.protein ?? 0),
            fat: max(0, value.fat ?? 0),
            carbs: max(0, value.carbs ?? 0)
        )
    }
}
