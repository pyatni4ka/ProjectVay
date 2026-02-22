import Foundation
import GRDB

struct ShoppingListItemRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: String
    var name: String
    var category: String
    var quantity: Double
    var unit: String
    var isCompleted: Bool
    var createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case quantity
        case unit
        case isCompleted = "is_completed"
        case createdAt = "created_at"
    }
    
    static let databaseTableName = "shopping_list_items"
}

extension ShoppingListItemRecord {
    init(item: ShoppingListItem) throws {
        id = item.id.uuidString
        name = item.name
        category = item.category
        quantity = item.quantity
        unit = item.unit.rawValue
        isCompleted = item.isCompleted
        createdAt = item.createdAt
    }

    func asDomain() throws -> ShoppingListItem {
        let parsedUnit = UnitType(rawValue: unit) ?? .pcs
        return ShoppingListItem(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            category: category,
            quantity: quantity,
            unit: parsedUnit,
            isCompleted: isCompleted,
            createdAt: createdAt
        )
    }
}
