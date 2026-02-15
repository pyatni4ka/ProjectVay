import SwiftUI

struct RootTabView: View {
    let inventoryService: any InventoryServiceProtocol
    let settingsService: any SettingsServiceProtocol
    let healthKitService: HealthKitService
    let barcodeLookupService: BarcodeLookupService
    let recipeServiceClient: RecipeServiceClient?

    enum Tab: Int, CaseIterable {
        case home
        case inventory
        case mealPlan
        case progress
        case settings

        var icon: String {
            switch self {
            case .home: return "house"
            case .inventory: return "refrigerator"
            case .mealPlan: return "fork.knife"
            case .progress: return "chart.line.uptrend.xyaxis"
            case .settings: return "gearshape"
            }
        }

        var selectedIcon: String {
            switch self {
            case .home: return "house.fill"
            case .inventory: return "refrigerator.fill"
            case .mealPlan: return "fork.knife.circle.fill"
            case .progress: return "chart.line.uptrend.xyaxis.circle.fill"
            case .settings: return "gearshape.fill"
            }
        }

        var title: String {
            switch self {
            case .home: return "Главная"
            case .inventory: return "Запасы"
            case .mealPlan: return "План"
            case .progress: return "Прогресс"
            case .settings: return "Ещё"
            }
        }
    }

    @State private var selectedTab: Tab = .home
    @State private var previousTab: Tab = .home
    @State private var tabBarVisible = true
    @State private var showScannerSheet = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(
                        inventoryService: inventoryService,
                        settingsService: settingsService,
                        onOpenScanner: { showScannerSheet = true }
                    )
                }
                .tag(Tab.home)

                NavigationStack {
                    InventoryView(
                        inventoryService: inventoryService,
                        onOpenScanner: { showScannerSheet = true }
                    )
                }
                .tag(Tab.inventory)

                NavigationStack {
                    MealPlanView(
                        inventoryService: inventoryService,
                        settingsService: settingsService,
                        healthKitService: healthKitService,
                        recipeServiceClient: recipeServiceClient,
                        onOpenScanner: { showScannerSheet = true }
                    )
                }
                .tag(Tab.mealPlan)

                NavigationStack {
                    ProgressTrackingView(
                        inventoryService: inventoryService,
                        settingsService: settingsService
                    )
                }
                .tag(Tab.progress)

                NavigationStack {
                    SettingsView(settingsService: settingsService)
                }
                .tag(Tab.settings)
            }
            .toolbar(.hidden, for: .tabBar)

            if tabBarVisible {
                customTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
        .onChange(of: selectedTab) { _, newValue in
            if newValue != previousTab {
                VayHaptic.selection()
                previousTab = newValue
            }
        }
        .vayDynamicType()
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, VaySpacing.sm)
        .padding(.top, VaySpacing.md)
        .padding(.bottom, VaySpacing.xxl)
        .background(.ultraThinMaterial)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: VayRadius.xxl,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: VayRadius.xxl,
                style: .continuous
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
        }
        .vayShadow(.card)
    }

    private func tabButton(for tab: Tab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(VayAnimation.springSnappy) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: VaySpacing.xs) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.vayPrimary : Color.secondary)
                    .scaleEffect(isSelected ? 1.15 : 1.0)
                    .symbolEffect(.bounce, value: isSelected)
                    .frame(height: 32)

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
}
