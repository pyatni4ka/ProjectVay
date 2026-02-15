import Foundation
import UserNotifications

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var isInitialized: Bool = false
    @Published var isOnboardingCompleted: Bool = false
    @Published var selectedTab: RootTab = .home

    private let settingsService: any SettingsServiceProtocol

    init(settingsService: any SettingsServiceProtocol) {
        self.settingsService = settingsService
    }

    func bootstrap() async {
        guard !isInitialized else { return }

        registerNotificationCategories()

        do {
            isOnboardingCompleted = try await settingsService.isOnboardingCompleted()
        } catch {
            isOnboardingCompleted = false
        }

        isInitialized = true
    }

    func completeOnboarding() {
        isOnboardingCompleted = true
    }

    // MARK: - Notification Categories

    private func registerNotificationCategories() {
        let consumedAction = UNNotificationAction(
            identifier: "CONSUMED_ACTION",
            title: "✅ Съедено",
            options: [.destructive]
        )
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "⏰ Напомнить через день",
            options: []
        )
        let expiryCategory = UNNotificationCategory(
            identifier: "EXPIRY_ALERT",
            actions: [consumedAction, snoozeAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Истекает срок годности",
            categorySummaryFormat: "%u продуктов скоро просрочатся",
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([expiryCategory])
    }
}

enum RootTab: Hashable {
    case home
    case inventory
    case mealPlan
    case progress
    case settings
}
