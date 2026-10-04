import Foundation
import SwiftData
import SwiftUI

/// Коллапсируемая AI-панель внизу рабочей области рукописи.
///
/// Провайдер один (OpenRouter), ключ лежит в Keychain и достаётся через
/// `AIConnectionStore`; провайдеров, вкладок и ручного ввода ключей здесь нет.
struct ChatPanelView: View {
    @Bindable var store: ManuscriptStore
    @StateObject private var connectionStore = AIConnectionStore.shared

    @AppStorage("chatPanelExpanded") private var isExpanded = true

    @Environment(\.modelContext) private var modelContext
    @StateObject private var chatVM = ChatViewModel()
    @State private var showConnectionWindow = false
    /// Ответы, уже дописанные в рукопись — чтобы не вставить дважды.
    @State private var insertedMessageIDs: Set<UUID> = []

    /// Активный блок (сцена) в редакторе — источник контекста для запроса.
    private var activeBlock: Block? { store.selectedBlock }

    /// Есть ли в активной сцене текст. Пустую сцену в запрос не отправляем,
    /// поэтому и чекбокс в этом случае гасится.
    private var hasSceneText: Bool { chatVM.contextIsAvailable(activeBlock) }

    /// Готов ли чат: есть подключение и выбрана модель.
    private var isReadyToSend: Bool {
        connectionStore.isConnected && !connectionStore.selectedModel.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                header
                Divider()
                // Список моделей стоит над чатом — так выбор модели виден
                // вместе с индикатором подключения.
                ModelSelectorView(store: connectionStore)
                Divider()
                messageList
                Divider()
                if connectionStore.isConnected {
                    inputBar
                } else {
                    setupPrompt
                }
            } else {
                collapsedBar
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showConnectionWindow) {
            ConnectionView()
        }
        .onAppear {
            AILog.chat("Панель чата открыта, подключён=\(connectionStore.isConnected)")
        }
    }

    // MARK: - Header (expanded)

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(.secondary)
            Text("AI-чат")
                .font(.subheadline.weight(.medium))

            Divider().frame(height: 16)

            if connectionStore.isConnected {
                Text(connectionStore.model(withID: connectionStore.selectedModel)?.displayName
                    ?? connectionStore.selectedModel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("AI не подключён")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showConnectionWindow = true
                AILog.chat("Открыто окно подключения")
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Подключение AI")

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded = false
                }
            } label: {
                Image(systemName: "chevron.down.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Свернуть панель")
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    // MARK: - Collapsed bar

    private var collapsedBar: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded = true
                }
            } label: {
                Image(systemName: "chevron.up.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Развернуть панель")

            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(.secondary)
            Text("AI-чат")
                .font(.subheadline)
            ConnectionStatusIndicator(status: connectionStore.status, showsTitle: false)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chatVM.messages.isEmpty {
                        Text(emptyChatHint)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    }
                    ForEach(chatVM.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                }
                .padding(10)
            }
            .onChange(of: chatVM.messages.last?.id) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private var emptyChatHint: String {
        connectionStore.isConnected
            ? "Задайте вопрос помощнику. Ответ будет печататься по мере поступления."
            : "AI не подключён. Откройте AI → Подключение…"
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            switch message.kind {
            case .user:
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(message.content)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    Text(message.usedContext ? "📎 с контекстом" : "💬 без контекста")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .assistant:
                VStack(alignment: .leading, spacing: 4) {
                    if message.content.isEmpty {
                        // Прелоадер — только пока реально ждём. Условие именно
                        // на isAwaitingFirstToken, а не на пустой контент:
                        // при пустом ответе модели спиннер завис бы навсегда.
                        Group {
                            if chatVM.isAwaitingFirstToken {
                                HStack(spacing: 6) {
                                    TypingIndicator()
                                    Text("AI печатает…")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            } else {
                                Text("…")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                            }
                        }
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text(message.content)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        insertButton(message)
                    }
                }
                Spacer(minLength: 60)
            case .system:
                Text(message.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                Spacer(minLength: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.kind == .user ? .trailing : .leading)
    }

    /// Кнопка «Добавить в текст» под ответом AI.
    ///
    /// Иконки взяты из самых ранних SF Symbols: в проекте уже ловилось
    /// предупреждение о неизвестном символе вроде `clock.badge.plus`.
    private func insertButton(_ message: ChatMessage) -> some View {
        let done = insertedMessageIDs.contains(message.id)
        return Button {
            insertIntoManuscript(message)
        } label: {
            Label(
                done ? "Добавлено в текст" : "Добавить в текст",
                systemImage: done ? "checkmark.circle" : "plus.circle"
            )
            .font(.caption2)
        }
        .buttonStyle(.link)
        .disabled(done || activeBlock == nil || message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help(activeBlock == nil ? "Нет активной сцены" : "Дописать в конец активной сцены")
    }

    /// Дописывает ответ AI в конец активной сцены.
    private func insertIntoManuscript(_ message: ChatMessage) {
        guard let block = activeBlock else { return }
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Редактор держит свой буфер и пишет его в блок с задержкой 600 мс.
        // Без сброса append посчитал бы устаревший block.content, а отложенная
        // запись затем затерела бы вставку — вместе с правками, которые автор
        // набрал, но ещё не успел сохранить.
        flushEditor(for: block)
        store.appendToBlock(block, text: text, context: modelContext)
        insertedMessageIDs.insert(message.id)
        AILog.chat("Ответ добавлен в блок «\(block.title)»: +\(text.count) симв.")
    }

    /// Сбрасывает несохранённый буфер редактора в блок, если открыт именно он.
    private func flushEditor(for block: Block) {
        guard let coordinator = BlockTextViewCoordinator.current,
              coordinator.isReadOnly == false,
              let editing = coordinator.block,
              editing === block
        else { return }
        coordinator.flush(saveNow: true)
    }

    // MARK: - Input / setup prompt

    private var inputBar: some View {
        VStack(alignment: .trailing, spacing: 4) {
            contextToggle
            HStack(spacing: 8) {
                TextField("Сообщение…", text: $chatVM.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        send()
                    }
                Button {
                    send()
                } label: {
                    if chatVM.isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(disabledSend)
                .help("Отправить")
            }
            sendStatus
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// Полоска под полем ввода: видно, что запрос ушёл, идёт ожидание или
    /// уже поступает текст.
    @ViewBuilder
    private var sendStatus: some View {
        if chatVM.isSending {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text(chatVM.isAwaitingFirstToken ? "Запрос отправлен, ждём ответ…" : "Ответ поступает…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 1)
        }
    }

    /// Чекбокс контекста — над полем ввода, у края с кнопкой отправки,
    /// чтобы не отнимать ширину у текста.
    private var contextToggle: some View {
        Toggle(isOn: $chatVM.useContext) {
            Label("Контекст", systemImage: "doc.text")
                .font(.caption)
        }
        .toggleStyle(.checkbox)
        .help(hasSceneText ? "Учитывать текущую сцену при ответе" : "Нет активной сцены")
        .disabled(!hasSceneText)
    }

    private var disabledSend: Bool {
        chatVM.isSending
            || !isReadyToSend
            || chatVM.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Подсказка вместо поля ввода, пока AI не подключён.
    private var setupPrompt: some View {
        HStack(spacing: 8) {
            Text("AI не подключён. Откройте AI → Подключение…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                showConnectionWindow = true
            } label: {
                Text("Подключить")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    // MARK: - Actions

    private func send() {
        guard !chatVM.isSending, isReadyToSend else { return }
        Task { await chatVM.sendMessage(activeBlock: activeBlock) }
    }

}

/// Анимированные точки вместо текста, пока AI не начал отвечать.
private struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 5, height: 5)
                    .foregroundStyle(.secondary)
                    .opacity(phase == index ? 1 : 0.2)
            }
        }
        .task {
            // Цикл сам останавливается, когда вьюха исчезнет из иерархии.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.easeInOut(duration: 0.18)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}
