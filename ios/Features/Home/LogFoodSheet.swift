import SwiftUI

struct LogFoodSheet: View {
    let healthKitService: HealthKitService
    var onLogged: ((Nutrition) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var carbsText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    nutrientField(icon: "flame.fill", color: .vayCalories, label: "Калории", text: $kcalText, suffix: "ккал")
                    nutrientField(icon: "drop.fill", color: .vayProtein, label: "Белки", text: $proteinText, suffix: "г")
                    nutrientField(icon: "circle.fill", color: .vayFat, label: "Жиры", text: $fatText, suffix: "г")
                    nutrientField(icon: "bolt.fill", color: .vayCarbs, label: "Углеводы", text: $carbsText, suffix: "г")
                } header: {
                    Text("Введите данные о приёме пищи")
                        .font(VayFont.caption(12))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                } footer: {
                    Text("Данные будут записаны в Apple Health.")
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(VayFont.caption(12))
                            .foregroundStyle(Color.vayDanger)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Съел другое")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Записать").bold()
                        }
                    }
                    .disabled(isSaving || parsedNutrition == nil)
                }
            }
        }
    }

    private var parsedNutrition: Nutrition? {
        let kcal = parseDouble(kcalText)
        let protein = parseDouble(proteinText)
        let fat = parseDouble(fatText)
        let carbs = parseDouble(carbsText)
        guard kcal != nil || protein != nil || fat != nil || carbs != nil else { return nil }
        return Nutrition(kcal: kcal, protein: protein, fat: fat, carbs: carbs)
    }

    private func parseDouble(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let v = Double(t), v > 0 else { return nil }
        return v
    }

    @MainActor
    private func save() async {
        guard let nutrition = parsedNutrition else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await healthKitService.logNutrition(nutrition, date: Date())
            onLogged?(nutrition)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func nutrientField(icon: String, color: Color, label: String, text: Binding<String>, suffix: String) -> some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: icon)
                .font(VayFont.label(13))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(label)
                .font(VayFont.body(15))

            Spacer()

            HStack(spacing: VaySpacing.xs) {
                TextField("—", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 60)
                Text(suffix)
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
