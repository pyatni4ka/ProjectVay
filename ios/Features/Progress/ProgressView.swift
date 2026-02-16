import Charts
import SwiftUI

private enum ProgressChartAnimationScope {
    case element
}

private extension View {
    @ViewBuilder
    func chartAnimate(by scope: ProgressChartAnimationScope) -> some View {
        switch scope {
        case .element:
            self.transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}

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
                progressHeaderSection
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
                    summaryOverviewCard
                    nutritionGoalsCard
                    inventoryTrendCard
                    consumptionStatsCard
                    wasteCard
                    spendingCard
                    categoryBreakdownCard
                }

                Color.clear.frame(height: VayLayout.tabBarOverlayInset)
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

    private var progressHeaderSection: some View {
        HStack(alignment: .top, spacing: VaySpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.vayInfo.opacity(0.2), .vayPrimary.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.vayInfo)
            }

            VStack(alignment: .leading, spacing: VaySpacing.xs) {
                Text("Аналитика запасов")
                    .font(VayFont.heading(19))
                Text("Следите за расходом, списаниями и динамикой категорий за выбранный период.")
                    .font(VayFont.body(14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .vayCard()
        .vayAccessibilityLabel("Аналитика запасов: расход, списания и динамика категорий")
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

    private var summaryOverviewCard: some View {
        let addEvents = filteredEvents.filter { $0.type == .add }
        let writeOffEvents = filteredEvents.filter { $0.type == .remove && ($0.reason == .expired || $0.reason == .writeOff) }
        let totalSpendingMinor = filteredPriceEntries.reduce(Int64.zero) { $0 + $1.price.asMinorUnits }
        let writeOffMinor = lossTotalMinor(events: writeOffEvents)
        let addedMinor = lossTotalMinor(events: addEvents)
        let addedValueText = addedMinor > 0 ? rubText(fromMinor: addedMinor) : "\(addEvents.count)"
        let addedCaption = addedMinor > 0 ? "оценка пополнения" : "операций добавления"

        return VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.vayPrimary)
                Text("Итоги периода")
                    .font(VayFont.heading(16))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: VaySpacing.sm) {
                summaryMetric(
                    title: "Потрачено",
                    value: rubText(fromMinor: totalSpendingMinor),
                    caption: "по чекам и ценам",
                    color: .vayWarning,
                    icon: "rublesign.circle.fill"
                )

                summaryMetric(
                    title: "Списано",
                    value: rubText(fromMinor: writeOffMinor),
                    caption: "просрочка и write-off",
                    color: .vayDanger,
                    icon: "trash.slash.fill"
                )

                summaryMetric(
                    title: "Добавлено",
                    value: addedValueText,
                    caption: addedCaption,
                    color: .vaySuccess,
                    icon: "plus.circle.fill"
                )
            }
        }
        .padding(VaySpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.vayPrimaryLight, .vayInfo.opacity(0.1), .vayAccent.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous)
                .stroke(Color.vayPrimary.opacity(0.12), lineWidth: 1)
        )
        .vayShadow(.card)
        .vayAccessibilityLabel("Итоги периода: потрачено \(rubText(fromMinor: totalSpendingMinor)), списано \(rubText(fromMinor: writeOffMinor)), добавлено \(addedValueText)")
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
        let averageCount = averageInventoryCount

