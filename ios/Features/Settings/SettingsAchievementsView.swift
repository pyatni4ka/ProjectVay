import SwiftUI

struct SettingsAchievementsView: View {
    @ObservedObject private var gamification = GamificationService.shared

    var body: some View {
        List {
            Section {
                statRow(title: "Открыто", value: "\(unlockedCount)/\(totalAchievements)")
                statRow(title: "Уровень", value: "\(gamification.userStats.level)")
                statRow(title: "XP", value: "\(gamification.userStats.totalXP)")
                statRow(title: "Текущая серия", value: "\(gamification.userStats.currentStreak) дн.")
                statRow(title: "Лучшая серия", value: "\(gamification.userStats.longestStreak) дн.")
                statRow(title: "Без потерь", value: "\(gamification.userStats.daysWithoutLoss) дн.")
                statRow(title: "Планов создано", value: "\(gamification.userStats.mealPlansGenerated)")
                statRow(title: "Квесты (день)", value: "\(gamification.userStats.dailyQuestsCompleted)")
                statRow(title: "Квесты (неделя)", value: "\(gamification.userStats.weeklyQuestsCompleted)")
            } header: {
                sectionHeader(icon: "chart.bar.fill", title: "Сводка")
            }

            if !gamification.dailyQuests.isEmpty {
                Section {
                    ForEach(gamification.dailyQuests) { quest in
                        questRow(quest)
                    }
                } header: {
                    sectionHeader(icon: "sun.max.fill", title: "Дневные квесты")
                }
            }

            if !gamification.weeklyQuests.isEmpty {
                Section {
                    ForEach(gamification.weeklyQuests) { quest in
                        questRow(quest)
                    }
                } header: {
                    sectionHeader(icon: "calendar", title: "Недельные квесты")
                }
            }

            Section {
                ForEach(sortedAchievements) { achievement in
                    achievementRow(achievement)
                }
            } header: {
                sectionHeader(icon: "trophy.fill", title: "Достижения")
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: VayLayout.tabBarOverlayInset)
        }
        .navigationTitle("Достижения")
    }

    private var sortedAchievements: [Achievement] {
        gamification.achievements
            .sorted { lhs, rhs in
                if lhs.isUnlocked != rhs.isUnlocked {
                    return lhs.isUnlocked && !rhs.isUnlocked
                }
                return lhs.title < rhs.title
            }
    }

    private var unlockedCount: Int {
        gamification.achievements.filter(\.isUnlocked).count
    }

    private var totalAchievements: Int {
        gamification.achievements.count
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(VayFont.body(15))
            Spacer()
            Text(value)
                .font(VayFont.label(14))
                .foregroundStyle(.secondary)
        }
    }

    private func achievementRow(_ achievement: Achievement) -> some View {
        HStack(spacing: VaySpacing.md) {
            Text(achievement.icon)
                .font(.system(size: 24))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: VaySpacing.xs) {
                HStack {
                    Text(achievement.title)
                        .font(VayFont.label(15))
                    if achievement.isUnlocked {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.vaySuccess)
                            .font(.system(size: 13))
                    }
                }

                Text(achievement.description)
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)

                ProgressView(value: achievement.progress)
                    .tint(achievement.isUnlocked ? Color.vaySuccess : Color.vayPrimary)

                Text("\(achievement.currentProgress)/\(achievement.requiredCount)")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, VaySpacing.xs)
    }

    private func questRow(_ quest: GamificationQuest) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.xs) {
            HStack {
                Text(quest.title)
                    .font(VayFont.label(14))
                Spacer()
                Text("+\(quest.rewardXP) XP")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }

            Text(quest.description)
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)

            ProgressView(value: quest.completionRatio)
                .tint(quest.completed ? Color.vaySuccess : Color.vayPrimary)

            HStack {
                Text("\(quest.progress)/\(quest.target)")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.tertiary)
                Spacer()
                if quest.completed {
                    Label("Выполнен", systemImage: "checkmark.seal.fill")
                        .font(VayFont.caption(11))
                        .foregroundStyle(Color.vaySuccess)
                }
            }
        }
        .padding(.vertical, VaySpacing.xs)
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(title)
        }
        .font(VayFont.caption(12))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}
