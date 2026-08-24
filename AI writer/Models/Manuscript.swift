import Foundation
import GRDB

struct Manuscript: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "manuscripts"

    static func create(title: String, now: Date = Date()) -> Manuscript {
        Manuscript(id: UUID(), title: title, createdAt: now, updatedAt: now)
    }

    mutating func touch(now: Date = Date()) {
        updatedAt = now
    }
}
