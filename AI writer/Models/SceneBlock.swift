import CoreTransferable
import Foundation
import GRDB
import UniformTypeIdentifiers

struct SceneBlock: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: UUID
    var manuscriptId: UUID
    var title: String
    var content: String
    var position: Int
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "scenes"

    static func blank(in manuscriptId: UUID, position: Int, now: Date = Date()) -> SceneBlock {
        SceneBlock(
            id: UUID(),
            manuscriptId: manuscriptId,
            title: "Новая сцена",
            content: "",
            position: position,
            createdAt: now,
            updatedAt: now
        )
    }

    mutating func merged(with other: SceneBlock, otherFirst: Bool, now: Date = Date()) {
        let joiner = "\n\n"
        content = otherFirst ? other.content + joiner + content : content + joiner + other.content
        title = otherFirst ? "\(other.title) + \(title)" : "\(title) + \(other.title)"
        touch(now: now)
    }

    mutating func touch(now: Date = Date()) {
        updatedAt = now
    }
}

extension SceneBlock: Transferable {
    static let sceneType = UTType(exportedAs: "com.khtulhu.ai-writer.scene")

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: SceneBlock.sceneType)
    }
}
