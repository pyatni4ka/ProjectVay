import Foundation
import UserNotifications

protocol SettingsServiceProtocol {
    func loadSettings() async throws -> AppSettings
    func saveSettings(_ settings: AppSettings) async throws -> AppSettings
    func isOnboardingCompleted() async throws -> Bool
    func setOnboardingCompleted() async throws
    func requestNotificationAuthorization() async throws -> Bool
}

actor SettingsService: SettingsServiceProtocol {
    private let repository: SettingsRepositoryProtocol
    private let inventoryRepository: InventoryRepositoryProtocol?
    private let notificationScheduler: (any NotificationScheduling)?
    private let center: UNUserNotificationCenter?

    init(
        repository: SettingsRepositoryProtocol,
        inventoryRepository: InventoryRepositoryProtocol? = nil,
        notificationScheduler: (any NotificationScheduling)? = nil,
        center: UNUserNotificationCenter? = nil
    ) {
        self.repository = repository
        self.inventoryRepository = inventoryRepository
        self.notificationScheduler = notificationScheduler
        self.center = center
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
}
