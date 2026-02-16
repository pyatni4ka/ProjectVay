import AppIntents

struct InventoryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddProductIntent(),
            phrases: [
                "Добавь продукт в \(.applicationName)",
                "Добавить продукт в \(.applicationName)",
                "Положи продукт в \(.applicationName)"
            ],
            shortTitle: "Добавить продукт",
            systemImageName: "plus.circle.fill"
        )
        
        AppShortcut(
            intent: CheckExpiryIntent(),
            phrases: [
                "Что скоро испортится в \(.applicationName)",
                "Проверь сроки годности в \(.applicationName)",
                "Какие продукты заканчиваются в \(.applicationName)"
            ],
            shortTitle: "Срок годности",
            systemImageName: "exclamationmark.triangle.fill"
        )
        
        AppShortcut(
            intent: GeneratePlanIntent(),
            phrases: [
                "Сгенерируй план питания в \(.applicationName)",
                "Создай план питания в \(.applicationName)",
                "Что приготовить в \(.applicationName)"
            ],
            shortTitle: "План питания",
            systemImageName: "fork.knife"
        )
        
        AppShortcut(
            intent: GetCaloriesIntent(),
            phrases: [
                "Сколько калорий в \(.applicationName)",
                "Сколько осталось калорий в \(.applicationName)",
                "Мой прогресс питания в \(.applicationName)"
            ],
            shortTitle: "Калории",
            systemImageName: "flame.fill"
        )
    }
}
