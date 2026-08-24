import Foundation
import GRDB

final class DatabaseService {
    let dbWriter: any DatabaseWriter

    private init(writer: any DatabaseWriter) {
        dbWriter = writer
    }

    static func live() -> DatabaseService {
        if let disk = try? diskBacked() {
            return disk
        }
        let memory = try! DatabaseQueue()
        try! migrate(memory)
        return DatabaseService(writer: memory)
    }

    private static func diskBacked() throws -> DatabaseService {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "AI Writer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: directory.appending(path: "ai-writer.sqlite").path)
        try migrate(pool)
        return DatabaseService(writer: pool)
    }

    private static func migrate(_ writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "manuscripts") { t in
                t.column("id", .text).primaryKey(onConflict: .replace)
                t.column("title", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "scenes") { t in
                t.column("id", .text).primaryKey(onConflict: .replace)
                t.column("manuscriptId", .text).notNull().indexed().references("manuscripts", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("content", .text).notNull()
                t.column("position", .integer).notNull().indexed()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        try migrator.migrate(writer)
    }
}

extension DatabaseService {
    func allManuscripts() async throws -> [Manuscript] {
        try await dbWriter.read { db in
            try Manuscript.order(Column("createdAt")).fetchAll(db)
        }
    }

    @discardableResult
    func insert(_ manuscript: Manuscript) async throws -> Manuscript {
        try await dbWriter.write { db in
            var record = manuscript
            try record.insert(db)
            return record
        }
    }

    func update(_ manuscript: Manuscript) async throws {
        try await dbWriter.write { db in
            var record = manuscript
            try record.update(db)
        }
    }

    func deleteManuscript(id: UUID) async throws {
        _ = try await dbWriter.write { db in
            _ = try Manuscript.deleteOne(db, key: id)
        }
    }

    func scenes(in manuscriptId: UUID) async throws -> [SceneBlock] {
        try await dbWriter.read { db in
            try SceneBlock.filter(Column("manuscriptId") == manuscriptId)
                .order(Column("position"))
                .fetchAll(db)
        }
    }

    @discardableResult
    func insert(_ scene: SceneBlock) async throws -> SceneBlock {
        try await dbWriter.write { db in
            var record = scene
            try record.insert(db)
            return record
        }
    }

    func update(_ scene: SceneBlock) async throws {
        try await dbWriter.write { db in
            var record = scene
            try record.update(db)
        }
    }

    func deleteScene(id: UUID) async throws {
        _ = try await dbWriter.write { db in
            _ = try SceneBlock.deleteOne(db, key: id)
        }
    }

    func setPositions(_ pairs: [(id: UUID, position: Int)]) async throws {
        _ = try await dbWriter.write { db in
            for pair in pairs {
                try db.execute(
                    sql: "UPDATE scenes SET position = ? WHERE id = ?",
                    arguments: [pair.position, pair.id]
                )
            }
        }
    }

    func merge(target: SceneBlock, removed: SceneBlock, positions: [(id: UUID, position: Int)]) async throws {
        _ = try await dbWriter.write { db in
            var updatedTarget = target
            try updatedTarget.update(db)
            _ = try SceneBlock.deleteOne(db, key: removed.id)
            for pair in positions {
                try db.execute(
                    sql: "UPDATE scenes SET position = ? WHERE id = ?",
                    arguments: [pair.position, pair.id]
                )
            }
        }
    }}
