import Foundation

struct GeminiService {

    static func testConnection(apiKey: String) async throws -> String {
        try await send(prompt: "Say hello in one short sentence.", apiKey: apiKey)
    }

    static func send(prompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)") else {
            throw GeminiError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["parts": [["text": prompt]]]]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }

        switch http.statusCode {
        case 200:      break
        case 400, 403: throw GeminiError.invalidAPIKey
        case 404:      throw GeminiError.modelNotFound
        default:       throw GeminiError.serverError(http.statusCode)
        }

        guard
            let json       = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"]              as? [[String: Any]],
            let content    = candidates.first?["content"]   as? [String: Any],
            let parts      = content["parts"]               as? [[String: Any]],
            let text       = parts.first?["text"]           as? String
        else { throw GeminiError.invalidResponse }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GeminiError: LocalizedError {
    case invalidAPIKey
    case invalidResponse
    case modelNotFound
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:      return "Invalid API key — please check it and try again."
        case .invalidResponse:    return "Unexpected response from Gemini."
        case .modelNotFound:      return "Gemini model not found. Please update the app."
        case .serverError(let c): return "Server error (\(c)). Try again in a moment."
        }
    }
}
