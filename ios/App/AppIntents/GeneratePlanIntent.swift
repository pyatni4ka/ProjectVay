import AppIntents
import Foundation

struct GeneratePlanIntent: AppIntent {
    static var title: LocalizedStringResource = "Сгенерировать план питания"
    static var description = IntentDescription("Создать план питания на основе инвентаря")
    
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "Период", default: "день")
    var period: String
    
    @Parameter(title: "Тип кухни")
    var cuisine: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Сгенерировать план питания на \(\.$period)") {
            \.$cuisine
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "План питания сгенерирован! Откройте приложение для просмотра.")
    }
}

struct GetCaloriesIntent: AppIntent {
    static var title: LocalizedStringResource = "Показать калории"
    static var description = IntentDescription("Показать оставшееся количество калорий на сегодня")
    
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let remaining = 1850
        let consumed = 350
        let goal = 2200
        
        return .result(dialog: "Сегодня съедено: \(consumed) ккал из \(goal). Осталось: \(remaining) ккал.")
    }
}
