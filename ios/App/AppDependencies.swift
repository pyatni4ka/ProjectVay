import Foundation
import UserNotifications
import Nuke

struct AppDependencies {
    let inventoryService: InventoryService
    let settingsService: SettingsService
    let healthKitService: HealthKitService
    let scannerService: ScannerService
    let barcodeLookupService: BarcodeLookupService
    let recipeServiceClient: RecipeServiceClient?
    private static var didConfigureImagePipeline = false

    static func makeLive() throws -> AppDependencies {
        configureImagePipelineIfNeeded()

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

    private static func configureImagePipelineIfNeeded() {
        guard !didConfigureImagePipeline else { return }
        didConfigureImagePipeline = true

        var configuration = ImagePipeline.Configuration()
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.requestCachePolicy = .returnCacheDataElseLoad
        sessionConfiguration.urlCache = URLCache(
            memoryCapacity: 40 * 1024 * 1024,
            diskCapacity: 250 * 1024 * 1024,
            directory: nil
        )
        configuration.dataLoader = DataLoader(configuration: sessionConfiguration)
        configuration.dataCache = try? DataCache(name: "com.projectvay.inventoryai.images")
        configuration.imageCache = ImageCache.shared
        ImagePipeline.shared = ImagePipeline(configuration: configuration)
    }
}
