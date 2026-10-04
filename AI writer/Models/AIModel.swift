import Foundation

/// Модель, доступная через OpenRouter.
///
/// `id` — это идентификатор для API (например, `qwen/qwen3.8-27b:free`),
/// который и передаётся в `model` при запросе к OpenRouter.
struct AIModel: Identifiable, Hashable {
    /// Идентификатор модели в API OpenRouter.
    let id: String
    /// Короткое имя для интерфейса.
    let displayName: String
    /// Кто выпустил модель.
    let provider: String
    /// Пояснение для пользователя: чем модель хороша.
    let description: String

    init(id: String, displayName: String, provider: String, description: String) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.description = description
    }
}

/// Список бесплатных моделей OpenRouter для MVP.
///
/// Список захардкодирован намеренно: он нужен до подключения, когда ключа ещё
/// нет, а каталог бесплатных моделей OpenRouter меняется часто — за месяц
/// половина ID исчезает. Поэтому состав списка сверялся с публичным
/// `/api/v1/models`; актуальность для уже подключённого пользователя
/// дополнительно проверяется через `AIConnectionStore.testConnection()` — если
/// модель исчезла, пользователь увидит красный индикатор вместо зелёного.
enum FreeModelsCatalog {
    static let all: [AIModel] = [
        AIModel(
            id: "openrouter/free",
            displayName: "Auto (бесплатно)",
            provider: "OpenRouter",
            description: "OpenRouter сам подбирает доступную бесплатную модель. Всегда актуальна."
        ),
        AIModel(
            id: "nvidia/nemotron-3.5-lightning:free",
            displayName: "Nemotron 3.5 Lightning",
            provider: "NVIDIA",
            description: "Быстрая универсальная модель с контекстом 1 000 000 токенов."
        ),
        AIModel(
            id: "google/gemma-4-31b-it:free",
            displayName: "Gemma 4 31B",
            provider: "Google",
            description: "Сильная открытая модель, хороша для редактуры и структуры текста."
        ),
        AIModel(
            id: "qwen/qwen3.8-27b:free",
            displayName: "Qwen 3.8 27B",
            provider: "Alibaba",
            description: "Многоязычная модель, уверенно работает с русским текстом."
        ),
        AIModel(
            id: "poolside/laguna-s-2.1:free",
            displayName: "Laguna S 2.1",
            provider: "Poolside",
            description: "Только текст, контекст 262 144 токена. Стабильная для черновиков."
        ),
    ]

    /// Модель по умолчанию: авто-маршрутизатор OpenRouter.
    ///
    /// Он всегда указывает на живую бесплатную модель, поэтому подключение
    /// работает даже после очередной ротации бесплатного списка.
    static var defaultModelID: String {
        all.first?.id ?? ""
    }
}
