import Charts
import SwiftUI

struct HomeView: View {
    let inventoryService: any InventoryServiceProtocol
    let settingsService: any SettingsServiceProtocol
    let healthKitService: HealthKitService
    var onOpenScanner: () -> Void = {}
    var onOpenMealPlan: () -> Void = {}
    var onOpenInventory: () -> Void = {}

    @AppStorage("showHealthCardOnHome") private var storedShowHealthCardOnHome: Bool = true

    @State private var products: [Product] = []
    @State private var batches: [Batch] = []
    @State private var events: [InventoryEvent] = []
    @State private var priceEntries: [PriceEntry] = []
    @State private var settings: AppSettings?
    @State private var appeared = false
    @State private var dashboardAppeared = false
    @State private var isLoading = true
    @State private var predictions: [ProductPrediction] = []
    @State private var adaptiveNutritionTarget: Nutrition = .empty
    @State private var healthWeightHistory: [HealthKitService.SamplePoint] = []
    @State private var isHealthCardLoading = false
    @State private var healthCardMessage: String?
    private let todayMenuSnapshotStore = TodayMenuSnapshotStore()

    private struct TodayPlanProgress {
        let completed: Int
        let total: Int

        var fraction: Double {
            guard total > 0 else { return 0 }
            return Double(completed) / Double(total)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: VaySpacing.lg) {
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
                    if let settings {
                        revealCard(0) {
                            nutritionSection(settings: settings)
                        }
                    }

                    revealCard(1) { selectedTodayMenuSection }
                    revealCard(2) { savingsMoneyCard }
                    revealCard(3) { progressSummaryCard }

                    if shouldShowHealthCard {
                        revealCard(4) { healthDynamicsCard }
                    }

                    revealCard(shouldShowHealthCard ? 5 : 4) { todayPlanProgressCard }
                    revealCard(shouldShowHealthCard ? 6 : 5) { budgetWeekCard }
                    revealCard(shouldShowHealthCard ? 7 : 6) { riskSection }
                    revealCard(shouldShowHealthCard ? 8 : 7) { noLossStreakCard }

                    if !predictions.isEmpty {
                        revealCard(shouldShowHealthCard ? 9 : 8) { predictionsSection }
                    }
                }


