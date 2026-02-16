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
    @State private var showScannerSheet = false
    @State private var showReceiptScanSheet = false

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
        .sheet(isPresented: $showScannerSheet, onDismiss: {
            postInventoryDidChange()
        }) {
            NavigationStack {
                ScannerView(
                    inventoryService: inventoryService,
                    barcodeLookupService: barcodeLookupService,
                    initialMode: .add,
                    onInventoryChanged: {
                        postInventoryDidChange()
                    }
                )
            }
        }
        .sheet(isPresented: $showReceiptScanSheet, onDismiss: {
            postInventoryDidChange()
        }) {
            NavigationStack {
                ReceiptScanView(
                    inventoryService: inventoryService,
                    onItemsAdded: {
                        postInventoryDidChange()
                    }
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
        .vayDynamicType()
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
                            onOpenMealPlan: { selectedTab = .mealPlan },
                            onOpenInventory: { selectedTab = .inventory }
                        )
                    }
                case .inventory:
                    NavigationStack {
                        InventoryView(
                            inventoryService: inventoryService,
                            onOpenScanner: { showScannerSheet = true },
                            onOpenReceiptScan: { showReceiptScanSheet = true }
                        )
                    }
                case .mealPlan:
                    NavigationStack {
                        MealPlanView(
                            inventoryService: inventoryService,
                            settingsService: settingsService,
                            healthKitService: healthKitService,
                            recipeServiceClient: recipeServiceClient,
                            onOpenScanner: { showScannerSheet = true }
                        )
                    }
                case .settings:
                    NavigationStack {
                        SettingsView(
                            settingsService: settingsService,
                            inventoryService: inventoryService,
                            healthKitService: healthKitService
                        )
                    }
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
            withAnimation(VayAnimation.springSmooth) {
                selectedTab = tab
            }
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

    private func postInventoryDidChange() {
        NotificationCenter.default.post(name: .inventoryDidChange, object: nil)
    }
}

struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(VayAnimation.easeOut, value: configuration.isPressed)
    }
}
