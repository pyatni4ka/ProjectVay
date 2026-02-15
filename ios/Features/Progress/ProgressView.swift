import Charts
import SwiftUI

struct ProgressTrackingView: View {
    let inventoryService: any InventoryServiceProtocol
    let settingsService: any SettingsServiceProtocol

    @State private var settings: AppSettings = .default
    @State private var products: [Product] = []
    @State private var batches: [Batch] = []
    @State private var events: [InventoryEvent] = []
    @State private var priceEntries: [PriceEntry] = []
    @State private var isLoading = true

    @State private var selectedPeriod: Period = .week

    enum Period: String, CaseIterable, Identifiable {
        case week, month, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week: return "Неделя"
            case .month: return "Месяц"
            case .all: return "Всё время"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: VaySpacing.xl) {
                periodPicker

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if products.isEmpty && events.isEmpty {
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Начните отслеживать инвентарь для статистики",
                        subtitle: "Добавляйте продукты и операции, чтобы видеть динамику расходов, потерь и потребления."
                    )
                } else {
                    nutritionGoalsCard
                    inventoryTrendCard
                    consumptionStatsCard
                    wasteCard
                    spendingCard
                    categoryBreakdownCard
                }

                Color.clear.frame(height: VaySpacing.huge + VaySpacing.xxl)
            }
            .padding(.horizontal, VaySpacing.lg)
        }
        .background(Color.vayBackground)
        .navigationTitle("Прогресс")
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(Period.allCases) { period in
                Button {
                    withAnimation(VayAnimation.springSnappy) {
                        selectedPeriod = period
                    }
                    VayHaptic.selection()
                } label: {
                    Text(period.title)
                        .font(VayFont.label(13))
                        .foregroundStyle(selectedPeriod == period ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, VaySpacing.sm)
                        .background(selectedPeriod == period ? Color.vayPrimary : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(VaySpacing.xs)
        .background(Color.vayCardBackground)
        .clipShape(Capsule())
        .vayShadow(.subtle)
        .vayAccessibilityLabel("Период статистики: \(selectedPeriod.title)")
    }

    private var nutritionGoalsCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Color.vayCalories)
                    .font(.system(size: 14, weight: .semibold))
                Text("Цели питания")
                    .font(VayFont.heading(16))
            }

            NutritionRingGroup(
                kcal: 0,
                protein: 0,
                fat: 0,
                carbs: 0,
                kcalGoal: settings.kcalGoal ?? 2000,
                proteinGoal: settings.proteinGoalGrams ?? 80,
                fatGoal: settings.fatGoalGrams ?? 65,
                carbsGoal: settings.carbsGoalGrams ?? 250
            )
            .frame(maxWidth: .infinity)
            .vayAccessibilityLabel("Кольца КБЖУ на сегодня")
        }
        .vayCard()
    }

    private var inventoryTrendCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(Color.vayInfo)
                    .font(.system(size: 14, weight: .semibold))
                Text("Инвентарь")
                    .font(VayFont.heading(16))
                Spacer()
                Text("\(products.count) продуктов")
                    .font(VayFont.caption(12))
                    .foregroundStyle(.tertiary)
            }

            if inventoryChartData.count >= 2 {
                Chart(inventoryChartData, id: \.date) { point in
                    LineMark(
                        x: .value("Дата", point.date),
                        y: .value("Количество", point.count)
                    )
                    .foregroundStyle(Color.vayInfo)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Дата", point.date),
                        y: .value("Количество", point.count)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.vayInfo.opacity(0.2), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .font(VayFont.caption(10))
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(VayFont.caption(9))
                    }
                }
                .frame(height: 160)
                .vayAccessibilityLabel("График динамики инвентаря")
            } else {
                Text("Недостаточно данных для графика")
                    .font(VayFont.caption())
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .vayCard()
    }

    private var consumptionStatsCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.vayDanger)
                    .font(.system(size: 14, weight: .semibold))
                Text("Расход")
                    .font(VayFont.heading(16))
            }

            let addEvents = filteredEvents.filter { $0.type == .add }
            let removeEvents = filteredEvents.filter { $0.type == .remove }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: VaySpacing.md) {
                miniStatCard(
                    icon: "plus.circle.fill",
                    label: "Добавлено",
                    value: "\(addEvents.count)",
                    color: .vaySuccess
                )

                miniStatCard(
                    icon: "minus.circle.fill",
                    label: "Списано",
                    value: "\(removeEvents.count)",
                    color: .vayDanger
                )
            }

            if !activityChartData.isEmpty {
                Chart(activityChartData, id: \.date) { point in
                    BarMark(
                        x: .value("Дата", point.date, unit: .day),
                        y: .value("Добавлено", point.added)
                    )
                    .foregroundStyle(Color.vaySuccess.opacity(0.7))
                    .cornerRadius(4)

                    BarMark(
                        x: .value("Дата", point.date, unit: .day),
                        y: .value("Списано", -point.removed)
                    )
                    .foregroundStyle(Color.vayDanger.opacity(0.7))
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .font(VayFont.caption(10))
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel(format: .dateTime.day())
                            .font(VayFont.caption(9))
                    }
                }
                .frame(height: 140)
                .vayAccessibilityLabel("График расхода и пополнения")
            }
        }
        .vayCard()
    }

    private var wasteCard: some View {
        let expiredEvents = filteredEvents.filter { $0.type == .remove && $0.reason == .expired }
        let writeOffEvents = filteredEvents.filter { $0.type == .remove && $0.reason == .writeOff }
        let consumedEvents = filteredEvents.filter { $0.type == .remove && $0.reason == .consumed }
        let totalLossMinor = lossTotalMinor(events: expiredEvents + writeOffEvents)

        return VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "trash.slash.fill")
                    .foregroundStyle(Color.vayDanger)
                    .font(.system(size: 14, weight: .semibold))
                Text("Потери")
                    .font(VayFont.heading(16))
                Spacer()
                Text(rubText(fromMinor: totalLossMinor))
                    .font(VayFont.label(16))
                    .foregroundStyle(Color.vayDanger)
            }
            .vayAccessibilityLabel("Потери за период: \(rubText(fromMinor: totalLossMinor))")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: VaySpacing.sm) {
                wasteMiniCard(
                    icon: "clock.badge.exclamationmark",
                    title: "Просрочено",
                    count: expiredEvents.count,
                    amountMinor: lossTotalMinor(events: expiredEvents),
                    color: .vayDanger
                )
                wasteMiniCard(
                    icon: "minus.circle.fill",
                    title: "Списано",
                    count: writeOffEvents.count,
                    amountMinor: lossTotalMinor(events: writeOffEvents),
                    color: .vayWarning
                )
                wasteMiniCard(
                    icon: "checkmark.circle.fill",
                    title: "Съедено",
                    count: consumedEvents.count,
                    amountMinor: lossTotalMinor(events: consumedEvents),
                    color: .vaySuccess
                )
            }

            if !wasteChartData.isEmpty {
                Chart(wasteChartData, id: \.date) { point in
                    LineMark(
                        x: .value("Дата", point.date),
                        y: .value("Потери", point.lossRub)
                    )
                    .foregroundStyle(Color.vayDanger)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Дата", point.date),
                        y: .value("Потери", point.lossRub)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.vayDanger.opacity(0.25), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .font(VayFont.caption(10))
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel(format: .dateTime.day())
                            .font(VayFont.caption(9))
                    }
                }
                .frame(height: 140)
                .vayAccessibilityLabel("График потерь в рублях")
            }
        }
        .vayCard()
    }

    private var spendingCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "rublesign.circle.fill")
                    .foregroundStyle(Color.vayWarning)
                    .font(.system(size: 14, weight: .semibold))
                Text("Расходы")
                    .font(VayFont.heading(16))
            }

            let totalSpending = filteredPriceEntries.reduce(Decimal.zero) { $0 + $1.price }

            HStack {
                Text("Всего")
                    .font(VayFont.body(14))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(NSDecimalNumber(decimal: totalSpending).doubleValue.formatted(.number.precision(.fractionLength(0)))) ₽")
                    .font(VayFont.title(20))
                    .foregroundStyle(Color.vayWarning)
            }

            if filteredPriceEntries.isEmpty {
                Text("Нет данных о ценах за выбранный период")
                    .font(VayFont.caption())
                    .foregroundStyle(.tertiary)
            }
        }
        .vayCard()
        .vayAccessibilityLabel("Расходы за период")
    }

    private var categoryBreakdownCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(Color.vaySecondary)
                    .font(.system(size: 14, weight: .semibold))
                Text("По категориям")
                    .font(VayFont.heading(16))
            }

            let categories = Dictionary(grouping: products, by: \.category)
                .map { (category: $0.key, count: $0.value.count) }
                .sorted { $0.count > $1.count }

            if categories.count >= 2 {
                Chart(categories, id: \.category) { item in
                    SectorMark(
                        angle: .value("Количество", item.count),
                        innerRadius: .ratio(0.6),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Категория", item.category))
                    .cornerRadius(4)
                }
                .chartLegend(position: .bottom)
                .frame(height: 180)
                .vayAccessibilityLabel("Диаграмма категорий продуктов")
            }

            ForEach(categories.prefix(6), id: \.category) { item in
                HStack {
                    Text(item.category)
                        .font(VayFont.body(14))
                    Spacer()
                    Text("\(item.count)")
                        .font(VayFont.label(14))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .vayCard()
    }

    private func wasteMiniCard(icon: String, title: String, count: Int, amountMinor: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)

            Text("\(count)")
                .font(VayFont.label(15))

            Text(title)
                .font(VayFont.caption(10))
                .foregroundStyle(.secondary)

            Text(rubText(fromMinor: amountMinor))
                .font(VayFont.caption(10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VaySpacing.sm)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
        .vayAccessibilityLabel("\(title): \(count), \(rubText(fromMinor: amountMinor))")
    }

    private func miniStatCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)

            Text(value)
                .font(VayFont.title(20))

            Text(label)
                .font(VayFont.caption(11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VaySpacing.md)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
        .vayAccessibilityLabel("\(label): \(value)")
    }

    private struct ChartPoint {
        let date: Date
        let count: Int
    }

    private struct ActivityPoint {
        let date: Date
        let added: Int
        let removed: Int
    }

    private struct WastePoint {
        let date: Date
        let lossRub: Double
    }

    private var inventoryChartData: [ChartPoint] {
        let grouped = Dictionary(grouping: events) { event in
            Calendar.current.startOfDay(for: event.timestamp)
        }

        var runningTotal = 0
        return grouped.keys.sorted().map { date in
            let dayEvents = grouped[date] ?? []
            for event in dayEvents {
                switch event.type {
                case .add: runningTotal += 1
                case .remove: runningTotal = max(0, runningTotal - 1)
                default: break
                }
            }
            return ChartPoint(date: date, count: runningTotal)
        }
    }

    private var activityChartData: [ActivityPoint] {
        let grouped = Dictionary(grouping: filteredEvents) { event in
            Calendar.current.startOfDay(for: event.timestamp)
        }

        return grouped.keys.sorted().map { date in
            let dayEvents = grouped[date] ?? []
            let added = dayEvents.filter { $0.type == .add }.count
            let removed = dayEvents.filter { $0.type == .remove }.count
            return ActivityPoint(date: date, added: added, removed: removed)
        }
    }

    private var wasteChartData: [WastePoint] {
        let wasteEvents = filteredEvents.filter { event in
            event.type == .remove && (event.reason == .expired || event.reason == .writeOff)
        }

        let grouped = Dictionary(grouping: wasteEvents) { event in
            Calendar.current.startOfDay(for: event.timestamp)
        }

        return grouped.keys.sorted().map { date in
            let dayEvents = grouped[date] ?? []
            let totalMinor = lossTotalMinor(events: dayEvents)
            return WastePoint(date: date, lossRub: Double(totalMinor) / 100)
        }
    }

    private var filteredEvents: [InventoryEvent] {
        let cutoff = periodCutoffDate
        return events.filter { $0.timestamp >= cutoff }
    }

    private var filteredPriceEntries: [PriceEntry] {
        let cutoff = periodCutoffDate
        return priceEntries.filter { $0.date >= cutoff }
    }

    private var latestPriceMinorByProduct: [UUID: Int64] {
        Dictionary(uniqueKeysWithValues: Dictionary(grouping: priceEntries, by: \.productId).compactMap { productID, entries in
            guard let latest = entries.max(by: { $0.date < $1.date }) else {
                return nil
            }
            return (productID, latest.price.asMinorUnits)
        })
    }

    private var periodCutoffDate: Date {
        switch selectedPeriod {
        case .week:
            return Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        case .month:
            return Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        case .all:
            return .distantPast
        }
    }

    private func eventValueMinor(_ event: InventoryEvent) -> Int64? {
        if let estimated = event.estimatedValueMinor {
            return estimated
        }

        guard let latestPriceMinor = latestPriceMinorByProduct[event.productId], latestPriceMinor > 0 else {
            return nil
        }

        let multiplier = max(abs(event.quantityDelta), 1)
        return Int64((Double(latestPriceMinor) * multiplier).rounded())
    }

    private func lossTotalMinor(events: [InventoryEvent]) -> Int64 {
        events.compactMap(eventValueMinor).reduce(0, +)
    }

    private func rubText(fromMinor minor: Int64) -> String {
        let value = Double(minor) / 100
        return "\(value.formatted(.number.precision(.fractionLength(0)))) ₽"
    }

    private func loadData() async {
        do {
            settings = try await settingsService.loadSettings()
            products = try await inventoryService.listProducts(location: nil, search: nil)
            batches = try await inventoryService.listBatches(productId: nil)

            var allEvents: [InventoryEvent] = []
            var allPrices: [PriceEntry] = []
            for product in products {
                let productEvents = try await inventoryService.listEvents(productId: product.id)
                allEvents.append(contentsOf: productEvents)
                let prices = try await inventoryService.listPriceHistory(productId: product.id)
                allPrices.append(contentsOf: prices)
            }
            events = allEvents
            priceEntries = allPrices
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}
