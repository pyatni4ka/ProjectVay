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
    private let localCatalog: LocalRecipeCatalog
    private let queue = DispatchQueue(label: "com.vay.networkmonitor")
    
    @Published private(set) var isOnline: Bool = true
    
    private var localCache: [String: CachedRecipe] = [:]
    private let maxCacheSize = 100
    private let cacheExpirationHours: TimeInterval = 24 * 7
    
    private let retryDelays: [TimeInterval] = [1, 2, 4, 8]

    init(
        baseURL: URL,
        session: URLSession = .shared,
        localCatalog: LocalRecipeCatalog = .init()
    ) {
        self.defaultBaseURL = baseURL
        self.baseURL = baseURL
        self.session = session
        self.localCatalog = localCatalog
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
            return localSearch(query: query)
        }

        let url = baseURL.appending(path: "/api/v1/recipes/search").appending(queryItems: [
            URLQueryItem(name: "q", value: query)
        ])

        do {
            return try await performRequestWithRetry {
                let (data, response) = try await self.session.data(from: url)
                try self.validate(response: response, data: data)
                let recipes = try self.decodeRecipes(data: data)
                self.cacheRecipes(recipes)
                return recipes
            }
        } catch {
            let mappedError = RecipeServiceClientError.from(error) ?? error
            if shouldFallbackToLocal(for: mappedError) {
                return localSearch(query: query)
            }
            throw mappedError
        }
    }

    func recommend(payload: RecommendRequest) async throws -> RecommendResponse {
        guard isOnline else {
            return effectiveLocalCatalog().recommend(payload: payload)
        }

        let endpoint = baseURL.appending(path: "/api/v1/recipes/recommend")

        do {
            return try await performRequestWithRetry {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(payload)
                let (data, response) = try await self.session.data(for: request)
                try self.validate(response: response, data: data)
                let decoded = try JSONDecoder().decode(RecommendResponse.self, from: data)
                self.cacheRecipes(decoded.items.map(\.recipe))
                return decoded
            }
        } catch {
            let mappedError = RecipeServiceClientError.from(error) ?? error
            if shouldFallbackToLocal(for: mappedError) {
                return effectiveLocalCatalog().recommend(payload: payload)
            }
            throw mappedError
        }
    }

    func generateMealPlan(payload: MealPlanGenerateRequest) async throws -> MealPlanGenerateResponse {
        guard isOnline else {
            return effectiveLocalCatalog().generateMealPlan(payload: payload)
        }

        let endpoint = baseURL.appending(path: "/api/v1/meal-plan/generate")

        do {
            return try await performRequestWithRetry {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(payload)
                let (data, response) = try await self.session.data(for: request)
                try self.validate(response: response, data: data)
                let decoded = try JSONDecoder().decode(MealPlanGenerateResponse.self, from: data)
                self.cacheRecipes(decoded.days.flatMap { $0.entries.map(\.recipe) })
                return decoded
            }
        } catch {
            let mappedError = RecipeServiceClientError.from(error) ?? error
            if shouldFallbackToLocal(for: mappedError) {
                return effectiveLocalCatalog().generateMealPlan(payload: payload)
            }
            throw mappedError
        }
    }

    func generateSmartMealPlan(payload: SmartMealPlanGenerateRequest) async throws -> SmartMealPlanGenerateResponse {
        guard isOnline else {
            return effectiveLocalCatalog().generateSmartMealPlan(payload: payload)
        }

        let endpoint = baseURL.appending(path: "/api/v1/meal-plan/smart-generate")

        do {
            return try await performRequestWithRetry {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(payload)
                let (data, response) = try await self.session.data(for: request)
                try self.validate(response: response, data: data)
                let decoded = try JSONDecoder().decode(SmartMealPlanGenerateResponse.self, from: data)
                self.cacheRecipes(decoded.days.flatMap { $0.entries.map(\.recipe) })
                return decoded
            }
        } catch {
            let mappedError = RecipeServiceClientError.from(error) ?? error
            if shouldFallbackToLocal(for: mappedError) {
                return effectiveLocalCatalog().generateSmartMealPlan(payload: payload)
            }
            throw mappedError
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
            let decoded = try JSONDecoder().decode(RecipeParseResponse.self, from: data)
            self.cacheRecipes([decoded.recipe])
            return decoded
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
    
    // MARK: - Weekly Autopilot

    func generateWeeklyAutopilot(payload: WeeklyAutopilotRequest) async throws -> WeeklyAutopilotResponse {
        guard isOnline else {
            throw RecipeServiceClientError.offlineMode
        }

        let endpoint = baseURL.appending(path: "/api/v1/meal-plan/week")

        return try await performRequestWithRetry {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await self.session.data(for: request)
            try self.validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(WeeklyAutopilotResponse.self, from: data)
            self.cacheRecipes(decoded.days.flatMap { $0.entries.map(\.recipe) })
            return decoded
        }
    }

    func replaceMeal(payload: ReplaceMealRequest) async throws -> ReplaceMealResponse {
        guard isOnline else {
            throw RecipeServiceClientError.offlineMode
        }

        let endpoint = baseURL.appending(path: "/api/v1/meal-plan/replace")

        return try await performRequestWithRetry {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await self.session.data(for: request)
            try self.validate(response: response, data: data)
            return try JSONDecoder().decode(ReplaceMealResponse.self, from: data)
        }
    }

    func adaptPlan(payload: AdaptPlanRequest) async throws -> AdaptPlanResponse {
        guard isOnline else {
            throw RecipeServiceClientError.offlineMode
        }

        let endpoint = baseURL.appending(path: "/api/v1/meal-plan/adapt")

        return try await performRequestWithRetry {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await self.session.data(for: request)
            try self.validate(response: response, data: data)
            return try JSONDecoder().decode(AdaptPlanResponse.self, from: data)
        }
    }

    func cookNow(payload: CookNowRequest) async throws -> CookNowResponse {
        guard isOnline else {
            throw RecipeServiceClientError.offlineMode
        }

        let endpoint = baseURL.appending(path: "/api/v1/recipes/cook-now")

        return try await performRequestWithRetry {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await self.session.data(for: request)
            try self.validate(response: response, data: data)
            return try JSONDecoder().decode(CookNowResponse.self, from: data)
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
    
    private func cacheRecipes(_ recipes: [Recipe]) {
        guard !recipes.isEmpty else { return }

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
        
        if let data = try? Data(contentsOf: cacheURL) {
            if let cachedDictionary = try? decoder.decode([String: CachedRecipe].self, from: data) {
                localCache = cachedDictionary
                return
            }

            if let cachedArray = try? decoder.decode([CachedRecipe].self, from: data) {
                localCache = Dictionary(uniqueKeysWithValues: cachedArray.map { ($0.recipe.id, $0) })
            }
        }
    }

    private func localSearch(query: String) -> [Recipe] {
        effectiveLocalCatalog().search(query: query, limit: 50)
    }

    private func effectiveLocalCatalog() -> LocalRecipeCatalog {
        let cachedRecipes = activeCachedRecipes()
        guard !cachedRecipes.isEmpty else {
            return localCatalog
        }

        return localCatalog.merging(
            additionalRecipes: cachedRecipes,
            sourceLabel: "\(localCatalog.sourceLabel)+cached"
        )
    }

    private func activeCachedRecipes() -> [Recipe] {
        var active: [Recipe] = []
        var removedExpired = false

        for (key, cached) in localCache {
            if cached.isExpired(expirationHours: cacheExpirationHours) {
                localCache.removeValue(forKey: key)
                removedExpired = true
                continue
            }
            active.append(cached.recipe)
        }

        if removedExpired {
            saveCacheToDisk()
        }

        return active
    }

    private func shouldFallbackToLocal(for error: Error) -> Bool {
        guard let clientError = error as? RecipeServiceClientError else {
            return false
        }

        switch clientError {
        case .noConnection, .offlineMode, .invalidResponse:
            return true
        case let .httpError(statusCode, _):
            return statusCode >= 500
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
