import Foundation
import UserNotifications

struct AppDependencies {
    let inventoryService: InventoryService
    let settingsService: SettingsService

    static func makeLive() throws -> AppDependencies {
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
        return AppDependencies(inventoryService: inventoryService, settingsService: settingsService)
    }
}
