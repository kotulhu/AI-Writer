import Foundation
import GRDB
import Observation

struct MergeCandidate: Identifiable {
    let id = UUID()
    let source: SceneBlock
    let target: SceneBlock
}

@MainActor
@Observable
final class WorkspaceViewModel {
    private let database: DatabaseService

    var manuscripts: [Manuscript] = []
    var scenes: [SceneBlock] = []
    var selectedManuscriptID: UUID?
    var selectedSceneID: UUID?
    var mergeCandidate: MergeCandidate?
    var aiSuggestion: String?
    var isGenerating = false
    var errorMessage: String?

    private var saveTasks: [UUID: Task<Void, Never>] = [:]

    var selectedManuscript: Manuscript? {
        manuscripts.first { $0.id == selectedManuscriptID }
    }

    var selectedScene: SceneBlock? {
        scenes.first { $0.id == selectedSceneID }
    }

    init(database: DatabaseService) {
        self.database = database
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
        guard let provider = makeProvider() else {
            errorMessage = "Некорректный адрес API — проверьте настройки"
            return
        }
        isGenerating = true
        aiSuggestion = nil
        defer { isGenerating = false }
        do {
            let prompt = Prompts.make(for: mode, scene: scene)
            aiSuggestion = try await provider.generate(
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

    private func makeProvider() -> OpenAIProvider? {
        let defaults = UserDefaults.standard
        let baseURLString = defaults.string(forKey: AIConfiguration.baseURLKey) ?? AIConfiguration.defaultBaseURL
        guard let url = URL(string: baseURLString), url.scheme != nil else { return nil }
        return OpenAIProvider(
            endpoint: url,
            apiKey: KeychainStore.get(account: AIConfiguration.keychainAccount),
            model: defaults.string(forKey: AIConfiguration.modelKey) ?? AIConfiguration.defaultModel
        )
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
