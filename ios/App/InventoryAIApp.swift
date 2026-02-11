import SwiftUI

@main
struct InventoryAIApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(coordinator)
                .preferredColorScheme(.light)
        }
    }
}
