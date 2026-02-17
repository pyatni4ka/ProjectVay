import Foundation
import Network
import Combine

enum RecipeServiceClientError: Error, Equatable, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case noConnection
    case offlineMode

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Сервер рецептов вернул некорректный ответ."
        case let .httpError(statusCode, _):
            if statusCode >= 500 {
                return "Сервер рецептов временно недоступен. Попробуйте позже."
            }
            return "Ошибка сервера рецептов (\(statusCode))."
        case .noConnection:
            return "Нет подключения к серверу рецептов."
        case .offlineMode:
            return "Сеть недоступна. Работаем в офлайн-режиме."
        }
    }

    static func from(_ error: Error) -> RecipeServiceClientError? {
        if let recipeError = error as? RecipeServiceClientError {
            return recipeError
        }

        guard let urlError = error as? URLError else {
            return nil
        }

        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .timedOut,
             .dataNotAllowed,
             .callIsActive:
            return .noConnection
        default:
            return nil
        }
    }
}

final class RecipeServiceClient: @unchecked Sendable {
    private let defaultBaseURL: URL
    private var baseURL: URL
    private let session: URLSession
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.vay.networkmonitor")
    
    @Published private(set) var isOnline: Bool = true
    
    private var localCache: [String: CachedRecipe] = [:]
    private let maxCacheSize = 100
    private let cacheExpirationHours: TimeInterval = 24 * 7
    
    private let retryDelays: [TimeInterval] = [1, 2, 4, 8]

    init(baseURL: URL, session: URLSession = .shared) {
        self.defaultBaseURL = baseURL
        self.baseURL = baseURL
        self.session = session
        self.monitor = NWPathMonitor()
        startMonitoring()
        loadCacheFromDisk()
    }
    
    deinit {
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    func updateBaseURL(_ url: URL?) {
        baseURL = url ?? defaultBaseURL
    }

    func search(query: String) async throws -> [Recipe] {
        guard isOnline else {
            return try await getCachedRecipes(for: query)
        }

        let url = baseURL.appending(path: "/api/v1/recipes/search").appending(queryItems: [
            URLQueryItem(name: "q", value: query)
        ])

        return try await performRequestWithRetry {
            let (data, response) = try await self.session.data(from: url)
            try self.validate(response: response, data: data)
            let recipes = try self.decodeRecipes(data: data)
            self.cacheRecipes(recipes, for: query)
            return recipes
        }
    }

    func recommend(payload: RecommendRequest) async throws -> RecommendResponse {
        guard isOnline else {
            throw RecipeServiceClientError.offlineMode
        }

        let endpoint = baseURL.appending(path: "/api/v1/recipes/recommend")

        return try await performRequestWithRetry {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await self.session.data(for: request)
            try self.validate(response: response, data: data)
            return try JSONDecoder().decode(RecommendResponse.self, from: data)
        }
    }

    func generateMealPlan(payload: MealPlanGenerateRequest) async throws -> MealPlanGenerateResponse {
        guard isOnline else {
            throw RecipeServiceClientError.offlineMode
        }

        let endpoint = baseURL.appending(path: "/api/v1/meal-plan/generate")

        return try await performRequestWithRetry {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await self.session.data(for: request)
            try self.validate(response: response, data: data)
            return try JSONDecoder().decode(MealPlanGenerateResponse.self, from: data)
        }
    }

    func generateSmartMealPlan(payload: SmartMealPlanGenerateRequest) async throws -> SmartMealPlanGenerateResponse {
        guard isOnline else {
            throw RecipeServiceClientError.offlineMode
        }

        let endpoint = baseURL.appending(path: "/api/v1/meal-plan/smart-generate")

        return try await performRequestWithRetry {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await self.session.data(for: request)
            try self.validate(response: response, data: data)
            return try JSONDecoder().decode(SmartMealPlanGenerateResponse.self, from: data)
        }
    }

    func parseRecipe(url: String) async throws -> RecipeParseResponse {
        guard isOnline else {
            throw RecipeServiceClientError.offlineMode
        }

        let endpoint = baseURL.appending(path: "/api/v1/recipes/parse")

        return try await performRequestWithRetry {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(RecipeParseRequest(url: url))
            let (data, response) = try await self.session.data(for: request)
            try self.validate(response: response, data: data)
            return try JSONDecoder().decode(RecipeParseResponse.self, from: data)
        }
    }

    func estimatePrices(payload: PriceEstimateRequest) async throws -> PriceEstimateResponse {
        guard isOnline else {
            throw RecipeServiceClientError.offlineMode
        }

        let endpoint = baseURL.appending(path: "/api/v1/prices/estimate")

        return try await performRequestWithRetry {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await self.session.data(for: request)
            try self.validate(response: response, data: data)
            return try JSONDecoder().decode(PriceEstimateResponse.self, from: data)
        }
    }
    
    private func performRequestWithRetry<T>(
        maxAttempts: Int = 4,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                let mappedError = RecipeServiceClientError.from(error) ?? error
                lastError = mappedError

                if case RecipeServiceClientError.noConnection = mappedError {
                    if attempt < maxAttempts - 1 {
                        let delay = retryDelays[min(attempt, retryDelays.count - 1)]
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                }

                if case RecipeServiceClientError.httpError(let statusCode, _) = mappedError {
                    if statusCode >= 500 && attempt < maxAttempts - 1 {
                        let delay = retryDelays[min(attempt, retryDelays.count - 1)]
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                }

                throw mappedError
            }
        }

        throw lastError ?? RecipeServiceClientError.invalidResponse
    }

    private func decodeRecipes(data: Data) throws -> [Recipe] {
        struct Wrapper: Decodable { let items: [Recipe] }
        return try JSONDecoder().decode(Wrapper.self, from: data).items
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RecipeServiceClientError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RecipeServiceClientError.httpError(statusCode: http.statusCode, body: body)
        }
    }
    
