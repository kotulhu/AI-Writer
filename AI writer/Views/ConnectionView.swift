import SwiftUI

/// Окно подключения к AI.
///
/// Провайдер один — OpenRouter, способ входа один — браузерный OAuth (PKCE).
/// Ни вкладок, ни ручного ввода ключа: единственное действие это авторизация.
struct ConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AIConnectionStore.shared
    @StateObject private var auth = OpenRouterAuth()
    /// Текст последней ошибки авторизации (nil, если всё в порядке).
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    if store.isConnected {
                        connectedCard
                        freeModelsCard
                    } else {
                        providerCard
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 460)
        // Закрытие окна во время авторизации отменяет флоу: иначе локальный
        // сервер и лист браузера остались бы висеть после закрытия.
        .onDisappear {
            if auth.isAuthorizing {
                auth.cancel()
            }
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.tint)
            Text("Подключение AI")
                .font(.headline)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Закрыть")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Карточка провайдера (не подключён)

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 20))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenRouter")
                        .font(.headline)
                    Text("Единая точка доступа к бесплатным моделям разных разработчиков.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            if auth.isAuthorizing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Ожидание подтверждения…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Отмена") {
                        auth.cancel()
                    }
                    .controlSize(.small)
                }
            } else {
                Button {
                    connect()
                } label: {
                    Label("Подключить через OpenRouter", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text("Откроется окно входа OpenRouter — войдите в аккаунт и подтвердите доступ. Приложение не получает пароль, только ключ для бесплатных моделей.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Карточка подключённого состояния

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ConnectionStatusIndicator(status: store.status)
                Text("OpenRouter — активно")
                    .font(.headline)
                Spacer()
            }

            if let detail = store.status.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if store.status.isFailed {
                    Button {
                        Task { await store.testConnection() }
                    } label: {
                        Label("Повторить", systemImage: "arrow.clockwise")
                    }
                }
                Button(role: .destructive) {
                    store.disconnect()
                    error = nil
                } label: {
                    Text("Отключить")
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var freeModelsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Бесплатные модели")
                .font(.subheadline.weight(.medium))

            ForEach(store.availableModels) { model in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: model.id == store.selectedModel ? "largecircle.fill.circle" : "circle")
                        .font(.caption)
                        .foregroundStyle(model.id == store.selectedModel ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.displayName)
                            .font(.callout)
                        Text(model.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Подвал

    private var footer: some View {
        HStack {
            Spacer()
            Button("Готово") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            // Пока идёт вход в браузере, закрывать окно нельзя: пользователь
            // потеряет флоу на полпути к подтверждению.
            .disabled(auth.isAuthorizing)
        }
        .padding(16)
    }

    // MARK: - Состояние и действия

    /// Запускает браузерную авторизацию и сразу проверяет подключение.
    private func connect() {
        error = nil
        Task {
            do {
                AILog.auth("Запуск авторизации из интерфейса")
                let key = try await auth.authorize()
                AILog.auth("Авторизация вернула ключ, сохраняю")
                guard store.connect(with: key) else {
                    AILog.auth("❌ Ключ не сохранён: \(store.status.detail ?? "нет деталей")")
                    error = store.status.detail ?? "Не удалось сохранить ключ."
                    return
                }
                AILog.auth("Проверяю подключение")
                await store.testConnection()
                AILog.auth("Итог подключения: статус=\(store.status)")
            } catch OpenRouterAuthError.userCancelled {
                // Отмена — штатный сценарий, не показываем ошибку.
                AILog.store("Авторизация отменена")
            } catch OpenRouterAuthError.cancelled {
                AILog.store("Окно авторизации закрыто")
            } catch {
                AILog.auth("❌ Авторизация провалилась: \(error.localizedDescription)")
                self.error = error.localizedDescription
            }
        }
    }
}
