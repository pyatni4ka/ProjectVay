import SwiftUI
import ConfettiSwiftUI

struct SettingsAchievementsView: View {
    private var gamification = GamificationService.shared
    @State private var flameScale: CGFloat = 1.0
    @State private var selectedAchievement: Achievement?
    @State private var confettiCounter: Int = 0

    var body: some View {
        List {
            Section {
                streakHeader
            } header: {
                sectionHeader(icon: "chart.bar.fill", title: "Сводка")
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: VaySpacing.sm) {
                        statPill(icon: "trophy.fill", color: .vayWarning, label: "Открыто", value: "\(unlockedCount)/\(totalAchievements)")
                        statPill(icon: "star.fill", color: .vayPrimary, label: "Уровень", value: "\(gamification.userStats.level)")
                        statPill(icon: "bolt.fill", color: .vayCalories, label: "XP", value: "\(gamification.userStats.totalXP)")
                        statPill(icon: "fork.knife", color: .vaySuccess, label: "Планов", value: "\(gamification.userStats.mealPlansGenerated)")
                        statPill(icon: "checkmark.seal.fill", color: .vayInfo, label: "Квесты/д", value: "\(gamification.userStats.dailyQuestsCompleted)")
                        statPill(icon: "calendar.badge.checkmark", color: .vaySecondary, label: "Квесты/н", value: "\(gamification.userStats.weeklyQuestsCompleted)")
                    }
                    .padding(.vertical, VaySpacing.xs)
                    .padding(.horizontal, VaySpacing.lg)
                }
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: VaySpacing.md) {
                        ForEach(sortedAchievements.filter(\.isUnlocked)) { achievement in
                            Button { selectedAchievement = achievement } label: {
                                achievementCard(achievement, unlocked: true)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(sortedAchievements.filter { !$0.isUnlocked }) { achievement in
                            Button { selectedAchievement = achievement } label: {
                                achievementCard(achievement, unlocked: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, VaySpacing.sm)
                    .padding(.horizontal, VaySpacing.lg)
                }
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            } header: {
                sectionHeader(icon: "trophy.fill", title: "Достижения")
            }

            // List view with description under each unlocked achievement
            Section {
                ForEach(sortedAchievements) { achievement in
                    Button { selectedAchievement = achievement } label: {
                        achievementListRow(achievement)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                sectionHeader(icon: "list.bullet", title: "Список достижений")
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: VayLayout.tabBarOverlayInset)
        }
        .navigationTitle("Достижения")
        .sheet(item: $selectedAchievement) { achievement in
            achievementDetailSheet(achievement)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .confettiCannon(counter: $confettiCounter, num: 50, openingAngle: Angle(degrees: 0), closingAngle: Angle(degrees: 360), radius: 200)
                .onAppear {
                    if achievement.isUnlocked {
                        confettiCounter += 1
                    }
                }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
            ) {
                flameScale = 1.18
            }
        }
    }

    private var streakHeader: some View {
        HStack(spacing: VaySpacing.lg) {
            VStack(alignment: .center, spacing: VaySpacing.xs) {
                HStack(spacing: VaySpacing.xs) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                        .scaleEffect(flameScale)
                    Text("\(gamification.userStats.currentStreak)")
                        .font(VayFont.title(28))
                        .foregroundStyle(Color.vayCalories)
                }
                Text("текущая серия")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 44)

            VStack(alignment: .center, spacing: VaySpacing.xs) {
                Text("\(gamification.userStats.longestStreak)")
                    .font(VayFont.title(28))
                    .foregroundStyle(Color.vayWarning)
                Text("рекорд дней")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 44)

            VStack(alignment: .center, spacing: VaySpacing.xs) {
                Text("\(gamification.userStats.daysWithoutLoss)")
                    .font(VayFont.title(28))
                    .foregroundStyle(Color.vaySuccess)
                Text("без потерь")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, VaySpacing.sm)
    }

    private func statPill(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: VaySpacing.xs) {
            Image(systemName: icon)
                .font(VayFont.label(16))
                .foregroundStyle(color)
            Text(value)
                .font(VayFont.label(15))
            Text(label)
                .font(VayFont.caption(10))
                .foregroundStyle(.secondary)
        }
        .frame(width: 72)
        .padding(.vertical, VaySpacing.sm)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
    }

    private func achievementListRow(_ achievement: Achievement) -> some View {
        HStack(spacing: VaySpacing.md) {
            Text(achievement.icon)
                .font(VayFont.title(28))
                .opacity(achievement.isUnlocked ? 1 : 0.4)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: VaySpacing.xs) {
                HStack(spacing: VaySpacing.xs) {
                    Text(achievement.title)
                        .font(VayFont.label(15))
                        .foregroundStyle(achievement.isUnlocked ? .primary : .secondary)
                    if achievement.isUnlocked {
                        Image(systemName: "checkmark.seal.fill")
                            .font(VayFont.caption(12))
                            .foregroundStyle(Color.vaySuccess)
                    }
                }

                Text(achievement.description)
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: VaySpacing.sm) {
                    ProgressView(value: achievement.progress)
                        .tint(achievement.isUnlocked ? Color.vaySuccess : Color.vayPrimary)

                    Text(achievement.isUnlocked
                         ? "Выполнено"
                         : "Осталось \(achievement.requiredCount - achievement.currentProgress)")
                        .font(VayFont.caption(10))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
            }

            Image(systemName: "chevron.right")
                .font(VayFont.caption(12))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, VaySpacing.xs)
    }

