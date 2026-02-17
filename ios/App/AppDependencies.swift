import Foundation
import UserNotifications

struct AppDependencies {
    let inventoryService: InventoryService
    let settingsService: SettingsService
    let healthKitService: HealthKitService
    let scannerService: ScannerService
    let barcodeLookupService: BarcodeLookupService
    let recipeServiceClient: RecipeServiceClient?

    static func makeLive() throws -> AppDependencies {
        let config = AppConfig.live()
        let dbQueue = try AppDatabase.makeDatabaseQueue()
        let inventoryRepository = InventoryRepository(dbQueue: dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)
        let notificationScheduler = NotificationScheduler(center: .current())

        let inventoryService = InventoryService(
            repository: inventoryRepository,
            settingsRepository: settingsRepository,
            notificationScheduler: notificationScheduler
        )

        let settingsService = SettingsService(
            repository: settingsRepository,
            inventoryRepository: inventoryRepository,
            notificationScheduler: notificationScheduler,
            center: .current()
        )
        let healthKitService = HealthKitService()
        let scannerService = ScannerService()

        var providers: [any BarcodeLookupProvider] = []
        if
            config.enableLocalBarcodeDB,
            let localBarcodeDBPath = config.localBarcodeDBPath,
            FileManager.default.fileExists(atPath: localBarcodeDBPath),
            let localProvider = try? LocalBarcodeDatabaseProvider(databasePath: localBarcodeDBPath)
        {
            providers.append(localProvider)
        }

        // Free public sources are primary defaults.
        if config.enableOpenFoodFacts {
            providers.append(OpenFoodFactsBarcodeProvider())
        }
        if config.enableOpenBeautyFacts {
            providers.append(OpenBeautyFactsBarcodeProvider())
        }
        if config.enableOpenPetFoodFacts {
            providers.append(OpenPetFoodFactsBarcodeProvider())
        }
        if config.enableOpenProductsFacts {
            providers.append(OpenProductsFactsBarcodeProvider())
        }
        if config.enableBarcodeListRu {
            providers.append(BarcodeListRuProvider())
        }
        if config.enableGoUPC {
            providers.append(GoUPCBarcodeProvider())
        }

        let barcodeLookupService = BarcodeLookupService(
            inventoryService: inventoryService,
            scannerService: scannerService,
            providers: providers,
            policy: config.lookupPolicy
        )

        let persistedSettings = (try? settingsRepository.loadSettings()) ?? .default
        let resolvedRecipeServiceBaseURL = config.recipeServiceBaseURL
        syncGlobalAppearanceSettings(persistedSettings)

        let recipeServiceClient = resolvedRecipeServiceBaseURL.map {
            RecipeServiceClient(baseURL: $0)
        }

        return AppDependencies(
            inventoryService: inventoryService,
            settingsService: settingsService,
            healthKitService: healthKitService,
            scannerService: scannerService,
            barcodeLookupService: barcodeLookupService,
            recipeServiceClient: recipeServiceClient
        )
    }

    private static func syncGlobalAppearanceSettings(_ settings: AppSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.preferredColorScheme ?? 0, forKey: "preferredColorScheme")
        defaults.set(settings.enableAnimations, forKey: "enableAnimations")
        defaults.set(settings.motionLevel.rawValue, forKey: "motionLevel")
        defaults.set(settings.hapticsEnabled, forKey: "hapticsEnabled")
        defaults.set(settings.showHealthCardOnHome, forKey: "showHealthCardOnHome")
    }
}
