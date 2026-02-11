import Foundation
import GRDB

protocol SettingsRepositoryProtocol: Sendable {
    func loadSettings() throws -> AppSettings
    func saveSettings(_ settings: AppSettings) throws
    func isOnboardingCompleted() throws -> Bool
    func setOnboardingCompleted(_ completed: Bool) throws
}

final class SettingsRepository: SettingsRepositoryProtocol {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func loadSettings() throws -> AppSettings {
        if let settings = try dbQueue.read({ db in
            try AppSettingsRecord.fetchOne(db, key: AppSettingsRecord.singletonID)?.asDomainSettings()
        }) {
            return settings
        }

        try dbQueue.write { db in
            var fallback = try AppSettingsRecord(settings: .default, onboardingCompleted: false)
            try fallback.insert(db)
        }

        return AppSettings.default
    }

    func saveSettings(_ settings: AppSettings) throws {
        try dbQueue.write { db in
            let completed = try Bool.fetchOne(
                db,
                sql: "SELECT onboarding_completed FROM app_settings WHERE id = ?",
                arguments: [AppSettingsRecord.singletonID]
            ) ?? false

            var record = try AppSettingsRecord(settings: settings, onboardingCompleted: completed)
            try record.save(db)
        }
    }

    func isOnboardingCompleted() throws -> Bool {
        try dbQueue.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT onboarding_completed FROM app_settings WHERE id = ?",
                arguments: [AppSettingsRecord.singletonID]
            ) ?? false
        }
    }

    func setOnboardingCompleted(_ completed: Bool) throws {
        try dbQueue.write { db in
            if var record = try AppSettingsRecord.fetchOne(db, key: AppSettingsRecord.singletonID) {
                record.onboardingCompleted = completed
                try record.update(db)
            } else {
                var record = try AppSettingsRecord(settings: .default, onboardingCompleted: completed)
                try record.insert(db)
            }
        }
    }
}
