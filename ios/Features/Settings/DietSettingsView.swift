import SwiftUI

struct DietSettingsView: View {
    let settingsService: any SettingsServiceProtocol
    @Environment(AppSettingsStore.self) private var appSettingsStore

    @State private var settings: AppSettings = .default
    @State private var lastPersistedSettings: AppSettings = .default
    @State private var isLoading = true
    @State private var isHydratingSettings = false
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var saveErrorMessage: String?

    @State private var macroGoalSource: AppSettings.MacroGoalSource = .automatic
    @State private var strictMacroTracking = true
    @State private var macroTolerancePercent = 25.0
    @State private var dietProfile: AppSettings.DietProfile = .medium
    @State private var dietGoalMode: AppSettings.DietGoalMode = .lose
    @State private var smartOptimizerProfile: AppSettings.SmartOptimizerProfile = .balanced
    @State private var activityLevel: NutritionCalculator.ActivityLevel = .moderatelyActive

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
        let smartOptimizerProfile: AppSettings.SmartOptimizerProfile
        let activityLevel: NutritionCalculator.ActivityLevel
        let kcalGoalText: String
        let proteinGoalText: String
        let fatGoalText: String
        let carbsGoalText: String
    }

    var body: some View {
        List {
            if isLoading {
                loadingSection
            }
            macroSourceSection
            precisionSection
            deficitProfileSection
            smartOptimizerSection
            activitySection
            goalModeSection
            if macroGoalSource == .manual {
                manualGoalsSection
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
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: VayLayout.tabBarOverlayInset)
        }
        .navigationTitle("Диета")
        .task { await loadSettings() }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsDidChange)) { notification in
            guard let updated = notification.object as? AppSettings else { return }
            guard updated != settings else { return }
            applyLoadedSettings(updated)
        }
        .onChange(of: appSettingsStore.settings) { _, updated in
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
        .onChange(of: smartOptimizerProfile) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onChange(of: activityLevel) { _, _ in
            Task { await saveSettingsIfValid() }
        }
        .onDisappear {
            autoSaveTask?.cancel()
            Task { await saveSettingsIfValid() }
        }
    }

    // MARK: - Extracted Sections

    private var loadingSection: some View {
        Section {
            HStack(spacing: VaySpacing.sm) {
                ProgressView()
                Text("Загружаем параметры диеты...")
                    .font(VayFont.body(14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var macroSourceSection: some View {
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
    }

    private var precisionSection: some View {
        Section {
            SettingsRowView(icon: "chart.bar.fill", color: .vayPrimary, title: "Строгий контроль КБЖУ") {
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
    }

    private var deficitProfileSection: some View {
        Section {
            HStack(spacing: VaySpacing.sm) {
                ForEach(AppSettings.DietProfile.allCases, id: \.rawValue) { profile in
                    optionCard(
                        icon: dietProfileIcon(profile),
                        title: profile.title,
                        description: dietProfileCardDescription(profile),
                        isSelected: dietProfile == profile
                    ) {
                        withAnimation(VayAnimation.springSnappy) {
                            dietProfile = profile
                        }
                        VayHaptic.selection()
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: VaySpacing.sm, leading: VaySpacing.sm, bottom: VaySpacing.sm, trailing: VaySpacing.sm))
            .listRowBackground(Color.clear)
        } header: {
            sectionHeader(icon: "leaf.circle.fill", title: "Профиль дефицита")
        }
    }

    private var smartOptimizerSection: some View {
        Section {
            HStack(spacing: VaySpacing.sm) {
                ForEach(AppSettings.SmartOptimizerProfile.allCases, id: \.rawValue) { profile in
                    optionCard(
                        icon: smartOptimizerIcon(profile),
                        title: profile.title,
                        description: smartOptimizerCardDescription(profile),
                        isSelected: smartOptimizerProfile == profile
                    ) {
                        withAnimation(VayAnimation.springSnappy) {
                            smartOptimizerProfile = profile
                        }
                        VayHaptic.selection()
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: VaySpacing.sm, leading: VaySpacing.sm, bottom: VaySpacing.sm, trailing: VaySpacing.sm))
            .listRowBackground(Color.clear)
        } header: {
            sectionHeader(icon: "slider.horizontal.2.square.on.square", title: "Smart-оптимизатор")
        } footer: {
            Text("Выбор влияет на smart-план: приоритет цены или точности КБЖУ.")
                .font(VayFont.caption(11))
                .foregroundStyle(.secondary)
        }
    }

    private var activitySection: some View {
        Section {
            Picker("Уровень активности", selection: $activityLevel) {
                ForEach(NutritionCalculator.ActivityLevel.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.vayPrimary)
            .font(VayFont.body(14))
        } header: {
            sectionHeader(icon: "figure.walk", title: "Активность")
        } footer: {
            Text("Влияет на расчёт TDEE и целевых калорий.")
                .font(VayFont.caption(11))
                .foregroundStyle(.secondary)
        }
    }

    private var goalModeSection: some View {
        Section {
            HStack(spacing: VaySpacing.sm) {
                ForEach(AppSettings.DietGoalMode.allCases, id: \.rawValue) { mode in
                    optionCard(
                        icon: goalModeIcon(mode),
                        title: mode.title,
                        description: goalModeCardDescription(mode),
                        isSelected: dietGoalMode == mode
                    ) {
                        withAnimation(VayAnimation.springSnappy) {
                            dietGoalMode = mode
                        }
                        VayHaptic.selection()
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: VaySpacing.sm, leading: VaySpacing.sm, bottom: VaySpacing.sm, trailing: VaySpacing.sm))
            .listRowBackground(Color.clear)
        } header: {
            sectionHeader(icon: "target", title: "Цель")
        }
    }

    private var manualGoalsSection: some View {
        Section {
            goalField(icon: "flame.fill", color: .vayCalories, label: "Калории", text: $kcalGoalText, suffix: "ккал")
            goalField(icon: "drop.fill", color: .vayProtein, label: "Белки", text: $proteinGoalText, suffix: "г")
            goalField(icon: "circle.fill", color: .vayFat, label: "Жиры", text: $fatGoalText, suffix: "г")
            goalField(icon: "bolt.fill", color: .vayCarbs, label: "Углеводы", text: $carbsGoalText, suffix: "г")
        } header: {
            sectionHeader(icon: "pencil", title: "Ручные цели")
        }
    }

    private var autoSaveState: AutoSaveState {
        AutoSaveState(
            macroGoalSource: macroGoalSource,
            strictMacroTracking: strictMacroTracking,
            macroTolerancePercent: macroTolerancePercent,
            dietProfile: dietProfile,
            dietGoalMode: dietGoalMode,
            smartOptimizerProfile: smartOptimizerProfile,
            activityLevel: activityLevel,
            kcalGoalText: kcalGoalText,
            proteinGoalText: proteinGoalText,
            fatGoalText: fatGoalText,
            carbsGoalText: carbsGoalText
        )
    }

    private func goalField(
        icon: String,
        color: Color,
        label: String,
        text: Binding<String>,
        suffix: String
    ) -> some View {
        SettingsRowView(icon: icon, color: color, title: label) {
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
                .font(VayFont.caption(11))
            Text(title)
        }
        .font(VayFont.caption(12))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    // MARK: - Option Card

    @ViewBuilder
    private func optionCard(
        icon: String,
        title: String,
        description: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: VaySpacing.sm) {
                Image(systemName: icon)
                    .font(VayFont.heading(22))
                    .frame(height: 26)
                Text(title)
                    .font(VayFont.label(13))
                    .lineLimit(1)
                Text(description)
                    .font(VayFont.caption(11))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, VaySpacing.md)
            .padding(.horizontal, VaySpacing.sm)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Color.vayPrimary : Color.vayCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.vayPrimary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(description)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Deficit Profile Helpers

    private func dietProfileIcon(_ profile: AppSettings.DietProfile) -> String {
        switch profile {
        case .light: return "leaf"
        case .medium: return "flame"
        case .extreme: return "bolt.fill"
        }
    }

    private func dietProfileCardDescription(_ profile: AppSettings.DietProfile) -> String {
        switch profile {
        case .light: return "-0.3 кг/нед"
        case .medium: return "-0.5 кг/нед"
        case .extreme: return "-0.8 кг/нед"
        }
    }

    // MARK: - Smart-Optimizer Helpers

    private func smartOptimizerIcon(_ profile: AppSettings.SmartOptimizerProfile) -> String {
        switch profile {
        case .economyAggressive: return "tag.fill"
        case .balanced: return "scale.3d"
        case .macroPrecision: return "scope"
        case .inventoryFirst: return "shippingbox.fill"
        }
    }

    private func smartOptimizerCardDescription(_ profile: AppSettings.SmartOptimizerProfile) -> String {
        switch profile {
        case .economyAggressive: return "Мин. цена"
        case .balanced: return "Цена + КБЖУ"
        case .macroPrecision: return "Точное КБЖУ"
        case .inventoryFirst: return "Мои запасы"
        }
    }

    // MARK: - Goal Mode Helpers

    private func goalModeIcon(_ mode: AppSettings.DietGoalMode) -> String {
        switch mode {
        case .lose: return "arrow.down.right"
        case .maintain: return "equal.circle"
        case .gain: return "arrow.up.right"
        }
    }

    private func goalModeCardDescription(_ mode: AppSettings.DietGoalMode) -> String {
        switch mode {
        case .lose: return "Дефицит"
        case .maintain: return "Баланс"
        case .gain: return "Профицит"
        }
    }

    private func loadSettings() async {
        defer { isLoading = false }

        do {
            let loaded = try await settingsService.loadSettings()
            applyLoadedSettings(loaded)
            appSettingsStore.update(loaded)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func applyLoadedSettings(_ loaded: AppSettings) {
        let normalized = loaded.normalized()
        isHydratingSettings = true
        defer { isHydratingSettings = false }

        settings = normalized
        lastPersistedSettings = normalized
        macroGoalSource = normalized.macroGoalSource
        strictMacroTracking = normalized.strictMacroTracking
        macroTolerancePercent = normalized.macroTolerancePercent
        dietProfile = normalized.dietProfile
        dietGoalMode = normalized.dietGoalMode
        smartOptimizerProfile = normalized.smartOptimizerProfile
        activityLevel = normalized.activityLevel

        kcalGoalText = formatGoal(normalized.kcalGoal)
        proteinGoalText = formatGoal(normalized.proteinGoalGrams)
        fatGoalText = formatGoal(normalized.fatGoalGrams)
        carbsGoalText = formatGoal(normalized.carbsGoalGrams)
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

    @MainActor
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
        updated.smartOptimizerProfile = smartOptimizerProfile
        updated.activityLevel = activityLevel

        if parsedKcal.valid { updated.kcalGoal = parsedKcal.value }
        if parsedProtein.valid { updated.proteinGoalGrams = parsedProtein.value }
        if parsedFat.valid { updated.fatGoalGrams = parsedFat.value }
        if parsedCarbs.valid { updated.carbsGoalGrams = parsedCarbs.value }

        do {
            let saved = try await settingsService.saveSettings(updated)
            settings = saved
            lastPersistedSettings = saved
            appSettingsStore.update(saved)
            if previous.dietProfile != saved.dietProfile {
                GamificationService.shared.trackDietProfileSwitch()
            }
            saveErrorMessage = nil
        } catch {
            rollbackToLastPersisted(with: error)
        }
    }

    @MainActor
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
        draft.smartOptimizerProfile = smartOptimizerProfile
        draft.activityLevel = activityLevel

        if parsedKcal.valid { draft.kcalGoal = parsedKcal.value }
        if parsedProtein.valid { draft.proteinGoalGrams = parsedProtein.value }
        if parsedFat.valid { draft.fatGoalGrams = parsedFat.value }
        if parsedCarbs.valid { draft.carbsGoalGrams = parsedCarbs.value }

        appSettingsStore.publishDraft(draft)
    }

    @MainActor
    private func rollbackToLastPersisted(with error: Error) {
        saveErrorMessage = error.localizedDescription
        applyLoadedSettings(lastPersistedSettings)
        appSettingsStore.update(lastPersistedSettings)
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
