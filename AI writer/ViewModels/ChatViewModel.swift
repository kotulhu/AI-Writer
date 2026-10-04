import Foundation
import Combine

/// Сообщение чата в памяти (не персистентно на этом этапе).
struct ChatMessage: Identifiable {
    enum Kind {
        case user, assistant, system
    }

    let id: UUID
    let kind: Kind
    var content: String
    /// Отправлялось ли это сообщение вместе с контекстом сцены.
    ///
    /// Хранится в самом сообщении, а не во флаге на панели, чтобы метка
    /// «📎 с контекстом» оставалась у своего сообщения и после следующих
    /// отправок с другим состоянием чекбокса.
    var usedContext: Bool

    init(id: UUID = UUID(), kind: Kind, content: String, usedContext: Bool = false) {
        self.id = id
        self.kind = kind
        self.content = content
        self.usedContext = usedContext
    }
}

/// Логика AI-чата: история, отправка в OpenRouter и работа с контекстом сцены.
@MainActor
final class ChatViewModel: ObservableObject {
    // MARK: - Настройки

    /// Учитывать контекст текущей сцены при запросе к AI.
    ///
    /// Хранится в `UserDefaults`, а не в `@AppStorage`: тот работает только
    /// как `DynamicProperty` во `View` и во вне-вьюшном классе не публикует
    /// изменения в интерфейс. Ключ прежний — `chatUseContext`.
    @Published var useContext: Bool {
        didSet { UserDefaults.standard.set(useContext, forKey: Self.useContextKey) }
    }

    private static let useContextKey = "chatUseContext"

    /// Был ли контекст в последнем запросе — для метки под сообщением.
    @Published private(set) var lastRequestUsedContext: Bool = false

    // MARK: - Состояние

    @Published private(set) var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published private(set) var isSending: Bool = false
    /// Запрос ушёл, но первый токен ещё не пришёл: показываем прелоадер.
    @Published private(set) var isAwaitingFirstToken: Bool = false

    private let connection: AIConnectionStore

    /// - Parameter connection: подключение AI. По умолчанию — общий синглтон.
    ///   Параметр nullable, а не `.shared` по умолчанию: аргумент по умолчанию
    ///   вычисляется вне главного актора и на `@MainActor static let` даёт
    ///   предупреждение изоляции.
    init(connection: AIConnectionStore? = nil) {
        self.connection = connection ?? .shared
        // По умолчанию включено: чаще автору нужно, чтобы AI видел сцену.
        // object(forKey:) вместо bool, иначе отсутствие ключа и `false`
        // не различить и настройка не смогла бы включиться по умолчанию.
        if let stored = UserDefaults.standard.object(forKey: Self.useContextKey) as? Bool {
            useContext = stored
        } else {
            useContext = true
        }
    }

    // MARK: - Сжатие контекста

    /// Маркер, которым заменяется середина длинной сцены.
    private static let omittedMarker = "середина сцены опущена для краткости"