    private func cacheRecipes(_ recipes: [Recipe], for _: String) {
        for recipe in recipes {
            let cached = CachedRecipe(
                recipe: recipe,
                cachedAt: Date()
            )
            localCache[recipe.id] = cached
        }
        
        cleanupCache()
        saveCacheToDisk()
    }
    
    private func getCachedRecipes(for query: String) async throws -> [Recipe] {
        let cacheKey = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let matchingRecipes = localCache.values
            .filter { !$0.isExpired(expirationHours: cacheExpirationHours) }
            .filter { $0.recipe.title.lowercased().contains(cacheKey) || 
                       $0.recipe.ingredients.joined(separator: " ").lowercased().contains(cacheKey) }
            .map { $0.recipe }
        
        if matchingRecipes.isEmpty {
            throw RecipeServiceClientError.offlineMode
        }
        
        return Array(matchingRecipes.prefix(50))
    }
    
    private func cleanupCache() {
        let sortedKeys = localCache.keys.sorted { key1, key2 in
            guard let c1 = localCache[key1], let c2 = localCache[key2] else { return false }
            return c1.cachedAt > c2.cachedAt
        }
        
        if localCache.count > maxCacheSize {
            let keysToRemove = sortedKeys.dropFirst(maxCacheSize)
            for key in keysToRemove {
                localCache.removeValue(forKey: key)
            }
        }
    }
    
    private func saveCacheToDisk() {
        guard let containerURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        
        let cacheURL = containerURL.appendingPathComponent("recipe_cache.json")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(Array(localCache.values)) {
            try? data.write(to: cacheURL)
        }
    }
    
    private func loadCacheFromDisk() {
        guard let containerURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        
        let cacheURL = containerURL.appendingPathComponent("recipe_cache.json")
        
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? decoder.decode([String: CachedRecipe].self, from: data) {
            localCache = cached
        }
    }
}

private struct CachedRecipe: Codable {
    let recipe: Recipe
    let cachedAt: Date
    
    func isExpired(expirationHours: TimeInterval) -> Bool {
        Date().timeIntervalSince(cachedAt) > expirationHours * 3600
    }
}
