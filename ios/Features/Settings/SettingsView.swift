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

    var body: some View {
        List {
            Section {
                settingRow(icon: "flame.fill", color: .vayCalories, label: "Калории (ккал)") {
                    TextField("2000", text: $kcalText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }

                settingRow(icon: "fish.fill", color: .vayProtein, label: "Белки (г)") {
                    TextField("80", text: $proteinText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }

                settingRow(icon: "drop.fill", color: .vayFat, label: "Жиры (г)") {
                    TextField("65", text: $fatText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }

                settingRow(icon: "leaf.fill", color: .vayCarbs, label: "Углеводы (г)") {
                    TextField("250", text: $carbsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                sectionHeader(icon: "target", title: "Цели питания")
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
                .vayAccessibilityLabel(
                    showSaved ? "Настройки сохранены" : "Сохранить настройки",
                    hint: "Применяет текущие параметры"
                )
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
                .vayAccessibilityLabel("Информация о приложении, версия \(appVersionText)")
            } header: {
                sectionHeader(icon: "info.circle", title: "О приложении")
            }
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
        .vayAccessibilityLabel(label)
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
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func saveSettings() async {
        guard !isSaving else { return }

        var updated = settings
        updated.kcalGoal = Double(kcalText)
        updated.proteinGoalGrams = Double(proteinText)
        updated.fatGoalGrams = Double(fatText)
        updated.carbsGoalGrams = Double(carbsText)
        updated.weightGoalKg = Double(weightText.replacingOccurrences(of: ",", with: "."))
        updated.quietStartMinute = Calendar.current.minuteOfDay(from: quietStartDate)
        updated.quietEndMinute = Calendar.current.minuteOfDay(from: quietEndDate)
        updated.mealSchedule.breakfastMinute = Calendar.current.minuteOfDay(from: breakfastDate)
        updated.mealSchedule.lunchMinute = Calendar.current.minuteOfDay(from: lunchDate)
        updated.mealSchedule.dinnerMinute = Calendar.current.minuteOfDay(from: dinnerDate)

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
}

extension Calendar {
    func minuteOfDay(from date: Date) -> Int {
        let components = dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
