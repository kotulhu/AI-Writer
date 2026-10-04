import Foundation

// MARK: - Сообщения

protocol AIChatMessage {
    var role: String { get }    // "user" / "assistant" / "system"
    var content: String { get }
}

struct AIChatMessageImpl: AIChatMessage {
    let role: String
    let content: String
}

/// Параметры одного запроса к провайдеру.
///
/// Ключ не хранится в структуре: вместо него `apiKeyRef` — ссылка на запись
/// Keychain. Так секрет не дублируется в моделях SwiftUI и в логах.
struct AIRequestSpec {
    var baseURL: String
    var apiKeyRef: String?
    var defaultModel: String
    var customHeaders: [String: String]?

    init(
        baseURL: String,
        apiKeyRef: String?,
        defaultModel: String,
        customHeaders: [String: String]? = nil
    ) {
        self.baseURL = baseURL
        self.apiKeyRef = apiKeyRef
        self.defaultModel = defaultModel
        self.customHeaders = customHeaders
    }
}

protocol AITextProvider {
    func testConnection(config: AIRequestSpec) async throws -> Bool
    func sendMessage(
        config: AIRequestSpec,
        messages: [AIChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error>
}

// MARK: - Ошибки

enum AIClientError: LocalizedError, CustomStringConvertible {
    case noAPIKey
    case invalidResponse(status: Int, body: String)
    case emptyModel
    /// Превышен лимит запросов (429) — временная ошибка, помогает повтор с паузой.
    case rateLimited(retryAfter: TimeInterval?, serverMessage: String)
    /// Не хватает средств/квоты у провайдера — повтор не поможет.
    case quotaExceeded(serverMessage: String)

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .noAPIKey:
            return "Не найден API-ключ. Подключите OpenRouter заново."
        case let .invalidResponse(status, body):
            let trimmed = body.isEmpty ? "(пустой ответ)" : String(body.prefix(300))
            return "Сервер ответил с ошибкой \(status): \(trimmed)"
        case .emptyModel:
            return "Не выбрана модель."
        case let .rateLimited(retryAfter, serverMessage):
            var text = "Превышен лимит запросов (429). \(serverMessage)"
            if let retryAfter {
                text += " Провайдер просит повторить через \(Int(retryAfter)) с."
            } else {
                text += " Повторите через несколько секунд."
            }
            return text
        case let .quotaExceeded(serverMessage):
            return "Не хватает средств или квоты у провайдера: \(serverMessage)"
        }
    }

    /// Нужно ли автоматически повторить запрос.
    var isRetryable: Bool {
        if case .rateLimited = self { return true }
        return false
    }
}

// MARK: - Разбор ответов

/// Разбирает JSON-тело ошибки API (OpenAI-совместимый формат) в читаемый текст.
private func extractServerMessage(_ data: Data, status: Int) -> String {
    guard !data.isEmpty else { return "" }
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? ""
            let type = error["type"] as? String
            let code = error["code"] as? String
            var details: [String] = []
            if let code, !code.isEmpty { details.append("code: \(code)") }
            if let type, !type.isEmpty { details.append("type: \(type)") }
            let joined = ([message] + details).filter { !$0.isEmpty }.joined(separator: ", ")
            if !joined.isEmpty {
                return joined
            }
        }
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
    }
    return String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "HTTP \(status)"
}

/// Отличает нехватку квоты/средств (повтор не поможет) от временного лимита запросов.
private func isQuotaError(_ serverMessage: String) -> Bool {
    let lowered = serverMessage.lowercased()
    return lowered.contains("insufficient_quota")
        || lowered.contains("quota")
        || lowered.contains("billing")
        || lowered.contains("credit")
        || lowered.contains("недостаточно средств")
        || lowered.contains("оплач")
}

/// Единая точка обработки не-2xx ответов: превращает их в типизированную ошибку.
private func makeStatusError(status: Int, data: Data, response: HTTPURLResponse) -> AIClientError {
    let serverMessage = extractServerMessage(data, status: status)
    if status == 429 {
        if isQuotaError(serverMessage) {
            return .quotaExceeded(serverMessage: serverMessage)
        }
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        return .rateLimited(retryAfter: retryAfter, serverMessage: serverMessage)
    }
    return .invalidResponse(status: status, body: serverMessage)
}

// MARK: - HTTP / SSE

/// Максимальный размер тела ошибки, который читаем (защита от огромных ответов).
private let errorBodyLimit = 64 * 1024

/// Параметры повторов при временных ошибках (429 и т.п.).
private struct RetryPolicy {
    var maxAttempts = 3
    var baseDelay: TimeInterval = 1

    /// Пауза перед попыткой `attempt` (1-based), с учётом Retry-After от сервера.
    func delay(forAttempt attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter, retryAfter > 0 {
            return min(retryAfter, 30)
        }
        let exponential = baseDelay * pow(2, Double(max(0, attempt - 1)))
        return min(exponential, 30)
    }
}

