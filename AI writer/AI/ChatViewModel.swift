import Foundation
import Observation

/// Роль участника диалога.
enum ChatRole: Equatable {
    case system
    case user
    case assistant
}

/// Одно сообщение истории чата.
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    var text: String
}

/// Модель чата с литературным помощником (MVVM).
/// Использует тот же активный ИИ-клиент, что и остальные функции приложения.
@MainActor
@Observable
final class ChatViewModel {
    private let workspace: WorkspaceViewModel

    /// Системная инструкция, задаёт роль модели как литературного редактора.
    static let systemPrompt = """
    Ты — редактор литературных текстов. Помогай автору: развивай сюжет, \
    углубляй характеры персонажей, улучшай диалоги, описывай эмоции и атмосферу.
    """

    /// Полная история, включая системное сообщение (не отображается).
    private(set) var messages: [ChatMessage] = []

    /// Черновик ввода.
    var draft = ""

    /// Идёт запрос к модели.
    private(set) var isSending = false

    /// Видимость нижней панели чата.
    var isPanelVisible = false

    /// Сколько последних реплик отправляем модели как контекст.
    private let contextLimit = 20

    init(workspace: WorkspaceViewModel) {
        self.workspace = workspace
        resetHistory()
    }

    /// AI доступен, если подключён хотя бы один провайдер с выбранной моделью.
    var isAIAvailable: Bool {
        workspace.hasActiveProvider
    }

    /// Сообщения для отображения — без системной инструкции.
    var visibleMessages: [ChatMessage] {
        messages.filter { $0.role != .system }
    }

    func togglePanel() {
        isPanelVisible.toggle()
    }

    /// Очищает историю и возвращает системную инструкцию.
    func clearChat() {
        resetHistory()
    }

    /// Отправляет черновик: добавляет реплику автора, запрашивает ответ модели.
    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending, isAIAvailable else { return }
        draft = ""
        messages.append(ChatMessage(role: .user, text: text))
        isSending = true
        defer { isSending = false }
        do {
            guard let client = workspace.chatClient() else {
                throw ChatCompletionsClient.AIError.emptyCompletion
            }
            let history = Array(
                messages.filter { $0.role != .system }.suffix(contextLimit).map {
                    ChatTurn(isFromUser: $0.role == .user, text: $0.text)
                }
            )
            let reply = try await client.generate(
                system: Self.systemPrompt,
                turns: history,
                temperature: 0.8
            )
            messages.append(ChatMessage(role: .assistant, text: reply))
        } catch {
            // Понятное пользователю сообщение прямо в истории чата.
            let reason = friendlyDescription(error)
            messages.append(ChatMessage(role: .assistant, text: "Не удалось получить ответ: \(reason)"))
        }
    }

    /// Кнопка «Добавить в текст» — дописывает ответ ассистента в конец текущей сцены.
    func addToScene(_ message: ChatMessage) {
        guard message.role == .assistant else { return }
        workspace.appendToSelectedScene(message.text)
    }

    private func resetHistory() {
        messages = [ChatMessage(role: .system, text: Self.systemPrompt)]
    }

    private func friendlyDescription(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let text = localized.errorDescription {
            return text
        }
        return error.localizedDescription
    }
}
