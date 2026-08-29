import Foundation
import SwiftData
import Observation

enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case books
    case characters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .books: "Книги"
        case .characters: "Персонажи"
        }
    }

    var icon: String {
        switch self {
        case .books: "books.vertical"
        case .characters: "person.2"
        }
    }
}

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case blocks
    case characters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blocks: "Блоки"
        case .characters: "Персонажи"
        }
    }

    var icon: String {
        switch self {
        case .blocks: "doc.text"
        case .characters: "person.2"
        }
    }
}

@MainActor
@Observable
final class ManuscriptStore {
    var selectedManuscript: Manuscript?
    var selectedBlock: Block?
    var appSection: AppSection = .books
    var workspaceMode: WorkspaceMode = .blocks

    // MARK: - Debounced save

    private var saveTask: Task<Void, Never>?
    private let saveDelay: Duration = .milliseconds(600)

    func scheduleAutoSave(_ block: Block, content: String, context: ModelContext) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: self?.saveDelay ?? .milliseconds(600))
            guard !Task.isCancelled else { return }
            block.content = content
            block.updatedAt = .now
            block.manuscript?.updatedAt = .now
            try? context.save()
        }
    }

    /// Writes immediately — used when the editor is torn down (block switch)
    /// so no pending input is lost before the debounce fires.
    func saveNow(_ block: Block, content: String, context: ModelContext) {
        saveTask?.cancel()
        saveTask = nil
        block.content = content
        block.updatedAt = .now
        block.manuscript?.updatedAt = .now
        try? context.save()
    }

    // MARK: - Manuscript CRUD

    @discardableResult
    func createManuscript(title: String, context: ModelContext) -> Manuscript {
        let manuscript = Manuscript(title: title)
        context.insert(manuscript)
        let firstBlock = Block(title: newBlockTitle(for: manuscript), order: 0, manuscript: manuscript)
        manuscript.blocks.append(firstBlock)
        context.insert(firstBlock)
        selectedManuscript = manuscript
        selectedBlock = firstBlock
        try? context.save()
        return manuscript
    }

    func deleteManuscript(_ manuscript: Manuscript, context: ModelContext) {
        if selectedManuscript?.id == manuscript.id {
            selectedManuscript = nil
            selectedBlock = nil
        }
        // SwiftData to-many cascade is unreliable on this SDK — remove children explicitly.
        for character in manuscript.characters {
            context.delete(character)
        }
        for block in manuscript.blocks {
            for version in block.versions {
                context.delete(version)
            }
            context.delete(block)
        }
        context.delete(manuscript)
        try? context.save()
    }

    func renameManuscript(_ manuscript: Manuscript, title: String, context: ModelContext) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        manuscript.title = trimmed
        manuscript.updatedAt = .now
        try? context.save()
    }

    // MARK: - Block helpers

    private func newBlockTitle(for manuscript: Manuscript) -> String {
        let count = manuscript.orderedBlocks.count
        return "Блок \(count + 1)"
    }

    // MARK: - Block CRUD

    /// Creates a block after `after` (or at the end when `after == nil`), and selects it.
    @discardableResult
    func addBlock(after: Block?, manuscript: Manuscript, context: ModelContext) -> Block {
        let blocks = manuscript.orderedBlocks
        let newOrder: Double
        if let after {
            if let idx = blocks.firstIndex(where: { $0.id == after.id }) {
                let next = idx + 1 < blocks.count ? blocks[idx + 1].order : after.order + 1
                newOrder = (after.order + next) / 2.0
            } else {
                newOrder = (blocks.last?.order ?? 0) + 1
            }
        } else {
            newOrder = (blocks.last?.order ?? 0) + 1
        }
        let block = Block(title: newBlockTitle(for: manuscript), order: newOrder, manuscript: manuscript)
        manuscript.blocks.append(block)
        context.insert(block)
        manuscript.updatedAt = .now
        try? context.save()
        selectedBlock = block
        return block
    }

    func renameBlock(_ block: Block, title: String, context: ModelContext) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        block.title = trimmed
        block.updatedAt = .now
        block.manuscript?.updatedAt = .now
        try? context.save()
    }

    /// Moves a block one position up (-1) or down (+1) by swapping its order with the neighbour.
    func moveBlock(_ block: Block, _ direction: Int, context: ModelContext) {
        guard let manuscript = block.manuscript else { return }
        let blocks = manuscript.orderedBlocks
        guard let idx = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        let target = idx + direction
        guard target >= 0, target < blocks.count else { return }
        let neighbor = blocks[target]
        let temp = block.order
        block.order = neighbor.order
        neighbor.order = temp
        block.updatedAt = .now
        neighbor.updatedAt = .now
        manuscript.updatedAt = .now
        try? context.save()
    }

    // MARK: - Versions

    /// Snapshot of the current block state. Returns nil when the block has no content.
    @discardableResult
    func createVersion(for block: Block, context: ModelContext) -> BlockVersion? {
        let content = block.content
        guard !content.isEmpty else { return nil }
        let version = BlockVersion(content: content, title: block.title, createdAt: .now)
        version.block = block
        context.insert(version)
        pruneVersions(for: block, context: context)
        block.updatedAt = .now
        try? context.save()
        return version
    }

    /// Keeps at most 10 versions; oldest non-pinned versions are removed first.
    private func pruneVersions(for block: Block, context: ModelContext) {
        var versions = block.versions.sorted { $0.createdAt < $1.createdAt }
        while versions.count > 10 {
            guard let idx = versions.firstIndex(where: { !$0.isPinned }) else { break }
            context.delete(versions[idx])
            versions.remove(at: idx)
        }
    }

    /// Copies a version into the block. The current (pre-restore) state is preserved
    /// as a new version so the history is not erased.
    func restoreVersion(_ version: BlockVersion, context: ModelContext) {
        guard let block = version.block else { return }
        createVersion(for: block, context: context)
        block.content = version.content
        if let title = version.title, !title.isEmpty {
            block.title = title
        }
        block.updatedAt = .now
        try? context.save()
    }

    func setVersionPinned(_ version: BlockVersion, _ pinned: Bool, context: ModelContext) {
        version.isPinned = pinned
        try? context.save()
    }

    // MARK: - Character CRUD

    @discardableResult
    func addCharacter(to manuscript: Manuscript, context: ModelContext) -> Character {
        let character = Character(manuscript: manuscript)
        manuscript.characters.append(character)
        context.insert(character)
        manuscript.updatedAt = .now
        try? context.save()
        return character
    }

    @discardableResult
    func duplicateCharacter(_ character: Character, context: ModelContext) -> Character {
        let copy = Character(
            manuscript: character.manuscript,
            name: character.name,
            species: character.species,
            isMale: character.isMale,
            age: character.age,
            height: character.height,
            weight: character.weight,
            hairColor: character.hairColor,
            hairLength: character.hairLength,
            appearanceDescription: character.appearanceDescription,
            clothingPreference: character.clothingPreference
        )
        if let manuscript = character.manuscript {
            manuscript.characters.append(copy)
        }
        context.insert(copy)
        character.manuscript?.updatedAt = .now
        try? context.save()
        return copy
    }

    func deleteCharacter(_ character: Character, context: ModelContext) {
        character.manuscript?.updatedAt = .now
        context.delete(character)
        try? context.save()
    }

    // MARK: - Debounced character save

    private var characterSaveTask: Task<Void, Never>?
    private let characterSaveDelay: Duration = .milliseconds(600)

    func scheduleCharacterSave(_ character: Character, context: ModelContext) {
        characterSaveTask?.cancel()
        characterSaveTask = Task { [weak self] in
            try? await Task.sleep(for: self?.characterSaveDelay ?? .milliseconds(600))
            guard !Task.isCancelled else { return }
            character.updatedAt = .now
            character.manuscript?.updatedAt = .now
            try? context.save()
        }
    }

    /// Writes immediately — used when the detail view is closed so no pending edits are lost.
    func saveCharacterNow(_ character: Character, context: ModelContext) {
        characterSaveTask?.cancel()
        characterSaveTask = nil
        character.updatedAt = .now
        character.manuscript?.updatedAt = .now
        try? context.save()
    }

    func deleteBlock(_ block: Block, context: ModelContext) {
        let blocks = block.manuscript?.orderedBlocks ?? []
        if let idx = blocks.firstIndex(where: { $0.id == block.id }) {
            let remaining = blocks.filter { $0.id != block.id }
            selectedBlock = idx > 0 ? remaining[idx - 1] : remaining.first
        } else {
            selectedBlock = nil
        }
        block.manuscript?.updatedAt = .now
        context.delete(block)
        try? context.save()
    }

    func duplicateBlock(_ block: Block, context: ModelContext) {
        guard let manuscript = block.manuscript else { return }
        let blocks = manuscript.orderedBlocks
        guard let idx = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        let nextOrder = idx + 1 < blocks.count ? blocks[idx + 1].order : block.order + 1
        let duplicate = Block(title: block.title, content: block.content, order: (block.order + nextOrder) / 2.0, manuscript: manuscript)
        manuscript.blocks.append(duplicate)
        context.insert(duplicate)
        manuscript.updatedAt = .now
        try? context.save()
        selectedBlock = duplicate
    }

    func mergeBlockWithNext(_ block: Block, context: ModelContext) {
        guard let manuscript = block.manuscript else { return }
        let blocks = manuscript.orderedBlocks
        guard let idx = blocks.firstIndex(where: { $0.id == block.id }),
              idx + 1 < blocks.count else { return }
        let next = blocks[idx + 1]
        let separator = block.content.isEmpty ? "" : "\n\n"
        block.content = block.content + separator + next.content
        block.updatedAt = .now
        context.delete(next)
        manuscript.updatedAt = .now
        try? context.save()
    }

    /// Splits a block: `head` stays in the original block, `tail` goes into a new
    /// block placed right after it (order midpoint with the current next block).
    func splitBlock(_ block: Block, head: String, tail: String, context: ModelContext) {
        guard let manuscript = block.manuscript else { return }
        saveTask?.cancel()
        saveTask = nil
        let blocks = manuscript.orderedBlocks
        guard let idx = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        let nextOrder = idx + 1 < blocks.count ? blocks[idx + 1].order : block.order + 1
        let newOrder = (block.order + nextOrder) / 2.0

        block.content = head
        block.updatedAt = .now
        let newBlock = Block(title: newBlockTitle(for: manuscript), content: tail, order: newOrder, manuscript: manuscript)
        manuscript.blocks.append(newBlock)
        context.insert(newBlock)
        manuscript.updatedAt = .now
        try? context.save()
        selectedBlock = newBlock
    }
}