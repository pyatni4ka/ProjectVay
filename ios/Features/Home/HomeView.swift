import SwiftUI

struct HomeView: View {
    let inventoryService: any InventoryServiceProtocol
    let settingsService: any SettingsServiceProtocol
    var onOpenScanner: () -> Void = {}
    var onOpenReceiptScan: () -> Void = {}

    @State private var products: [Product] = []
    @State private var batches: [Batch] = []
    @State private var events: [InventoryEvent] = []
    @State private var priceEntries: [PriceEntry] = []
    @State private var settings: AppSettings?
    @State private var appeared = false
    @State private var isLoading = true
    @State private var predictions: [ProductPrediction] = []

    var body: some View {
        ScrollView {
            VStack(spacing: VaySpacing.xl) {
                heroSection

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if products.isEmpty {
                    EmptyStateView(
                        icon: "refrigerator",
                        title: "Начните добавлять продукты",
                        subtitle: "Сканируйте первый товар или добавьте его вручную, чтобы увидеть статистику и рекомендации.",
                        actionTitle: "Сканировать первый товар",
                        action: onOpenScanner
                    )
                    .padding(.top, VaySpacing.xl)
                } else {
                    quickStatsSection
                    savingsMoneyCard
                    weeklyBreakdownCard
                    progressSummaryCard

                    if !expiringSoonBatches.isEmpty {
                        expiringSoonSection
                    }

                    if let settings {
                        nutritionSection(settings: settings)
                    }

                    if !lowStockProducts.isEmpty {
                        lowStockSection
                    }
                    
                    if !predictions.isEmpty {
                        predictionsSection
                    }
                }


                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, VaySpacing.lg)
        }
        .background(Color.vayBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        onOpenScanner()
                    } label: {
                        Label("Сканировать штрихкод", systemImage: "barcode.viewfinder")
                    }
                    
                    Button {
                        onOpenReceiptScan()
                    } label: {
                        Label("Сканировать чек", systemImage: "doc.text.viewfinder")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.vayPrimary)
                }
            }
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            Text(greetingText)
                .font(VayFont.caption())
                .foregroundStyle(.secondary)
                .vayAccessibilityLabel("Приветствие: \(greetingText)")

            Text("ДомИнвентарь")
                .font(VayFont.hero())
                .foregroundStyle(.primary)
                .vayAccessibilityLabel("ДомИнвентарь — главная")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, VaySpacing.sm)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(VayAnimation.springSmooth) {
                appeared = true
            }
        }
    }

    private var quickStatsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: VaySpacing.md),
            GridItem(.flexible(), spacing: VaySpacing.md)
        ], spacing: VaySpacing.md) {
            StatCard(
                icon: "cube.box",
                title: "Продукты",
                value: "\(products.count)",
                subtitle: "в инвентаре",
                color: .vayPrimary
            )
            .vayAccessibilityLabel("Продуктов в инвентаре: \(products.count)")

            StatCard(
                icon: "shippingbox",
                title: "Партии",
                value: "\(batches.count)",
                subtitle: totalQuantityText,
                color: .vayInfo
            )
            .vayAccessibilityLabel("Партий: \(batches.count), \(totalQuantityText)")

            StatCard(
                icon: "exclamationmark.triangle",
                title: "Истекает",
                value: "\(expiringSoonBatches.count)",
                subtitle: "в ближ. 3 дня",
                color: .vayWarning
            )
            .vayAccessibilityLabel("Истекает скоро: \(expiringSoonBatches.count) партий в ближайшие 3 дня")

            StatCard(
                icon: "snowflake",
                title: "Морозилка",
                value: "\(freezerCount)",
                subtitle: "партий",
                color: .vayFreezer
            )
            .vayAccessibilityLabel("В морозилке: \(freezerCount) партий")
        }
    }

    private var savingsMoneyCard: some View {
        let savedMinor = weeklySavedMinor
        let lostMinor = weeklyLossMinor

        return VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: "leaf.fill", title: "Сэкономлено на этой неделе", color: .vaySuccess)

            HStack(alignment: .firstTextBaseline) {
                Text(rubText(fromMinor: savedMinor))
                    .font(VayFont.title(28))
                    .foregroundStyle(Color.vaySuccess)

                Spacer()

                VStack(alignment: .trailing, spacing: VaySpacing.xs) {
                    Text("Потери")
                        .font(VayFont.caption(12))
                        .foregroundStyle(.secondary)
                    Text(rubText(fromMinor: lostMinor))
                        .font(VayFont.label(15))
                        .foregroundStyle(lostMinor > 0 ? Color.vayDanger : Color.secondary)
                }
            }

            if savedMinor + lostMinor > 0 {
                let efficiency = Double(savedMinor) / Double(savedMinor + lostMinor)
                VStack(alignment: .leading, spacing: VaySpacing.xs) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.vayDanger.opacity(0.15))
                                .frame(height: 6)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.vaySuccess, .vayPrimary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * efficiency, height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("Эффективность: \(Int(efficiency * 100))%")
                        .font(VayFont.caption(11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .vayCard()
        .vayAccessibilityLabel("Сэкономлено на этой неделе \(rubText(fromMinor: savedMinor)), потери \(rubText(fromMinor: lostMinor))")
    }

    private var weeklyBreakdownCard: some View {
        let consumedCount = weeklyConsumedCount
        let expiredCount = weeklyExpiredCount
        let writeOffCount = weeklyWriteOffCount

        return VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: "chart.bar.fill", title: "Операции недели", color: .vayInfo)

            HStack(spacing: VaySpacing.md) {
                miniPill(icon: "checkmark.circle.fill", label: "Съедено", value: "\(consumedCount)", color: .vaySuccess)
                miniPill(icon: "clock.badge.exclamationmark", label: "Просрочено", value: "\(expiredCount)", color: .vayDanger)
                miniPill(icon: "minus.circle.fill", label: "Списано", value: "\(writeOffCount)", color: .vayWarning)
            }
        }
        .vayCard()
        .vayAccessibilityLabel("За неделю: съедено \(consumedCount), просрочено \(expiredCount), списано \(writeOffCount)")
    }

    private var progressSummaryCard: some View {
        NavigationLink {
            ProgressTrackingView(
                inventoryService: inventoryService,
                settingsService: settingsService
            )
        } label: {
            VStack(alignment: .leading, spacing: VaySpacing.md) {
                HStack(spacing: VaySpacing.sm) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.vayInfo)
                    Text("Прогресс")
                        .font(VayFont.heading(16))
                    Spacer()
                    Text("Подробнее")
                        .font(VayFont.label(12))
                        .foregroundStyle(Color.vayPrimary)
                }

                HStack(spacing: VaySpacing.md) {
                    miniPill(icon: "checkmark.circle.fill", label: "Съедено", value: "\(weeklyConsumedCount)", color: .vaySuccess)
                    miniPill(icon: "minus.circle.fill", label: "Списано", value: "\(weeklyWriteOffCount)", color: .vayWarning)
                    miniPill(icon: "clock.badge.exclamationmark", label: "Потери", value: rubText(fromMinor: weeklyLossMinor), color: .vayDanger)
                }

                HStack {
                    Text("Расходы за 7 дней")
                        .font(VayFont.caption(12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(rubText(fromMinor: weeklySpendingMinor))
                        .font(VayFont.label(14))
                        .foregroundStyle(Color.vayWarning)
                }
            }
            .vayCard()
        }
        .buttonStyle(.plain)
        .vayAccessibilityLabel("Прогресс: съедено \(weeklyConsumedCount), списано \(weeklyWriteOffCount), потери \(rubText(fromMinor: weeklyLossMinor)), расходы \(rubText(fromMinor: weeklySpendingMinor))")
    }

    private var expiringSoonSection: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: "clock.badge.exclamationmark", title: "Скоро истекает", color: .vayWarning)

            ForEach(expiringSoonBatches.prefix(5)) { batch in
                if let product = products.first(where: { $0.id == batch.productId }) {
                    expiryRow(product: product, batch: batch)
                }
            }
        }
        .vayCard()
        .vayAccessibilityLabel("Скоро истекает: \(expiringSoonBatches.count) продуктов")
    }

    private func expiryRow(product: Product, batch: Batch) -> some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: batch.location.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(batch.location.color)
                .frame(width: 32, height: 32)
                .background(batch.location.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: VayRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(VayFont.label(14))
                    .lineLimit(1)

                Text("\(batch.quantity.formatted()) \(batch.unit.title)")
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let expiry = batch.expiryDate {
                Text(expiry.expiryLabel)
                    .font(VayFont.label(12))
                    .foregroundStyle(expiry.expiryColor)
                    .padding(.horizontal, VaySpacing.sm)
                    .padding(.vertical, VaySpacing.xs)
                    .background(expiry.expiryColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .vayAccessibilityLabel("\(product.name), \(batch.quantity.formatted()) \(batch.unit.title), \(batch.expiryDate?.expiryLabel ?? "")")
    }

    private func nutritionSection(settings: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: "flame.fill", title: "Цели на сегодня", color: .vayCalories)

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

    private var lowStockSection: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: "arrow.down.circle", title: "Заканчивается", color: .vayDanger)

            ForEach(lowStockProducts.prefix(5)) { product in
                HStack(spacing: VaySpacing.md) {
                    Image(systemName: "cube.box")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.vayDanger)
                        .frame(width: 28, height: 28)
                        .background(Color.vayDanger.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    Text(product.name)
                        .font(VayFont.label(14))
                        .lineLimit(1)

                    Spacer()

                    let count = batches.filter { $0.productId == product.id }.count
                    Text("\(count) шт.")
                        .font(VayFont.caption(12))
                        .foregroundStyle(.secondary)
                }
                .vayAccessibilityLabel("\(product.name) заканчивается, осталось \(batches.filter { $0.productId == product.id }.count) штук")
            }
        }
        .vayCard()
    }
    
    private var predictionsSection: some View {
        PredictionsCard(
            predictions: predictions,
            onAddToShoppingList: { _ in
                GamificationService.shared.trackExpiryWarning()
            }
        )
    }
    
    private func miniPill(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.xs) {
            HStack(spacing: VaySpacing.xs) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(label)
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(VayFont.label(16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VaySpacing.sm)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
        .vayAccessibilityLabel("\(label): \(value)")
    }

    private func sectionHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(VayFont.heading(16))
        }
    }

    private var expiringSoonBatches: [Batch] {
        batches
            .filter { batch in
                guard let expiry = batch.expiryDate else { return false }
                return expiry.daysUntilExpiry <= 3
            }
            .sorted { a, b in
                (a.expiryDate ?? .distantFuture) < (b.expiryDate ?? .distantFuture)
            }
    }

    private var lowStockProducts: [Product] {
        let productBatchCounts = Dictionary(grouping: batches, by: \.productId)
            .mapValues { $0.count }
        return products.filter { (productBatchCounts[$0.id] ?? 0) <= 1 }
    }

    private var freezerCount: Int {
        batches.filter { $0.location == .freezer }.count
    }

    private var totalQuantityText: String {
        let total = batches.reduce(0.0) { $0 + $1.quantity }
        return "всего \(Int(total)) ед."
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

    private var weeklySavedMinor: Int64 {
        weeklyEvents
            .filter { $0.reason == .consumed }
            .compactMap(\.estimatedValueMinor)
            .reduce(0, +)
    }

    private var weeklyLossMinor: Int64 {
        weeklyEvents
            .filter { $0.reason == .expired || $0.reason == .writeOff }
            .compactMap(\.estimatedValueMinor)
            .reduce(0, +)
    }

    private var weeklySpendingMinor: Int64 {
        weeklyPriceEntries
            .map { $0.price.asMinorUnits }
            .reduce(0, +)
    }

    private var weeklyPriceEntries: [PriceEntry] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return priceEntries.filter { $0.date >= weekAgo }
    }

    private func rubText(fromMinor minor: Int64) -> String {
        let rub = Double(minor) / 100
        return "\(rub.formatted(.number.precision(.fractionLength(0)))) ₽"
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 6 { return "Доброй ночи 🌙" }
        if hour < 12 { return "Доброе утро ☀️" }
        if hour < 18 { return "Добрый день 🌤" }
        return "Добрый вечер 🌇"
    }

    private func loadData() async {
        do {
            products = try await inventoryService.listProducts(location: nil, search: nil)
            batches = try await inventoryService.listBatches(productId: nil)
            settings = try await settingsService.loadSettings()

            var allEvents: [InventoryEvent] = []
            var allPrices: [PriceEntry] = []
            for product in products {
                let productEvents = try await inventoryService.listEvents(productId: product.id)
                allEvents.append(contentsOf: productEvents)
                let history = try await inventoryService.listPriceHistory(productId: product.id)
                allPrices.append(contentsOf: history)
            }
            events = allEvents
            priceEntries = allPrices
            
            let inventoryItems = products.map { product in
                let quantity = batches.filter { $0.productId == product.id }.reduce(0.0) { $0 + $1.quantity }
                return (name: product.name, quantity: quantity, expiryDate: batches.first { $0.productId == product.id }?.expiryDate)
            }
            predictions = PredictionService.shared.predictNeededProducts(currentInventory: inventoryItems)

            isLoading = false
        } catch {
            isLoading = false
        }
    }
}
