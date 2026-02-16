import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

final class GamificationService: ObservableObject {
    static let shared = GamificationService()
    
    @Published private(set) var achievements: [Achievement] = []
    @Published private(set) var userStats: UserStats = .initial
    
    private let userDefaults = UserDefaults.standard
    private let achievementsKey = "vay_achievements"
    private let statsKey = "vay_user_stats"
    
    private init() {
        loadData()
    }
    
    func trackProductAdded() {
        userStats.totalProductsAdded += 1
        updateAchievement(id: "first_product", progress: userStats.totalProductsAdded)
        saveData()
    }
    
    func trackInventoryCount(_ count: Int) {
        if count > userStats.maxInventoryCount {
            userStats.maxInventoryCount = count
        }
        updateAchievement(id: "stocked_up", progress: count)
        saveData()
    }
    
    func trackMealPlanGenerated() {
        userStats.mealPlansGenerated += 1
        updateAchievement(id: "planner", progress: userStats.mealPlansGenerated)
        checkMasterAchievement()
        saveData()
    }
    
    func trackExpiryWarning() {
        userStats.expiryWarningsMarked += 1
        updateAchievement(id: "vigilant", progress: userStats.expiryWarningsMarked)
        saveData()
    }
    
    func updateStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastActive = calendar.startOfDay(for: userStats.lastActiveDate)
        
        let daysDiff = calendar.dateComponents([.day], from: lastActive, to: today).day ?? 0
        
        if daysDiff == 1 {
            userStats.currentStreak += 1
        } else if daysDiff > 1 {
            userStats.currentStreak = 1
        }
        
        if userStats.currentStreak > userStats.longestStreak {
            userStats.longestStreak = userStats.currentStreak
        }
        
        userStats.lastActiveDate = Date()
        
        updateAchievement(id: "streak_7", progress: userStats.currentStreak)
        checkMasterAchievement()
        saveData()
    }
    
    private func updateAchievement(id: String, progress: Int) {
        guard let index = achievements.firstIndex(where: { $0.id == id }) else { return }
        
        var achievement = achievements[index]
        achievement.currentProgress = progress
        
        if progress >= achievement.requiredCount && !achievement.isUnlocked {
            achievement.isUnlocked = true
            achievement.unlockedAt = Date()
            triggerHapticFeedback()
        }
        
        achievements[index] = achievement
    }
    
    private func checkMasterAchievement() {
        let unlockedCount = achievements.filter { $0.isUnlocked && $0.id != "master" }.count
        guard let masterIndex = achievements.firstIndex(where: { $0.id == "master" }) else { return }
        
        var master = achievements[masterIndex]
        master.currentProgress = unlockedCount
        
        if unlockedCount >= master.requiredCount && !master.isUnlocked {
            master.isUnlocked = true
            master.unlockedAt = Date()
            triggerHapticFeedback()
        }
        
        achievements[masterIndex] = master
    }
    
    private func triggerHapticFeedback() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
    
    private func loadData() {
        if let data = userDefaults.data(forKey: achievementsKey),
           let saved = try? JSONDecoder().decode([Achievement].self, from: data) {
            achievements = saved
        } else {
            achievements = Achievement.defaultAchievements()
        }
        
        if let data = userDefaults.data(forKey: statsKey),
           let saved = try? JSONDecoder().decode(UserStats.self, from: data) {
            userStats = saved
        }
        
        updateStreak()
    }
    
    private func saveData() {
        if let data = try? JSONEncoder().encode(achievements) {
            userDefaults.set(data, forKey: achievementsKey)
        }
        
        if let data = try? JSONEncoder().encode(userStats) {
            userDefaults.set(data, forKey: statsKey)
        }
    }
    
    func resetProgress() {
        achievements = Achievement.defaultAchievements()
        userStats = .initial
        saveData()
    }
}
