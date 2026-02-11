import Foundation

protocol BarcodeLookupProvider: Sendable {
    var providerID: String { get }
    func lookup(barcode: String) async throws -> BarcodeLookupPayload?
}

enum BarcodeLookupProviderError: Error {
    case invalidEndpoint
}

final class EANDBBarcodeProvider: BarcodeLookupProvider, @unchecked Sendable {
    let providerID = "ean_db"

    private let apiKey: String?
    private let endpoint: URL?
    private let session: URLSession

    init(apiKey: String?, endpoint: URL? = URL(string: "https://ean-db.com/api"), session: URLSession = .shared) {
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint
        self.session = session
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        guard let endpoint, let apiKey, !apiKey.isEmpty else { return nil }

        let url = endpoint.appending(queryItems: [
            URLQueryItem(name: "barcode", value: barcode),
            URLQueryItem(name: "keycode", value: apiKey)
        ])

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
        else {
            return nil
        }

        let brand = (json["brand"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = ((json["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Продукты"

        return BarcodeLookupPayload(
            barcode: barcode,
            name: title,
            brand: brand?.isEmpty == true ? nil : brand,
            category: category,
            nutrition: .empty
        )
    }
}

final class RFBarcodeProvider: BarcodeLookupProvider, @unchecked Sendable {
    let providerID = "rf_source"

    private let endpoint: URL?
    private let session: URLSession

    init(endpoint: URL?, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        guard let endpoint else { return nil }

        let url = endpoint.appending(path: "/barcode/lookup").appending(queryItems: [
            URLQueryItem(name: "code", value: barcode)
        ])

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        struct Response: Decodable {
            struct Item: Decodable {
                struct NutritionPayload: Decodable {
                    let kcal: Double?
                    let protein: Double?
                    let fat: Double?
                    let carbs: Double?
                }

                let barcode: String?
                let name: String?
                let brand: String?
                let category: String?
                let nutrition: NutritionPayload?
            }

            let found: Bool
            let product: Item?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard decoded.found, let product = decoded.product else { return nil }

        let name = product.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }

        let category = product.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BarcodeLookupPayload(
            barcode: product.barcode ?? barcode,
            name: name,
            brand: product.brand?.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category?.isEmpty == false ? category! : "Продукты",
            nutrition: Nutrition(
                kcal: product.nutrition?.kcal,
                protein: product.nutrition?.protein,
                fat: product.nutrition?.fat,
                carbs: product.nutrition?.carbs
            )
        )
    }
}

final class OpenFoodFactsBarcodeProvider: BarcodeLookupProvider, @unchecked Sendable {
    let providerID = "open_food_facts"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json") else {
            throw BarcodeLookupProviderError.invalidEndpoint
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        struct OFFResponse: Decodable {
            struct ProductData: Decodable {
                struct Nutriments: Decodable {
                    let kcal: Double?
                    let proteins: Double?
                    let fat: Double?
                    let carbs: Double?

                    enum CodingKeys: String, CodingKey {
                        case kcal = "energy-kcal_100g"
                        case proteins = "proteins_100g"
                        case fat = "fat_100g"
                        case carbs = "carbohydrates_100g"
                    }
                }

                let productNameRU: String?
                let productName: String?
                let brands: String?
                let categories: String?
                let nutriments: Nutriments?

                enum CodingKeys: String, CodingKey {
                    case productNameRU = "product_name_ru"
                    case productName = "product_name"
                    case brands
                    case categories
                    case nutriments
                }
            }

            let status: Int?
            let product: ProductData?
        }

        let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
        guard decoded.status == 1, let product = decoded.product else { return nil }

        let name = (product.productNameRU ?? product.productName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let brand = product.brands?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first

        let category = product.categories?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Продукты"

        let nutrition = Nutrition(
            kcal: product.nutriments?.kcal,
            protein: product.nutriments?.proteins,
            fat: product.nutriments?.fat,
            carbs: product.nutriments?.carbs
        )

        return BarcodeLookupPayload(
            barcode: barcode,
            name: name,
            brand: brand,
            category: category,
            nutrition: nutrition
        )
    }
}

private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }

        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url ?? self
    }
}
