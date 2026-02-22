import Foundation

protocol ImageSearchProvider: Sendable {
    func searchImage(query: String) async throws -> URL?
}

enum GoogleImageSearchError: Error {
    case invalidURL
    case invalidResponse
    case quotaExceeded
    case underlying(Error)
}

final class GoogleImageSearchProvider: ImageSearchProvider {
    private let apiKey: String
    private let searchEngineId: String
    private let session: URLSession

    init(apiKey: String, searchEngineId: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.searchEngineId = searchEngineId
        self.session = session
    }

    func searchImage(query: String) async throws -> URL? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var components = URLComponents(string: "https://www.googleapis.com/customsearch/v1")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "cx", value: searchEngineId),
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "searchType", value: "image"),
            URLQueryItem(name: "num", value: "1") // We only need the top result
        ]

        guard let url = components.url else {
            throw GoogleImageSearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GoogleImageSearchError.underlying(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleImageSearchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 429 {
                throw GoogleImageSearchError.quotaExceeded
            }
            throw GoogleImageSearchError.invalidResponse
        }

        do {
            let result = try JSONDecoder().decode(GoogleSearchResponse.self, from: data)
            guard let firstItem = result.items?.first, let link = firstItem.link else {
                return nil
            }
            return URL(string: link)
        } catch {
            throw GoogleImageSearchError.underlying(error)
        }
    }
}

// MARK: - Response Models
private struct GoogleSearchResponse: Decodable {
    let items: [GoogleSearchItem]?
}

private struct GoogleSearchItem: Decodable {
    let link: String?
}
