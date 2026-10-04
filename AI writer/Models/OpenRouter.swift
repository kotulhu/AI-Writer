import Foundation

/// Константы OpenRouter: единственный провайдер в приложении.
enum OpenRouter {
    /// Страница входа. Возвращает код авторизации на `callback_url`.
    static let authorizeURL = URL(string: "https://openrouter.ai/auth")!
    /// Endpoint обмена кода на API-ключ.
    static let tokenURL = URL(string: "https://openrouter.ai/api/v1/auth/keys")!
    /// Базовый адрес API (OpenAI-совместимый).
    static let baseURL = "https://openrouter.ai/api/v1"
    /// Путь endpoint чата.
    static let chatPath = "/chat/completions"
    /// Таймаут ожидания callback: 5 минут.
    static let authorizationTimeout: Duration = .seconds(300)

    /// Заголовки, которые OpenRouter просит указывать для корректной маршрутизации.
    static let defaultHeaders: [String: String] = [
        "HTTP-Referer": "https://github.com/ai-writer-app",
        "X-Title": "AI Writer",
    ]

    /// Полный URL endpoint чата.
    static var chatURL: URL {
        URL(string: baseURL + chatPath)!
    }

    // MARK: - Сборка запросов
    //
    // Вынесено отдельными чистыми функциями, чтобы правила формирования URL и
    // тела проверялись тестами напрямую, а не через копию логики в тесте.

    /// Метод PKCE. Обязан совпадать при запросе кода и при обмене кода на
    /// ключ: иначе OpenRouter отвечает `400` / `403`.
    static let codeChallengeMethod = "S256"

    /// Собирает URL страницы входа с `callback_url`, PKCE-параметрами и state.
    static func makeAuthorizeURL(port: UInt16, challenge: String, state: String) -> URL? {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "callback_url", value: "http://127.0.0.1:\(port)/callback"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod),
            URLQueryItem(name: "state", value: state),
            // Метка ключа в аккаунте: его легко опознать и отозвать.
            URLQueryItem(name: "key_label", value: "AI Writer"),
        ]
        return components?.url
    }

    /// Собирает POST-запрос обмена кода на ключ.
    ///
    /// `code_challenge_method` здесь обязателен: без него вместе с
    /// `code_verifier` OpenRouter отвечает `403 Invalid code or code_verifier`.
    static func makeTokenRequest(code: String, codeVerifier: String) throws -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code,
            "code_verifier": codeVerifier,
            "code_challenge_method": codeChallengeMethod,
        ])
        return request
    }
}