    /// Трёхуровневая стратегия сжатия.
    ///
    /// Короткий текст уходит целиком; длинный — начало и конец, между ними
    /// маркер. Начало несёт завязку, конец — текущий момент, поэтому AI
    /// продолжает сцену осмысленно. Дальше на этом месте можно поставить
    /// суммаризацию моделью.
    func compressContext(_ text: String, maxChars: Int = 4000) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }

        let half = maxChars / 2
        let head = String(trimmed.prefix(half))
        let tail = String(trimmed.suffix(half))
        return "\(head)\n\n[… \(Self.omittedMarker) …]\n\n\(tail)"
    }

    /// Системное сообщение с фрагментом сцены.
    ///
    /// Отдельная строка: просим учитывать сцену, но не пересказывать её и не
    /// цитировать дословно без просьбы автора. С контекстом модель сразу
    /// работает как писатель и не задаёт уточняющих вопросов — автор сцена
    /// занят текстом, а не перепиской с помощником.
    private static func contextSystemMessage(_ compressed: String) -> String {
        """
        Ты — литературный редактор. Ниже приведён фрагмент текущей сцены, над которой работает автор. Учитывай его при ответе, но не пересказывай его и не цитируй дословно, если автор не попросит.

        Перейди в роль писателя: отвечай готовым текстом, а не разбором, планом или советами. Задавать автору дополнительные вопросы не нужно — работай по тому, что есть, и при нехватке сведений принимай решение сам.

        --- НАЧАЛО СЦЕНЫ ---
        \(compressed)
        --- КОНЕЦ СЦЕНЫ ---
        """
    }

    // MARK: - Отправка

    /// Отправляет черновик в AI, при необходимости добавив контекст сцены.
    ///
    /// - Parameter activeBlock: текущий открытый блок (сцена). `nil` или
    ///   пустой блок означают, что контекста в запросе не будет.
    func sendMessage(activeBlock: Block?) async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        draft = ""

        // Контекст берём только когда чекбокс включён и в сцене есть текст:
        // пустой блок отправлять бессмысленно.
        let sceneText = activeBlock?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasContext = useContext && !sceneText.isEmpty
        let compressed = hasContext ? compressContext(sceneText) : nil

        AILog.chat("Отправка сообщения. Контекст: \(useContext ? "вкл" : "выкл"), активный блок: \(activeBlock?.title ?? "нет")")
        if hasContext, let compressed {
            AILog.chat("Размер контекста: \(sceneText.count) символов, после сжатия: \(compressed.count)")
        } else if useContext, activeBlock != nil {
            AILog.chat("Активная сцена пуста, контекст не добавлен")
        }

        messages.append(ChatMessage(kind: .user, content: trimmed, usedContext: hasContext))
        lastRequestUsedContext = hasContext

        // Ключ берётся из Keychain по ref; сам ключ в коде не появляется.
        let spec = AIRequestSpec(
            baseURL: OpenRouter.baseURL,
            apiKeyRef: AIConnectionStore.keychainRef,
            defaultModel: connection.selectedModel,
            customHeaders: OpenRouter.defaultHeaders
        )
        let client = OpenAICompatibleClient()

        // Системное сообщение с контекстом идёт перед историей и только в
        // запрос — в панели его не видно.
        var payload: [AIChatMessage] = []
        if let compressed {
            payload.append(AIChatMessageImpl(role: "system", content: Self.contextSystemMessage(compressed)))
        }
        for message in messages {
            switch message.kind {
            case .user:
                payload.append(AIChatMessageImpl(role: "user", content: message.content))
            case .assistant:
                // Пустой placeholder во время стриминга в запрос не идёт.
                if !message.content.isEmpty {
                    payload.append(AIChatMessageImpl(role: "assistant", content: message.content))
                }
            case .system:
                break
            }
        }

        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, kind: .assistant, content: ""))
        isSending = true
        isAwaitingFirstToken = true

        do {
            let stream = try await client.sendMessage(config: spec, messages: payload)
            for try await token in stream {
                if isAwaitingFirstToken {
                    isAwaitingFirstToken = false
                    AILog.chat("Первый токен получен, перехожу в режим печати")
                }
                if let index = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[index].content += token
                }
            }
            AILog.chatBlock("Ответ провайдера", replyText(for: assistantId))
            AILog.chat("Ответ получен полностью")
        } catch {
            // Часть ответа успела прийти до обрыва — она тоже нужна для разбора.
            let partial = replyText(for: assistantId)
            if !partial.isEmpty {
                AILog.chatBlock("Ответ провайдера (обрыв)", partial)
            }
            AILog.chat("Ошибка запроса: \(error.localizedDescription)")
            messages.append(ChatMessage(kind: .system, content: "Ошибка: \(error.localizedDescription)"))
        }
        isAwaitingFirstToken = false
        isSending = false
    }

    /// Текст, накопленный в ответе ассистента, — для журнала.
    private func replyText(for id: UUID) -> String {
        messages.first(where: { $0.id == id })?.content ?? ""
    }

    /// Снимает контекстный флаг, когда активный блок сменился или исчез.
    func contextIsAvailable(_ block: Block?) -> Bool {
        !(block?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }
}
