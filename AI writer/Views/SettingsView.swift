import SwiftUI

struct SettingsView: View {
    @AppStorage(AIConfiguration.baseURLKey) private var baseURL = AIConfiguration.defaultBaseURL
    @AppStorage(AIConfiguration.modelKey) private var model = AIConfiguration.defaultModel
    @State private var apiKey = ""

    var body: some View {
        Form {
            Section("AI провайдер (OpenAI-совместимый API)") {
                TextField("Базовый URL", text: $baseURL)
                TextField("Модель", text: $model)
                SecureField("API ключ", text: $apiKey)
                Text("Ключ хранится в Связке ключей macOS. Для локальных моделей укажите адрес вроде http://localhost:11434/v1 (Ollama).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear {
            apiKey = KeychainStore.get(account: AIConfiguration.keychainAccount) ?? ""
        }
        .onChange(of: apiKey) { _, newValue in
            KeychainStore.set(newValue.isEmpty ? nil : newValue, account: AIConfiguration.keychainAccount)
        }
    }
}
