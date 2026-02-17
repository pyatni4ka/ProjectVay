import SwiftUI

struct DietSettingsView: View {
    let settingsService: any SettingsServiceProtocol
    @EnvironmentObject private var appSettingsStore: AppSettingsStore

    @State private var settings: AppSettings = .default
    @State private var isLoading = true
    @State private var isHydratingSettings = false
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var saveErrorMessage: String?

    @State private var macroGoalSource: AppSettings.MacroGoalSource = .automatic
    @State private var strictMacroTracking = true
    @State private var macroTolerancePercent = 25.0
    @State private var dietProfile: AppSettings.DietProfile = .medium
    @State private var dietGoalMode: AppSettings.DietGoalMode = .lose

    @State private var kcalGoalText = ""
    @State private var proteinGoalText = ""
    @State private var fatGoalText = ""
    @State private var carbsGoalText = ""

    private struct AutoSaveState: Equatable {
        let macroGoalSource: AppSettings.MacroGoalSource
        let strictMacroTracking: Bool
        let macroTolerancePercent: Double
        let dietProfile: AppSettings.DietProfile
        let dietGoalMode: AppSettings.DietGoalMode
        let kcalGoalText: String
        let proteinGoalText: String
        let fatGoalText: String
        let carbsGoalText: String
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack(spacing: VaySpacing.sm) {
                        ProgressView()
                        Text("Загружаем параметры диеты...")
                            .font(VayFont.body(14))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Picker("Источник КБЖУ", selection: $macroGoalSource) {
                    ForEach(AppSettings.MacroGoalSource.allCases, id: \.rawValue) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                sectionHeader(icon: "flame.fill", title: "Источник КБЖУ")
            } footer: {
                Text("Профиль диеты влияет только на авто-режим.")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }

            Section {
                settingRow(icon: "chart.bar.fill", color: .vayPrimary, label: "Строгий контроль КБЖУ") {
                    Toggle("", isOn: $strictMacroTracking)
                        .labelsHidden()
                        .tint(Color.vayPrimary)
                }

                if strictMacroTracking {
                    VStack(alignment: .leading, spacing: VaySpacing.sm) {
                        HStack {
                            Text("Допуск")
                                .font(VayFont.body(14))
                            Spacer()
                            Text("±\(Int(macroTolerancePercent))%")
                                .font(VayFont.label(13))
                                .foregroundStyle(Color.vayPrimary)
                        }

                        Slider(value: $macroTolerancePercent, in: 5...60, step: 5)
                            .tint(Color.vayPrimary)
                    }
                    .padding(.vertical, VaySpacing.xs)
                }
            } header: {
                sectionHeader(icon: "slider.horizontal.3", title: "Точность")
            }

            Section {
                Picker("Профиль", selection: $dietProfile) {
                    ForEach(AppSettings.DietProfile.allCases, id: \.rawValue) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .pickerStyle(.segmented)

                Text(dietProfileDescription(dietProfile))
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
                    .padding(.top, VaySpacing.xs)
            } header: {
                sectionHeader(icon: "leaf.circle.fill", title: "Профиль дефицита")
            } footer: {
                Text("Лайт/Медиум/Экстрим = 0.3/0.5/0.8 кг в неделю.")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Режим цели", selection: $dietGoalMode) {
                    ForEach(AppSettings.DietGoalMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(goalModeDescription(dietGoalMode))
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
                    .padding(.top, VaySpacing.xs)
            } header: {
                sectionHeader(icon: "target", title: "Цель")
            }

            if macroGoalSource == .manual {
                Section {
                    goalField(icon: "flame.fill", color: .vayCalories, label: "Калории", text: $kcalGoalText, suffix: "ккал")
                    goalField(icon: "drop.fill", color: .vayProtein, label: "Белки", text: $proteinGoalText, suffix: "г")
                    goalField(icon: "circle.fill", color: .vayFat, label: "Жиры", text: $fatGoalText, suffix: "г")
                    goalField(icon: "bolt.fill", color: .vayCarbs, label: "Углеводы", text: $carbsGoalText, suffix: "г")
                } header: {
                    sectionHeader(icon: "pencil", title: "Ручные цели")
                }
            }

            if let saveErrorMessage {
                Section {
                    Text(saveErrorMessage)
                        .font(VayFont.caption(12))
                        .foregroundStyle(Color.vayDanger)
                }
            }
        }
        .listStyle(.insetGrouped)
        .dismissKeyboardOnTap()
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: VayLayout.tabBarOverlayInset)
        }
        .navigationTitle("Диета")
        .task {
            await loadSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsDidChange)) { notification in
            guard let updated = notification.object as? AppSettings else { return }
            guard updated != settings else { return }
            applyLoadedSettings(updated)
        }
        .onChange(of: autoSaveState) { _, _ in
            publishLiveDietDraft()
            scheduleAutoSave()
        }
        .onChange(of: macroGoalSource) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: strictMacroTracking) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: macroTolerancePercent) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: dietProfile) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: dietGoalMode) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onDisappear {
            autoSaveTask?.cancel()
            Task { await saveSettingsIfValid() }
        }
    }

    private var autoSaveState: AutoSaveState {
        AutoSaveState(
            macroGoalSource: macroGoalSource,
            strictMacroTracking: strictMacroTracking,
            macroTolerancePercent: macroTolerancePercent,
            dietProfile: dietProfile,
            dietGoalMode: dietGoalMode,
            kcalGoalText: kcalGoalText,
            proteinGoalText: proteinGoalText,
            fatGoalText: fatGoalText,
            carbsGoalText: carbsGoalText
        )
    }

    private func settingRow<Content: View>(
        icon: String,
        color: Color,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(label)
                .font(VayFont.body(15))

            Spacer()

            content()
        }
    }

    private func goalField(
        icon: String,
        color: Color,
        label: String,
        text: Binding<String>,
        suffix: String
    ) -> some View {
        settingRow(icon: icon, color: color, label: label) {
            HStack(spacing: VaySpacing.xs) {
                TextField("—", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 64)
                Text(suffix)
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
            }
        }
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

    private func dietProfileDescription(_ profile: AppSettings.DietProfile) -> String {
        switch profile {
        case .light:
            return "Лайт: мягкий дефицит, комфортный темп и ниже риск срывов."
        case .medium:
            return "Медиум: сбалансированный темп снижения веса."
        case .extreme:
            return "Экстрим: быстрый темп, только при хорошей переносимости."
        }
    }

    private func goalModeDescription(_ mode: AppSettings.DietGoalMode) -> String {
        switch mode {
        case .lose:
            return "Фокус на снижении веса с адаптивным дефицитом."
        case .maintain:
            return "Фокус на удержании текущего веса без агрессивной коррекции."
        case .gain:
            return "Фокус на наборе массы с контролируемым профицитом."
        }
    }

    private func loadSettings() async {
        defer { isLoading = false }

        do {
            let loaded = try await settingsService.loadSettings()
            applyLoadedSettings(loaded)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func applyLoadedSettings(_ loaded: AppSettings) {
        isHydratingSettings = true
        defer { isHydratingSettings = false }

        settings = loaded
        macroGoalSource = loaded.macroGoalSource
        strictMacroTracking = loaded.strictMacroTracking
        macroTolerancePercent = loaded.macroTolerancePercent
        dietProfile = loaded.dietProfile
        dietGoalMode = loaded.dietGoalMode

        kcalGoalText = formatGoal(loaded.kcalGoal)
        proteinGoalText = formatGoal(loaded.proteinGoalGrams)
        fatGoalText = formatGoal(loaded.fatGoalGrams)
        carbsGoalText = formatGoal(loaded.carbsGoalGrams)
    }

    private func scheduleAutoSave() {
        guard !isHydratingSettings else { return }

        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await saveSettingsIfValid()
        }
    }

    private func saveSettingsIfValid() async {
        guard !isHydratingSettings else { return }
        autoSaveTask?.cancel()
        autoSaveTask = nil

        let previous = settings
        let parsedKcal = parseGoal(kcalGoalText)
        let parsedProtein = parseGoal(proteinGoalText)
        let parsedFat = parseGoal(fatGoalText)
        let parsedCarbs = parseGoal(carbsGoalText)

        if macroGoalSource == .manual {
            guard parsedKcal.valid, parsedProtein.valid, parsedFat.valid, parsedCarbs.valid else {
                return
            }
        }

        var updated = settings
        updated.macroGoalSource = macroGoalSource
        updated.strictMacroTracking = strictMacroTracking
        updated.macroTolerancePercent = macroTolerancePercent
        updated.dietProfile = dietProfile
        updated.dietGoalMode = dietGoalMode

        if parsedKcal.valid { updated.kcalGoal = parsedKcal.value }
        if parsedProtein.valid { updated.proteinGoalGrams = parsedProtein.value }
        if parsedFat.valid { updated.fatGoalGrams = parsedFat.value }
        if parsedCarbs.valid { updated.carbsGoalGrams = parsedCarbs.value }

        do {
            let saved = try await settingsService.saveSettings(updated)
            settings = saved
            appSettingsStore.update(saved)
            if previous.dietProfile != saved.dietProfile {
                GamificationService.shared.trackDietProfileSwitch()
            }
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func publishLiveDietDraft() {
        guard !isHydratingSettings else { return }
        let parsedKcal = parseGoal(kcalGoalText)
        let parsedProtein = parseGoal(proteinGoalText)
        let parsedFat = parseGoal(fatGoalText)
        let parsedCarbs = parseGoal(carbsGoalText)

        if macroGoalSource == .manual {
            guard parsedKcal.valid, parsedProtein.valid, parsedFat.valid, parsedCarbs.valid else {
                return
            }
        }

        var draft = settings
        draft.macroGoalSource = macroGoalSource
        draft.strictMacroTracking = strictMacroTracking
        draft.macroTolerancePercent = macroTolerancePercent
        draft.dietProfile = dietProfile
        draft.dietGoalMode = dietGoalMode

        if parsedKcal.valid { draft.kcalGoal = parsedKcal.value }
        if parsedProtein.valid { draft.proteinGoalGrams = parsedProtein.value }
        if parsedFat.valid { draft.fatGoalGrams = parsedFat.value }
        if parsedCarbs.valid { draft.carbsGoalGrams = parsedCarbs.value }

        appSettingsStore.update(draft)
    }

    private func parseGoal(_ text: String) -> (value: Double?, valid: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (nil, true)
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0 else {
            return (nil, false)
        }

        return (value, true)
    }

    private func formatGoal(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
