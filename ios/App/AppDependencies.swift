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
        if config.enableEANDB {
            providers.append(EANDBBarcodeProvider(apiKey: config.eanDBApiKey))
        }
        if config.enableRFProvider, let rfLookupBaseURL = config.rfLookupBaseURL {
            providers.append(RFBarcodeProvider(endpoint: rfLookupBaseURL))
        }
        if config.enableOpenFoodFacts {
            providers.append(OpenFoodFactsBarcodeProvider())
        }

        let barcodeLookupService = BarcodeLookupService(
            inventoryService: inventoryService,
            scannerService: scannerService,
            providers: providers,
            policy: config.lookupPolicy
        )

        let recipeServiceClient = config.recipeServiceBaseURL.map {
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
}
