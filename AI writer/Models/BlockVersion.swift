import Foundation
import SwiftData

@Model
final class BlockVersion {
    var id: UUID
    var content: String
    var title: String?
    var createdAt: Date
    var label: String?
    var isPinned: Bool

    var block: Block?

    init(
        content: String,
        title: String? = nil,
        createdAt: Date = .now,
        label: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = UUID()
        self.content = content
        self.title = title
        self.createdAt = createdAt
        self.label = label
        self.isPinned = isPinned
    }
}