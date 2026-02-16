import AppIntents
import Foundation

struct AddProductIntent: AppIntent {
    static var title: LocalizedStringResource = "Добавить продукт"
    static var description = IntentDescription("Добавить продукт в инвентарь")
    
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Название продукта")
    var productName: String
    
    @Parameter(title: "Количество", default: 1)
    var quantity: Double
    
    @Parameter(title: "Единица измерения", default: "шт")
    var unit: String
    
    @Parameter(title: "Срок годности (дней)", default: 7)
    var expiryDays: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Добавить \(\.$productName)") {
            \.$quantity
            \.$unit
            \.$expiryDays
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "Укажите название продукта")
        }
        
        return .result(dialog: "Добавлено: \(productName) (\(Int(quantity)) \(unit))")
    }
}
