import Foundation

struct Achievement: Identifiable, Codable, Equatable {
    let id: String
    let icon: String
    let title: String
    let description: String
    let requiredCount: Int
    
    var isUnlocked: Bool
    var currentProgress: Int
    var unlockedAt: Date?
    
    var progress: Double {
        guard requiredCount > 0 else { return 1.0 }
        return min(1.0, Double(currentProgress) / Double(requiredCount))
    }
    
    static func defaultAchievements() -> [Achievement] {
        [
            Achievement(
                id: "first_product",
                icon: "🥚",
                title: "Первая партия",
                description: "Добавить первый продукт в инвентарь",
                requiredCount: 1,
                isUnlocked: false,
                currentProgress: 0,
                unlockedAt: nil
            ),
            Achievement(
                id: "stocked_up",
                icon: "📦",
                title: "Запасливый",
                description: "Иметь 10 продуктов в инвентаре",
                requiredCount: 10,
                isUnlocked: false,
                currentProgress: 0,
                unlockedAt: nil
            ),
            Achievement(
                id: "planner",
                icon: "👨‍🍳",
                title: "Планировщик",
                description: "Сгенерировать 5 планов питания",
                requiredCount: 5,
                isUnlocked: false,
                currentProgress: 0,
                unlockedAt: nil
            ),
            Achievement(
                id: "streak_7",
                icon: "🔥",
                title: "Серия 7 дней",
                description: "Использовать приложение 7 дней подряд",
                requiredCount: 7,
                isUnlocked: false,
                currentProgress: 0,
                unlockedAt: nil
            ),
            Achievement(
                id: "vigilant",
                icon: "⚠️",
                title: "Бдительный",
                description: "Отметить 10 продуктов как 'скоро истекает'",
                requiredCount: 10,
                isUnlocked: false,
                currentProgress: 0,
                unlockedAt: nil
            ),
            Achievement(
                id: "master",
                icon: "🏆",
                title: "Мастер",
                description: "Получить все достижения",
                requiredCount: 5,
                isUnlocked: false,
                currentProgress: 0,
                unlockedAt: nil
            )
        ]
    }
}

struct UserStats: Codable, Equatable {
    var totalProductsAdded: Int
    var maxInventoryCount: Int
    var mealPlansGenerated: Int
    var currentStreak: Int
    var longestStreak: Int
    var expiryWarningsMarked: Int
    var lastActiveDate: Date
    var firstLaunchDate: Date
    
    static var initial: UserStats {
        UserStats(
            totalProductsAdded: 0,
            maxInventoryCount: 0,
            mealPlansGenerated: 0,
            currentStreak: 0,
            longestStreak: 0,
            expiryWarningsMarked: 0,
            lastActiveDate: Date(),
            firstLaunchDate: Date()
        )
    }
}
