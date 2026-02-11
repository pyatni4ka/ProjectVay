import Foundation
import UserNotifications

enum SettingsServiceError: LocalizedError {
    case inventoryUnavailable
    case unableToPrepareExportDirectory

    var errorDescription: String? {
        switch self {
        case .inventoryUnavailable:
            return "Локальное хранилище инвентаря недоступно."
        case .unableToPrepareExportDirectory:
            return "Не удалось подготовить папку для экспорта."
        }
    }
}

struct LocalDataExportSnapshot: Codable {
    struct Metadata: Codable {
        var schemaVersion: Int
        var appName: String
        var generatedAt: Date
    }

    var metadata: Metadata
    var settings: AppSettings
    var products: [Product]
    var batches: [Batch]
    var priceEntries: [PriceEntry]
    var inventoryEvents: [InventoryEvent]
}

protocol SettingsServiceProtocol {
    func loadSettings() async throws -> AppSettings
    func saveSettings(_ settings: AppSettings) async throws -> AppSettings
    func isOnboardingCompleted() async throws -> Bool
    func setOnboardingCompleted() async throws
    func requestNotificationAuthorization() async throws -> Bool
    func exportLocalData() async throws -> URL
    func deleteAllLocalData(resetOnboarding: Bool) async throws
}

actor SettingsService: SettingsServiceProtocol {
    private let repository: SettingsRepositoryProtocol
    private let inventoryRepository: InventoryRepositoryProtocol?
    private let notificationScheduler: (any NotificationScheduling)?
    private let center: UNUserNotificationCenter?
    private let fileManager: FileManager
    private let exportsDirectoryURL: URL?

    init(
        repository: SettingsRepositoryProtocol,
        inventoryRepository: InventoryRepositoryProtocol? = nil,
        notificationScheduler: (any NotificationScheduling)? = nil,
        center: UNUserNotificationCenter? = nil,
        fileManager: FileManager = .default,
        exportsDirectoryURL: URL? = nil
    ) {
        self.repository = repository
        self.inventoryRepository = inventoryRepository
        self.notificationScheduler = notificationScheduler
        self.center = center
        self.fileManager = fileManager
        self.exportsDirectoryURL = exportsDirectoryURL
    }

    func loadSettings() async throws -> AppSettings {
        try repository.loadSettings().normalized()
    }

    func saveSettings(_ settings: AppSettings) async throws -> AppSettings {
        let normalized = settings.normalized()
        try repository.saveSettings(normalized)
        try await rescheduleAllExpiryNotifications(settings: normalized)
        return normalized
    }

    func isOnboardingCompleted() async throws -> Bool {
        try repository.isOnboardingCompleted()
    }

    func setOnboardingCompleted() async throws {
        try repository.setOnboardingCompleted(true)
    }

    func requestNotificationAuthorization() async throws -> Bool {
        guard let center else { return false }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func exportLocalData() async throws -> URL {
        guard let inventoryRepository else {
            throw SettingsServiceError.inventoryUnavailable
        }

        let settings = try repository.loadSettings().normalized()
        let products = try inventoryRepository.listProducts(location: nil, search: nil)
        let batches = try inventoryRepository.listBatches(productId: nil)
        let events = try inventoryRepository.listInventoryEvents(productId: nil)

        var prices: [PriceEntry] = []
        for product in products {
            let history = try inventoryRepository.listPriceHistory(productId: product.id)
            prices.append(contentsOf: history)
        }

        let snapshot = LocalDataExportSnapshot(
            metadata: .init(
                schemaVersion: 1,
                appName: "InventoryAI",
                generatedAt: Date()
            ),
            settings: settings,
            products: products,
            batches: batches,
            priceEntries: prices.sorted(by: { $0.date > $1.date }),
            inventoryEvents: events
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let directory = try resolveExportsDirectoryURL()
        let filename = "inventory-export-\(exportTimestampString(Date())).json"
        let fileURL = directory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func deleteAllLocalData(resetOnboarding: Bool = true) async throws {
        guard let inventoryRepository else {
            throw SettingsServiceError.inventoryUnavailable
        }

        let batches = try inventoryRepository.listBatches(productId: nil)
        if let notificationScheduler {
            for batch in batches {
                try await notificationScheduler.cancelExpiryNotifications(batchId: batch.id)
            }
        }

        center?.removeAllPendingNotificationRequests()
        center?.removeAllDeliveredNotifications()

        try inventoryRepository.deleteAllInventoryData()
        try repository.saveSettings(.default)
        try repository.setOnboardingCompleted(!resetOnboarding)
    }

    private func rescheduleAllExpiryNotifications(settings: AppSettings) async throws {
        guard
            let inventoryRepository,
            let notificationScheduler
        else {
            return
        }

        let products = try inventoryRepository.listProducts(location: nil, search: nil)
        let productByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        let batches = try inventoryRepository.listBatches(productId: nil)

        for batch in batches {
            guard
                batch.expiryDate != nil,
                let product = productByID[batch.productId]
            else {
                continue
            }
            try await notificationScheduler.rescheduleExpiryNotifications(
                for: batch,
                product: product,
                settings: settings
            )
        }
    }

    private func resolveExportsDirectoryURL() throws -> URL {
        if let exportsDirectoryURL {
            try ensureDirectory(at: exportsDirectoryURL)
            return exportsDirectoryURL
        }

        let appSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootDirectory = appSupportDirectory.appendingPathComponent("InventoryAI", isDirectory: true)
        let exportsDirectory = rootDirectory.appendingPathComponent("Exports", isDirectory: true)
        try ensureDirectory(at: exportsDirectory)
        return exportsDirectory
    }

    private func ensureDirectory(at directoryURL: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw SettingsServiceError.unableToPrepareExportDirectory
            }
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func exportTimestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.string(from: date)
    }
}
