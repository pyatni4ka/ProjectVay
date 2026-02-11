import Foundation
import UserNotifications

struct AppDependencies {
    let inventoryService: InventoryService
    let settingsService: SettingsService
    let scannerService: ScannerService
    let barcodeLookupService: BarcodeLookupService

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

        let settingsService = SettingsService(repository: settingsRepository)
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

        return AppDependencies(
            inventoryService: inventoryService,
            settingsService: settingsService,
            scannerService: scannerService,
            barcodeLookupService: barcodeLookupService
        )
    }
}
