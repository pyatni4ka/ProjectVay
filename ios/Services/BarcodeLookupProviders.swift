import Foundation
import GRDB

protocol BarcodeLookupProvider: Sendable {
    var providerID: String { get }
    func lookup(barcode: String) async throws -> BarcodeLookupPayload?
}

enum BarcodeLookupProviderError: Error {
    case invalidEndpoint
}

enum BarcodeLookupPayloadValidator {
    static func normalizeName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    static func isMeaningfulName(_ rawName: String, barcode: String) -> Bool {
        let name = normalizeName(rawName)
        guard !name.isEmpty else { return false }

        let lower = name.lowercased()
        if lower == "поиск" || lower == "search" || lower == "lookup" { return false }
        if lower.contains("штрих-код") || lower.contains("штрихкод") || lower.contains("barcode") { return false }
        if name == barcode { return false }
        if looksLikeSearchPlaceholder(lowercasedName: lower, barcode: barcode) {
            return false
        }

        let hasLetters = name.range(of: #"[A-Za-zА-Яа-яЁё]"#, options: .regularExpression) != nil
        guard hasLetters else { return false }

        // Guard against "4601576009686 - 4601576009686" style placeholders.
        let digitsOnly = name.filter(\.isNumber)
        if digitsOnly == barcode && name.count <= barcode.count + 4 {
            return false
        }

        return true
    }

    private static func looksLikeSearchPlaceholder(lowercasedName: String, barcode: String) -> Bool {
        let compact = lowercasedName.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        for prefix in ["поиск", "search", "lookup"] {
            guard compact.hasPrefix(prefix) else { continue }
            let suffixStart = compact.index(compact.startIndex, offsetBy: prefix.count)
            var suffix = String(compact[suffixStart...])
            suffix = suffix.trimmingCharacters(in: CharacterSet(charactersIn: ":-_#/\\|.,;[](){}'\""))
            guard !suffix.isEmpty else { return true }

            let suffixHasLetters = suffix.range(of: #"[A-Za-zА-Яа-яЁё]"#, options: .regularExpression) != nil
            if !suffixHasLetters {
                return true
            }

            let digitsOnly = suffix.filter(\.isNumber)
            if digitsOnly == barcode {
                return true
            }
        }
        return false
    }

    static func isValidPayload(_ payload: BarcodeLookupPayload, requestedBarcode: String) -> Bool {
        isMeaningfulName(payload.name, barcode: requestedBarcode)
    }
}

final class LocalBarcodeDatabaseProvider: BarcodeLookupProvider, @unchecked Sendable {
    let providerID = "local_barcode_db"

    private let reader: LocalBarcodeDatabaseReader

    init(databasePath: String) throws {
        reader = try LocalBarcodeDatabaseReader(path: databasePath)
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        guard let record = try await reader.lookup(barcode: barcode) else {
            return nil
        }

        guard BarcodeLookupPayloadValidator.isMeaningfulName(record.name, barcode: barcode) else {
            return nil
        }

        return BarcodeLookupPayload(
            barcode: record.barcode,
            name: record.name,
            brand: record.brand,
            category: record.category,
            nutrition: .empty
        )
    }
}

private actor LocalBarcodeDatabaseReader {
    fileprivate struct ProductRecord {
        let barcode: String
        let name: String
        let brand: String?
        let category: String
    }

    private let dbQueue: DatabaseQueue

    init(path: String) throws {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.foreignKeysEnabled = false
        dbQueue = try DatabaseQueue(path: path, configuration: configuration)
    }

    fileprivate func lookup(barcode: String) throws -> ProductRecord? {
        try dbQueue.read { db in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql: """
                    SELECT barcode, name, brand, category
                    FROM products
                    WHERE barcode = ?
                    LIMIT 1
                    """,
                    arguments: [barcode]
                )
            else {
                return nil
            }

            let resolvedBarcode = (row["barcode"] as String?)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? barcode
            let resolvedCategory = ((row["category"] as String?)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : $0
            } ?? "Продукты"
            let brand = ((row["brand"] as String?)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { value in
                value.isEmpty ? nil : value
            }

            return ProductRecord(
                barcode: resolvedBarcode,
                name: (row["name"] as String?) ?? "",
                brand: brand,
                category: resolvedCategory
            )
        }
    }
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
            !title.isEmpty,
            BarcodeLookupPayloadValidator.isMeaningfulName(title, barcode: barcode)
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
        guard !name.isEmpty, BarcodeLookupPayloadValidator.isMeaningfulName(name, barcode: barcode) else { return nil }

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

class OpenFactsBarcodeProvider: BarcodeLookupProvider, @unchecked Sendable {
    let providerID: String

    private let host: String
    private let defaultCategory: String
    private let session: URLSession

    init(providerID: String, host: String, defaultCategory: String, session: URLSession = .shared) {
        self.providerID = providerID
        self.host = host
        self.defaultCategory = defaultCategory
        self.session = session
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        guard var components = URLComponents(string: "https://\(host)/api/v2/product/\(barcode).json") else {
            throw BarcodeLookupProviderError.invalidEndpoint
        }
        components.queryItems = [
            URLQueryItem(name: "lc", value: "ru"),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_ru,generic_name,generic_name_ru,brands,categories,categories_tags_ru,nutriments")
        ]
        guard let url = components.url else {
            throw BarcodeLookupProviderError.invalidEndpoint
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(OpenFactsResponse.self, from: data)
        guard decoded.status == 1, let product = decoded.product else { return nil }

        let name = [
            product.productNameRU,
            product.productName,
            product.genericNameRU,
            product.genericName
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        guard let name else { return nil }
        guard BarcodeLookupPayloadValidator.isMeaningfulName(name, barcode: barcode) else { return nil }

        let brand = product.brands?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        let categoryFromTags = product.categoriesTagsRU?
            .compactMap { tag -> String? in
                let raw = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return nil }
                if raw.hasPrefix("ru:") {
                    return String(raw.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return raw
            }
            .first(where: { !$0.isEmpty })

        let categoryFromText = product.categories?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: {
                !$0.isEmpty &&
                !$0.hasPrefix("en:") &&
                !$0.hasPrefix("fr:")
            })

        let category = categoryFromTags ?? categoryFromText ?? defaultCategory
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

final class OpenFoodFactsBarcodeProvider: OpenFactsBarcodeProvider, @unchecked Sendable {
    init(session: URLSession = .shared) {
        super.init(
            providerID: "open_food_facts",
            host: "world.openfoodfacts.org",
            defaultCategory: "Продукты",
            session: session
        )
    }
}

final class OpenBeautyFactsBarcodeProvider: OpenFactsBarcodeProvider, @unchecked Sendable {
    init(session: URLSession = .shared) {
        super.init(
            providerID: "open_beauty_facts",
            host: "world.openbeautyfacts.org",
            defaultCategory: "Косметика",
            session: session
        )
    }
}

final class OpenPetFoodFactsBarcodeProvider: OpenFactsBarcodeProvider, @unchecked Sendable {
    init(session: URLSession = .shared) {
        super.init(
            providerID: "open_pet_food_facts",
            host: "world.openpetfoodfacts.org",
            defaultCategory: "Корма для животных",
            session: session
        )
    }
}

final class OpenProductsFactsBarcodeProvider: OpenFactsBarcodeProvider, @unchecked Sendable {
    init(session: URLSession = .shared) {
        super.init(
            providerID: "open_products_facts",
            host: "world.openproductsfacts.org",
            defaultCategory: "Товары",
            session: session
        )
    }
}

private struct OpenFactsResponse: Decodable {
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
        let genericNameRU: String?
        let genericName: String?
        let brands: String?
        let categories: String?
        let categoriesTagsRU: [String]?
        let nutriments: Nutriments?

        enum CodingKeys: String, CodingKey {
            case productNameRU = "product_name_ru"
            case productName = "product_name"
            case genericNameRU = "generic_name_ru"
            case genericName = "generic_name"
            case brands
            case categories
            case categoriesTagsRU = "categories_tags_ru"
            case nutriments
        }
    }

    let status: Int?
    let product: ProductData?
}

// MARK: - go-upc.com (HTML parsing)

final class GoUPCBarcodeProvider: BarcodeLookupProvider, @unchecked Sendable {
    let providerID = "go_upc"

    private static let requestTimeoutSeconds: TimeInterval = 6.0
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        guard var components = URLComponents(string: "https://go-upc.com/search") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "q", value: barcode)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeoutSeconds)
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            return nil
        }

        return GoUPCParser.parse(barcode: barcode, document: html)
    }
}

// MARK: - barcode-list.ru (HTML parsing)

final class BarcodeListRuProvider: BarcodeLookupProvider, @unchecked Sendable {
    let providerID = "barcode_list_ru"

    private static let directRequestTimeoutSeconds: TimeInterval = 3.0
    private static let mirrorRequestTimeoutSeconds: TimeInterval = 7.0
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        await withTaskGroup(of: BarcodeLookupPayload?.self, returning: BarcodeLookupPayload?.self) { group in
            group.addTask { [self] in
                try? await lookupViaMirror(barcode: barcode)
            }
            group.addTask { [self] in
                try? await lookupDirect(barcode: barcode)
            }

            while let payload = await group.next() {
                if let payload {
                    group.cancelAll()
                    return payload
                }
            }

            return nil
        }
    }

    private func lookupDirect(barcode: String) async throws -> BarcodeLookupPayload? {
        guard var components = URLComponents(string: "https://barcode-list.ru/barcode/RU/Поиск.htm") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "barcode", value: barcode)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: Self.directRequestTimeoutSeconds)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("ru-RU,ru;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else {
            return nil
        }

