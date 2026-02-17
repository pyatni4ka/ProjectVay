import SwiftUI

@main
struct InventoryAIApp: App {
    private let dependencies: AppDependencies
    @StateObject private var coordinator: AppCoordinator
    
    @AppStorage("preferredColorScheme") private var storedColorScheme: Int = 0
    @AppStorage("motionLevel") private var motionLevelRaw: String = AppSettings.MotionLevel.full.rawValue
    @AppStorage("enableAnimations") private var legacyAnimationsEnabled: Bool = true

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
            .animation(isAnimationsEnabled ? .default : .none, value: isAnimationsEnabled)
            .transaction { transaction in
                if !isAnimationsEnabled {
                    transaction.disablesAnimations = true
                }
            }
            .task {
                await coordinator.bootstrap()
            }
        }
    }

    private var isAnimationsEnabled: Bool {
        if let motionLevel = AppSettings.MotionLevel(rawValue: motionLevelRaw) {
            return motionLevel != .off
        }
        return legacyAnimationsEnabled
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
