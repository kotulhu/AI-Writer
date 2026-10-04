import Foundation
import Network

/// Локальный HTTP-сервер для приёма OAuth-callback на `127.0.0.1`.
///
/// Слушает только loopback и только путь `/callback`, отвечает на `GET`
/// HTML-страницей. Наружу порт не открывается, писать что-либо сервер не умеет —
/// это делает его безопасным местом для одноразового кода авторизации.
final class LoopbackCallbackServer {
    /// Путь, на который OpenRouter возвращает код авторизации.
    static let callbackPath = "/callback"

    /// Вызывается, когда сервер получил корректный callback-запрос.
    var onCallback: ((URL) -> Void)?

    private let queue = DispatchQueue(label: "ai.loopback-callback")
    private var listener: NWListener?
    private var isStopped = false
    /// Соединения, принятые listener'ом.
    ///
    /// Хранятся, чтобы `stop()` закрывал их явно: `cancel()` listener'а обрывает
    /// и уже принятые соединения, из-за чего браузер не успевает прочитать ответ.
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

    /// Запускает сервер на свободном loopback-порту и возвращает его номер.
    ///
    /// Порт 0 передаётся системе — она выбирает свободный. Метод синхронный
    /// и блокируется до готовности listener, потому что вызывающему нужно знать
    /// порт сразу, чтобы собрать `callback_url`.
    func start() throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Слушаем строго loopback: из внешней сети порт недоступен.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters, on: .any)

        let ready = DispatchSemaphore(value: 0)
        var startupError: NWError?

        listener.stateUpdateHandler = { state in
            AILog.auth("CallbackServer state: \(state)")
            switch state {
            case .ready:
                ready.signal()
            case let .failed(error):
                startupError = error
                ready.signal()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        self.listener = listener
        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + 5) == .success else {
            listener.cancel()
            throw OpenRouterAuthError.localServerFailed("сервер не запустился за 5 секунд")
        }
        if let startupError {
            listener.cancel()
            throw OpenRouterAuthError.localServerFailed(startupError.localizedDescription)
        }
        guard let port = listener.port?.rawValue else {
            listener.cancel()
            throw OpenRouterAuthError.localServerFailed("не удалось определить порт")
        }

        AILog.auth("Локальный сервер запущен на порту \(port)")
        return port
    }

    /// Останавливает сервер и освобождает порт.
    ///
    /// `reason` попадает в лог: без него невозможно отличить штатное завершение
    /// флоу от преждевременной остановки, из-за которой браузер не доходит
    /// до сервера.
    func stop(reason: String = "без причины") {
        guard !isStopped else { return }
        isStopped = true
        AILog.auth("CallbackServer: остановлен (\(reason)), соединений: \(activeConnections.count)")
        listener?.cancel()
        listener = nil
        for connection in activeConnections.values {
            connection.cancel()
        }
        activeConnections.removeAll()
    }

    deinit {
        stop(reason: "deinit")
    }

    // MARK: - Обработка запроса

    private func accept(_ connection: NWConnection) {
        AILog.auth("CallbackServer: соединение принято")
        activeConnections[ObjectIdentifier(connection)] = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard case .cancelled = state else { return }
            self?.activeConnections.removeValue(forKey: ObjectIdentifier(connection))
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    /// Накапливает данные до конца заголовков и разбирает первую строку запроса.
    private func receive(on connection: NWConnection) {
        var buffer = Data()

        func process() {
            AILog.auth("CallbackServer: запрос (\(buffer.count) байт): \(Self.firstLine(of: buffer) ?? "нечитаемый")")
            guard let request = String(data: buffer, encoding: .utf8),
                  let url = parseCallbackURL(from: request) else {
                respond(with: Self.failurePage, on: connection, then: nil)
                return
            }
            // Провайдер сообщает об отказе прямо в callback (`?error=…`).
            // Показывать в этом случае страницу успеха нельзя: пользователь
            // увидит «успешно», хотя доступ не выдан.
            let isDenied = Self.queryValue("error", in: url) != nil
                || Self.queryValue("error_description", in: url) != nil
            // Порядок обязателен. `onCallback` останавливает listener, а его
            // `cancel()` обрывает и это соединение — если сообщить раньше, чем
            // байты ушли, Safari не дождётся страницы и напишет
            // «Safari не может подключиться к серверу».
            respond(with: isDenied ? Self.failurePage : Self.successPage, on: connection) { [weak self] in
                self?.onCallback?(url)
            }
        }

        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, _, error in
                if error == nil, let data, !data.isEmpty {
                    buffer.append(data)
                    let headersComplete = buffer.range(of: Data("\r\n\r\n".utf8)) != nil
                        || buffer.range(of: Data("\n\n".utf8)) != nil
                    if headersComplete || buffer.count >= 16 * 1024 {
                        process()
                    } else {
                        readMore()
                    }
                } else if let error {
                    AILog.auth("CallbackServer: ошибка чтения — \(error.localizedDescription)")
                    if buffer.isEmpty { connection.cancel() } else { process() }
                } else if buffer.isEmpty {
                    AILog.auth("CallbackServer: соединение закрыто клиентом без данных")
                    connection.cancel()
                } else {
                    process()
                }
            }
        }

        readMore()
    }

    /// Достаёт URL из первой строки HTTP-запроса вида `GET /callback?code=… HTTP/1.1`.
    ///
    /// Путь может содержать схему (`http://127.0.0.1:1234/callback`), поэтому
    /// недостаточно отбросить префикс хоста. Если схемы нет, host берётся из
    /// заголовка `Host`, чтобы в URL сохранились query-параметры.
    private func parseCallbackURL(from request: String) -> URL? {
        guard let firstLine = request.split(separator: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        // Безопасность: принимаем только GET, чтобы сервер нельзя было
        // использовать для записи данных.
        guard parts[0].uppercased() == "GET" else { return nil }

        let target = parts[1]
        let pathOnly = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        guard pathOnly.hasSuffix(Self.callbackPath) else { return nil }

        if target.contains("://") {
            return URL(string: target)
        }
        let host = request
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("host:") }
            .map { $0.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? "" }
            ?? "127.0.0.1"
        return URL(string: "http://\(host)\(target)")
    }

    /// Первая строка запроса для лога, обрезанная до разумной длины.
    static func firstLine(of buffer: Data) -> String? {
        let text = String(decoding: buffer, as: UTF8.self)
        guard let line = text.split(separator: "\r\n").first else { return nil }
        return line.count > 160 ? String(line.prefix(160)) + "…" : String(line)
    }

    /// Значение query-параметра по имени.
    static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private func respond(with html: String, on connection: NWConnection, then completion: (() -> Void)?) {
        let body = Data(html.utf8)
        // HTTP требует CRLF: с обычным \n CFNetwork отвечает «cannot parse response»
        // и страница в браузере не показывается.
        let header = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        var payload = Data(header.utf8)
        payload.append(body)

        connection.send(content: payload, completion: .contentProcessed { error in
            if let error {
                AILog.auth("CallbackServer: не отправил ответ — \(error.localizedDescription)")
            }
            // Соединение закрываем до вызова completion: браузер уже получил
            // ответ, и только теперь приложение продолжает флоу.
            connection.cancel()
            completion?()
        })
    }

    // MARK: - Страницы

    private static let successPage = """
    <!DOCTYPE html>
    <html lang="ru">
    <head>
        <meta charset="utf-8">
        <title>Авторизация успешна</title>
        <style>
            body { font-family: -apple-system, system-ui, sans-serif; text-align: center;
                   margin-top: 18vh; color: #1a1a1a; background: #f6f7f9; }
            h1 { font-size: 22px; margin-bottom: 12px; }
            p { color: #555; font-size: 14px; }
        </style>
    </head>
    <body>
        <h1>✅ Авторизация успешна!</h1>
        <p>Можете закрыть это окно — приложение уже получило доступ.</p>
    </body>
    </html>
    """

    private static let failurePage = """
    <!DOCTYPE html>
    <html lang="ru">
    <head>
        <meta charset="utf-8">
        <title>Ошибка авторизации</title>
        <style>
            body { font-family: -apple-system, system-ui, sans-serif; text-align: center;
                   margin-top: 18vh; color: #1a1a1a; background: #f6f7f9; }
            h1 { font-size: 22px; margin-bottom: 12px; }
            p { color: #555; font-size: 14px; }
        </style>
    </head>
    <body>
        <h1>⚠️ Не удалось завершить авторизацию</h1>
        <p>Вернитесь в приложение и попробуйте снова.</p>
    </body>
    </html>
    """
}
