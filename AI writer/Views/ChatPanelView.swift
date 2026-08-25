import SwiftUI

/// Нижняя панель чата с литературным помощником.
struct ChatPanelView: View {
    @Environment(ChatViewModel.self) private var chat
    @Environment(\.openSettings) private var openSettings

    /// Идентификатор индикатора «модель думает» для прокрутки.
    private static let sendingIndicatorID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if chat.isAIAvailable {
                messageList
            } else {
                unavailableState
            }
            Divider()
            inputBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Заголовок

    private var header: some View {
        HStack(spacing: 10) {
            Label("Литературный помощник", systemImage: "sparkles")
                .font(.headline)
            Spacer()
            Button {
                chat.clearChat()
            } label: {
                Label("Очистить чат", systemImage: "trash")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
            .disabled(chat.visibleMessages.isEmpty)
            Button {
                chat.togglePanel()
            } label: {
                Label("Скрыть панель", systemImage: "chevron.down")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - История сообщений

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(chat.visibleMessages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if chat.isSending {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Модель думает…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .id(Self.sendingIndicatorID)
                    }
                }
                .padding(14)
            }
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(
                        chat.visibleMessages.last?.id ?? Self.sendingIndicatorID,
                        anchor: .bottom
                    )
                }
            }
            .onChange(of: chat.isSending) { _, _ in
                proxy.scrollTo(Self.sendingIndicatorID, anchor: .bottom)
            }
        }
    }

    /// Состояние «AI не подключен».
    private var unavailableState: some View {
        VStack(spacing: 10) {
            Text("📚 AI не подключен. Перейдите в Настройки → AI и добавьте API-ключ.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Открыть настройки") {
                openSettings()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Поле ввода

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextEditor(text: Binding(
                get: { chat.draft },
                set: { chat.draft = $0 }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 40, maxHeight: 80)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
            .disabled(!chat.isAIAvailable || chat.isSending)

            VStack(alignment: .trailing, spacing: 6) {
                if chat.isSending {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await chat.send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!chat.isAIAvailable || chat.isSending || chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Отправить (Enter)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Пузырь одного сообщения чата.
private struct MessageBubble: View {
    @Environment(ChatViewModel.self) private var chat
    let message: ChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Text(message.text)
                .font(.callout)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleColor)
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if !isUser && !message.text.hasPrefix("Не удалось получить ответ") {
                Button("Добавить в текст") {
                    chat.addToScene(message)
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.horizontal, 4)
    }

    private var bubbleColor: Color {
        isUser ? Color.accentColor : Color(nsColor: .quaternarySystemFill)
    }
}
