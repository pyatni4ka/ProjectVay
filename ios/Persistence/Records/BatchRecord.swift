import Foundation
import GRDB

struct BatchRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "batches"

    var id: String
    var productID: String
    var location: String
    var quantity: Double
    var unit: String
    var expiryDate: Date?
    var isOpened: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case productID = "product_id"
        case location
        case quantity
        case unit
        case expiryDate = "expiry_date"
        case isOpened = "is_opened"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension BatchRecord {
    init(batch: Batch) {
        id = batch.id.uuidString
        productID = batch.productId.uuidString
        location = batch.location.rawValue
        quantity = batch.quantity
        unit = batch.unit.rawValue
        expiryDate = batch.expiryDate
        isOpened = batch.isOpened
        createdAt = batch.createdAt
        updatedAt = batch.updatedAt
    }

    func asDomain() -> Batch {
        Batch(
            id: UUID(uuidString: id) ?? UUID(),
            productId: UUID(uuidString: productID) ?? UUID(),
            location: InventoryLocation(rawValue: location) ?? .fridge,
            quantity: quantity,
            unit: UnitType(rawValue: unit) ?? .pcs,
            expiryDate: expiryDate,
            isOpened: isOpened,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
