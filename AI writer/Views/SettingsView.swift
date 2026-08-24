import SwiftUI

struct SettingsView: View {
    @Environment(WorkspaceViewModel.self) private var workspace
    @State private var expandedIds: Set<String> = []

    var body: some View {
        Form {
            Section("Провайдеры ИИ") {
                ForEach(ProviderInfo.all) { info in
                    ProviderRow(
                        info: info,
                        expanded: Binding(
                            get: { expandedIds.contains(info.id) },
                            set: { newValue in
                                if newValue {
                                    expandedIds.insert(info.id)
                                } else {
                                    expandedIds.remove(info.id)
                                }
                            }
                        )
                    )
                }
            }
            Section {
                Text("OpenRouter поддерживает вход через браузер (OAuth) — ключ создаётся автоматически. Для остальных провайдеров получите API-ключ по ссылке и вставьте его в поле. Ключи хранятся только в Связке ключей macOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 560)
    }
}

private struct ProviderRow: View {
    let info: ProviderInfo
    @Binding var expanded: Bool
    @Environment(WorkspaceViewModel.self) private var workspace

    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKeyInput = ""
    @State private var didLoadSnapshot = false

    private var isConnected: Bool {
        workspace.connections[info.id] != nil
    }

    private var isActive: Bool {
        workspace.activeProviderID == info.id && isConnected
    }

    private var modelChoices: [String] {
        let fetched = workspace.fetchedModels[info.id]
        return (fetched?.isEmpty == false ? fetched! : info.fallbackModels)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                if info.allowsCustomBaseURL {
                    LabeledContent("Адрес") {
                        TextField("http://localhost:11434/v1", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                LabeledContent("Модель") {
                    HStack {
                        TextField("Модель", text: $model)
                            .textFieldStyle(.roundedBorder)
                        Menu {
                            ForEach(modelChoices, id: \.self) { candidate in
                                Button(candidate) {
                                    model = candidate
                                }
                            }
                            if modelChoices.isEmpty {
                                Text("Список недоступен")
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                if info.authStyle != AuthStyle.none {
                    LabeledContent("API ключ") {
                        HStack {
                            SecureField(
                                isConnected ? "Сохранён — введите новый для замены" : "API ключ",
                                text: $apiKeyInput
                            )
                            .textFieldStyle(.roundedBorder)
                            if let keysPage = info.keysPageURL, let url = URL(string: keysPage) {
                                Link("Получить ключ", destination: url)
                                    .font(.caption)
                            }
                        }
                    }
                }
                HStack(spacing: 10) {
                    if info.usesOAuth && !isConnected {
                        Button {
                            Task { await workspace.connectViaBrowser(info) }
                        } label: {
                            Label("Подключить через браузер", systemImage: "globe")
                        }
                        .disabled(workspace.isConnectingViaBrowser)
                        if workspace.isConnectingViaBrowser {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Button("Сохранить подключение") {
                        workspace.saveConnection(
                            providerId: info.id,
                            baseURLString: baseURL,
                            model: model,
                            enteredApiKey: apiKeyInput
                        )
                        apiKeyInput = ""
                    }
                    if isConnected {
                        Button("Сделать активным") {
                            workspace.setActiveProvider(info.id)
                        }
                        .disabled(isActive)
                        Button("Отключить", role: .destructive) {
                            workspace.disconnect(providerId: info.id)
                            didLoadSnapshot = false
                        }
                    }
                }
                .font(.callout)
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(isConnected ? Color.accentColor : Color.secondary)
                Text(info.name)
                Spacer()
                if isActive {
                    Label("активен", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if isConnected {
                    Label("подключён", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("не подключён")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: expanded) { _, isExpanded in
            guard isExpanded else { return }
            loadSnapshot()
            Task { await workspace.fetchModelsIfNeeded(for: info) }
        }
    }

    private func loadSnapshot() {
        let connection = workspace.connections[info.id]
        baseURL = connection?.baseURLString ?? info.defaultBaseURL
        model = connection?.model ?? info.fallbackModels.first ?? ""
        apiKeyInput = ""
        didLoadSnapshot = true
    }
}
