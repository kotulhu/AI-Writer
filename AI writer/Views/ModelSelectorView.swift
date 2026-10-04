import SwiftUI

/// Панель выбора модели над чатом.
///
/// Слева — индикатор подключения, по центру — список бесплатных моделей,
/// справа — кнопка «Обновить», повторяющая проверку подключения.
struct ModelSelectorView: View {
    @ObservedObject var store: AIConnectionStore

    var body: some View {
        HStack(spacing: 10) {
            ConnectionStatusIndicator(status: store.status, showsTitle: false)
                .help("Статус подключения: \(store.status.title)")

            if store.availableModels.isEmpty {
                Text("Нет доступных моделей")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Модель", selection: $store.selectedModel) {
                    ForEach(store.availableModels) { model in
                        Text(model.displayName)
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 260)
                .help("Модель для чата: \(selectedModelDescription)")
            }

            Spacer()

            Button {
                Task { await store.testConnection() }
            } label: {
                Text("Обновить")
            }
            .controlSize(.small)
            .disabled(store.status.isChecking || !store.isConnected)
            .help("Повторить проверку подключения")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Пояснение выбранной модели для подсказки.
    private var selectedModelDescription: String {
        guard let model = store.model(withID: store.selectedModel) else {
            return store.selectedModel
        }
        return "\(model.provider) — \(model.description)"
    }
}
