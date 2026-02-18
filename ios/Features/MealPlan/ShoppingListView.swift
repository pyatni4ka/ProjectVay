import SwiftUI

/// Full shopping list screen from the Weekly Autopilot plan.
/// Shows quantities, grouped categories, budget projection, and "already have" toggles.
struct ShoppingListView: View {
    let plan: WeeklyAutopilotResponse

    @State private var checkedItems: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    private var groupedItems: [(String, [WeeklyAutopilotResponse.ShoppingItemQuantity])] {
        let groups = plan.shoppingListGrouped
        let items = plan.shoppingListWithQuantities

        var result: [(String, [WeeklyAutopilotResponse.ShoppingItemQuantity])] = []
        var covered: Set<String> = []

        for (groupName, ingredientNames) in groups.sorted(by: { $0.key < $1.key }) {
            let groupItems = items.filter { item in
                ingredientNames.contains(where: { $0.lowercased() == item.ingredient.lowercased() })
            }
            if !groupItems.isEmpty {
                result.append((groupName, groupItems))
                groupItems.forEach { covered.insert($0.id) }
            }
        }

        let uncovered = items.filter { !covered.contains($0.id) }
        if !uncovered.isEmpty {
            result.append(("Другое", uncovered))
        }

        return result
    }

    private var remainingCost: Double {
        let unchecked = plan.shoppingListWithQuantities.filter { !checkedItems.contains($0.id) }
        return plan.estimatedTotalCost * Double(unchecked.count) / Double(max(plan.shoppingListWithQuantities.count, 1))
    }

    var body: some View {
        NavigationStack {
            List {
                // Budget section
                Section {
                    budgetRow
                }

                // Items by category
                ForEach(groupedItems, id: \.0) { (category, items) in
                    Section(category) {
                        ForEach(items) { item in
                            shoppingRow(item)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Список покупок")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Готово") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сбросить") {
                        checkedItems.removeAll()
                    }
                    .disabled(checkedItems.isEmpty)
                }
            }
        }
    }

    private var budgetRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Оценка стоимости")
                    .font(VayFont.label(14))
                Text("Примерно — часть товаров может быть у вас дома")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                let bp = plan.budgetProjection
                if bp.week.target > 0 {
                    Text("~\(plan.estimatedTotalCost.formatted(.number.precision(.fractionLength(0)))) из \(bp.week.target.formatted(.number.precision(.fractionLength(0)))) ₽")
                        .font(VayFont.label(13))
                        .foregroundStyle(plan.estimatedTotalCost > bp.week.target * 1.05 ? Color.vayWarning : Color.vaySuccess)
                } else {
                    Text("~\(plan.estimatedTotalCost.formatted(.number.precision(.fractionLength(0)))) ₽")
                        .font(VayFont.label(13))
                }

                if !checkedItems.isEmpty {
                    Text("Осталось ~\(remainingCost.formatted(.number.precision(.fractionLength(0)))) ₽")
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, VaySpacing.xs)
    }

    private func shoppingRow(_ item: WeeklyAutopilotResponse.ShoppingItemQuantity) -> some View {
        let isChecked = checkedItems.contains(item.id)

        return Button {
            if isChecked {
                checkedItems.remove(item.id)
            } else {
                checkedItems.insert(item.id)
            }
        } label: {
            HStack(spacing: VaySpacing.md) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isChecked ? Color.vaySuccess : .secondary)

                Text(item.ingredient.capitalized)
                    .font(VayFont.body(14))
                    .strikethrough(isChecked)
                    .foregroundStyle(isChecked ? .secondary : .primary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.approximate
                         ? "~\(formatAmount(item.amount)) \(unitLabel(item.unit))"
                         : "\(formatAmount(item.amount)) \(unitLabel(item.unit))")
                        .font(VayFont.caption(12))
                        .foregroundStyle(.secondary)

                    if item.approximate {
                        Text("примерно")
                            .font(VayFont.caption(10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func formatAmount(_ amount: Double) -> String {
        if amount == 0 { return "—" }
        if amount.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(amount))
        }
        return amount.formatted(.number.precision(.fractionLength(1)))
    }

    private func unitLabel(_ unit: String) -> String {
        switch unit {
        case "g": return "г"
        case "ml": return "мл"
        case "piece": return "шт"
        default: return unit
        }
    }
}
