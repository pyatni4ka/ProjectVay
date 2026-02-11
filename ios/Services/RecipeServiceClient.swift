import Foundation

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
        let (data, _) = try await session.data(from: url)
        return try decodeRecipes(data: data)
    }

    func recommend(payload: RecommendRequest) async throws -> RecommendResponse {
        let endpoint = baseURL.appending(path: "/api/v1/recipes/recommend")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(RecommendResponse.self, from: data)
    }

    private func decodeRecipes(data: Data) throws -> [Recipe] {
        struct Wrapper: Decodable { let items: [Recipe] }
        return try JSONDecoder().decode(Wrapper.self, from: data).items
    }
}
