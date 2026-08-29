import Foundation
import SwiftData

@Model
final class Block {
    var id: UUID
    var title: String = ""
    var content: String
    var order: Double
    var createdAt: Date
    var updatedAt: Date

    var manuscript: Manuscript?

    init(
        title: String = "",
        content: String = "",
        order: Double = 0,
        manuscript: Manuscript? = nil,
        now: Date = .now
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.order = order
        self.createdAt = now
        self.updatedAt = now
        self.manuscript = manuscript
    }
}