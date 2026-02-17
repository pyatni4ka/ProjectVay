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
            // Inventory scale
            make(id: "first_product", icon: "🥚", title: "Первая партия", description: "Добавить первый продукт в инвентарь", requiredCount: 1),
            make(id: "products_10", icon: "📦", title: "Запасливый", description: "Иметь 10 продуктов", requiredCount: 10),
            make(id: "products_25", icon: "🧊", title: "Холодный склад", description: "Иметь 25 продуктов", requiredCount: 25),
            make(id: "products_50", icon: "🏬", title: "Мини-склад", description: "Иметь 50 продуктов", requiredCount: 50),
            make(id: "products_100", icon: "🏭", title: "Логист", description: "Иметь 100 продуктов", requiredCount: 100),

            // Meal planning
            make(id: "planner_1", icon: "👨‍🍳", title: "Первый план", description: "Сгенерировать план питания", requiredCount: 1),
            make(id: "planner_5", icon: "📅", title: "Планировщик", description: "Сгенерировать 5 планов питания", requiredCount: 5),
            make(id: "planner_15", icon: "🗓️", title: "Системный подход", description: "Сгенерировать 15 планов", requiredCount: 15),
            make(id: "planner_30", icon: "🧠", title: "Стратег", description: "Сгенерировать 30 планов", requiredCount: 30),

            // Streaks
            make(id: "streak_3", icon: "🔥", title: "Разгон", description: "Серия 3 дня", requiredCount: 3),
            make(id: "streak_7", icon: "🔥", title: "Серия 7 дней", description: "Использовать приложение 7 дней подряд", requiredCount: 7),
            make(id: "streak_14", icon: "⚡️", title: "Серия 14 дней", description: "Использовать приложение 14 дней подряд", requiredCount: 14),
            make(id: "streak_30", icon: "🌋", title: "Серия 30 дней", description: "Использовать приложение 30 дней подряд", requiredCount: 30),
            make(id: "streak_90", icon: "🏅", title: "Железная дисциплина", description: "Серия 90 дней", requiredCount: 90),

            // Expiry/loss prevention
            make(id: "vigilant_10", icon: "⚠️", title: "Бдительный", description: "Отметить 10 позиций по срокам", requiredCount: 10),
            make(id: "vigilant_50", icon: "🛡️", title: "Инспектор", description: "Отметить 50 позиций по срокам", requiredCount: 50),
            make(id: "vigilant_100", icon: "🛰️", title: "Радар кухни", description: "Отметить 100 позиций по срокам", requiredCount: 100),

            // Economy progression (derived from level/xp counters)
            make(id: "xp_500", icon: "⭐️", title: "Первые очки", description: "Набрать 500 XP", requiredCount: 500),
            make(id: "xp_1500", icon: "🌟", title: "На подъёме", description: "Набрать 1500 XP", requiredCount: 1500),
            make(id: "xp_5000", icon: "💫", title: "Эксперт кухни", description: "Набрать 5000 XP", requiredCount: 5000),
            make(id: "xp_12000", icon: "✨", title: "Легенда кухни", description: "Набрать 12000 XP", requiredCount: 12000),

            // Quests
            make(id: "quests_daily_10", icon: "🎯", title: "Ежедневник", description: "Закрыть 10 дневных квестов", requiredCount: 10),
            make(id: "quests_daily_50", icon: "🎯", title: "Режим фокуса", description: "Закрыть 50 дневных квестов", requiredCount: 50),
            make(id: "quests_weekly_8", icon: "🧭", title: "Недельный ритм", description: "Закрыть 8 недельных квестов", requiredCount: 8),
            make(id: "quests_weekly_24", icon: "🗺️", title: "Долгий цикл", description: "Закрыть 24 недельных квеста", requiredCount: 24),

            // Anti-loss streak (days without write-off)
            make(id: "no_loss_3", icon: "🍃", title: "Без потерь 3", description: "3 дня без потерь", requiredCount: 3),
            make(id: "no_loss_7", icon: "🌱", title: "Без потерь 7", description: "7 дней без потерь", requiredCount: 7),
            make(id: "no_loss_14", icon: "🌿", title: "Без потерь 14", description: "14 дней без потерь", requiredCount: 14),
            make(id: "no_loss_30", icon: "🌳", title: "Без потерь 30", description: "30 дней без потерь", requiredCount: 30),

            // Body & diet adherence
            make(id: "body_goal_set", icon: "⚖️", title: "Фокус на цели", description: "Указать желаемый вес", requiredCount: 1),
            make(id: "diet_profile_switch_5", icon: "🥗", title: "Диет-архитектор", description: "Сменить профиль диеты 5 раз", requiredCount: 5),
            make(id: "macro_manual_10", icon: "📐", title: "Точный расчёт", description: "10 дней в ручном КБЖУ", requiredCount: 10),
            make(id: "macro_auto_20", icon: "🤖", title: "Автопилот", description: "20 дней в авто-режиме КБЖУ", requiredCount: 20),

            // Shopping intelligence
            make(id: "price_entries_20", icon: "🧾", title: "Ценовой архив", description: "Сохранить 20 цен", requiredCount: 20),
            make(id: "price_entries_100", icon: "📊", title: "Аналитик цен", description: "Сохранить 100 цен", requiredCount: 100),
            make(id: "receipt_scans_10", icon: "🛒", title: "Чек-сканер", description: "Отсканировать 10 чеков", requiredCount: 10),
            make(id: "receipt_scans_50", icon: "🧮", title: "Финконтроль", description: "Отсканировать 50 чеков", requiredCount: 50),
            make(id: "receipt_scans_100", icon: "🏪", title: "Суперкасса", description: "Отсканировать 100 чеков", requiredCount: 100),
            make(id: "price_entries_250", icon: "📈", title: "Ценовой радар", description: "Сохранить 250 цен", requiredCount: 250),
            make(id: "planner_60", icon: "🧩", title: "План-мастер", description: "Сгенерировать 60 планов", requiredCount: 60),
            make(id: "streak_180", icon: "🏔️", title: "Полгода ритма", description: "Серия 180 дней", requiredCount: 180),
            make(id: "no_loss_60", icon: "🌲", title: "Без потерь 60", description: "60 дней без потерь", requiredCount: 60),

            // Completion/meta
            make(id: "kitchen_marathon", icon: "🥇", title: "Кухонный марафон", description: "Открыть 30 достижений", requiredCount: 30),
            make(id: "kitchen_elite", icon: "👑", title: "Кухонная элита", description: "Открыть 40 достижений", requiredCount: 40),
            make(id: "master", icon: "🏆", title: "Мастер", description: "Получить все достижения", requiredCount: 44)
        ]
    }

    private static func make(
        id: String,
        icon: String,
        title: String,
        description: String,
        requiredCount: Int
    ) -> Achievement {
        Achievement(
            id: id,
            icon: icon,
            title: title,
            description: description,
            requiredCount: requiredCount,
            isUnlocked: false,
            currentProgress: 0,
            unlockedAt: nil
        )
    }
}

