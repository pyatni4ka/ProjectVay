import SwiftUI

@main
struct InventoryAIApp: App {
    private let dependencies: AppDependencies
    @StateObject private var coordinator: AppCoordinator
    
    @AppStorage("preferredColorScheme") private var storedColorScheme: Int = 0
    @AppStorage("enableAnimations") private var animationsEnabled: Bool = true

    init() {
        do {
            let resolvedDependencies = try AppDependencies.makeLive()
            dependencies = resolvedDependencies
            _coordinator = StateObject(
                wrappedValue: AppCoordinator(settingsService: resolvedDependencies.settingsService)
            )
        } catch {
            fatalError("Не удалось инициализировать базу данных: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if coordinator.isInitialized {
                    if coordinator.isOnboardingCompleted {
                        RootTabView(
                            inventoryService: dependencies.inventoryService,
                            settingsService: dependencies.settingsService,
                            healthKitService: dependencies.healthKitService,
                            barcodeLookupService: dependencies.barcodeLookupService,
                            recipeServiceClient: dependencies.recipeServiceClient
                        )
                    } else {
                        NavigationStack {
                            OnboardingFlowView(
                                settingsService: dependencies.settingsService,
                                onComplete: {
                                    await coordinator.bootstrap()
                                    coordinator.completeOnboarding()
                                }
                            )
                        }
                    }
                } else {
                    SwiftUI.ProgressView("Подготовка данных...")
                }
            }
            .environmentObject(coordinator)
            .preferredColorScheme(colorScheme)
            .animation(animationsEnabled ? .default : .none, value: animationsEnabled)
            .task {
                await coordinator.bootstrap()
            }
        }
    }
    
    private var colorScheme: ColorScheme? {
        switch storedColorScheme {
        case 0:
            return nil
        case 1:
            return .light
        case 2:
            return .dark
        default:
            return nil
        }
    }
}