        return BarcodeListRuParser.parse(barcode: barcode, document: html)
    }

    private func lookupViaMirror(barcode: String) async throws -> BarcodeLookupPayload? {
        // Use http for the target URL because barcode-list.ru often has cert issues.
        // The mirror itself (r.jina.ai) is accessed via https.
        guard var components = URLComponents(string: "https://r.jina.ai/http://barcode-list.ru/barcode/RU/%D0%9F%D0%BE%D0%B8%D1%81%D0%BA.htm") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "barcode", value: barcode)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: Self.mirrorRequestTimeoutSeconds)
        request.setValue("text/plain, text/markdown;q=0.9, */*;q=0.1", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        guard let markdown = String(data: data, encoding: .utf8), !markdown.isEmpty else {
            return nil
        }

        return BarcodeListRuParser.parse(barcode: barcode, document: markdown)
    }
}

enum GoUPCParser {
    static func parse(barcode: String, document: String) -> BarcodeLookupPayload? {
        let lower = document.lowercased()
        if lower.contains("<title>invalid value") || lower.contains("<title>barcode not found") {
            return nil
        }

        guard
            let name = extractProductName(from: document),
            BarcodeLookupPayloadValidator.isMeaningfulName(name, barcode: barcode)
        else {
            return nil
        }

        let brand = extractMetadataValue(label: "Brand", from: document)
        let category = extractMetadataValue(label: "Category", from: document) ?? "Продукты"

        return BarcodeLookupPayload(
            barcode: barcode,
            name: name,
            brand: brand,
            category: category,
            nutrition: .empty
        )
    }

