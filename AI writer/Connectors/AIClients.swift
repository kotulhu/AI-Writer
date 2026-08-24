import Foundation

protocol TextGenerating: Sendable {
    func generate(system: String, user: String, temperature: Double) async throws -> String
}

struct ClientConfig {
    let provider: ProviderInfo
    let baseURL: URL
    let apiKey: String?
    let model: String
}

enum AIClientFactory {
    static func client(for config: ClientConfig) -> TextGenerating {
        if config.provider.id == "anthropic" {
            return AnthropicClient(config: config)
        }
        return ChatCompletionsClient(config: config)
    }
}

struct ChatCompletionsClient: TextGenerating {
    let config: ClientConfig
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

    struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message?
        }

        let choices: [Choice]?
    }

    func generate(system: String, user: String, temperature: Double) async throws -> String {
        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyAuth(to: &request, config: config)
        request.httpBody = try JSONEncoder().encode(
            Request(
                model: config.model,
                messages: [
                    Message(role: "system", content: system),
                    Message(role: "user", content: user),
                ],
                temperature: temperature
            )
        )

        let (data, response) = try await session.data(for: request)
        try Self.ensureOK(response, data: data)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices?.first?.message?.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AIError.emptyCompletion
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func applyAuth(to request: inout URLRequest, config: ClientConfig) {
        switch config.provider.authStyle {
        case .bearer:
            if let key = config.apiKey, !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        case .xApiKey:
            if let key = config.apiKey, !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
            }
        case .none:
            break
        }
    }

    static func ensureOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func fetchModels() async throws -> [String] {
        var request = URLRequest(url: config.baseURL.appending(path: "models"))
        request.timeoutInterval = 30
        Self.applyAuth(to: &request, config: config)
        let (data, response) = try await session.data(for: request)
        try Self.ensureOK(response, data: data)
        let decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return (decoded.data ?? []).map(\.id).sorted()
    }
}

struct ModelListResponse: Decodable {
    struct Item: Decodable {
        let id: String
    }

    let data: [Item]?
}

struct AnthropicClient: TextGenerating {
    let config: ClientConfig
    var session: URLSession = .shared

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct Request: Encodable {
        let model: String
        let max_tokens: Int
        let temperature: Double
        let system: String
        let messages: [Message]
    }

    struct Response: Decodable {
        struct Block: Decodable {
            let type: String?
            let text: String?
        }

        let content: [Block]?
    }

    func generate(system: String, user: String, temperature: Double) async throws -> String {
        var request = URLRequest(url: config.baseURL.appending(path: "messages"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        ChatCompletionsClient.applyAuth(to: &request, config: config)
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(
            Request(
                model: config.model,
                max_tokens: 2048,
                temperature: temperature,
                system: system,
                messages: [Message(role: "user", content: user)]
            )
        )

        let (data, response) = try await session.data(for: request)
        try ChatCompletionsClient.ensureOK(response, data: data)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = (decoded.content ?? [])
            .filter { $0.type == nil || $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatCompletionsClient.AIError.emptyCompletion
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ChatCompletionsClient {
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
}
