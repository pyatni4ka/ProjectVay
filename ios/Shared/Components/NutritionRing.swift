import SwiftUI

struct NutritionRing: View {
    let label: String
    let value: Double
    let goal: Double
    let color: Color
    let unit: String

    @State private var animatedProgress: CGFloat = 0

    private var progress: CGFloat {
        guard goal > 0 else { return 0 }
        return min(CGFloat(value / goal), 1.0)
    }

    var body: some View {
        VStack(spacing: VaySpacing.sm) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 6)

                // Progress ring
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // Center value
                VStack(spacing: 0) {
                    Text("\(Int(value))")
                        .font(VayFont.label(16))
                        .foregroundStyle(color)
                    Text(unit)
                        .font(VayFont.caption(9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)

            Text(label)
                .font(VayFont.caption(11))
                .foregroundStyle(.secondary)
        }
        .onAppear {
            withAnimation(VayAnimation.gentleBounce.delay(0.2)) {
                animatedProgress = progress
            }
        }
        .onChange(of: value) {
            withAnimation(VayAnimation.springSmooth) {
                animatedProgress = progress
            }
        }
        .vayAccessibilityLabel(
            "\(label): \(Int(value)) из \(Int(goal)) \(unit)",
            hint: "Кольцо прогресса"
        )
    }
}

// MARK: - Nutrition Ring Group (КБЖУ)

struct NutritionRingGroup: View {
    let kcal: Double
    let protein: Double
    let fat: Double
    let carbs: Double
    let kcalGoal: Double
    let proteinGoal: Double
    let fatGoal: Double
    let carbsGoal: Double

    var body: some View {
        HStack(spacing: VaySpacing.xl) {
            NutritionRing(
                label: "Ккал",
                value: kcal,
                goal: kcalGoal,
                color: .vayCalories,
                unit: "ккал"
            )

            NutritionRing(
                label: "Белки",
                value: protein,
                goal: proteinGoal,
                color: .vayProtein,
                unit: "г"
            )

            NutritionRing(
                label: "Жиры",
                value: fat,
                goal: fatGoal,
                color: .vayFat,
                unit: "г"
            )

            NutritionRing(
                label: "Углев.",
                value: carbs,
                goal: carbsGoal,
                color: .vayCarbs,
                unit: "г"
            )
        }
    }
}

// MARK: - Compact Inline Macros

struct InlineMacros: View {
    let kcal: Double?
    let protein: Double?
    let fat: Double?
    let carbs: Double?

    var body: some View {
        HStack(spacing: VaySpacing.md) {
            if let kcal {
                macroItem("К", value: kcal, color: .vayCalories)
            }
            if let protein {
                macroItem("Б", value: protein, color: .vayProtein)
            }
            if let fat {
                macroItem("Ж", value: fat, color: .vayFat)
            }
            if let carbs {
                macroItem("У", value: carbs, color: .vayCarbs)
            }
        }
        .font(VayFont.caption(11))
    }

    private func macroItem(_ letter: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(letter)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text("\(Int(value))")
                .foregroundStyle(.secondary)
        }
    }
}
