import Foundation

protocol ShoppingListServiceProtocol: Sendable {
    func getItems() async throws -> [ShoppingListItem]
    func addItem(name: String, quantity: Double, unit: UnitType) async throws
    func toggleItemCompletion(id: UUID) async throws
    func deleteItem(id: UUID) async throws
    func clearCompleted() async throws
    func deleteAllItems() async throws
    func generateFromMealPlan(_ missingIngredients: [String]) async throws
}

final class ShoppingListService: ShoppingListServiceProtocol {
    private let repository: ShoppingListRepositoryProtocol

    init(repository: ShoppingListRepositoryProtocol) {
        self.repository = repository
    }

    func getItems() async throws -> [ShoppingListItem] {
        try repository.listItems()
    }

    func addItem(name: String, quantity: Double, unit: UnitType) async throws {
        let classification = ProductClassifier.classify(rawCategory: name)
        let category = classification.category
        let item = ShoppingListItem(name: name, category: category, quantity: quantity, unit: unit)
        try repository.addItem(item)
    }

    func toggleItemCompletion(id: UUID) async throws {
        let items = try repository.listItems()
        guard var item = items.first(where: { $0.id == id }) else { return }
        
        item.isCompleted.toggle()
        try repository.updateItem(item)
    }

    func deleteItem(id: UUID) async throws {
        try repository.deleteItem(id: id)
    }

    func clearCompleted() async throws {
        try repository.clearCompletedItems()
    }

    func deleteAllItems() async throws {
        try repository.deleteAllItems()
    }

    func generateFromMealPlan(_ missingIngredients: [String]) async throws {
        let currentItems = try repository.listItems()
        let existingNames = Set(currentItems.map { $0.name.lowercased() })
        
        for ingredient in missingIngredients {
            let normalized = ingredient.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !existingNames.contains(normalized.lowercased()) else {
                continue
            }
            
            let classification = ProductClassifier.classify(rawCategory: normalized)
            let category = classification.category
            
            // For now, defaulting quantity to 1 and unit to pcs for string-based ingredients
            let item = ShoppingListItem(name: normalized, category: category, quantity: 1, unit: .pcs)
            try repository.addItem(item)
        }
    }
}
