import Foundation
import Observation

struct ProviderConnection: Codable, Equatable {
    var baseURLString: String
    var model: String
}

struct MergeCandidate: Identifiable {
    let id = UUID()
    let source: SceneBlock
    let target: SceneBlock
}

struct RephraseRequest: Equatable {
    let style: RephraseStyle
    let originalText: String
    let location: Int
    let length: Int
    let sceneID: UUID
}

struct SynonymRequest: Equatable {
    let originalFragment: String
    let location: Int
    let length: Int
    let sceneID: UUID
}

@MainActor
@Observable
final class WorkspaceViewModel {
    private let database: DatabaseService

    private static let connectionsKey = "providers.connections"
    private static let activeProviderKey = "providers.active"
    private static let legacyBaseURLKey = "ai.baseURL"
    private static let legacyModelKey = "ai.model"

    var manuscripts: [Manuscript] = []
    var scenes: [SceneBlock] = []
    var selectedManuscriptID: UUID?
    var selectedSceneID: UUID?
    var mergeCandidate: MergeCandidate?
    var aiSuggestion: String?
    var isGenerating = false
    var errorMessage: String?

    var connections: [String: ProviderConnection] = [:]
    var activeProviderID: String?
    var fetchedModels: [String: [String]] = [:]
    var isLoadingModels = false
    var isConnectingViaBrowser = false

    var rephraseRequest: RephraseRequest?
    var rephraseVariants: [String] = []

    var synonymRequest: SynonymRequest?
    var synonymVariants: [String] = []

    private var saveTasks: [UUID: Task<Void, Never>] = [:]

    var selectedManuscript: Manuscript? {
        manuscripts.first { $0.id == selectedManuscriptID }
    }

    var selectedScene: SceneBlock? {
        scenes.first { $0.id == selectedSceneID }
    }

    var connectedProviders: [ProviderInfo] {
        ProviderInfo.all.filter { connections[$0.id] != nil }
    }

    var hasActiveProvider: Bool {
        activeProvider() != nil
    }

    var activeProviderName: String? {
        activeProvider()?.info.name
    }

    init(database: DatabaseService) {
        self.database = database
        loadConnections()
    }

    nonisolated static func keychainAccount(for providerId: String) -> String {
        "provider.key.\(providerId)"
    }

    func start() async {
        do {
            manuscripts = try await database.allManuscripts()
            if manuscripts.isEmpty {
                let created = try await database.insert(Manuscript.create(title: "Новая рукопись"))
                manuscripts.append(created)
            }
            if selectedManuscriptID == nil {
                selectedManuscriptID = manuscripts.first?.id
            }
            await reloadScenes()
        } catch {
            errorMessage = "Не удалось загрузить данные: \(error.localizedDescription)"
        }
    }

    func selectManuscript(_ id: UUID?) async {
        guard id != selectedManuscriptID else { return }
        selectedManuscriptID = id
        selectedSceneID = nil
        await reloadScenes()
    }

    func reloadScenes() async {
        guard let manuscriptId = selectedManuscriptID else {
            scenes = []
            return
        }
        do {
            scenes = try await database.scenes(in: manuscriptId)
            if selectedSceneID == nil || !scenes.contains(where: { $0.id == selectedSceneID }) {
                selectedSceneID = scenes.first?.id
            }
        } catch {
            errorMessage = "Не удалось загрузить сцены: \(error.localizedDescription)"
        }
    }

