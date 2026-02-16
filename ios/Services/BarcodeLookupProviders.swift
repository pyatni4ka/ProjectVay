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
        guard var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json") else {
            throw BarcodeLookupProviderError.invalidEndpoint
        }
        components.queryItems = [
            URLQueryItem(name: "lc", value: "ru"),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_ru,brands,categories,categories_tags_ru,nutriments")
        ]
        guard let url = components.url else {
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

        let rawCategory = product.categories?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("en:") && !$0.hasPrefix("fr:") })
        let category = rawCategory ?? "Продукты"

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

// MARK: - barcode-list.ru (HTML parsing)

final class BarcodeListRuProvider: BarcodeLookupProvider, @unchecked Sendable {
    let providerID = "barcode_list_ru"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        guard var components = URLComponents(string: "https://barcode-list.ru/barcode/RU/Поиск.htm") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "barcode", value: barcode)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("ru-RU,ru;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else {
            return nil
        }

        // Extract product name from <title> tag: "Штрихкод ... - ProductName"
        let name = extractProductName(from: html)
        guard let name, !name.isEmpty else { return nil }

        let brand = extractMeta(named: "brand", from: html)
        let category = extractBreadcrumbCategory(from: html)

        return BarcodeLookupPayload(
            barcode: barcode,
            name: name,
            brand: brand,
            category: category ?? "Продукты",
            nutrition: .empty
        )
    }

    // MARK: - HTML Parsing Helpers

    private func extractProductName(from html: String) -> String? {
        // Helper to check if a name is just a generic "Barcode ..." string
        func isGeneric(_ name: String) -> Bool {
            let lower = name.lowercased()
            return lower.hasPrefix("штрих-код") || lower.hasPrefix("штрихкод") || lower.hasPrefix("barcode") || lower == "поиск"
        }

        // Try og:title meta tag first
        if let ogTitle = extractMeta(property: "og:title", from: html) {
            // Format: "Штрихкод 4607... - Название продукта"
            if let dashRange = ogTitle.range(of: " - ") {
                let name = String(ogTitle[dashRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty && !isGeneric(name) { return name }
            }
        }

        // Fallback: try <title> tag
        if let titleContent = extractTagContent(tag: "title", from: html) {
            // Format similar to og:title
            if let dashRange = titleContent.range(of: " - ") {
                let name = String(titleContent[dashRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty && !isGeneric(name) { return name }
            } else if !isGeneric(titleContent) {
                 return titleContent
            }
        }

        // Fallback: try <h1> tag
        if let h1 = extractTagContent(tag: "h1", from: html) {
            let cleaned = h1.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && cleaned.count > 3 && !isGeneric(cleaned) { return cleaned }
        }

        return nil
    }

    private func extractMeta(property: String, from html: String) -> String? {
        // <meta property="og:title" content="...">
        let pattern = "<meta[^>]+property=\"\(property)\"[^>]+content=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let contentRange = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractMeta(named name: String, from html: String) -> String? {
        // <meta name="brand" content="...">
        let pattern = "<meta[^>]+name=\"\(name)\"[^>]+content=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let contentRange = Range(match.range(at: 1), in: html) else { return nil }
        let value = String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func extractTagContent(tag: String, from html: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let contentRange = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractBreadcrumbCategory(from html: String) -> String? {
        // Try to find breadcrumb-like category links
        let pattern = "class=\"breadcrumb[^\"]*\"[^>]*>[^<]*<a[^>]*>([^<]+)</a>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        // Take the last breadcrumb as most specific category
        guard let lastMatch = matches.last,
              let contentRange = Range(lastMatch.range(at: 1), in: html) else { return nil }
        let value = String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
