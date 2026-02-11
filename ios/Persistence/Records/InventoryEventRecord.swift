import Foundation
import GRDB

struct InventoryEventRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "inventory_events"

    var id: String
    var type: String
    var productID: String
    var batchID: String?
    var quantityDelta: Double
    var timestamp: Date
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case productID = "product_id"
        case batchID = "batch_id"
        case quantityDelta = "quantity_delta"
        case timestamp
        case note
    }
}

extension InventoryEventRecord {
    init(event: InventoryEvent) {
        id = event.id.uuidString
        type = event.type.rawValue
        productID = event.productId.uuidString
        batchID = event.batchId?.uuidString
        quantityDelta = event.quantityDelta
        timestamp = event.timestamp
        note = event.note
    }

    func asDomain() -> InventoryEvent {
        InventoryEvent(
            id: UUID(uuidString: id) ?? UUID(),
            type: InventoryEvent.EventType(rawValue: type) ?? .adjust,
            productId: UUID(uuidString: productID) ?? UUID(),
            batchId: batchID.flatMap(UUID.init(uuidString:)),
            quantityDelta: quantityDelta,
            timestamp: timestamp,
            note: note
        )
    }
}