        return VStack(alignment: .leading, spacing: VaySpacing.md) {
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

            Text("Кривая показывает динамику количества товаров, пунктир — среднее значение за период.")
                .font(VayFont.caption(11))
                .foregroundStyle(.secondary)

            if inventoryChartData.count >= 2 {
                Chart(inventoryChartData, id: \.date) { point in
                    LineMark(
                        x: .value("Дата", point.date),
                        y: .value("Количество", point.count)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.vayInfo, .vayPrimary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Дата", point.date),
                        y: .value("Количество", point.count)
                    )
                    .foregroundStyle(Color.vayInfo)
                    .symbolSize(48)

                    AreaMark(
                        x: .value("Дата", point.date),
                        y: .value("Количество", point.count)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.vayInfo.opacity(0.28), .vayPrimary.opacity(0.12), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    if averageCount > 0 {
                        RuleMark(y: .value("Среднее", averageCount))
                            .foregroundStyle(Color.vayInfo.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Среднее \(averageCount.formatted(.number.precision(.fractionLength(1))))")
                                    .font(VayFont.caption(9))
                                    .foregroundStyle(Color.vayInfo)
                                    .padding(.horizontal, VaySpacing.xs)
                                    .padding(.vertical, VaySpacing.xxs)
                                    .background(Color.vayInfo.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                    }
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
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(
                            RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous)
                                .fill(Color.vayInfo.opacity(0.06))
                        )
                }
                .frame(height: 160)
                .chartAnimate(by: .element)
                .id(selectedPeriod)
                .animation(VayAnimation.springSmooth, value: selectedPeriod)
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
        let averageAdded = averageDailyAdded
        let averageRemoved = averageDailyRemoved

        return VStack(alignment: .leading, spacing: VaySpacing.md) {
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
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.vaySuccess, .vayPrimary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(8)

                    BarMark(
                        x: .value("Дата", point.date, unit: .day),
                        y: .value("Списано", -point.removed)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.vayDanger, .vayWarning],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(8)

                    if averageAdded > 0 {
                        RuleMark(y: .value("Среднее добавлено", averageAdded))
                            .foregroundStyle(Color.vaySuccess.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 4]))
                    }

                    if averageRemoved > 0 {
                        RuleMark(y: .value("Среднее списано", -averageRemoved))
                            .foregroundStyle(Color.vayDanger.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 4]))
                    }
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
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(
                            RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous)
                                .fill(Color.vayPrimary.opacity(0.06))
                        )
                }
                .frame(height: 140)
                .chartAnimate(by: .element)
                .id(selectedPeriod)
                .animation(VayAnimation.springSmooth, value: selectedPeriod)
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
        let averageLoss = averageWasteLoss

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
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.vayDanger, .vayWarning],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Дата", point.date),
                        y: .value("Потери", point.lossRub)
                    )
                    .foregroundStyle(Color.vayDanger)
                    .symbolSize(42)

                    AreaMark(
                        x: .value("Дата", point.date),
                        y: .value("Потери", point.lossRub)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.vayDanger.opacity(0.3), .vayWarning.opacity(0.14), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    if averageLoss > 0 {
                        RuleMark(y: .value("Средние потери", averageLoss))
                            .foregroundStyle(Color.vayDanger.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
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
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(
                            RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous)
                                .fill(Color.vayDanger.opacity(0.06))
                        )
                }
                .frame(height: 140)
                .chartAnimate(by: .element)
                .id(selectedPeriod)
                .animation(VayAnimation.springSmooth, value: selectedPeriod)
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
                    let style = categoryStyle(for: item.category)
                    SectorMark(
                        angle: .value("Количество", item.count),
                        innerRadius: .ratio(0.6),
                        angularInset: 2
                    )
                    .foregroundStyle(style.color.gradient)
                    .cornerRadius(6)
                }
                .chartLegend(.hidden)
                .frame(height: 180)
                .chartAnimate(by: .element)
                .id(selectedPeriod)
                .animation(VayAnimation.springSmooth, value: selectedPeriod)
                .vayAccessibilityLabel("Диаграмма категорий продуктов")
            }

            ForEach(categories.prefix(6), id: \.category) { item in
                let style = categoryStyle(for: item.category)
                HStack(spacing: VaySpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(style.color.opacity(0.14))
                            .frame(width: 24, height: 24)
                        Image(systemName: style.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(style.color)
                    }

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

    private func summaryMetric(title: String, value: String, caption: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)

            Text(value)
                .font(VayFont.title(22))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(VayFont.label(12))

            Text(caption)
                .font(VayFont.caption(10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VaySpacing.md)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
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

    private struct CategoryVisual {
        let icon: String
        let color: Color
    }

    private var inventoryChartData: [ChartPoint] {
        let grouped = Dictionary(grouping: filteredEvents) { event in
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

    private var averageInventoryCount: Double {
        guard !inventoryChartData.isEmpty else {
            return 0
        }
        let total = inventoryChartData.reduce(0) { $0 + Double($1.count) }
        return total / Double(inventoryChartData.count)
    }

    private var averageDailyAdded: Double {
        guard !activityChartData.isEmpty else {
            return 0
        }
        let total = activityChartData.reduce(0) { $0 + Double($1.added) }
        return total / Double(activityChartData.count)
    }

    private var averageDailyRemoved: Double {
        guard !activityChartData.isEmpty else {
            return 0
        }
        let total = activityChartData.reduce(0) { $0 + Double($1.removed) }
        return total / Double(activityChartData.count)
    }

    private var averageWasteLoss: Double {
        guard !wasteChartData.isEmpty else {
            return 0
        }
        let total = wasteChartData.reduce(0) { $0 + $1.lossRub }
        return total / Double(wasteChartData.count)
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

    private func categoryStyle(for category: String) -> CategoryVisual {
        let lower = category.lowercased()
        if lower.contains("мясо") || lower.contains("птиц") || lower.contains("рыб") {
            return CategoryVisual(icon: "fish", color: .vayInfo)
        }
        if lower.contains("молоч") || lower.contains("сыр") {
            return CategoryVisual(icon: "cup.and.saucer.fill", color: .vaySecondary)
        }
        if lower.contains("овощ") || lower.contains("фрукт") {
            return CategoryVisual(icon: "carrot.fill", color: .vaySuccess)
        }
        if lower.contains("круп") || lower.contains("макарон") || lower.contains("хлеб") {
            return CategoryVisual(icon: "basket.fill", color: .vayWarning)
        }
        if lower.contains("напит") {
            return CategoryVisual(icon: "waterbottle.fill", color: .vayInfo)
        }
        if lower.contains("заморож") {
            return CategoryVisual(icon: "snowflake", color: .vayFreezer)
        }
        if lower.contains("конс") {
            return CategoryVisual(icon: "takeoutbag.and.cup.and.straw.fill", color: .vayAccent)
        }
        if lower.contains("специ") || lower.contains("соус") {
            return CategoryVisual(icon: "flame.fill", color: .vayCalories)
        }
        return CategoryVisual(icon: "fork.knife.circle.fill", color: .vayPrimary)
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
