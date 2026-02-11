import Foundation

enum RecipeServiceClientError: Error {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
}

final class RecipeServiceClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func search(query: String) async throws -> [Recipe] {
        let url = baseURL.appending(path: "/api/v1/recipes/search").appending(queryItems: [
            URLQueryItem(name: "q", value: query)
        ])
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        return try decodeRecipes(data: data)
    }

    func recommend(payload: RecommendRequest) async throws -> RecommendResponse {
        let endpoint = baseURL.appending(path: "/api/v1/recipes/recommend")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(RecommendResponse.self, from: data)
    }

    func generateMealPlan(payload: MealPlanGenerateRequest) async throws -> MealPlanGenerateResponse {
        let endpoint = baseURL.appending(path: "/api/v1/meal-plan/generate")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(MealPlanGenerateResponse.self, from: data)
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
}
