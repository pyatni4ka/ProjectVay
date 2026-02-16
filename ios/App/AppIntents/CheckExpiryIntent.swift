import AppIntents
import Foundation
import SwiftUI

struct CheckExpiryIntent: AppIntent {
    static var title: LocalizedStringResource = "Проверить срок годности"
    static var description = IntentDescription("Показать продукты с истекающим сроком годности")
    
    static var openAppWhenRun: Bool = false
    
    static var parameterSummary: some ParameterSummary {
        Summary("Что скоро испортится")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let products = [
            "Молоко (1 шт) - истекает завтра",
            "Йогурт (2 шт) - истекает через 3 дня",
            "Сыр - истекает через 5 дней"
        ]
        
        let message: String
        if products.isEmpty {
            message = "Нет продуктов с истекающим сроком годности. Всё свежее! 🎉"
        } else {
            message = "Скоро истекает:\n" + products.joined(separator: "\n")
        }
        
        return .result(dialog: IntentDialog(stringLiteral: message)) {
            ExpiryListView(products: products)
        }
    }
}

struct ExpiryListView: View {
    let products: [String]
    
    var body: some View {
        List(products, id: \.self) { product in
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(product)
            }
        }
        .listStyle(.plain)
    }
}
