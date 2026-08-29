import Foundation
import SwiftData

@Model
final class Manuscript {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Block.manuscript)
    var blocks: [Block]

    @Relationship(deleteRule: .cascade, inverse: \Character.manuscript)
    var characters: [Character]

    init(title: String, now: Date = .now) {
        self.id = UUID()
        self.title = title
        self.createdAt = now
        self.updatedAt = now
        self.blocks = []
        self.characters = []
    }

    var orderedBlocks: [Block] {
        blocks.sorted { $0.order < $1.order }
    }

    var orderedCharacters: [Character] {
        characters.sorted { $0.createdAt < $1.createdAt }
    }
}