import Foundation

import OSLog

/// Единая точка логирования приложения.
///
/// Пишет и в консоль Xcode (`print`), и в системный unified-лог (`os.Logger`),
/// и в файл `editor.log`, который уже использовался редактором. Формат
/// сообщения — `[Префикс] текст`, чтобы строки разных подсистем не путались.
enum AILog {
    /// Префиксы подсистем — по ним строки в логе относятся к своему модулю.
    enum Prefix {
        static let auth = "OpenRouterAuth"
        static let store = "AIConnectionStore"
        static let client = "AIClient"
        static let chat = "ChatView"
    }

    private static let logger = Logger(subsystem: "AIWriter", category: "AI")

    /// Пишет строку в консоль, unified-лог и файл журнала.
    static func log(_ prefix: String, _ message: String) {
        let line = "[\(prefix)] \(message)"
        print(line)
        logger.info("\(line, privacy: .public)")
        writeToFile(line)
    }

    static func auth(_ message: String) { log(Prefix.auth, message) }
    static func store(_ message: String) { log(Prefix.store, message) }
    static func client(_ message: String) { log(Prefix.client, message) }
    static func chat(_ message: String) { log(Prefix.chat, message) }

    /// Порог, за которым многострочный блок обрезается в журнале.
    private static let maxBlockChars = 20_000

    /// Пишет многострочный блок — например, полный ответ провайдера.
    ///
    /// Тело уходит в консоль и в файл, но **не** в unified-лог: `os_log`
    /// рассчитан на короткие события, длинная проза там всё равно
    /// обрезается, а многострочная запись разъезжается по записям. Заголовок
    /// при этом пишется во все три канала, чтобы событие было видно и в
    /// системном логе.
    static func block(_ prefix: String, _ title: String, _ body: String) {
        guard !body.isEmpty else {
            log(prefix, "\(title): пусто")
            return
        }

        log(prefix, "\(title) (\(body.count) симв.)")

        let text = body.count > maxBlockChars
            ? String(body.prefix(maxBlockChars))
                + "\n…[обрезано в журнале, всего \(body.count) символов]"
            : body
        print(text)
        writeToFile("[\(prefix)] \(title)\n\(text)")
    }

    static func chatBlock(_ title: String, _ body: String) {
        block(Prefix.chat, title, body)
    }

    /// Путь к файлу журнала (в Application Support).
    static var logURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("editor.log")
    }

    private static func writeToFile(_ line: String) {
        guard let url = logURL else { return }
        let data = Data("[\(Date())] \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