struct UserStats: Codable, Equatable {
    var totalProductsAdded: Int
    var maxInventoryCount: Int
    var mealPlansGenerated: Int
    var currentStreak: Int
    var longestStreak: Int
    var expiryWarningsMarked: Int
    var totalXP: Int
    var level: Int
    var dailyQuestsCompleted: Int
    var weeklyQuestsCompleted: Int
    var daysWithoutLoss: Int
    var priceEntriesSaved: Int
    var receiptsScanned: Int
    var dietProfileSwitches: Int
    var manualMacroDays: Int
    var automaticMacroDays: Int
    var bodyGoalSetCount: Int
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
            totalXP: 0,
            level: 1,
            dailyQuestsCompleted: 0,
            weeklyQuestsCompleted: 0,
            daysWithoutLoss: 0,
            priceEntriesSaved: 0,
            receiptsScanned: 0,
            dietProfileSwitches: 0,
            manualMacroDays: 0,
            automaticMacroDays: 0,
            bodyGoalSetCount: 0,
            lastActiveDate: Date(),
            firstLaunchDate: Date()
        )
    }
}

extension UserStats {
    private enum CodingKeys: String, CodingKey {
        case totalProductsAdded
        case maxInventoryCount
        case mealPlansGenerated
        case currentStreak
        case longestStreak
        case expiryWarningsMarked
        case totalXP
        case level
        case dailyQuestsCompleted
        case weeklyQuestsCompleted
        case daysWithoutLoss
        case priceEntriesSaved
        case receiptsScanned
        case dietProfileSwitches
        case manualMacroDays
        case automaticMacroDays
        case bodyGoalSetCount
        case lastActiveDate
        case firstLaunchDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalProductsAdded = try container.decodeIfPresent(Int.self, forKey: .totalProductsAdded) ?? 0
        maxInventoryCount = try container.decodeIfPresent(Int.self, forKey: .maxInventoryCount) ?? 0
        mealPlansGenerated = try container.decodeIfPresent(Int.self, forKey: .mealPlansGenerated) ?? 0
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        longestStreak = try container.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
        expiryWarningsMarked = try container.decodeIfPresent(Int.self, forKey: .expiryWarningsMarked) ?? 0
        totalXP = try container.decodeIfPresent(Int.self, forKey: .totalXP) ?? 0
        level = max(1, try container.decodeIfPresent(Int.self, forKey: .level) ?? 1)
        dailyQuestsCompleted = try container.decodeIfPresent(Int.self, forKey: .dailyQuestsCompleted) ?? 0
        weeklyQuestsCompleted = try container.decodeIfPresent(Int.self, forKey: .weeklyQuestsCompleted) ?? 0
        daysWithoutLoss = try container.decodeIfPresent(Int.self, forKey: .daysWithoutLoss) ?? 0
        priceEntriesSaved = try container.decodeIfPresent(Int.self, forKey: .priceEntriesSaved) ?? 0
        receiptsScanned = try container.decodeIfPresent(Int.self, forKey: .receiptsScanned) ?? 0
        dietProfileSwitches = try container.decodeIfPresent(Int.self, forKey: .dietProfileSwitches) ?? 0
        manualMacroDays = try container.decodeIfPresent(Int.self, forKey: .manualMacroDays) ?? 0
        automaticMacroDays = try container.decodeIfPresent(Int.self, forKey: .automaticMacroDays) ?? 0
        bodyGoalSetCount = try container.decodeIfPresent(Int.self, forKey: .bodyGoalSetCount) ?? 0
        lastActiveDate = try container.decodeIfPresent(Date.self, forKey: .lastActiveDate) ?? Date()
        firstLaunchDate = try container.decodeIfPresent(Date.self, forKey: .firstLaunchDate) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalProductsAdded, forKey: .totalProductsAdded)
        try container.encode(maxInventoryCount, forKey: .maxInventoryCount)
        try container.encode(mealPlansGenerated, forKey: .mealPlansGenerated)
        try container.encode(currentStreak, forKey: .currentStreak)
        try container.encode(longestStreak, forKey: .longestStreak)
        try container.encode(expiryWarningsMarked, forKey: .expiryWarningsMarked)
        try container.encode(totalXP, forKey: .totalXP)
        try container.encode(level, forKey: .level)
        try container.encode(dailyQuestsCompleted, forKey: .dailyQuestsCompleted)
        try container.encode(weeklyQuestsCompleted, forKey: .weeklyQuestsCompleted)
        try container.encode(daysWithoutLoss, forKey: .daysWithoutLoss)
        try container.encode(priceEntriesSaved, forKey: .priceEntriesSaved)
        try container.encode(receiptsScanned, forKey: .receiptsScanned)
        try container.encode(dietProfileSwitches, forKey: .dietProfileSwitches)
        try container.encode(manualMacroDays, forKey: .manualMacroDays)
        try container.encode(automaticMacroDays, forKey: .automaticMacroDays)
        try container.encode(bodyGoalSetCount, forKey: .bodyGoalSetCount)
        try container.encode(lastActiveDate, forKey: .lastActiveDate)
        try container.encode(firstLaunchDate, forKey: .firstLaunchDate)
    }
}

