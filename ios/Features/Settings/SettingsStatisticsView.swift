import Charts
import SwiftUI

struct SettingsStatisticsView: View {
    let inventoryService: any InventoryServiceProtocol

    @State private var products: [Product] = []
    @State private var batches: [Batch] = []
    @State private var events: [InventoryEvent] = []
    @State private var isLoading = true
    @State private var hasFallbackData = false
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: VaySpacing.xl) {
                headerCard

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    inventoryOverviewGrid
                    expiryAlertCard
                    weeklyOperationsCard
                    locationBreakdownCard
                    categoryDonutCard

                    if hasFallbackData {
                        fallbackNotice
                    }
                }

                Color.clear.frame(height: VayLayout.tabBarOverlayInset)
            }
            .padding(.horizontal, VaySpacing.lg)
        }
        .background(Color.vayBackground)
        .navigationTitle("Статистика")
        .task {
            await loadStatistics()
            withAnimation(VayAnimation.springSmooth) {
                appeared = true
            }
        }
        .refreshable {
            await loadStatistics()
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(alignment: .top, spacing: VaySpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.vaySecondary.opacity(0.2), .vayPrimary.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
                    .font(VayFont.heading(22))
                    .foregroundStyle(Color.vaySecondary)
            }

            VStack(alignment: .leading, spacing: VaySpacing.xs) {
                Text("Статистика запасов")
                    .font(VayFont.heading(19))
                Text("Сводка по инвентарю, срокам годности, операциям и распределению по местам хранения.")
                    .font(VayFont.body(14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .vayCard()
        .vayAccessibilityLabel("Статистика запасов: сводка инвентаря")
    }

    // MARK: - Inventory Overview Grid

    private var inventoryOverviewGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: VaySpacing.sm) {
            overviewMiniCard(
                icon: "cube.box.fill",
                title: "Продукты",
                value: "\(products.count)",
                color: .vayPrimary
            )
            overviewMiniCard(
                icon: "shippingbox.fill",
                title: "Партии",
                value: "\(batches.count)",
                color: .vayInfo
            )
            overviewMiniCard(
                icon: "snowflake",
                title: "Морозилка",
                value: "\(freezerBatchesCount)",
                color: .vaySecondary
            )
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96)
    }

    // MARK: - Expiry Alert Card

    private var expiryAlertCard: some View {
        ColoredGlassCard(tint: .vayWarning) {
            HStack(spacing: VaySpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.vayWarning.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .font(VayFont.heading(20))
                        .foregroundStyle(Color.vayWarning)
                }

                VStack(alignment: .leading, spacing: VaySpacing.xs) {
                    Text("Истекает в ближайшие 3 дня")
                        .font(VayFont.label(13))
                        .foregroundStyle(.secondary)
                    Text("\(expiringSoonCount)")
                        .font(VayFont.title(28))
                        .foregroundStyle(expiringSoonCount > 0 ? Color.vayWarning : .primary)
                }

                Spacer()

                if expiringSoonCount > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(VayFont.heading(22))
                        .foregroundStyle(Color.vayWarning.opacity(0.5))
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96)
        .vayAccessibilityLabel("Истекает в ближайшие 3 дня: \(expiringSoonCount)")
    }

    // MARK: - Weekly Operations Card

    private var weeklyOperationsCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(Color.vayInfo)
                    .font(VayFont.label(14))
                Text("Операции за 7 дней")
                    .font(VayFont.heading(16))
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: VaySpacing.sm) {
                operationMiniCard(
                    icon: "fork.knife.circle.fill",
                    title: "Съедено",
                    value: weeklyConsumedCount,
                    color: .vaySuccess
                )
                operationMiniCard(
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    title: "Просрочено",
                    value: weeklyExpiredCount,
                    color: .vayDanger
                )
                operationMiniCard(
                    icon: "minus.circle.fill",
                    title: "Списано",
                    value: weeklyWriteOffCount,
                    color: .vayWarning
                )
            }
        }
        .vayCard()
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96)
        .vayAccessibilityLabel("Операции за 7 дней: съедено \(weeklyConsumedCount), просрочено \(weeklyExpiredCount), списано \(weeklyWriteOffCount)")
    }

    // MARK: - Location Breakdown Card

    private var locationBreakdownCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "square.split.2x2.fill")
                    .foregroundStyle(Color.vayPrimary)
                    .font(VayFont.label(14))
                Text("По местам хранения")
                    .font(VayFont.heading(16))
            }

            let totalBatches = max(batches.count, 1)

            ForEach(InventoryLocation.allCases) { location in
                let count = batches.filter { $0.location == location }.count
                let fraction = Double(count) / Double(totalBatches)

                HStack(spacing: VaySpacing.md) {
                    ZStack {
                        Circle()
                            .fill(location.color.opacity(0.14))
                            .frame(width: 32, height: 32)
                        Image(systemName: location.icon)
                            .font(VayFont.label(14))
                            .foregroundStyle(location.color)
                    }

                    VStack(alignment: .leading, spacing: VaySpacing.xxs) {
                        Text(location.title)
                            .font(VayFont.label(14))
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: VayRadius.sm, style: .continuous)
                                    .fill(location.color.opacity(0.1))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: VayRadius.sm, style: .continuous)
                                    .fill(location.color.gradient)
                                    .frame(width: max(proxy.size.width * fraction, 4), height: 8)
                            }
                        }
                        .frame(height: 8)
                    }

                    Spacer(minLength: 0)

                    Text("\(count)")
                        .font(VayFont.label(15))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .vayCard()
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96)
        .vayAccessibilityLabel("Распределение по местам хранения")
    }

    // MARK: - Category Donut Card

    private var categoryDonutCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(Color.vaySecondary)
                    .font(VayFont.label(14))
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
                .vayAccessibilityLabel("Диаграмма категорий продуктов")
            } else if categories.isEmpty {
                Text("Нет данных по категориям")
                    .font(VayFont.caption())
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }

            ForEach(categories.prefix(6), id: \.category) { item in
                let style = categoryStyle(for: item.category)
                HStack(spacing: VaySpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(style.color.opacity(0.14))
                            .frame(width: 24, height: 24)
                        Image(systemName: style.icon)
                            .font(VayFont.caption(12))
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
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96)
    }

    // MARK: - Fallback Notice

    private var fallbackNotice: some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Часть данных недоступна. Показаны безопасные значения по умолчанию.")
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)
        }
        .vayCard()
    }

    // MARK: - Mini Card Builders

    private func overviewMiniCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.xs) {
            Image(systemName: icon)
                .font(VayFont.label(14))
                .foregroundStyle(color)

            Text(value)
                .font(VayFont.title(22))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(VayFont.caption(11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VaySpacing.md)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
        .vayAccessibilityLabel("\(title): \(value)")
    }

    private func operationMiniCard(icon: String, title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.xs) {
            Image(systemName: icon)
                .font(VayFont.label(14))
                .foregroundStyle(color)

            Text("\(value)")
                .font(VayFont.label(18))
                .foregroundStyle(value > 0 ? color : .primary)

            Text(title)
                .font(VayFont.caption(10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VaySpacing.sm)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
        .vayAccessibilityLabel("\(title): \(value)")
    }

    // MARK: - Chart Animation Helper

    private struct CategoryVisual {
        let icon: String
        let color: Color
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

    // MARK: - Computed Properties

    private var freezerBatchesCount: Int {
        batches.filter { $0.location == .freezer }.count
    }

    private var expiringSoonCount: Int {
        batches.filter { batch in
            guard let expiry = batch.expiryDate else { return false }
            return expiry.daysUntilExpiry <= 3
        }.count
    }

    private var weeklyEvents: [InventoryEvent] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return events.filter { $0.type == .remove && $0.timestamp >= weekAgo }
    }

    private var weeklyConsumedCount: Int {
        weeklyEvents.filter { $0.reason == .consumed }.count
    }

    private var weeklyExpiredCount: Int {
        weeklyEvents.filter { $0.reason == .expired }.count
    }

    private var weeklyWriteOffCount: Int {
        weeklyEvents.filter { $0.reason == .writeOff }.count
    }

    // MARK: - Data Loading

    private func loadStatistics() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let loadedProducts = inventoryService.listProducts(location: nil, search: nil)
            async let loadedBatches = inventoryService.listBatches(productId: nil)
            async let loadedEvents = inventoryService.listEvents(productId: nil)

            products = try await loadedProducts
            batches = try await loadedBatches
            events = try await loadedEvents
            hasFallbackData = false
        } catch {
            products = []
            batches = []
            events = []
            hasFallbackData = true
        }
    }
}

// MARK: - Chart Animation Scope (mirror ProgressView pattern)

private enum StatisticsChartAnimationScope {
    case element
}

private extension View {
    @ViewBuilder
    func chartAnimate(by scope: StatisticsChartAnimationScope) -> some View {
        switch scope {
        case .element:
            self.transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}
