import SwiftUI

struct SettingsView: View {
    @Environment(WorkspaceViewModel.self) private var workspace
    @State private var expandedIds: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Провайдеры ИИ")
                    .font(.title2.bold())
                    .padding(.bottom, 2)
                ForEach(ProviderInfo.all) { info in
                    ProviderCard(
                        info: info,
                        isExpanded: Binding(
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
                Text("OpenRouter поддерживает вход через браузер (OAuth) — ключ создаётся автоматически. Для остальных провайдеров вставьте API-ключ. Ключи хранятся только в Связке ключей macOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 660, height: 620)
    }
}

private struct ProviderCard: View {
    let info: ProviderInfo
    @Binding var isExpanded: Bool
    @Environment(WorkspaceViewModel.self) private var workspace

    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKeyInput = ""
    @State private var connectionTestStatus: ConnectionTestStatus = .idle

    private enum ConnectionTestStatus: Equatable {
        case idle, running, success, error(String)
    }

    private var isConnected: Bool {
        workspace.connections[info.id] != nil
    }

    private var isActive: Bool {
        workspace.activeProviderID == info.id && isConnected
    }

    private var modelChoices: [String] {
        let fetched = workspace.fetchedModels[info.id]
        let base = fetched?.isEmpty == false ? fetched! : info.fallbackModels
        return base.sorted { lhs, rhs in
            let lhsFree = lhs.contains(":free")
            let rhsFree = rhs.contains(":free")
            if lhsFree != rhsFree { return lhsFree }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: iconName)
                        .font(.system(size: 15))
                        .foregroundStyle(isConnected ? Color.accentColor : Color.secondary)
                        .frame(width: 24)
                    Text(info.name)
                        .font(.headline)
                    BillingChip(billing: info.billing)
                    Spacer()
                    statusView
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.vertical, 10)
                detailContent
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .onChange(of: isExpanded) { _, newValue in
            guard newValue else { return }
            loadSnapshot()
            connectionTestStatus = .idle
            Task { await workspace.fetchModelsIfNeeded(for: info) }
        }
        .task(id: isExpanded) {
            guard isExpanded else { return }
            await workspace.refreshUsage(for: info)
        }
    }

    private var iconName: String {
        switch info.id {
        case "ollama": "server.rack"
        case "lmstudio": "desktopcomputer"
        case "custom": "terminal"
        default: "cpu"
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if isActive {
            Label("активен", systemImage: "star.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if isConnected {
            Label("подключён", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Text("не подключён")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if info.allowsCustomBaseURL {
                LabeledContent("Адрес") {
                    TextField("http://localhost:1234/v1", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                }
            }
            LabeledContent("Модель") {
                HStack {
                    TextField("Модель", text: $model)
                        .textFieldStyle(.roundedBorder)
                    Menu {
                        ForEach(modelChoices, id: \.self) { candidate in
                            Button {
                                model = candidate
                            } label: {
                                if candidate.hasSuffix(":free") {
                                    HStack {
                                        Text(candidate)
                                        Text("FREE")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.green)
                                    }
                                } else {
                                    Text(candidate)
                                }
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
            if info.requiresApiKey {
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
            } else {
                Label("Авторизация не требуется", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if info.id == "openrouter" {
                usageSection
            }

            HStack(spacing: 10) {
                if info.usesOAuth && !isConnected {
                    Button {
                        Task { await workspace.connectViaBrowser(info) }
                    } label: {
                        Label("Войти через браузер", systemImage: "globe")
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
                    Task { await workspace.fetchModelsIfNeeded(for: info) }
                }
                if isConnected {
                    Button("Сделать активным") {
                        workspace.setActiveProvider(info.id)
                    }
                    .disabled(isActive)
                    Button("Отключить", role: .destructive) {
                        workspace.disconnect(providerId: info.id)
                    }
                }
            }
            .font(.callout)

            if isConnected {
                HStack(spacing: 8) {
                    Button("Проверить подключение") {
                        Task { await runConnectionTest() }
                    }
                    .controlSize(.small)
                    .disabled(connectionTestStatus == .running)
                    switch connectionTestStatus {
                    case .idle:
                        EmptyView()
                    case .running:
                        ProgressView()
                            .controlSize(.small)
                    case .success:
                        Label("Подключено ✅", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .error(let message):
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Не подключено ❌", systemImage: "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private func runConnectionTest() async {
        connectionTestStatus = .running
        let result = await workspace.testProvider(info)
        connectionTestStatus = result == nil ? .success : .error(result!)
    }

    @ViewBuilder
    private var usageSection: some View {
        if let usage = workspace.providerUsage[info.id] {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Баланс ключа")
                        .font(.callout.weight(.medium))
                    if usage.isFreeTier {
                        Text("Free tier")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if let remaining = usage.remainingPercent {
                        Text("Осталось ≈ \(Int(remaining.rounded()))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(remaining < 20 ? Color.red : Color.secondary)
                    }
                    Button {
                        Task { await workspace.refreshUsage(for: info, force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Обновить данные о балансе")
                }
                if let used = usage.usedPercent {
                    ProgressView(value: used, total: 100)
                        .tint(used > 80 ? Color.red : Color.accentColor)
                }
                Text(limitText(usage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func limitText(_ usage: ProviderUsage) -> String {
        func money(_ value: Double) -> String {
            value.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(value))
                : String(format: "%.2f", value)
        }
        if let limit = usage.limit {
            return "Израсходовано $\(money(usage.usage)) из $\(money(limit))"
        }
        return "Израсходовано $\(money(usage.usage)) · лимит не задан"
    }

    private func loadSnapshot() {
        let connection = workspace.connections[info.id]
        baseURL = connection?.baseURLString ?? info.defaultBaseURL
        model = connection?.model ?? info.fallbackModels.first ?? ""
        apiKeyInput = ""
    }
}

private struct BillingChip: View {
    let billing: ProviderBilling

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private var label: String {
        switch billing {
        case .local: "Бесплатно · Локально"
        case .freeTier: "Есть бесплатный тариф"
        case .paid: "Платный"
        case .unknown: "Свой сервер"
        }
    }

    private var tint: Color {
        switch billing {
        case .local: .green
        case .freeTier: .mint
        case .paid: .orange
        case .unknown: .gray
        }
    }
}