struct GamificationQuest: Identifiable, Codable, Equatable {
    enum Period: String, Codable {
        case daily
        case weekly
    }

    let id: String
    let title: String
    let description: String
    let target: Int
    var progress: Int
    var rewardXP: Int
    var period: Period
    var completed: Bool

    var completionRatio: Double {
        guard target > 0 else { return 1 }
        return min(1, Double(progress) / Double(target))
    }

    static func defaultDailyQuests() -> [GamificationQuest] {
        [
            .init(id: "daily_add_product", title: "Пополнить запасы", description: "Добавить 1 продукт", target: 1, progress: 0, rewardXP: 40, period: .daily, completed: false),
            .init(id: "daily_check_expiry", title: "Проверить сроки", description: "Отметить 2 позиции по сроку", target: 2, progress: 0, rewardXP: 35, period: .daily, completed: false),
            .init(id: "daily_plan", title: "Собрать план", description: "Сгенерировать 1 план питания", target: 1, progress: 0, rewardXP: 50, period: .daily, completed: false)
        ]
    }

    static func defaultWeeklyQuests() -> [GamificationQuest] {
        [
            .init(id: "weekly_no_loss", title: "Неделя без потерь", description: "3 дня без списаний", target: 3, progress: 0, rewardXP: 180, period: .weekly, completed: false),
            .init(id: "weekly_price_log", title: "Контроль цен", description: "Сохранить 8 цен", target: 8, progress: 0, rewardXP: 140, period: .weekly, completed: false),
            .init(id: "weekly_plans", title: "Режим планирования", description: "Сгенерировать 4 плана", target: 4, progress: 0, rewardXP: 200, period: .weekly, completed: false)
        ]
    }
}
