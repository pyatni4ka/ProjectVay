import Foundation
import GRDB

enum AppDatabase {
    static func makeDatabaseQueue() throws -> DatabaseQueue {
        let fileManager = FileManager.default
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("InventoryAI", isDirectory: true)

        if !fileManager.fileExists(atPath: supportDirectory.path) {
            try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        }

        let databaseURL = supportDirectory.appendingPathComponent("inventory.sqlite")

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.label = "InventoryAI.Database"

        let dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try AppMigrations.migrator.migrate(dbQueue)
        return dbQueue
    }

    static func makeInMemoryQueue() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(path: ":memory:", configuration: configuration)
        try AppMigrations.migrator.migrate(dbQueue)
        return dbQueue
    }
}
