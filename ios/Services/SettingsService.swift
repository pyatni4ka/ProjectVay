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
    private let center: UNUserNotificationCenter

    init(repository: SettingsRepositoryProtocol, center: UNUserNotificationCenter = .current()) {
        self.repository = repository
        self.center = center
    }

    func loadSettings() async throws -> AppSettings {
        try repository.loadSettings().normalized()
    }

    func saveSettings(_ settings: AppSettings) async throws -> AppSettings {
        let normalized = settings.normalized()
        try repository.saveSettings(normalized)
        return normalized
    }

    func isOnboardingCompleted() async throws -> Bool {
        try repository.isOnboardingCompleted()
    }

    func setOnboardingCompleted() async throws {
        try repository.setOnboardingCompleted(true)
    }

    func requestNotificationAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
