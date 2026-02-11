import Foundation
import GRDB

struct ProductRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "products"

    var id: String
    var barcode: String?
    var name: String
    var brand: String?
    var category: String
    var imageURL: String?
    var localImagePath: String?
    var defaultUnit: String
    var nutritionJSON: String
    var disliked: Bool
    var mayContainBones: Bool
    var createdAt: Date
    var updatedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let barcode = Column(CodingKeys.barcode)
        static let name = Column(CodingKeys.name)
        static let brand = Column(CodingKeys.brand)
        static let category = Column(CodingKeys.category)
        static let imageURL = Column(CodingKeys.imageURL)
        static let localImagePath = Column(CodingKeys.localImagePath)
        static let defaultUnit = Column(CodingKeys.defaultUnit)
        static let nutritionJSON = Column(CodingKeys.nutritionJSON)
        static let disliked = Column(CodingKeys.disliked)
        static let mayContainBones = Column(CodingKeys.mayContainBones)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case barcode
        case name
        case brand
        case category
        case imageURL = "image_url"
        case localImagePath = "local_image_path"
        case defaultUnit = "default_unit"
        case nutritionJSON = "nutrition_json"
        case disliked
        case mayContainBones = "may_contain_bones"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension ProductRecord {
    init(product: Product) throws {
        id = product.id.uuidString
        barcode = product.barcode
        name = product.name
        brand = product.brand
        category = product.category
        imageURL = product.imageURL?.absoluteString
        localImagePath = product.localImagePath
        defaultUnit = product.defaultUnit.rawValue
        nutritionJSON = try JSONEncoder().encode(product.nutrition).utf8String
        disliked = product.disliked
        mayContainBones = product.mayContainBones
        createdAt = product.createdAt
        updatedAt = product.updatedAt
    }

    func asDomain() throws -> Product {
        let nutritionData = Data(nutritionJSON.utf8)
        let nutrition = (try? JSONDecoder().decode(Nutrition.self, from: nutritionData)) ?? .empty

        return Product(
            id: UUID(uuidString: id) ?? UUID(),
            barcode: barcode,
            name: name,
            brand: brand,
            category: category,
            imageURL: imageURL.flatMap(URL.init(string:)),
            localImagePath: localImagePath,
            defaultUnit: UnitType(rawValue: defaultUnit) ?? .pcs,
            nutrition: nutrition,
            disliked: disliked,
            mayContainBones: mayContainBones,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private extension Data {
    var utf8String: String {
        String(data: self, encoding: .utf8) ?? "{}"
    }
}