    func addManuscript() async {
        do {
            let created = try await database.insert(Manuscript.create(title: "Новая рукопись"))
            manuscripts.append(created)
            selectedManuscriptID = created.id
            await reloadScenes()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameManuscript(_ id: UUID, title: String) async {
        guard let index = manuscripts.firstIndex(where: { $0.id == id }) else { return }
        var updated = manuscripts[index]
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, updated.title != trimmed else { return }
        updated.title = trimmed
        updated.touch()
        manuscripts[index] = updated
        do {
            try await database.update(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteManuscript(_ id: UUID) async {
        do {
            try await database.deleteManuscript(id: id)
            manuscripts.removeAll { $0.id == id }
            if selectedManuscriptID == id {
                selectedManuscriptID = manuscripts.first?.id
                selectedSceneID = nil
                await reloadScenes()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addScene() async {
        guard let manuscriptId = selectedManuscriptID else { return }
        do {
            let blank = SceneBlock.blank(in: manuscriptId, position: scenes.count)
            let created = try await database.insert(blank)
            scenes.append(created)
            selectedSceneID = created.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicateScene(_ id: UUID) async {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        let original = scenes[index]
        var copy = original
        copy.id = UUID()
        copy.title = original.title + " (копия)"
        copy.createdAt = Date()
        copy.updatedAt = copy.createdAt
        var reordered = scenes
        reordered.insert(copy, at: index + 1)
        applyPositions(reordered)
        do {
            copy = try await database.insert(copy)
            await persistPositions()
            selectedSceneID = copy.id
        } catch {
            errorMessage = error.localizedDescription
            await reloadScenes()
        }
    }

    func deleteScene(_ id: UUID) async {
        do {
            try await database.deleteScene(id: id)
            scenes.removeAll { $0.id == id }
            applyPositions(scenes)
            await persistPositions()
            if selectedSceneID == id {
                selectedSceneID = scenes.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveScene(_ scene: SceneBlock, toGap gap: Int) async {
        guard let from = scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        var to = min(max(gap, 0), scenes.count)
        if from < to { to -= 1 }
        guard to != from else { return }
        var reordered = scenes
        let moving = reordered.remove(at: from)
        reordered.insert(moving, at: to)
        applyPositions(reordered)
        await persistPositions()
    }

    func moveScene(_ id: UUID, offset: Int) async {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + offset
        guard scenes.indices.contains(targetIndex), targetIndex != index else { return }
        var reordered = scenes
        reordered.swapAt(index, targetIndex)
        applyPositions(reordered)
        await persistPositions()
    }

    func proposeMerge(source: SceneBlock, into target: SceneBlock) {
        guard source.id != target.id else { return }
        mergeCandidate = MergeCandidate(source: source, target: target)
    }

    func performMerge(otherFirst: Bool) async {
        guard let candidate = mergeCandidate else { return }
        mergeCandidate = nil
        guard
            let targetIndex = scenes.firstIndex(where: { $0.id == candidate.target.id }),
            let sourceIndex = scenes.firstIndex(where: { $0.id == candidate.source.id })
        else { return }

        var target = scenes[targetIndex]
        let source = scenes[sourceIndex]
        target.merged(with: source, otherFirst: otherFirst)
        scenes[targetIndex] = target
        scenes.remove(at: sourceIndex)
        applyPositions(scenes)
        selectedSceneID = target.id

        do {
            try await database.merge(
                target: target,
                removed: source,
                positions: scenes.map { (id: $0.id, position: $0.position) }
            )
        } catch {
            errorMessage = "Не удалось сохранить склейку: \(error.localizedDescription)"
            await reloadScenes()
        }
    }

    func updateSceneContent(_ id: UUID, content: String) {
        mutate(id) { $0.content = content }
    }

    func renameScene(_ id: UUID, title: String) {
        mutate(id) { $0.title = title }
    }

    func generate(_ mode: AIMode) async {
        guard !isGenerating, let scene = selectedScene else { return }
        guard let client = makeClient() else {
            errorMessage = "Подключите ИИ-провайдера в настройках"
            return
        }
        isGenerating = true
        aiSuggestion = nil
        defer { isGenerating = false }
        do {
            let prompt = Prompts.make(for: mode, scene: scene)
            aiSuggestion = try await client.generate(
                system: prompt.system,
                user: prompt.user,
                temperature: 0.9
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptSuggestion() {
        guard let suggestion = aiSuggestion, let id = selectedSceneID else { return }
        aiSuggestion = nil
        mutate(id) { scene in
            scene.content = scene.content.isEmpty ? suggestion : scene.content + "\n\n" + suggestion
        }
    }

    func discardSuggestion() {
        aiSuggestion = nil
    }

    func rephrase(style: RephraseStyle, sourceText: String, location: Int, length: Int, sceneID: UUID) async {
        guard !isGenerating else { return }
        guard let client = makeClient() else {
            errorMessage = "Подключите ИИ-провайдера в настройках"
            return
        }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let prompt = Prompts.rephrase(style: style, text: sourceText)
            let raw = try await client.generate(system: prompt.system, user: prompt.user, temperature: 0.85)
            let variants = raw
                .components(separatedBy: Prompts.variantMarker)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !variants.isEmpty else {
                throw ChatCompletionsClient.AIError.emptyCompletion
            }
            rephraseRequest = RephraseRequest(
                style: style,
                originalText: sourceText,
                location: location,
                length: length,
                sceneID: sceneID
            )
            rephraseVariants = Array(variants.prefix(3))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelRephrase() {
        rephraseRequest = nil
        rephraseVariants = []
    }

    func findSynonyms(
        fragment: String,
        context: String,
        location: Int,
        length: Int,
        sceneID: UUID
    ) async {
        guard !isGenerating else { return }
        guard let client = makeClient() else {
            errorMessage = "Подключите ИИ-провайдера в настройках"
            return
        }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let prompt = Prompts.synonyms(word: fragment, context: context)
            let raw = try await client.generate(system: prompt.system, user: prompt.user, temperature: 0.7)
            let variants = raw
                .components(separatedBy: Prompts.variantMarker)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !variants.isEmpty else {
                throw ChatCompletionsClient.AIError.emptyCompletion
            }
            synonymRequest = SynonymRequest(
                originalFragment: fragment,
                location: location,
                length: length,
                sceneID: sceneID
            )
            synonymVariants = Array(variants.prefix(8))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearSynonyms() {
        synonymRequest = nil
        synonymVariants = []
    }

    func saveConnection(providerId: String, baseURLString: String, model: String, enteredApiKey: String) {
        let info = ProviderInfo.byId(providerId)
        let effectiveBase = (info?.allowsCustomBaseURL ?? false) ? baseURLString : (info?.defaultBaseURL ?? baseURLString)
        let trimmedBase = effectiveBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: trimmedBase), url.scheme != nil else {
            errorMessage = "Некорректный адрес API для «\(info?.name ?? providerId)»"
            return
        }

        let account = Self.keychainAccount(for: providerId)
        let storedKey = KeychainStore.get(account: account) ?? ""
        let needsKey = info?.authStyle != AuthStyle.none
        let enteredKey = enteredApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if needsKey && storedKey.isEmpty && enteredKey.isEmpty {
            errorMessage = "Введите API-ключ для «\(info?.name ?? providerId)»"
            return
        }
        if !enteredKey.isEmpty {
            KeychainStore.set(enteredKey, account: account)
        }

        connections[providerId] = ProviderConnection(baseURLString: trimmedBase, model: trimmedModel)
        persistConnections()

        if activeProviderID == nil || connections[activeProviderID ?? ""] == nil {
            setActiveProvider(providerId)
        }
        fetchedModels.removeValue(forKey: providerId)
    }

    func disconnect(providerId: String) {
        KeychainStore.set(nil, account: Self.keychainAccount(for: providerId))
        connections.removeValue(forKey: providerId)
        fetchedModels.removeValue(forKey: providerId)
        if activeProviderID == providerId {
            activeProviderID = connectedProviders.first?.id
            UserDefaults.standard.set(activeProviderID, forKey: Self.activeProviderKey)
        }
        persistConnections()
    }

    func setActiveProvider(_ id: String?) {
        guard let id, connections[id] != nil else { return }
        activeProviderID = id
        UserDefaults.standard.set(id, forKey: Self.activeProviderKey)
    }

    func connectViaBrowser(_ info: ProviderInfo) async {
        isConnectingViaBrowser = true
        defer { isConnectingViaBrowser = false }
        do {
            let key = try await OAuthService.connectOpenRouter()
            saveConnection(
                providerId: info.id,
                baseURLString: info.defaultBaseURL,
                model: info.fallbackModels.first ?? "",
                enteredApiKey: key
            )
        } catch {
            if !(error is CancellationError) {
                errorMessage = "Не удалось подключить \(info.name): \(error.localizedDescription)"
            }
        }
    }

    func fetchModelsIfNeeded(for info: ProviderInfo) async {
        guard fetchedModels[info.id] == nil, !isLoadingModels else { return }
        let baseURLString = connections[info.id]?.baseURLString ?? info.defaultBaseURL
        guard let url = URL(string: baseURLString), url.scheme != nil else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }
        let config = ClientConfig(
            provider: info,
            baseURL: url,
            apiKey: KeychainStore.get(account: Self.keychainAccount(for: info.id)),
            model: connections[info.id]?.model ?? ""
        )
        do {
            let models = try await ChatCompletionsClient(config: config).fetchModels()
            let unique = Array(Set(models)).sorted()
            fetchedModels[info.id] = unique.isEmpty ? info.fallbackModels : unique
        } catch {
            fetchedModels[info.id] = info.fallbackModels
        }
    }

    private func loadConnections() {
        if let data = UserDefaults.standard.data(forKey: Self.connectionsKey),
           let decoded = try? JSONDecoder().decode([String: ProviderConnection].self, from: data) {
            connections = decoded
        }
        activeProviderID = UserDefaults.standard.string(forKey: Self.activeProviderKey)
        migrateLegacyConnectionIfNeeded()
        if activeProviderID == nil || connections[activeProviderID ?? ""] == nil {
            activeProviderID = connectedProviders.first?.id
            persistConnections()
        }
    }

    private func migrateLegacyConnectionIfNeeded() {
        guard connections.isEmpty else { return }
        let defaults = UserDefaults.standard
        guard let base = defaults.string(forKey: Self.legacyBaseURLKey),
              let url = URL(string: base), url.scheme != nil
        else { return }
        connections["custom"] = ProviderConnection(
            baseURLString: base,
            model: defaults.string(forKey: Self.legacyModelKey) ?? ""
        )
    }

    private func persistConnections() {
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: Self.connectionsKey)
        }
    }

    private struct ActiveClient {
        let info: ProviderInfo
        let client: TextGenerating
    }

    private func activeProvider() -> ActiveClient? {
        guard let id = activeProviderID,
              let connection = connections[id],
              let info = ProviderInfo.byId(id),
              let url = URL(string: connection.baseURLString), url.scheme != nil,
              !connection.model.isEmpty
        else { return nil }
        let config = ClientConfig(
            provider: info,
            baseURL: url,
            apiKey: KeychainStore.get(account: Self.keychainAccount(for: id)),
            model: connection.model
        )
        return ActiveClient(info: info, client: AIClientFactory.client(for: config))
    }

    private func makeClient() -> TextGenerating? {
        activeProvider()?.client
    }

    private func mutate(_ id: UUID, _ change: (inout SceneBlock) -> Void) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        var updated = scenes[index]
        let before = updated
        change(&updated)
        guard updated != before else { return }
        updated.touch()
        scenes[index] = updated
        scheduleSave(updated)
    }

    private func scheduleSave(_ scene: SceneBlock) {
        saveTasks[scene.id]?.cancel()
        let snapshot = scene
        saveTasks[scene.id] = Task {
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            try? await database.update(snapshot)
        }
    }

    private func applyPositions(_ ordered: [SceneBlock]) {
        var result: [SceneBlock] = []
        result.reserveCapacity(ordered.count)
        for (index, var scene) in ordered.enumerated() {
            scene.position = index
            result.append(scene)
        }
        scenes = result
    }

    private func persistPositions() async {
        let pairs = scenes.map { (id: $0.id, position: $0.position) }
        do {
            try await database.setPositions(pairs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
