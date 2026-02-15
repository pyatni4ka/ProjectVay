import Foundation
import GRDB

struct InventoryEventRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "inventory_events"

    var id: String
    var type: String
    var productID: String
    var batchID: String?
    var quantityDelta: Double
    var reason: String
    var estimatedValueMinor: Int64?
    var timestamp: Date
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case productID = "product_id"
        case batchID = "batch_id"
        case quantityDelta = "quantity_delta"
        case reason
        case estimatedValueMinor = "estimated_value_minor"
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
        reason = event.reason.rawValue
        estimatedValueMinor = event.estimatedValueMinor
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
            reason: InventoryEventReason(rawValue: reason) ?? .unknown,
            estimatedValueMinor: estimatedValueMinor,
            timestamp: timestamp,
            note: note
        )
    }
}
