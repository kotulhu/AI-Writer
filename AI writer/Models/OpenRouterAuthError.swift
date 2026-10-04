import Foundation

/// Ошибки авторизации OpenRouter.
enum OpenRouterAuthError: LocalizedError, Equatable {
    /// Не удалось поднять локальный сервер для приёма callback.
    case localServerFailed(String)
    /// Системное окно авторизации не открылось.
    case sessionStartFailed
    /// Пользователь закрыл окно браузера.
    case cancelled
    /// Пользователь отменил авторизацию из приложения.
    case userCancelled
    /// Callback не пришёл за отведённое время.
    case timedOut
    /// Провайдер не вернул код авторизации.
    case missingCode
    /// Ответ не совпал с запросом (защита от подмены).
    case stateMismatch
    /// Провайдер ответил ошибкой.
    case provider(String)
    /// Ошибка сети.
    case network(String)
    /// В успешном ответе нет ключа.
    case missingKey

    var errorDescription: String? {
        switch self {
        case let .localServerFailed(reason):
            "Не удалось запустить локальный сервер: \(reason)"
        case .sessionStartFailed:
            "Не удалось открыть браузер для авторизации."
        case .cancelled:
            "Окно авторизации было закрыто."
        case .userCancelled:
            "Авторизация отменена."
        case .timedOut:
            "Превышено время ожидания авторизации. Попробуйте снова."
        case .missingCode:
            "OpenRouter не вернул код авторизации."
        case .stateMismatch:
            "Ответ авторизации не совпал с запросом. Попробуйте снова."
        case let .provider(message):
            "OpenRouter отклонил авторизацию: \(message)"
        case let .network(message):
            "Ошибка связи с OpenRouter: \(message)"
        case .missingKey:
            "OpenRouter вернул ответ без ключа."
        }
    }
}
