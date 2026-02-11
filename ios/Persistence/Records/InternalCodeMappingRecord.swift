import Foundation
import GRDB

struct InternalCodeMappingRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "internal_code_mappings"

    var code: String
    var productID: String
    var parsedWeightGrams: Double?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case code
        case productID = "product_id"
        case parsedWeightGrams = "parsed_weight_grams"
        case createdAt = "created_at"
    }
}

extension InternalCodeMappingRecord {
    init(mapping: InternalCodeMapping) {
        code = mapping.code
        productID = mapping.productId.uuidString
        parsedWeightGrams = mapping.parsedWeightGrams
        createdAt = mapping.createdAt
    }

    func asDomain() -> InternalCodeMapping {
        InternalCodeMapping(
            code: code,
            productId: UUID(uuidString: productID) ?? UUID(),
            parsedWeightGrams: parsedWeightGrams,
            createdAt: createdAt
        )
    }
}
