import Foundation

/// Состояние подключения к AI-провайдеру.
///
/// В приложении провайдер ровно один — OpenRouter, поэтому хранилище не имеет
/// реестра провайдеров. Оно публикует наружу только три вещи, которые нужны
/// интерфейсу: подключён ли AI, какая модель выбрана и какие модели доступны.
@MainActor
final class AIConnectionStore: ObservableObject {
    /// Общий экземпляр на всё приложение.
    static let shared = AIConnectionStore()

    /// Подключён ли AI: в Keychain есть ключ OpenRouter.
    @Published private(set) var isConnected: Bool = false

    /// Выбранная модель. Сохраняется в UserDefaults и переживает перезапуск.
    @Published var selectedModel: String {
        didSet {
            guard selectedModel != oldValue else { return }
            UserDefaults.standard.set(selectedModel, forKey: Self.modelDefaultsKey)
            AILog.store("Выбрана модель: \(selectedModel)")
        }
    }

    /// Бесплатные модели, доступные через OpenRouter.
    @Published private(set) var availableModels: [AIModel]

    /// Результат последней проверки подключения — им рисуется индикатор.
    @Published private(set) var status: ConnectionStatus = .disconnected

    /// Ключ записи Keychain с API-ключом OpenRouter.
    static let keychainRef = "openrouter_api_key"
    /// Ключ UserDefaults с выбранной моделью.
    static let modelDefaultsKey = "selected_model"

    private init() {
        let models = FreeModelsCatalog.all
        availableModels = models
        // Модель из UserDefaults берём только если она ещё есть в каталоге:
        // иначе после смены каталога остался бы несуществующий идентификатор.
        let saved = UserDefaults.standard.string(forKey: Self.modelDefaultsKey) ?? ""
        if let match = models.first(where: { $0.id == saved }) {
            selectedModel = match.id
        } else {
            selectedModel = models.first?.id ?? ""
        }
        isConnected = KeychainStore.read(ref: Self.keychainRef) != nil
        status = isConnected ? .unknown : .disconnected
        AILog.store("init: подключён=\(isConnected), модель=\(selectedModel)")
    }

    /// Сохраняет полученный ключ и переводит хранилище в состояние «проверяем».
    ///
    /// Здесь и в `sendMessage` ключ берётся по `apiKeyRef` из Keychain — сам
    /// секрет не проходит через SwiftUI-модели и не попадает в логи.
    @discardableResult
    func connect(with key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            AILog.store("❌ Пустой ключ, подключение не сохранено")
            return false
        }
        guard KeychainStore.save(secret: trimmed, ref: Self.keychainRef) else {
            AILog.store("❌ Keychain не принял ключ")
            status = .failed("Не удалось сохранить ключ в связке ключей.")
            return false
        }
        isConnected = true
        status = .checking
        AILog.store("✅ Ключ сохранён в Keychain (\(OpenRouterAuth.masked(trimmed)))")
        return true
    }

    /// Удаляет ключ и возвращает хранилище в исходное состояние.
    func disconnect() {
        _ = KeychainStore.delete(ref: Self.keychainRef)
        isConnected = false
        status = .disconnected
        AILog.store("Подключение сброшено, ключ удалён")
    }

    /// Отправляет тестовый запрос выбранной модели и обновляет индикатор статуса.
    ///
    /// Возвращает `true`, если провайдер принял ключ и модель ответила.
    @discardableResult
    func testConnection() async -> Bool {
        guard isConnected else {
            AILog.store("Тест пропущен: нет подключения")
            status = .disconnected
            return false
        }
        let model = selectedModel
        AILog.store("Тестовый запрос к \(model)...")

        status = .checking
        let client = OpenAICompatibleClient()
        do {
            let spec = AIRequestSpec(
                baseURL: OpenRouter.baseURL,
                apiKeyRef: Self.keychainRef,
                defaultModel: model,
                customHeaders: OpenRouter.defaultHeaders
            )
            _ = try await client.testConnection(config: spec)
            status = .working
            AILog.store("Результат: ✅ OK")
            return true
        } catch {
            status = .failed(error.localizedDescription)
            AILog.store("Результат: ❌ FAIL — \(error.localizedDescription)")
            return false
        }
    }

    /// Модель по идентификатору (для показа имени в интерфейсе).
    func model(withID id: String) -> AIModel? {
        availableModels.first { $0.id == id }
    }
}

/// Состояние подключения для индикатора в интерфейсе.
enum ConnectionStatus: Equatable {
    /// Не подключено.
    case disconnected
    /// Подключено, но проверка ещё не выполнялась.
    case unknown
    /// Идёт проверка.
    case checking
    /// Проверка прошла: ключ и модель работают.
    case working
    /// Проверка провалилась, с сообщением для пользователя.
    case failed(String)

    /// Цвет индикатора.
    var color: StatusColor {
        switch self {
        case .disconnected: .red
        case .unknown: .secondary
        case .checking: .yellow
        case .working: .green
        case .failed: .red
        }
    }

    /// Текстовый статус для окна подключения.
    var title: String {
        switch self {
        case .disconnected: "Не подключено"
        case .unknown: "Подключено"
        case .checking: "Проверка…"
        case .working: "✅ Работает"
        case .failed: "❌ Ошибка"
        }
    }

    /// Пояснение под статусом.
    var detail: String? {
        if case let .failed(message) = self { return message }
        return nil
    }

    /// Проверка завершилась ошибкой — интерфейсу показывать кнопку «Повторить».
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Идёт ли сейчас проверка.
    var isChecking: Bool {
        self == .checking
    }
}

/// Цвет индикатора статуса (обёртка, чтобы SwiftUI не тянул Color в модель).
enum StatusColor {
    case green, red, yellow, secondary
}
