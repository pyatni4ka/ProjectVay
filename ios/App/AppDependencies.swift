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
        // Free public sources are primary defaults; optional providers remain opt-in.
        if config.enableOpenFoodFacts {
            providers.append(OpenFoodFactsBarcodeProvider())
        }
        if config.enableBarcodeListRu {
            providers.append(BarcodeListRuProvider())
        }
        if config.enableEANDB {
            providers.append(EANDBBarcodeProvider(apiKey: config.eanDBApiKey))
        }
        if config.enableRFProvider, let rfLookupBaseURL = config.rfLookupBaseURL {
            providers.append(RFBarcodeProvider(endpoint: rfLookupBaseURL))
        }

        let barcodeLookupService = BarcodeLookupService(
            inventoryService: inventoryService,
            scannerService: scannerService,
            providers: providers,
            policy: config.lookupPolicy
        )

        let persistedSettings = (try? settingsRepository.loadSettings()) ?? .default
        let overrideRecipeServiceURL = resolvedRecipeServiceURL(
            from: persistedSettings.recipeServiceBaseURLOverride,
            allowInsecure: config.allowInsecureRecipeServiceURL
        )
        let resolvedRecipeServiceBaseURL = overrideRecipeServiceURL ?? config.recipeServiceBaseURL

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

    private static func resolvedRecipeServiceURL(from rawValue: String?, allowInsecure: Bool) -> URL? {
        guard
            let raw = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            let url = URL(string: raw),
            let scheme = url.scheme?.lowercased()
        else {
            return nil
        }

        if allowInsecure {
            return scheme == "http" || scheme == "https" ? url : nil
        }

        return scheme == "https" ? url : nil
    }
}
