import SwiftUI

struct SettingsView: View {
    let settingsService: any SettingsServiceProtocol

    @State private var settings: AppSettings = .default
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showSaved = false
    @State private var isSaving = false

    @State private var quietStartDate = Date()
    @State private var quietEndDate = Date()
    @State private var breakfastDate = Date()
    @State private var lunchDate = Date()
    @State private var dinnerDate = Date()

    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var carbsText = ""
    @State private var weightText = ""

    @State private var selectedTheme: Int = 0
    @State private var healthKitReadEnabled: Bool = true
    @State private var healthKitWriteEnabled: Bool = false
    @State private var animationsEnabled: Bool = true
    @State private var macroGoalSource: AppSettings.MacroGoalSource = .automatic
    @State private var recipeServiceURLText: String = ""

    @ObservedObject private var gamification = GamificationService.shared

    private let themeOptions = ["Системный", "Светлый", "Тёмный"]

    var body: some View {
        List {
            Section {
                settingRow(icon: "paintpalette.fill", color: .vayAccent, label: "Тема") {
                    Picker("Тема", selection: $selectedTheme) {
                        ForEach(0..<themeOptions.count, id: \.self) { index in
                            Text(themeOptions[index]).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.vayPrimary)
                }
            } header: {
                sectionHeader(icon: "paintbrush.fill", title: "Внешний вид")
            }

            Section {
                settingRow(icon: "heart.fill", color: .vayDanger, label: "Читать данные") {
                    Toggle("", isOn: $healthKitReadEnabled)
                        .labelsHidden()
                        .tint(Color.vayPrimary)
                }

                settingRow(icon: "heart.text.square.fill", color: .vaySuccess, label: "Записывать калории") {
                    Toggle("", isOn: $healthKitWriteEnabled)
                        .labelsHidden()
                        .tint(Color.vayPrimary)
                }
            } header: {
                sectionHeader(icon: "apple.logo", title: "Apple Health")
            } footer: {
                Text("Разрешить чтение данных о весе и активности из Apple Health.")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }

            Section {
                settingRow(icon: "network", color: .vayInfo, label: "Сервер рецептов") {
                    TextField("http://192.168.1.10:8080", text: $recipeServiceURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                sectionHeader(icon: "wifi.router", title: "Подключение")
            } footer: {
                Text("Оставьте поле пустым, чтобы использовать адрес по умолчанию из конфигурации приложения.")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }

            Section {
                settingRow(icon: "sparkles", color: .vaySecondary, label: "Анимации") {
                    Toggle("", isOn: $animationsEnabled)
                        .labelsHidden()
                        .tint(Color.vayPrimary)
                }
            } header: {
                sectionHeader(icon: "wand.and.stars", title: "Анимация и эффекты")
            }

            Section {
                settingRow(icon: "slider.horizontal.3", color: .vayPrimary, label: "Источник") {
                    Picker("Источник КБЖУ", selection: $macroGoalSource) {
                        ForEach(AppSettings.MacroGoalSource.allCases, id: \.rawValue) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.vayPrimary)
                }

                settingRow(icon: "flame.fill", color: .vayCalories, label: "Калории (ккал)") {
                    TextField("2000", text: $kcalText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .disabled(macroGoalSource == .automatic)
                        .foregroundStyle(macroGoalSource == .automatic ? .secondary : .primary)
                }

                settingRow(icon: "fish.fill", color: .vayProtein, label: "Белки (г)") {
                    TextField("80", text: $proteinText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .disabled(macroGoalSource == .automatic)
                        .foregroundStyle(macroGoalSource == .automatic ? .secondary : .primary)
                }

                settingRow(icon: "drop.fill", color: .vayFat, label: "Жиры (г)") {
                    TextField("65", text: $fatText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .disabled(macroGoalSource == .automatic)
                        .foregroundStyle(macroGoalSource == .automatic ? .secondary : .primary)
                }

                settingRow(icon: "leaf.fill", color: .vayCarbs, label: "Углеводы (г)") {
                    TextField("250", text: $carbsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .disabled(macroGoalSource == .automatic)
                        .foregroundStyle(macroGoalSource == .automatic ? .secondary : .primary)
                }
            } header: {
                sectionHeader(icon: "target", title: "Цели питания")
            } footer: {
                Text(macroGoalSource == .automatic
                     ? "В режиме «Авто» КБЖУ рассчитываются на экране плана питания по HealthKit и формулам."
                     : "В режиме «Вручную» используем ваши фиксированные цели КБЖУ.")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }

            Section {
                settingRow(icon: "scalemass.fill", color: .vayInfo, label: "Цель (кг)") {
                    TextField("70", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                sectionHeader(icon: "figure.stand", title: "Вес")
            }

            Section {
                settingRow(icon: "sunrise.fill", color: .vayAccent, label: "Завтрак") {
                    DatePicker("", selection: $breakfastDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                settingRow(icon: "sun.max.fill", color: .vayWarning, label: "Обед") {
                    DatePicker("", selection: $lunchDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                settingRow(icon: "moon.stars.fill", color: .vaySecondary, label: "Ужин") {
                    DatePicker("", selection: $dinnerDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            } header: {
                sectionHeader(icon: "clock.fill", title: "Расписание приёмов пищи")
            }

            Section {
                settingRow(icon: "moon.zzz.fill", color: .vaySecondary, label: "Начало") {
                    DatePicker("", selection: $quietStartDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                settingRow(icon: "alarm.fill", color: .vayAccent, label: "Конец") {
                    DatePicker("", selection: $quietEndDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            } header: {
                sectionHeader(icon: "bell.slash.fill", title: "Тихие часы")
            }

            Section {
                ForEach(gamification.achievements) { achievement in
                    achievementRow(achievement)
                }
            } header: {
                sectionHeader(icon: "trophy.fill", title: "Достижения")
            } footer: {
                HStack {
                    Text("Серия: \(gamification.userStats.currentStreak) дней")
                    Spacer()
                    Text("Всего продуктов: \(gamification.userStats.totalProductsAdded)")
                }
                .font(VayFont.caption(11))
            }

            Section {
                Button {
                    VayHaptic.selection()
                    Task { await saveSettings() }
                } label: {
                    HStack {
                        Spacer()
                        HStack(spacing: VaySpacing.sm) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else if showSaved {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Сохранено")
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                Text("Сохранить")
                            }
                        }
                        .font(VayFont.label())
                        Spacer()
                    }
                    .padding(.vertical, VaySpacing.md)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: showSaved
                                ? [Color.vaySuccess, Color.vayPrimary]
                                : [Color.vayPrimary, Color.vayAccent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
                    .scaleEffect(isSaving ? 0.98 : 1)
                    .animation(VayAnimation.springSmooth, value: isSaving)
                    .animation(VayAnimation.springSmooth, value: showSaved)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            .listRowBackground(Color.clear)

            Section {
                VStack(alignment: .leading, spacing: VaySpacing.xs) {
                    Text("ДомИнвентарь")
                        .font(VayFont.label(14))
                    Text("Версия \(appVersionText)")
                        .font(VayFont.caption(12))
                        .foregroundStyle(.secondary)
                    Text("© 2026 ProjectVay")
                        .font(VayFont.caption(11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, VaySpacing.xs)
            } header: {
                sectionHeader(icon: "info.circle", title: "О приложении")
            }

            Section {
                Color.clear.frame(height: 60)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Настройки")
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
        .task {
            await loadSettings()
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
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

    private func achievementRow(_ achievement: Achievement) -> some View {
        HStack(spacing: VaySpacing.md) {
            Text(achievement.icon)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(achievement.isUnlocked ? Color.vayPrimaryLight : Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(VayFont.label(14))
                    .foregroundStyle(achievement.isUnlocked ? .primary : .secondary)

                Text(achievement.description)
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)

                if !achievement.isUnlocked {
                    ProgressView(value: achievement.progress)
                        .tint(Color.vayPrimary)
                }
            }

            Spacer()

            if achievement.isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.vaySuccess)
            } else {
                Text("\(achievement.currentProgress)/\(achievement.requiredCount)")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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

    private func loadSettings() async {
        do {
            let s = try await settingsService.loadSettings()
            settings = s
            kcalText = s.kcalGoal.map { "\(Int($0))" } ?? ""
            proteinText = s.proteinGoalGrams.map { "\(Int($0))" } ?? ""
            fatText = s.fatGoalGrams.map { "\(Int($0))" } ?? ""
            carbsText = s.carbsGoalGrams.map { "\(Int($0))" } ?? ""
            weightText = s.weightGoalKg.map { String(format: "%.1f", $0) } ?? ""
            quietStartDate = DateComponents.from(minutes: s.quietStartMinute).asDate
            quietEndDate = DateComponents.from(minutes: s.quietEndMinute).asDate
            breakfastDate = DateComponents.from(minutes: s.mealSchedule.breakfastMinute).asDate
            lunchDate = DateComponents.from(minutes: s.mealSchedule.lunchMinute).asDate
            dinnerDate = DateComponents.from(minutes: s.mealSchedule.dinnerMinute).asDate
            
            selectedTheme = s.preferredColorScheme ?? 0
            healthKitReadEnabled = s.healthKitReadEnabled
            healthKitWriteEnabled = s.healthKitWriteEnabled
            animationsEnabled = s.enableAnimations
            macroGoalSource = s.macroGoalSource
            recipeServiceURLText = s.recipeServiceBaseURLOverride ?? ""

            if macroGoalSource == .automatic {
                if kcalText.isEmpty { kcalText = "2100" }
                if proteinText.isEmpty { proteinText = "140" }
                if fatText.isEmpty { fatText = "65" }
                if carbsText.isEmpty { carbsText = "230" }
            }
            
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func saveSettings() async {
        guard !isSaving else { return }

        let normalizedRecipeServiceURL = recipeServiceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedRecipeServiceURL.isEmpty, !isValidRecipeServerURL(normalizedRecipeServiceURL) {
            errorMessage = "Укажите корректный URL сервера (http:// или https://)."
            return
        }

        var updated = settings
        updated.kcalGoal = Double(kcalText)
        updated.proteinGoalGrams = Double(proteinText)
        updated.fatGoalGrams = Double(fatText)
        updated.carbsGoalGrams = Double(carbsText)
        updated.weightGoalKg = Double(weightText.replacingOccurrences(of: ",", with: "."))
        updated.macroGoalSource = macroGoalSource
        updated.quietStartMinute = Calendar.current.minuteOfDay(from: quietStartDate)
        updated.quietEndMinute = Calendar.current.minuteOfDay(from: quietEndDate)
        updated.mealSchedule.breakfastMinute = Calendar.current.minuteOfDay(from: breakfastDate)
        updated.mealSchedule.lunchMinute = Calendar.current.minuteOfDay(from: lunchDate)
        updated.mealSchedule.dinnerMinute = Calendar.current.minuteOfDay(from: dinnerDate)
        
        updated.preferredColorScheme = selectedTheme
        updated.healthKitReadEnabled = healthKitReadEnabled
        updated.healthKitWriteEnabled = healthKitWriteEnabled
        updated.enableAnimations = animationsEnabled
        updated.recipeServiceBaseURLOverride = normalizedRecipeServiceURL.isEmpty ? nil : normalizedRecipeServiceURL

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await settingsService.saveSettings(updated)
            settings = updated
            VayHaptic.success()
            withAnimation(VayAnimation.springSmooth) {
                showSaved = true
            }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(VayAnimation.springSmooth) {
                showSaved = false
            }
        } catch {
            VayHaptic.error()
            errorMessage = error.localizedDescription
        }
    }

    private func isValidRecipeServerURL(_ value: String) -> Bool {
        guard
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased()
        else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}

extension Calendar {
    func minuteOfDay(from date: Date) -> Int {
        let components = dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
