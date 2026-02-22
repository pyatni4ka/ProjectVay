import Foundation
import Combine
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable final class GamificationService {
    static let shared = GamificationService()

    struct XPToast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let icon: String
    }

    private(set) var achievements: [Achievement] = []
    private(set) var userStats: UserStats = .initial
    private(set) var dailyQuests: [GamificationQuest] = []
    private(set) var weeklyQuests: [GamificationQuest] = []
    private(set) var lastXPToast: XPToast?
    var pendingLevelUp: Int? // Track state if a level-up splash needs to be shown

    private let userDefaults = UserDefaults.standard
    private let achievementsKey = "vay_achievements"
    private let statsKey = "vay_user_stats"
    private let dailyQuestsKey = "vay_daily_quests"
    private let weeklyQuestsKey = "vay_weekly_quests"
    private let dailyResetKey = "vay_daily_quests_reset_date"
    private let weeklyResetKey = "vay_weekly_quests_reset_date"

    private init() {
        loadData()
    }

    func trackProductAdded(count: Int = 1) {
        guard count > 0 else { return }
        refreshQuestWindows()
        updateStreakIfNeeded()

        userStats.totalProductsAdded += count
        addXP(12 * count, toastText: "+\(12 * count) XP за пополнение", icon: "shippingbox.fill")
        advanceQuest(id: "daily_add_product", amount: count)

        updateAllAchievements()
        saveData()
    }

    func trackInventoryCount(_ count: Int) {
        userStats.maxInventoryCount = max(userStats.maxInventoryCount, count)
        updateAllAchievements()
        saveData()
    }

    func trackMealPlanGenerated() {
        refreshQuestWindows()
        updateStreakIfNeeded()

        userStats.mealPlansGenerated += 1
        addXP(35, toastText: "+35 XP за план", icon: "fork.knife.circle.fill")
        advanceQuest(id: "daily_plan", amount: 1)
        advanceQuest(id: "weekly_plans", amount: 1)

        updateAllAchievements()
        saveData()
    }

    func trackExpiryWarning() {
        refreshQuestWindows()
        updateStreakIfNeeded()

        userStats.expiryWarningsMarked += 1
        addXP(8, toastText: "+8 XP за контроль сроков", icon: "clock.badge.exclamationmark")
        advanceQuest(id: "daily_check_expiry", amount: 1)

        updateAllAchievements()
        saveData()
    }

    func trackPriceEntrySaved(count: Int = 1) {
        guard count > 0 else { return }
        refreshQuestWindows()

        userStats.priceEntriesSaved += count
        addXP(6 * count, toastText: "+\(6 * count) XP за цены", icon: "rublesign.circle.fill")
        advanceQuest(id: "weekly_price_log", amount: count)

        updateAllAchievements()
        saveData()
    }

    func trackReceiptScan(count: Int = 1) {
        guard count > 0 else { return }
        refreshQuestWindows()

        userStats.receiptsScanned += count
        addXP(10 * count, toastText: "+\(10 * count) XP за чек", icon: "doc.text.viewfinder")

        updateAllAchievements()
        saveData()
    }

    func trackDietProfileSwitch() {
        userStats.dietProfileSwitches += 1
        addXP(10, toastText: "+10 XP за настройку диеты", icon: "leaf.circle.fill")
        updateAllAchievements()
        saveData()
    }

    func trackMacroModeDay(source: AppSettings.MacroGoalSource) {
        switch source {
        case .automatic:
            userStats.automaticMacroDays += 1
        case .manual:
            userStats.manualMacroDays += 1
        }
        addXP(5, toastText: "+5 XP за дисциплину питания", icon: "chart.bar.fill")
        updateAllAchievements()
        saveData()
    }

    func trackBodyGoalSet() {
        userStats.bodyGoalSetCount += 1
        addXP(15, toastText: "+15 XP за цель веса", icon: "target")
        updateAllAchievements()
        saveData()
    }

    func trackNoLossDay() {
        userStats.daysWithoutLoss += 1
        addXP(18, toastText: "+18 XP за день без потерь", icon: "leaf.fill")
        advanceQuest(id: "weekly_no_loss", amount: 1)
        updateAllAchievements()
        saveData()
    }

    func updateStreak() {
        updateStreakIfNeeded(forceUpdate: true)
        updateAllAchievements()
        saveData()
    }

    func clearToast() {
        lastXPToast = nil
    }

    func clearLevelUp() {
        pendingLevelUp = nil
    }

    func resetProgress() {
        achievements = Achievement.defaultAchievements()
        userStats = .initial
        dailyQuests = GamificationQuest.defaultDailyQuests()
        weeklyQuests = GamificationQuest.defaultWeeklyQuests()
        userDefaults.set(Date(), forKey: dailyResetKey)
        userDefaults.set(Date(), forKey: weeklyResetKey)
        lastXPToast = nil
        saveData()
    }

    private func loadData() {
        let defaults = Achievement.defaultAchievements()
        if
            let data = userDefaults.data(forKey: achievementsKey),
            let saved = try? JSONDecoder().decode([Achievement].self, from: data)
        {
            achievements = mergeAchievements(saved: saved, defaults: defaults)
        } else {
            achievements = defaults
        }

        if
            let data = userDefaults.data(forKey: statsKey),
            let saved = try? JSONDecoder().decode(UserStats.self, from: data)
        {
            userStats = saved
        }

        if
            let data = userDefaults.data(forKey: dailyQuestsKey),
            let saved = try? JSONDecoder().decode([GamificationQuest].self, from: data)
        {
            dailyQuests = mergeQuests(saved: saved, defaults: GamificationQuest.defaultDailyQuests())
        } else {
            dailyQuests = GamificationQuest.defaultDailyQuests()
        }

        if
            let data = userDefaults.data(forKey: weeklyQuestsKey),
            let saved = try? JSONDecoder().decode([GamificationQuest].self, from: data)
        {
            weeklyQuests = mergeQuests(saved: saved, defaults: GamificationQuest.defaultWeeklyQuests())
        } else {
            weeklyQuests = GamificationQuest.defaultWeeklyQuests()
        }

        refreshQuestWindows()
        updateStreakIfNeeded()
        updateAllAchievements()
        saveData()
    }

    private func saveData() {
        if let data = try? JSONEncoder().encode(achievements) {
            userDefaults.set(data, forKey: achievementsKey)
        }
        if let data = try? JSONEncoder().encode(userStats) {
            userDefaults.set(data, forKey: statsKey)
        }
        if let data = try? JSONEncoder().encode(dailyQuests) {
            userDefaults.set(data, forKey: dailyQuestsKey)
        }
        if let data = try? JSONEncoder().encode(weeklyQuests) {
            userDefaults.set(data, forKey: weeklyQuestsKey)
        }
    }

    private func refreshQuestWindows(now: Date = Date()) {
        let calendar = Calendar.current
        let storedDailyReset = (userDefaults.object(forKey: dailyResetKey) as? Date) ?? now
        if !calendar.isDate(storedDailyReset, inSameDayAs: now) {
            dailyQuests = GamificationQuest.defaultDailyQuests()
            userDefaults.set(now, forKey: dailyResetKey)
        }

        let storedWeeklyReset = (userDefaults.object(forKey: weeklyResetKey) as? Date) ?? now
        if startOfWeek(for: storedWeeklyReset) != startOfWeek(for: now) {
            weeklyQuests = GamificationQuest.defaultWeeklyQuests()
            userDefaults.set(now, forKey: weeklyResetKey)
        }
    }

    private func updateStreakIfNeeded(forceUpdate: Bool = false, now: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let lastActive = calendar.startOfDay(for: userStats.lastActiveDate)
        let daysDiff = calendar.dateComponents([.day], from: lastActive, to: today).day ?? 0

        if daysDiff == 0 && !forceUpdate {
            return
        }

        if daysDiff == 1 {
            userStats.currentStreak += 1
            userStats.daysWithoutLoss += 1
        } else if daysDiff == 2, userStats.totalXP >= 150 {
            // Streak rescue: keep streak continuity by spending XP buffer.
            userStats.totalXP -= 150
            userStats.currentStreak += 1
            userStats.daysWithoutLoss += 1
            lastXPToast = XPToast(text: "Серия спасена (-150 XP)", icon: "lifepreserver")
        } else {
            userStats.currentStreak = 1
            userStats.daysWithoutLoss = 0
        }

        userStats.longestStreak = max(userStats.longestStreak, userStats.currentStreak)
        userStats.lastActiveDate = now
        addXP(5, toastText: "+5 XP за активность", icon: "calendar")
    }

    private func addXP(_ value: Int, toastText: String, icon: String) {
        guard value > 0 else { return }

        let previousLevel = userStats.level
        userStats.totalXP += value
        userStats.level = level(for: userStats.totalXP)

        if userStats.level > previousLevel {
            triggerHapticFeedback()
            // We use the full screen level up splash instead of the toast
            pendingLevelUp = userStats.level
        } else {
            lastXPToast = XPToast(text: toastText, icon: icon)
        }
    }

    private func level(for totalXP: Int) -> Int {
        var remainingXP = max(0, totalXP)
        var level = 1
        var threshold = 220

        while remainingXP >= threshold {
            remainingXP -= threshold
            level += 1
            threshold = Int((Double(threshold) * 1.16).rounded())
        }

        return max(1, level)
    }

    private func advanceQuest(id: String, amount: Int) {
        guard amount > 0 else { return }
        var completedAny = false

        for index in dailyQuests.indices where dailyQuests[index].id == id {
            if !dailyQuests[index].completed {
                dailyQuests[index].progress = min(dailyQuests[index].target, dailyQuests[index].progress + amount)
                if dailyQuests[index].progress >= dailyQuests[index].target {
                    dailyQuests[index].completed = true
                    userStats.dailyQuestsCompleted += 1
                    addXP(
                        dailyQuests[index].rewardXP,
                        toastText: "+\(dailyQuests[index].rewardXP) XP за квест",
                        icon: "checkmark.seal.fill"
                    )
                    completedAny = true
                }
            }
        }

        for index in weeklyQuests.indices where weeklyQuests[index].id == id {
            if !weeklyQuests[index].completed {
                weeklyQuests[index].progress = min(weeklyQuests[index].target, weeklyQuests[index].progress + amount)
                if weeklyQuests[index].progress >= weeklyQuests[index].target {
                    weeklyQuests[index].completed = true
                    userStats.weeklyQuestsCompleted += 1
                    addXP(
                        weeklyQuests[index].rewardXP,
                        toastText: "+\(weeklyQuests[index].rewardXP) XP за недельный квест",
                        icon: "star.fill"
                    )
                    completedAny = true
                }
            }
        }

        if completedAny {
            triggerHapticFeedback()
        }
    }

    private func updateAllAchievements() {
        setAchievementProgress("first_product", userStats.totalProductsAdded)
        setAchievementProgress("products_10", userStats.maxInventoryCount)
        setAchievementProgress("products_25", userStats.maxInventoryCount)
        setAchievementProgress("products_50", userStats.maxInventoryCount)
        setAchievementProgress("products_100", userStats.maxInventoryCount)

        setAchievementProgress("planner_1", userStats.mealPlansGenerated)
        setAchievementProgress("planner_5", userStats.mealPlansGenerated)
        setAchievementProgress("planner_15", userStats.mealPlansGenerated)
        setAchievementProgress("planner_30", userStats.mealPlansGenerated)
        setAchievementProgress("planner_60", userStats.mealPlansGenerated)

        setAchievementProgress("streak_3", userStats.currentStreak)
        setAchievementProgress("streak_7", userStats.currentStreak)
        setAchievementProgress("streak_14", userStats.currentStreak)
        setAchievementProgress("streak_30", userStats.currentStreak)
        setAchievementProgress("streak_90", userStats.currentStreak)
        setAchievementProgress("streak_180", userStats.currentStreak)

        setAchievementProgress("vigilant_10", userStats.expiryWarningsMarked)
        setAchievementProgress("vigilant_50", userStats.expiryWarningsMarked)
        setAchievementProgress("vigilant_100", userStats.expiryWarningsMarked)

        setAchievementProgress("xp_500", userStats.totalXP)
        setAchievementProgress("xp_1500", userStats.totalXP)
        setAchievementProgress("xp_5000", userStats.totalXP)
        setAchievementProgress("xp_12000", userStats.totalXP)

        setAchievementProgress("quests_daily_10", userStats.dailyQuestsCompleted)
        setAchievementProgress("quests_daily_50", userStats.dailyQuestsCompleted)
        setAchievementProgress("quests_weekly_8", userStats.weeklyQuestsCompleted)
        setAchievementProgress("quests_weekly_24", userStats.weeklyQuestsCompleted)

        setAchievementProgress("no_loss_3", userStats.daysWithoutLoss)
        setAchievementProgress("no_loss_7", userStats.daysWithoutLoss)
        setAchievementProgress("no_loss_14", userStats.daysWithoutLoss)
        setAchievementProgress("no_loss_30", userStats.daysWithoutLoss)
        setAchievementProgress("no_loss_60", userStats.daysWithoutLoss)

        setAchievementProgress("body_goal_set", userStats.bodyGoalSetCount)
        setAchievementProgress("diet_profile_switch_5", userStats.dietProfileSwitches)
        setAchievementProgress("macro_manual_10", userStats.manualMacroDays)
        setAchievementProgress("macro_auto_20", userStats.automaticMacroDays)

        setAchievementProgress("price_entries_20", userStats.priceEntriesSaved)
        setAchievementProgress("price_entries_100", userStats.priceEntriesSaved)
        setAchievementProgress("price_entries_250", userStats.priceEntriesSaved)
        setAchievementProgress("receipt_scans_10", userStats.receiptsScanned)
        setAchievementProgress("receipt_scans_50", userStats.receiptsScanned)
        setAchievementProgress("receipt_scans_100", userStats.receiptsScanned)

        let unlockedWithoutMeta = achievements.filter {
            $0.isUnlocked
                && $0.id != "kitchen_marathon"
                && $0.id != "kitchen_elite"
                && $0.id != "master"
        }.count
        setAchievementProgress("kitchen_marathon", unlockedWithoutMeta)
        setAchievementProgress("kitchen_elite", unlockedWithoutMeta)

        let unlockedWithoutMaster = achievements.filter {
            $0.isUnlocked && $0.id != "master"
        }.count
        setAchievementProgress("master", unlockedWithoutMaster)
    }

    private func setAchievementProgress(_ id: String, _ progress: Int) {
        guard let index = achievements.firstIndex(where: { $0.id == id }) else { return }

        var achievement = achievements[index]
        achievement.currentProgress = min(progress, achievement.requiredCount)

        if progress >= achievement.requiredCount, !achievement.isUnlocked {
            achievement.isUnlocked = true
            achievement.unlockedAt = Date()
            triggerHapticFeedback()
        }

        achievements[index] = achievement
    }

    private func mergeAchievements(saved: [Achievement], defaults: [Achievement]) -> [Achievement] {
        let savedByID = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        return defaults.map { base in
            guard let persisted = savedByID[base.id] else { return base }
            return Achievement(
                id: base.id,
                icon: base.icon,
                title: base.title,
                description: base.description,
                requiredCount: base.requiredCount,
                isUnlocked: persisted.isUnlocked,
                currentProgress: min(persisted.currentProgress, base.requiredCount),
                unlockedAt: persisted.unlockedAt
            )
        }
    }

    private func mergeQuests(saved: [GamificationQuest], defaults: [GamificationQuest]) -> [GamificationQuest] {
        let savedByID = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        return defaults.map { base in
            guard let persisted = savedByID[base.id] else { return base }
            var merged = base
            merged.progress = min(base.target, max(0, persisted.progress))
            merged.completed = persisted.completed
            return merged
        }
    }

    private func startOfWeek(for date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }

    private func triggerHapticFeedback() {
        #if canImport(UIKit)
        VayHaptic.success()
        #endif
    }
}