    private static func extractProductName(from html: String) -> String? {
        if let fromH1 = extractFirstMatch(
            pattern: #"<h1[^>]*class="[^"]*product-name[^"]*"[^>]*>(.*?)</h1>"#,
            from: html
        ) {
            let cleaned = cleanup(fromH1)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        if let rawTitle = extractFirstMatch(pattern: #"<title>(.*?)</title>"#, from: html) {
            var title = cleanup(rawTitle)
            if let range = title.range(of: " — EAN ", options: .caseInsensitive) {
                title = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let range = title.range(of: " - EAN ", options: .caseInsensitive) {
                title = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return title.isEmpty ? nil : title
        }

        return nil
    }

    private static func extractMetadataValue(label: String, from html: String) -> String? {
        let escapedLabel = NSRegularExpression.escapedPattern(for: label)
        let pattern = #"<td[^>]*class="metadata-label"[^>]*>\s*"# + escapedLabel + #"\s*</td>\s*<td>(.*?)</td>"#
        guard let value = extractFirstMatch(pattern: pattern, from: html) else {
            return nil
        }

        let cleaned = cleanup(value)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func extractFirstMatch(pattern: String, from html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..., in: html)
        guard
            let match = regex.firstMatch(in: html, range: range),
            let valueRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        return String(html[valueRange])
    }

    private static func cleanup(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum BarcodeListRuParser {
    // MARK: - HTML Parsing Helpers

    static func parse(barcode: String, document: String) -> BarcodeLookupPayload? {
        let name = extractProductName(from: document, barcode: barcode)
        guard let name, !name.isEmpty else { return nil }

        let brand = extractMeta(named: "brand", from: document)
        let category = extractBreadcrumbCategory(from: document) ?? "Продукты"

        return BarcodeLookupPayload(
            barcode: barcode,
            name: name,
            brand: brand,
            category: category,
            nutrition: .empty
        )
    }

    private static func extractProductName(from html: String, barcode: String) -> String? {
        func isGeneric(_ name: String) -> Bool {
            !BarcodeLookupPayloadValidator.isMeaningfulName(name, barcode: barcode)
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

        if let titleLine = extractMarkdownTitle(from: html), !isGeneric(titleLine) {
            return titleLine
        }

        // Search results fallback: parse row that contains exact barcode.
        if let fromRows = extractNameFromSearchRows(barcode: barcode, from: html) {
            let cleaned = fromRows.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && !isGeneric(cleaned) {
                return cleaned
            }
        }

        return nil
    }

    private static func extractMeta(property: String, from html: String) -> String? {
        // <meta property="og:title" content="...">
        let pattern = "<meta[^>]+property=\"\(property)\"[^>]+content=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let contentRange = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractMeta(named name: String, from html: String) -> String? {
        // <meta name="brand" content="...">
        let pattern = "<meta[^>]+name=\"\(name)\"[^>]+content=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let contentRange = Range(match.range(at: 1), in: html) else { return nil }
        let value = String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func extractTagContent(tag: String, from html: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let contentRange = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractBreadcrumbCategory(from html: String) -> String? {
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

    private static func extractNameFromSearchRows(barcode: String, from html: String) -> String? {
        if let bestFromMarkdown = extractBestNameFromMarkdownTable(barcode: barcode, in: html) {
            return bestFromMarkdown
        }

        let text = plainText(from: html)
        let lines = text.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard line.contains(barcode) else { continue }

            if line.contains("|") {
                let columns = line
                    .split(separator: "|")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if let codeIndex = columns.firstIndex(of: barcode), columns.indices.contains(codeIndex + 1) {
                    let candidate = columns[codeIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if BarcodeLookupPayloadValidator.isMeaningfulName(candidate, barcode: barcode) {
                        return candidate
                    }
                }
                continue
            }

            guard let range = line.range(of: barcode) else { continue }
            var candidate = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }

            // Drop trailing unit/rating fragments (e.g. "ШТ. 1", "КГ 2").
            candidate = candidate.replacingOccurrences(
                of: #"(\s+[А-ЯA-Z]{1,4}\.?[\s]+[0-9]+)\s*$"#,
                with: "",
                options: .regularExpression
            )
            candidate = candidate.replacingOccurrences(
                of: #"\s+[0-9]+\s*$"#,
                with: "",
                options: .regularExpression
            )
            candidate = candidate.replacingOccurrences(
                of: #"^[|:\-\s]+"#,
                with: "",
                options: .regularExpression
            )
            if let firstPipe = candidate.firstIndex(of: "|") {
                candidate = String(candidate[..<firstPipe]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            if BarcodeLookupPayloadValidator.isMeaningfulName(candidate, barcode: barcode) {
                return candidate
            }
        }

        return nil
    }

    private static func extractBestNameFromMarkdownTable(barcode: String, in text: String) -> String? {
        let escapedBarcode = NSRegularExpression.escapedPattern(for: barcode)
        let pattern = #"(?mi)^\|\s*\d+\s*\|\s*"# + escapedBarcode + #"\s*\|\s*([^|]+?)\s*\|\s*[^|]*\|\s*(\d+)\s*\|?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)

        var bestName: String?
        var bestScore = Int.min

        for match in regex.matches(in: text, range: nsRange) {
            guard
                let nameRange = Range(match.range(at: 1), in: text),
                let ratingRange = Range(match.range(at: 2), in: text)
            else {
                continue
            }

            let candidate = String(text[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard BarcodeLookupPayloadValidator.isMeaningfulName(candidate, barcode: barcode) else { continue }

            let rating = Int(String(text[ratingRange])) ?? 0
            let letterCount = candidate.unicodeScalars.reduce(into: 0) { partialResult, scalar in
                if CharacterSet.letters.contains(scalar) {
                    partialResult += 1
                }
            }
            let score = rating * 1000 + letterCount * 2 + candidate.count
            if score > bestScore {
                bestScore = score
                bestName = candidate
            }
        }

        return bestName
    }

    private static func extractMarkdownTitle(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.lowercased().hasPrefix("title:") else { continue }
            let value = line.dropFirst("title:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 4 {
                return value
            }
        }
        return nil
    }

    private static func plainText(from html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</tr>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)

        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")

        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
        return text
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