                Color.clear.frame(height: VayLayout.tabBarOverlayInset)
            }
            .padding(.horizontal, VaySpacing.lg)
        }
        .background(Color.vayBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .onAppear {
            guard !dashboardAppeared else { return }
            dashboardAppeared = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsDidChange)) { notification in
            if let updated = notification.object as? AppSettings {
                applyUpdatedSettings(updated)
                Task {
                    await recalculateAdaptiveNutritionTarget(using: updated)
                    await loadHealthCardData(
                        ifNeeded: updated.showHealthCardOnHome,
                        healthReadEnabled: updated.healthKitReadEnabled
                    )
                }
            } else {
                Task {
                    await refreshSettingsOnly()
                }
            }
        }
        .onChange(of: storedShowHealthCardOnHome) { _, newValue in
            Task {
                await loadHealthCardData(
                    ifNeeded: newValue,
                    healthReadEnabled: settings?.healthKitReadEnabled ?? true
                )
            }
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

    private var todayPlanProgressCard: some View {
        Button(action: onOpenMealPlan) {
            VStack(alignment: .leading, spacing: VaySpacing.md) {
                HStack(spacing: VaySpacing.sm) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.vayInfo)
                    Text("План на сегодня")
                        .font(VayFont.heading(16))
                    Spacer()
                    openChip
                }

                if let progress = todayPlanProgress {
                    VStack(alignment: .leading, spacing: VaySpacing.xs) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.vayInfo.opacity(0.15))
                                    .frame(height: 8)

                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.vayInfo, .vayPrimary],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * progress.fraction, height: 8)
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Text("Выполнено по расписанию: \(progress.completed)/\(progress.total)")
                                .font(VayFont.caption(12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int((progress.fraction * 100).rounded()))%")
                                .font(VayFont.label(13))
                                .foregroundStyle(Color.vayPrimary)
                        }
                    }
                } else {
                    Text("План еще не создан. Сгенерируйте меню на сегодня.")
                        .font(VayFont.body(14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .vayCard()
        }
        .buttonStyle(.plain)
        .vayAccessibilityLabel("План на сегодня", hint: "Открыть экран плана питания")
    }

    private var budgetWeekCard: some View {
        let spentMinor = weeklySpendingMinor
        let limitMinor = weeklyBudgetLimitMinor

        return VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: "wallet.pass.fill", title: "Бюджет недели", color: .vayWarning)

            if let limitMinor {
                let ratio = min(1, Double(spentMinor) / Double(max(limitMinor, 1)))
                let remainingMinor = max(0, limitMinor - spentMinor)
                let overMinor = max(0, spentMinor - limitMinor)

                HStack {
                    VStack(alignment: .leading, spacing: VaySpacing.xs) {
                        Text("Потрачено")
                            .font(VayFont.caption(12))
                            .foregroundStyle(.secondary)
                        Text(rubText(fromMinor: spentMinor))
                            .font(VayFont.label(16))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: VaySpacing.xs) {
                        Text("Лимит")
                            .font(VayFont.caption(12))
                            .foregroundStyle(.secondary)
                        Text(rubText(fromMinor: limitMinor))
                            .font(VayFont.label(16))
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.vayWarning.opacity(0.15))
                            .frame(height: 8)

                        Capsule()
                            .fill(overMinor > 0 ? Color.vayDanger : Color.vayWarning)
                            .frame(width: geo.size.width * ratio, height: 8)
                    }
                }
                .frame(height: 8)

                Text(
                    overMinor > 0
                        ? "Перерасход: \(rubText(fromMinor: overMinor))"
                        : "Остаток: \(rubText(fromMinor: remainingMinor))"
                )
                .font(VayFont.caption(12))
                .foregroundStyle(overMinor > 0 ? Color.vayDanger : .secondary)
            } else {
                Text("Лимит недели не задан. Укажите бюджет в настройках.")
                    .font(VayFont.body(14))
                    .foregroundStyle(.secondary)
            }
        }
        .vayCard()
        .vayAccessibilityLabel("Бюджет недели")
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

    private var healthDynamicsCard: some View {
        NavigationLink {
            BodyMetricsView(
                settingsService: settingsService,
                healthKitService: healthKitService
            )
        } label: {
            VStack(alignment: .leading, spacing: VaySpacing.md) {
                HStack(spacing: VaySpacing.sm) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.vayDanger)
                    Text("Моё тело: динамика")
                        .font(VayFont.heading(16))
                    Spacer()
                    Text("Подробнее")
                        .font(VayFont.label(12))
                        .foregroundStyle(Color.vayPrimary)
                }

                if let latestWeight = latestWeightValue {
                    HStack {
                        Text("\(latestWeight.formatted(.number.precision(.fractionLength(0...1)))) кг")
                            .font(VayFont.title(24))
                            .foregroundStyle(Color.vayPrimary)
                        Spacer()
                        if let delta = weightDeltaValue {
                            Text("\(signedNumberText(delta, digits: 1)) кг за 14 дней")
                                .font(VayFont.caption(12))
                                .foregroundStyle(delta <= 0 ? Color.vaySuccess : Color.vayWarning)
                        }
                    }

                    if healthWeightHistory.count >= 2 {
                        Chart(healthWeightHistory) { point in
                            LineMark(
                                x: .value("Дата", point.date),
                                y: .value("Вес", point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.vayPrimary, .vayInfo],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                            AreaMark(
                                x: .value("Дата", point.date),
                                y: .value("Вес", point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.vayPrimary.opacity(0.22), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                        .frame(height: 104)
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                    }
                } else if isHealthCardLoading {
                    HStack(spacing: VaySpacing.sm) {
                        ProgressView()
                        Text("Загружаем динамику из Apple Health...")
                            .font(VayFont.body(14))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(healthCardMessage ?? "Нет данных о весе. Откройте «Моё тело» и разрешите доступ к Apple Health.")
                        .font(VayFont.body(14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .vayCard()
        }
        .buttonStyle(.plain)
    }

    private var riskSection: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: "exclamationmark.triangle.fill", title: "Риски просрочки", color: .vayDanger)

            if expiringSoonBatches.isEmpty {
                HStack(spacing: VaySpacing.sm) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Color.vaySuccess)
                    Text("На ближайшие 3 дня рисков просрочки нет.")
                        .font(VayFont.body(14))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(expiringSoonBatches.prefix(3)) { batch in
                    if let product = products.first(where: { $0.id == batch.productId }) {
                        expiryRow(product: product, batch: batch)
                    }
                }

                Button(action: onOpenInventory) {
                    Label("Открыть запасы", systemImage: "refrigerator.fill")
                        .font(VayFont.label(13))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.vayPrimary)
            }
        }
        .vayCard()
        .vayAccessibilityLabel("Риски просрочки")
    }

    private var noLossStreakCard: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            sectionHeader(icon: "shield.lefthalf.filled", title: "Серия дней без потерь", color: .vaySuccess)

            if let streak = noLossStreakDays {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(streak)")
                        .font(VayFont.title(30))
                        .foregroundStyle(Color.vaySuccess)
                    Text("дней")
                        .font(VayFont.label(14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(streak >= 7 ? "Отличный темп" : "Держите серию")
                        .font(VayFont.caption(12))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Недостаточно данных для расчета серии.")
                    .font(VayFont.body(14))
                    .foregroundStyle(.secondary)
            }
        }
        .vayCard()
        .vayAccessibilityLabel("Серия дней без потерь")
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
        let dayTarget = resolvedHomeNutritionTarget(from: settings)

        return Button(action: onOpenMealPlan) {
            VStack(alignment: .leading, spacing: VaySpacing.md) {
                HStack {
                    sectionHeader(icon: "flame.fill", title: "Цели на сегодня", color: .vayCalories)
                    Spacer()
                    openChip
                }

                NutritionRingGroup(
                    kcal: 0,
                    protein: 0,
                    fat: 0,
                    carbs: 0,
                    kcalGoal: dayTarget.kcal ?? 2000,
                    proteinGoal: dayTarget.protein ?? 80,
                    fatGoal: dayTarget.fat ?? 65,
                    carbsGoal: dayTarget.carbs ?? 250
                )
                .frame(maxWidth: .infinity)
                .vayAccessibilityLabel("Кольца КБЖУ на сегодня")
            }
            .vayCard()
        }
        .buttonStyle(.plain)
        .vayAccessibilityLabel("Цели на сегодня", hint: "Открыть экран плана питания")
    }

    private var selectedTodayMenuSection: some View {
        let snapshot = freshTodayMenuSnapshot

        return Button(action: onOpenMealPlan) {
            VStack(alignment: .leading, spacing: VaySpacing.md) {
                HStack {
                    sectionHeader(icon: "fork.knife", title: "Выбранное меню на сегодня", color: .vayPrimary)
                    Spacer()
                    openChip
                }

                if let snapshot {
                    ForEach(Array(snapshot.items.prefix(3).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: VaySpacing.sm) {
                            Text(mealTypeTitle(item.mealType))
                                .font(VayFont.caption(11))
                                .foregroundStyle(.secondary)
                            Text(item.title)
                                .font(VayFont.body(14))
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.kcal.formatted(.number.precision(.fractionLength(0)))) ккал")
                                .font(VayFont.caption(11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let estimatedCost = snapshot.estimatedCost {
                        HStack {
                            Text("Оценка стоимости")
                                .font(VayFont.caption(12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(estimatedCost.formatted(.number.precision(.fractionLength(0)))) ₽")
                                .font(VayFont.label(13))
                                .foregroundStyle(Color.vayWarning)
                        }
                    }
                } else {
                    Text("Пока нет выбранного меню на сегодня. Откройте «План», чтобы сгенерировать.")
                        .font(VayFont.body(14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .vayCard()
        }
        .buttonStyle(.plain)
        .vayAccessibilityLabel("Выбранное меню на сегодня", hint: "Открыть экран плана питания")
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

    private var openChip: some View {
        Text("Открыть")
            .font(VayFont.caption(11))
            .foregroundStyle(Color.vayPrimary)
            .padding(.horizontal, VaySpacing.sm)
            .padding(.vertical, VaySpacing.xs)
            .background(Color.vayPrimary.opacity(0.12))
            .clipShape(Capsule())
    }

    private func revealCard<Content: View>(
        _ index: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(dashboardAppeared ? 1 : 0)
            .offset(y: dashboardAppeared ? 0 : 12)
            .animation(
                VayAnimation.springSmooth.delay(Double(index) * 0.04),
                value: dashboardAppeared
            )
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

    private var freshTodayMenuSnapshot: TodayMenuSnapshot? {
        guard let snapshot = todayMenuSnapshotStore.load() else {
            return nil
        }
        guard todayMenuSnapshotStore.isFreshForToday(snapshot), !snapshot.items.isEmpty else {
            return nil
        }
        return snapshot
    }

    private var shouldShowHealthCard: Bool {
        storedShowHealthCardOnHome
    }

    private var latestWeightValue: Double? {
        healthWeightHistory.last?.value
    }

    private var weightDeltaValue: Double? {
        guard let first = healthWeightHistory.first?.value, let last = healthWeightHistory.last?.value else {
            return nil
        }
        return last - first
    }

    private var todayPlanProgress: TodayPlanProgress? {
        guard let snapshot = freshTodayMenuSnapshot, !snapshot.items.isEmpty else {
            return nil
        }

        let nowMinute = minuteOfDay(Date())
        let completed = snapshot.items.filter { item in
            nowMinute >= mealScheduleMinute(for: item.mealType)
        }.count
        let total = snapshot.items.count

        return TodayPlanProgress(
            completed: min(completed, total),
            total: total
        )
    }

    private var weeklyBudgetLimitMinor: Int64? {
        guard let settings else { return nil }
        let weeklyBudget =
            settings.budgetWeek
            ?? settings.budgetMonth.map(AppSettings.weeklyBudget(fromMonthly:))
            ?? (settings.budgetDay * Decimal(7))
        let value = NSDecimalNumber(decimal: weeklyBudget).doubleValue
        guard value > 0 else { return nil }
        return Int64((value * 100).rounded())
    }

    private var noLossStreakDays: Int? {
        guard !events.isEmpty else { return nil }

        let calendar = Calendar.current
        let lossDays = Set(
            events
                .filter { event in
                    event.type == .remove && (event.reason == .expired || event.reason == .writeOff)
                }
                .map { calendar.startOfDay(for: $0.timestamp) }
        )

        let earliestKnownDay = calendar.startOfDay(
            for: events.map(\.timestamp).min() ?? Date()
        )
        var cursor = calendar.startOfDay(for: Date())
        var streak = 0

        while cursor >= earliestKnownDay {
            if lossDays.contains(cursor) {
                break
            }
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previous
        }

        return streak
    }

    private var weeklyEvents: [InventoryEvent] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return events.filter { $0.type == .remove && $0.timestamp >= weekAgo }
    }

    private var weeklyConsumedCount: Int {
        weeklyEvents.filter { $0.reason == .consumed }.count
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

    private func signedNumberText(_ value: Double, digits: Int) -> String {
        let prefix = value > 0 ? "+" : ""
        let formatted = value.formatted(.number.precision(.fractionLength(0...digits)))
        return "\(prefix)\(formatted)"
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 6 { return "Доброй ночи 🌙" }
        if hour < 12 { return "Доброе утро ☀️" }
        if hour < 18 { return "Добрый день 🌤" }
        return "Добрый вечер 🌇"
    }

    private func mealTypeTitle(_ raw: String) -> String {
        switch raw {
        case "breakfast":
            return "Завтрак"
        case "lunch":
            return "Обед"
        case "dinner":
            return "Ужин"
        default:
            return raw
        }
    }

    private func mealScheduleMinute(for mealType: String) -> Int {
        let schedule = settings?.mealSchedule ?? .default
        switch mealType {
        case "breakfast":
            return schedule.breakfastMinute
        case "lunch":
            return schedule.lunchMinute
        case "dinner":
            return schedule.dinnerMinute
        default:
            return 23 * 60 + 59
        }
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func loadData() async {
        do {
            products = try await inventoryService.listProducts(location: nil, search: nil)
            batches = try await inventoryService.listBatches(productId: nil)
            let loadedSettings = try await settingsService.loadSettings()
            settings = loadedSettings
            storedShowHealthCardOnHome = loadedSettings.showHealthCardOnHome
            await recalculateAdaptiveNutritionTarget(using: loadedSettings)

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

            await loadHealthCardData(
                ifNeeded: loadedSettings.showHealthCardOnHome,
                healthReadEnabled: loadedSettings.healthKitReadEnabled
            )
            
            let inventoryItems = products.map { product in
                let quantity = batches.filter { $0.productId == product.id }.reduce(0.0) { $0 + $1.quantity }
                return (name: product.name, quantity: quantity, expiryDate: batches.first { $0.productId == product.id }?.expiryDate)
            }
            predictions = PredictionService.shared.predictNeededProducts(currentInventory: inventoryItems)

            isLoading = false
        } catch {
            healthWeightHistory = []
            healthCardMessage = nil
            isHealthCardLoading = false
            isLoading = false
        }
    }

    private func refreshSettingsOnly() async {
        guard let loaded = try? await settingsService.loadSettings() else { return }
        applyUpdatedSettings(loaded)
        await recalculateAdaptiveNutritionTarget(using: loaded)
        await loadHealthCardData(
            ifNeeded: loaded.showHealthCardOnHome,
            healthReadEnabled: loaded.healthKitReadEnabled
        )
    }

    private func applyUpdatedSettings(_ loaded: AppSettings) {
        settings = loaded
        storedShowHealthCardOnHome = loaded.showHealthCardOnHome
    }

    private func resolvedHomeNutritionTarget(from settings: AppSettings) -> Nutrition {
        if let kcal = adaptiveNutritionTarget.kcal,
           let protein = adaptiveNutritionTarget.protein,
           let fat = adaptiveNutritionTarget.fat,
           let carbs = adaptiveNutritionTarget.carbs,
           kcal > 0, protein > 0, fat > 0, carbs > 0
        {
            return adaptiveNutritionTarget
        }

        return Nutrition(
            kcal: settings.kcalGoal ?? 2000,
            protein: settings.proteinGoalGrams ?? 80,
            fat: settings.fatGoalGrams ?? 65,
            carbs: settings.carbsGoalGrams ?? 250
        )
    }

    private func recalculateAdaptiveNutritionTarget(using settings: AppSettings) async {
        var automaticDailyCalories: Double?
        var weightKG: Double?

        if settings.macroGoalSource == .automatic, settings.healthKitReadEnabled {
            if let metrics = try? await healthKitService.fetchLatestMetrics() {
                automaticDailyCalories = Double(
                    healthKitService.calculateDailyCalories(
                        metrics: metrics,
                        targetLossPerWeek: settings.dietProfile.targetLossPerWeek
                    )
                )
                weightKG = metrics.weightKG
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

        adaptiveNutritionTarget = output.baselineDayTarget
    }

    private func loadHealthCardData(ifNeeded shouldLoad: Bool, healthReadEnabled: Bool) async {
        guard shouldLoad else {
            healthWeightHistory = []
            healthCardMessage = nil
            isHealthCardLoading = false
            return
        }

        guard healthReadEnabled else {
            healthWeightHistory = []
            healthCardMessage = "Включите чтение Apple Health в настройках."
            isHealthCardLoading = false
            return
        }

        isHealthCardLoading = true
        defer { isHealthCardLoading = false }

        do {
            let points = try await healthKitService.fetchWeightHistory(days: 14)
            let sorted = points.sorted(by: { $0.date < $1.date })
            healthWeightHistory = sorted
            healthCardMessage = sorted.isEmpty ? "Данные о весе пока отсутствуют." : nil
        } catch {
            healthWeightHistory = []
            healthCardMessage = "Нет доступа к данным Apple Health."
        }
    }
}
