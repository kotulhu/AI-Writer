import Foundation

enum AuthStyle {
    case bearer
    case xApiKey
    case none
}

enum ProviderBilling {
    case local
    case freeTier
    case paid
    case unknown
}

struct ProviderInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let defaultBaseURL: String
    let authStyle: AuthStyle
    let usesOAuth: Bool
    let keysPageURL: String?
    let fallbackModels: [String]
    let allowsCustomBaseURL: Bool
    let billing: ProviderBilling

    var requiresApiKey: Bool { authStyle != .none }

    /// Порядок отображения: без авторизации → бесплатные тарифы → платные.
    static let all: [ProviderInfo] = [.ollama, .lmstudio, .gemini, .openai, .anthropic, .openrouter, .custom]

    static func byId(_ id: String) -> ProviderInfo? {
        all.first { $0.id == id }
    }

    static let ollama = ProviderInfo(
        id: "ollama",
        name: "Ollama (локально)",
        defaultBaseURL: "http://localhost:11434/v1",
        authStyle: .none,
        usesOAuth: false,
        keysPageURL: nil,
        fallbackModels: ["llama3.1", "qwen2.5", "mistral"],
        allowsCustomBaseURL: true,
        billing: .local
    )

    static let lmstudio = ProviderInfo(
        id: "lmstudio",
        name: "LM Studio (локально)",
        defaultBaseURL: "http://localhost:1234/v1",
        authStyle: .none,
        usesOAuth: false,
        keysPageURL: nil,
        fallbackModels: [],
        allowsCustomBaseURL: true,
        billing: .local
    )

    static let gemini = ProviderInfo(
        id: "gemini",
        name: "Google Gemini",
        defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
        authStyle: .bearer,
        usesOAuth: false,
        keysPageURL: "https://aistudio.google.com/app/apikey",
        fallbackModels: ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"],
        allowsCustomBaseURL: false,
        billing: .freeTier
    )

    static let openai = ProviderInfo(
        id: "openai",
        name: "OpenAI",
        defaultBaseURL: "https://api.openai.com/v1",
        authStyle: .bearer,
        usesOAuth: false,
        keysPageURL: "https://platform.openai.com/api-keys",
        fallbackModels: ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1"],
        allowsCustomBaseURL: false,
        billing: .paid
    )

    static let anthropic = ProviderInfo(
        id: "anthropic",
        name: "Anthropic Claude",
        defaultBaseURL: "https://api.anthropic.com/v1",
        authStyle: .xApiKey,
        usesOAuth: false,
        keysPageURL: "https://console.anthropic.com/settings/keys",
        fallbackModels: ["claude-sonnet-4-5", "claude-haiku-4-5", "claude-opus-4-1"],
        allowsCustomBaseURL: false,
        billing: .paid
    )

    static let openrouter = ProviderInfo(
        id: "openrouter",
        name: "OpenRouter",
        defaultBaseURL: "https://openrouter.ai/api/v1",
        authStyle: .bearer,
        usesOAuth: true,
        keysPageURL: "https://openrouter.ai/keys",
        fallbackModels: [
            "deepseek/deepseek-chat-v3.1",
            "google/gemini-2.5-flash",
            "openai/gpt-4o-mini",
            "anthropic/claude-sonnet-4.5",
        ],
        allowsCustomBaseURL: false,
        billing: .paid
    )

    static let custom = ProviderInfo(
        id: "custom",
        name: "Другой (OpenAI-совместимый)",
        defaultBaseURL: "",
        authStyle: .bearer,
        usesOAuth: false,
        keysPageURL: nil,
        fallbackModels: [],
        allowsCustomBaseURL: true,
        billing: .unknown
    )
}