    @ViewBuilder
    private func achievementDetailSheet(_ achievement: Achievement) -> some View {
        ScrollView {
            VStack(spacing: VaySpacing.lg) {
                // Icon + title
                VStack(spacing: VaySpacing.sm) {
                    Text(achievement.icon)
                        .font(VayFont.hero(64))
                        .opacity(achievement.isUnlocked ? 1 : 0.4)

                    Text(achievement.title)
                        .font(VayFont.heading(20))
                        .multilineTextAlignment(.center)

                    if achievement.isUnlocked {
                        Label("Открыто", systemImage: "checkmark.seal.fill")
                            .font(VayFont.label(13))
                            .foregroundStyle(Color.vaySuccess)
                        if let date = achievement.unlockedAt {
                            Text(date.formatted(date: .long, time: .omitted))
                                .font(VayFont.caption(12))
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Label("Заблокировано", systemImage: "lock.fill")
                            .font(VayFont.label(13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, VaySpacing.lg)

                // Description
                Text(achievement.description)
                    .font(VayFont.body(15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, VaySpacing.lg)

                // Progress
                VStack(alignment: .leading, spacing: VaySpacing.sm) {
                    HStack {
                        Text("Прогресс")
                            .font(VayFont.label(14))
                        Spacer()
                        Text("\(achievement.currentProgress) / \(achievement.requiredCount)")
                            .font(VayFont.label(14))
                            .foregroundStyle(Color.vayPrimary)
                    }
                    ProgressView(value: achievement.progress)
                        .tint(achievement.isUnlocked ? Color.vaySuccess : Color.vayPrimary)

                    if !achievement.isUnlocked {
                        let remaining = achievement.requiredCount - achievement.currentProgress
                        Text("Осталось выполнить: \(remaining)")
                            .font(VayFont.caption(12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, VaySpacing.lg)
                .vayCard()
                .padding(.horizontal, VaySpacing.md)

                Spacer(minLength: VaySpacing.lg)
            }
        }
        .background(Color.vayBackground)
    }

    private func achievementCard(_ achievement: Achievement, unlocked: Bool) -> some View {
        VStack(spacing: VaySpacing.sm) {
            Text(achievement.icon)
                .font(VayFont.title(28))
                .opacity(unlocked ? 1 : 0.35)

            Text(achievement.title)
                .font(VayFont.caption(11))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 80)

            ProgressView(value: achievement.progress)
                .tint(unlocked ? Color.vaySuccess : Color.vayPrimary)
                .frame(width: 64)

            if unlocked {
                Image(systemName: "checkmark.seal.fill")
                    .font(VayFont.caption(12))
                    .foregroundStyle(Color.vaySuccess)
            } else {
                Text("\(achievement.currentProgress)/\(achievement.requiredCount)")
                    .font(VayFont.caption(10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 96)
        .padding(.vertical, VaySpacing.sm)
        .background(Color.vayCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous)
                .stroke(unlocked ? Color.vaySuccess.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
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
                .font(VayFont.title(24))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: VaySpacing.xs) {
                HStack {
                    Text(achievement.title)
                        .font(VayFont.label(15))
                    if achievement.isUnlocked {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.vaySuccess)
                            .font(VayFont.label(13))
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
                .font(VayFont.caption(11))
            Text(title)
        }
        .font(VayFont.caption(12))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}
