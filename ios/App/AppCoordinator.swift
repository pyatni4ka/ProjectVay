import Foundation

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
}

enum RootTab: Hashable {
    case home
    case inventory
    case mealPlan
    case progress
    case settings
}
