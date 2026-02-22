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
    let shoppingListService: ShoppingListService
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

        let shoppingListRepository = ShoppingListRepository(dbQueue: dbQueue)
        let shoppingListService = ShoppingListService(repository: shoppingListRepository)

        let settingsService = SettingsService(
            repository: settingsRepository,
            inventoryRepository: inventoryRepository,
            notificationScheduler: notificationScheduler,
            center: .current()
        )
        let healthKitService = HealthKitService()
        let scannerService = ScannerService()

        var providers: [any BarcodeLookupProvider] = []
        if config.enableLocalBarcodeDB {
            var resolvedPath: String?
            
            if let configPath = config.localBarcodeDBPath, FileManager.default.fileExists(atPath: configPath) {
                resolvedPath = configPath
            } else if let bundleURL = Bundle.main.url(forResource: "local_barcode_db", withExtension: "sqlite") {
                resolvedPath = bundleURL.path
            }
            
            if let finalPath = resolvedPath, let localProvider = try? LocalBarcodeDatabaseProvider(databasePath: finalPath) {
                providers.append(localProvider)
            }
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
        if config.enableEdamam, let appId = config.edamamAppId, let appKey = config.edamamAppKey {
            providers.append(EdamamBarcodeProvider(appId: appId, appKey: appKey))
        }

        var imageSearchProvider: GoogleImageSearchProvider?
        if config.enableGoogleImageSearch, let apiKey = config.googleSearchApiKey, let searchEngineId = config.googleSearchEngineId {
            imageSearchProvider = GoogleImageSearchProvider(apiKey: apiKey, searchEngineId: searchEngineId)
        }

        let barcodeLookupService = BarcodeLookupService(
            inventoryService: inventoryService,
            scannerService: scannerService,
            providers: providers,
            imageSearchProvider: imageSearchProvider,
            policy: config.lookupPolicy
        )

        let persistedSettings = (try? settingsRepository.loadSettings()) ?? .default
        let resolvedRecipeServiceBaseURL = config.recipeServiceBaseURL
        syncGlobalAppearanceSettings(persistedSettings)

        let localRecipeCatalog = LocalRecipeCatalog(datasetPathOverride: config.localRecipeDatasetPath)
        let recipeServiceClient = resolvedRecipeServiceBaseURL.map {
            RecipeServiceClient(baseURL: $0, localCatalog: localRecipeCatalog)
        }

        return AppDependencies(
            inventoryService: inventoryService,
            settingsService: settingsService,
            healthKitService: healthKitService,
            scannerService: scannerService,
            barcodeLookupService: barcodeLookupService,
            recipeServiceClient: recipeServiceClient,
            shoppingListService: shoppingListService
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

    private static func configureImagePipelineIfNeeded() {
        guard !didConfigureImagePipeline else { return }
        didConfigureImagePipeline = true

        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: "com.projectvay.inventoryai.urlcache"
        )

        let dataLoader = DataLoader(configuration: configuration)
        let dataCache = try? DataCache(name: "com.projectvay.inventoryai.nuke")
        ImagePipeline.shared = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = ImageCache.shared
            $0.dataCache = dataCache
            $0.isTaskCoalescingEnabled = true
            $0.isRateLimiterEnabled = true
        }
    }
}
