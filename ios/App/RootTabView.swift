import SwiftUI
import PopupView

struct RootTabView: View {
    let inventoryService: any InventoryServiceProtocol
    let settingsService: any SettingsServiceProtocol
    let healthKitService: HealthKitService
    let barcodeLookupService: BarcodeLookupService
    let recipeServiceClient: RecipeServiceClient?
    let shoppingListService: ShoppingListServiceProtocol
    @State private var appSettingsStore: AppSettingsStore
    private var gamification = GamificationService.shared

    enum Tab: Int, CaseIterable {
        case home
        case inventory
        case mealPlan
        case settings

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .inventory: return "refrigerator.fill"
            case .mealPlan: return "fork.knife.circle.fill"
            case .settings: return "gearshape.fill"
            }
        }

        var title: String {
            switch self {
            case .home: return "Главная"
            case .inventory: return "Запасы"
            case .mealPlan: return "План"
            case .settings: return "Настройки"
            }
        }
    }

    static let leadingTabs: [Tab] = [.home, .inventory]
    static let trailingTabs: [Tab] = [.mealPlan, .settings]

    @State private var selectedTab: Tab = .home
    @State private var previousTab: Tab = .home
    @State private var loadedTabs: Set<Tab> = [.home]
    @State private var tabRootResetTokens: [Tab: UUID] = Dictionary(uniqueKeysWithValues: Tab.allCases.map { ($0, UUID()) })
    @State private var showScannerSheet = false
    @State private var showReceiptScanSheet = false

    init(
        inventoryService: any InventoryServiceProtocol,
        settingsService: any SettingsServiceProtocol,
        healthKitService: HealthKitService,
        barcodeLookupService: BarcodeLookupService,
        recipeServiceClient: RecipeServiceClient?,
        shoppingListService: ShoppingListServiceProtocol
    ) {
        self.inventoryService = inventoryService
        self.settingsService = settingsService
        self.healthKitService = healthKitService
        self.barcodeLookupService = barcodeLookupService
        self.recipeServiceClient = recipeServiceClient
        self.shoppingListService = shoppingListService
        _appSettingsStore = State(initialValue: AppSettingsStore())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                tabContent(for: .home)
                tabContent(for: .inventory)
                tabContent(for: .mealPlan)
                tabContent(for: .settings)
            }

            customTabBar
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showScannerSheet) {
            NavigationStack {
                ScannerView(
                    inventoryService: inventoryService,
                    barcodeLookupService: barcodeLookupService,
                    initialMode: .add,
                    onInventoryChanged: {}
                )
            }
        }
        .sheet(isPresented: $showReceiptScanSheet) {
            NavigationStack {
                ReceiptScanView(
                    inventoryService: inventoryService,
                    onItemsAdded: { _ in }
                )
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            loadedTabs.insert(newValue)
            if newValue != previousTab {
                VayHaptic.selection()
                previousTab = newValue
            }
        }
        .task {
            await hydrateSettingsStore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsDidChange)) { notification in
            guard let updated = notification.object as? AppSettings else { return }
            appSettingsStore.update(updated)
        }
        .environment(appSettingsStore)
        .vayDynamicType()
        .popup(item: Binding(
            get: { gamification.lastXPToast },
            set: { if $0 == nil { gamification.clearToast() } }
        )) { toast in
            HStack(spacing: 12) {
                Image(systemName: toast.icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text(toast.text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.vayPrimary)
            .clipShape(Capsule())
            .vayShadow(.card)
            .padding(.bottom, 100) // Render safely above the custom tab bar
        } customize: {
            $0
                .type(.floater(verticalPadding: 0, horizontalPadding: 20, useSafeAreaInset: false))
                .position(.bottom)
                .animation(.spring(response: 0.4, dampingFraction: 0.7))
                .autohideIn(3.0)
                .closeOnTap(true)
        }
        .fullScreenCover(item: Binding(
            get: {
                if let pendingLevel = gamification.pendingLevelUp {
                    return IdentifiableLevel(level: pendingLevel)
                }
                return nil
            },
            set: { _ in gamification.clearLevelUp() }
        )) { (levelData: IdentifiableLevel) in
            LevelUpSplashView(level: levelData.level) {
                gamification.clearLevelUp()
            }
        }
    }

    struct IdentifiableLevel: Identifiable {
        let id = UUID()
        let level: Int
    }

    @ViewBuilder
    private func tabContent(for tab: Tab) -> some View {
        let isSelected = selectedTab == tab
        Group {
            if loadedTabs.contains(tab) {
                switch tab {
                case .home:
                    NavigationStack {
                        HomeView(
                            inventoryService: inventoryService,
                            settingsService: settingsService,
                            healthKitService: healthKitService,
                            onOpenScanner: { showScannerSheet = true },
                            onOpenMealPlan: { openTab(.mealPlan) },
                            onOpenInventory: { openTab(.inventory) }
                        )
                    }
                    .id(tabRootResetTokens[.home] ?? UUID())
                case .inventory:
                    NavigationStack {
                        InventoryView(
                            inventoryService: inventoryService,
                            onOpenScanner: { showScannerSheet = true },
                            onOpenReceiptScan: { showReceiptScanSheet = true }
                        )
                    }
                    .id(tabRootResetTokens[.inventory] ?? UUID())
                case .mealPlan:
                    NavigationStack {
                        MealPlanView(
                            inventoryService: inventoryService,
                            settingsService: settingsService,
                            healthKitService: healthKitService,
                            barcodeLookupService: barcodeLookupService,
                            recipeServiceClient: recipeServiceClient,
                            shoppingListService: shoppingListService,
                            onOpenScanner: { showScannerSheet = true }
                        )
                    }
                    .id(tabRootResetTokens[.mealPlan] ?? UUID())
                case .settings:
                    NavigationStack {
                        SettingsView(
                            settingsService: settingsService,
                            inventoryService: inventoryService,
                            shoppingListService: shoppingListService,
                            healthKitService: healthKitService
                        )
                    }
                    .id(tabRootResetTokens[.settings] ?? UUID())
                }
            } else {
                Color.clear
            }
        }
        .opacity(isSelected ? 1 : 0)
        .allowsHitTesting(isSelected)
    }

    private var customTabBar: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                tabGroup(Self.leadingTabs)

                Color.clear
                    .frame(width: 72)

                tabGroup(Self.trailingTabs)
            }
            .padding(.horizontal, VaySpacing.sm)
            .padding(.top, VaySpacing.md)
            .padding(.bottom, VaySpacing.sm)
            .background(.ultraThinMaterial)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: VayRadius.xxl,
                    bottomLeadingRadius: VayRadius.xxl,
                    bottomTrailingRadius: VayRadius.xxl,
                    topTrailingRadius: VayRadius.xxl,
                    style: .continuous
                )
            )
            .vayShadow(.card)

            fabButton
                .offset(y: -22)
        }
        .frame(height: 80)
        .padding(.bottom, VaySpacing.xs)
    }

    private func tabGroup(_ tabs: [Tab]) -> some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.rawValue) { tab in
                tabButton(for: tab)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var fabButton: some View {
        Button {
            VayHaptic.medium()
            withAnimation(VayAnimation.springSnappy) {
                showScannerSheet = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.vayPrimary, .vayAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .vayShadow(.glow)

                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(FABButtonStyle())
        .vayAccessibilityLabel("Открыть сканер", hint: "Сканировать штрихкод товара")
    }

    private func tabButton(for tab: Tab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            openTab(tab)
        } label: {
            VStack(spacing: VaySpacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: isSelected ? 22 : 20, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.vayPrimary : Color.secondary)
                    .frame(height: 28)

                Text(tab.title)
                    .font(VayFont.caption(10))
                    .foregroundStyle(isSelected ? Color.vayPrimary : Color.secondary.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .vayAccessibilityLabel(
            "Вкладка \(tab.title)",
            hint: isSelected ? "Текущая вкладка" : "Дважды нажмите для перехода"
        )
    }

    private func openTab(_ tab: Tab) {
        if selectedTab == tab {
            tabRootResetTokens[tab] = UUID()
            return
        }

        tabRootResetTokens[tab] = UUID()
        withAnimation(VayAnimation.springSmooth) {
            selectedTab = tab
        }
    }

    @MainActor
    private func hydrateSettingsStore() async {
        guard let loaded = try? await settingsService.loadSettings() else { return }
        appSettingsStore.update(loaded)
    }
}

struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(VayAnimation.easeOut, value: configuration.isPressed)
    }
}
