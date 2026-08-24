import Foundation

protocol TextGenerating: Sendable {
    func generate(system: String, user: String, temperature: Double) async throws -> String
}

enum AIConfiguration {
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"
    static let baseURLKey = "ai.baseURL"
    static let modelKey = "ai.model"
    static let keychainAccount = "openai-api-key"
}

struct OpenAIProvider: TextGenerating {
    let endpoint: URL
    let apiKey: String?
    let model: String
    var session: URLSession = .shared

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct Request: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    enum AIError: LocalizedError {
        case invalidResponse
        case httpStatus(Int, String)
        case emptyCompletion

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Некорректный ответ сервера"
            case .httpStatus(let code, let body):
                "Ошибка API (\(code)): \(body.truncated(to: 400))"
            case .emptyCompletion:
                "Модель вернула пустой ответ"
            }
        }
    }

    func generate(system: String, user: String, temperature: Double) async throws -> String {
        var request = URLRequest(url: endpoint.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let payload = Request(
            model: model,
            messages: [
                Message(role: "system", content: system),
                Message(role: "user", content: user),
            ],
            temperature: temperature
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw AIError.emptyCompletion
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
