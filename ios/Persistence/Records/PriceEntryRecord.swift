import Foundation
import GRDB

struct PriceEntryRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "price_entries"

    var id: String
    var productID: String
    var store: String
    var priceMinor: Int64
    var currency: String
    var date: Date

    enum CodingKeys: String, CodingKey {
        case id
        case productID = "product_id"
        case store
        case priceMinor = "price_minor"
        case currency
        case date
    }
}

extension PriceEntryRecord {
    init(priceEntry: PriceEntry) {
        id = priceEntry.id.uuidString
        productID = priceEntry.productId.uuidString
        store = priceEntry.store.rawValue
        priceMinor = priceEntry.price.asMinorUnits
        currency = priceEntry.currency
        date = priceEntry.date
    }

    func asDomain() -> PriceEntry {
        PriceEntry(
            id: UUID(uuidString: id) ?? UUID(),
            productId: UUID(uuidString: productID) ?? UUID(),
            store: Store(rawValue: store) ?? .custom,
            price: Decimal.fromMinorUnits(priceMinor),
            currency: currency,
            date: date
        )
    }
}
