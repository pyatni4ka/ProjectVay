import Foundation

struct ShoppingListItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var category: String
    var quantity: Double
    var unit: UnitType
    var isCompleted: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: String = "Продукты",
        quantity: Double,
        unit: UnitType,
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}