/// Выполняет запрос с повторами при временных ошибках (например, 429).
/// Повтор делается, только если поток ещё не начал отдавать данные.
private func performWithRetry<T>(
    policy: RetryPolicy,
    _ operation: () async throws -> T
) async throws -> T {
    var attempt = 1
    while true {
        do {
            return try await operation()
        } catch let error as AIClientError where error.isRetryable && attempt < policy.maxAttempts {
            let serverRetryAfter: TimeInterval?
            if case let .rateLimited(value, _) = error {
                serverRetryAfter = value
            } else {
                serverRetryAfter = nil
            }
            let pause = policy.delay(forAttempt: attempt, retryAfter: serverRetryAfter)
            AILog.client("повтор \(attempt + 1)/\(policy.maxAttempts) через \(String(format: "%.1f", pause)) с — \(error.localizedDescription)")
            try await Task.sleep(for: .seconds(pause))
            attempt += 1
        }
    }
}

private func normalizedPath(_ baseURL: String, tail: String) -> URL? {
    var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    while base.hasSuffix("/") { base.removeLast() }
    return URL(string: base + tail)
}

/// Извлекает текст дельты из SSE-события OpenAI-совместимого формата.
private func parseOpenAIPayload(_ payload: String) -> String? {
    if payload == "[DONE]" { return nil }
    guard let data = payload.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let delta = choices.first?["delta"] as? [String: Any],
          let text = delta["content"] as? String
    else { return nil }
    return text
}

/// Читает SSE-поток и отдаёт содержимое `delta.content` по мере поступления.
private func readSSE(for request: URLRequest) async throws -> AsyncThrowingStream<String, Error> {
    let (responseBytes, urlResponse) = try await URLSession.shared.bytes(for: request)
    guard let http = urlResponse as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    AILog.client("Response status: \(http.statusCode)")
    guard (200...299).contains(http.statusCode) else {
        // Тело ошибки читаем целиком: без него непонятно, был ли лимит или квота.
        var errorBody = Data()
        for try await byte in responseBytes {
            errorBody.append(byte)
            if errorBody.count >= errorBodyLimit { break }
        }
        throw makeStatusError(status: http.statusCode, data: errorBody, response: http)
    }

    return AsyncThrowingStream<String, Error> { continuation in
        Task {
            do {
                // Событие всегда занимает одну строку `data: …`, поэтому
                // разбираем построчно без накопления между событиями.
                for try await line in responseBytes.lines {
                    let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
                    guard trimmed.hasPrefix("data:") else { continue }
                    let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
                    guard !payload.isEmpty else { continue }
                    if let text = parseOpenAIPayload(payload) {
                        continuation.yield(text)
                    }
                }
                continuation.finish()
            } catch {
                AILog.client("Ошибка потока: \(error.localizedDescription)")
                continuation.finish(throwing: error)
            }
        }
    }
}

private func makeJSONRequest(url: URL, method: String = "POST") -> NSMutableURLRequest {
    let request = NSMutableURLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return request
}

// MARK: - OpenAICompatibleClient

/// OpenAI-совместимый клиент. Единственный используемый клиент приложения:
/// OpenRouter говорит на этом формате (`POST {baseURL}/chat/completions`).
struct OpenAICompatibleClient: AITextProvider {
    private let retryPolicy = RetryPolicy()

    /// Проверка подключения: короткий запрос с `max_tokens: 5`.
    func testConnection(config: AIRequestSpec) async throws -> Bool {
        let url = try endpoint(for: config)
        let body: [String: Any] = [
            "model": config.defaultModel,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 5,
            "stream": false,
        ]
        let request = try buildRequest(for: config, url: url, body: body)
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        AILog.client("Response status: \(http.statusCode) (testConnection)")
        guard (200...299).contains(http.statusCode) else {
            throw makeStatusError(status: http.statusCode, data: data, response: http)
        }
        return true
    }

    /// Отправка сообщений в потоковом режиме.
    func sendMessage(
        config: AIRequestSpec,
        messages: [AIChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        let url = try endpoint(for: config)
        let body: [String: Any] = [
            "model": config.defaultModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true,
        ]
        let request = try buildRequest(for: config, url: url, body: body)
        // Повтор только до начала стриминга: если поток уже пошёл, повтор
        // привёл бы к дублированию уже показанного текста.
        return try await performWithRetry(policy: retryPolicy) {
            try await readSSE(for: request)
        }
    }

    private func endpoint(for config: AIRequestSpec) throws -> URL {
        guard let url = normalizedPath(config.baseURL, tail: OpenRouter.chatPath) else {
            throw URLError(.badURL)
        }
        return url
    }

    private func buildRequest(for config: AIRequestSpec, url: URL, body: [String: Any]) throws -> URLRequest {
        guard !config.defaultModel.isEmpty else {
            throw AIClientError.emptyModel
        }
        let request = makeJSONRequest(url: url)

        let key = config.apiKeyRef.flatMap { KeychainStore.read(ref: $0) }
        guard let key, !key.isEmpty else {
            AILog.client("Error: нет ключа для ref \(config.apiKeyRef ?? "nil")")
            throw AIClientError.noAPIKey
        }
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        for (name, value) in config.customHeaders ?? [:] {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData

        // В лог идёт только маска ключа: сам секрет не печатается.
        AILog.client("POST \(url.absoluteString)")
        AILog.client("Headers: Authorization: Bearer \(OpenRouterAuth.masked(key))")
        AILog.client("Body: \(String(decoding: bodyData, as: UTF8.self).prefix(200))")
        return request as URLRequest
    }
}
