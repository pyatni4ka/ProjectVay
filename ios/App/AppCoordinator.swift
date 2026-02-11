import Foundation

final class AppCoordinator: ObservableObject {
    @Published var isOnboardingCompleted: Bool = false
    @Published var selectedTab: RootTab = .home
}

enum RootTab: Hashable {
    case home
    case inventory
    case mealPlan
    case progress
    case settings
}
