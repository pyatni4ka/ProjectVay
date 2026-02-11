import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    let inventoryService: any InventoryServiceProtocol
    let settingsService: any SettingsServiceProtocol
    let barcodeLookupService: BarcodeLookupService

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            NavigationStack { HomeView(inventoryService: inventoryService) }
                .tabItem { Label("Что приготовить", systemImage: "sparkles") }
                .tag(RootTab.home)

            NavigationStack {
                InventoryView(
                    inventoryService: inventoryService,
                    barcodeLookupService: barcodeLookupService
                )
            }
                .tabItem { Label("Инвентарь", systemImage: "refrigerator") }
                .tag(RootTab.inventory)

            NavigationStack { MealPlanView() }
                .tabItem { Label("План", systemImage: "calendar") }
                .tag(RootTab.mealPlan)

            NavigationStack { ProgressView() }
                .tabItem { Label("Прогресс", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(RootTab.progress)

            NavigationStack { SettingsView(settingsService: settingsService) }
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(RootTab.settings)
        }
    }
}
