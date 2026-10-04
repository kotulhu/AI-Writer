import Foundation
import AppKit
import AuthenticationServices

/// Авторизация в OpenRouter по OAuth 2.0 + PKCE с локальным callback.
///
/// Класс отвечает только за получение API-ключа; хранение ключа — задача
/// `AIConnectionStore`. Ключ наружу не логируется: в консоль попадает только
/// префикс и последние символы.
///
/// Полный флоу:
/// 1. генерируется `code_verifier` и его S256-производное `code_challenge`;
/// 2. поднимается локальный сервер на свободном порту `127.0.0.1`;
/// 3. открывается `ASWebAuthenticationSession` на `https://openrouter.ai/auth`
///    с `callback_url` этого сервера;
/// 4. после подтверждения в браузере провайдер возвращает `code`;
/// 5. `code` + `code_verifier` обмениваются на ключ `sk-or-v1-…`;
/// 6. локальный сервер останавливается.
@MainActor
final class OpenRouterAuth: NSObject, ObservableObject {
    /// Идёт ли сейчас авторизация (для индикатора в интерфейсе).
    @Published private(set) var isAuthorizing = false

    /// Ожидание callback: кто завершит флоу первым — локальный сервер, сама
    /// сессия (закрытие окна), отмена или таймаут.
    private var callbackWaiter: OneShot<URL>?
    private var session: ASWebAuthenticationSession?
    private var server: LoopbackCallbackServer?
    private var timeoutTask: Task<Void, Never>?
    /// Флоу идёт через обычный браузер, а не через системное окно.
    ///
    /// Пока флаг поднят, события `ASWebAuthenticationSession` игнорируются:
    /// сессия всё равно не работает, а её ошибка не должна рубить флоу.
    private var isUsingSystemBrowser = false

    /// Выполняет авторизацию и возвращает API-ключ OpenRouter.
    func authorize() async throws -> String {
        AILog.auth("Генерация PKCE...")
        reset()
        isAuthorizing = true

        defer { reset() }

        let verifier = PKCE.makeCodeVerifier()
        let challenge = PKCE.codeChallenge(for: verifier)
        AILog.auth("code_challenge: \(challenge)")

        let server = LoopbackCallbackServer()
        let port = try server.start()
        self.server = server

        // state защищает от подмены: чужой ответ не подойдёт, если не совпадёт.
        let state = PKCE.makeCodeVerifier(length: 32)

        guard let url = OpenRouter.makeAuthorizeURL(port: port, challenge: challenge, state: state) else {
            throw OpenRouterAuthError.localServerFailed("не удалось собрать URL авторизации")
        }
        AILog.auth("Открываю браузер: \(url.absoluteString)")

        let callbackURL = try await startSession(url: url, server: server)

        if let returnedState = LoopbackCallbackServer.queryValue("state", in: callbackURL),
           returnedState != state {
            AILog.auth("❌ state не совпал — отклоняю ответ")
            throw OpenRouterAuthError.stateMismatch
        }

        guard let code = LoopbackCallbackServer.queryValue("code", in: callbackURL), !code.isEmpty else {
            AILog.auth("❌ В callback нет параметра code")
            throw OpenRouterAuthError.missingCode
        }

        AILog.auth("Обмениваю код на ключ...")
        let key = try await exchangeCodeForKey(code: code, verifier: verifier)
        AILog.auth("Ключ получен: \(Self.masked(key))")
        return key
    }

    /// Отменяет авторизацию: закрывает окно браузера, останавливает сервер.
    func cancel() {
        guard isAuthorizing else { return }
        AILog.auth("Авторизация отменена пользователем")
        session?.cancel()
        session = nil
        server?.stop()
        server = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        server?.stop(reason: "отмена пользователем")
        callbackWaiter?.resume(throwing: OpenRouterAuthError.userCancelled)
        callbackWaiter = nil
    }

    // MARK: - Шаги флоу

    /// Запускает `ASWebAuthenticationSession` и ждёт завершения флоу.
    private func startSession(url: URL, server: LoopbackCallbackServer) async throws -> URL {
        let waiter = OneShot<URL>()
        callbackWaiter = waiter

        // Успешный путь: браузер приходит на локальный сервер.
        server.onCallback = { [weak self] callbackURL in
            Task { @MainActor [weak self] in
                AILog.auth("Браузер вернул callback, разбираю параметры")
                self?.session?.cancel()
                self?.callbackWaiter?.resume(returning: callbackURL)
            }
        }

        if !startWebSession(url: url) {
            // Запасной путь: обычный браузер по умолчанию.
            //
            // Код всё равно приходит на локальный HTTP-сервер, а не по схеме
            // URL, поэтому флоу не сломается, если системное окно почему-то
            // не показалось. Ошибки сессии после этого игнорируются — иначе
            // она сорвёт ожидание и закроет сервер прямо во время входа.
            AILog.auth("Системное окно авторизации недоступно — открываю браузер по умолчанию")
            guard NSWorkspace.shared.open(url) else {
                throw OpenRouterAuthError.sessionStartFailed
            }
            isUsingSystemBrowser = true
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: OpenRouter.authorizationTimeout)
            guard !Task.isCancelled else { return }
            AILog.auth("⏱ Таймаут: callback не получен за 5 минут")
            self?.callbackWaiter?.resume(throwing: OpenRouterAuthError.timedOut)
        }

        let result = try await waiter.value()
        finishSession()
        return result
    }

    /// Пытается открыть системное окно авторизации.
    ///
    /// Возвращает `false`, если окно показать не удалось, — вызывающий перейдёт
    /// на браузер по умолчанию.
    private func startWebSession(url: URL) -> Bool {
        let webSession = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Флоу ведёт обычный браузер: он придёт на локальный сервер, и
                // любое событие недоступной системной сессии тут лишнее. Раньше
                // её ошибка прилетала уже после открытия браузера, роняла
                // ожидание и останавливала сервер — Safari затем приходил на
                // уже закрытый порт.
                guard !self.isUsingSystemBrowser else {
                    AILog.auth("Событие системной сессии игнорировано (\(Self.describe(error)))")
                    return
                }
                if let callbackURL {
                    self.callbackWaiter?.resume(returning: callbackURL)
                } else if let code = (error as? ASWebAuthenticationSessionError)?.code, code == .canceledLogin {
                    self.callbackWaiter?.resume(throwing: OpenRouterAuthError.cancelled)
                } else if let code = (error as? ASWebAuthenticationSessionError)?.code,
                          code == .presentationContextNotProvided || code == .presentationContextInvalid {
                    self.callbackWaiter?.resume(throwing: OpenRouterAuthError.sessionStartFailed)
                } else if let error {
                    self.callbackWaiter?.resume(throwing: OpenRouterAuthError.network(error.localizedDescription))
                } else {
                    self.callbackWaiter?.resume(throwing: OpenRouterAuthError.cancelled)
                }
            }
        }
        // Общая сессия браузера: пользователь не вводит логин заново.
        webSession.prefersEphemeralWebBrowserSession = false
        // Обязательно: без этого сессия падает с presentationContextNotProvided.
        webSession.presentationContextProvider = self
        session = webSession

        guard webSession.start() else {
            AILog.auth("ASWebAuthenticationSession.start() вернул false")
            session = nil
            return false
        }
        return true
    }

    /// Освобождает ресурсы после завершения сессии.
    private func finishSession() {
        timeoutTask?.cancel()
        timeoutTask = nil
        session?.cancel()
        session = nil
        server?.stop(reason: "callback получен, флоу завершён")
        server = nil
    }

    /// Обмен `code` + `code_verifier` на API-ключ.
    private func exchangeCodeForKey(code: String, verifier: String) async throws -> String {
        let request = try OpenRouter.makeTokenRequest(code: code, codeVerifier: verifier)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            AILog.auth("❌ Ошибка сети при обмене кода: \(error.localizedDescription)")
            throw OpenRouterAuthError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterAuthError.network("некорректный ответ сервера")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        guard (200...299).contains(http.statusCode) else {
            // Тело ответа логируем целиком: у провайдера разные коды ошибок
            // (`400` / `403`) с разными формулировками, и без них диагностика
            // превращается в угадывание.
            let message = Self.errorMessage(from: json) ?? "HTTP \(http.statusCode)"
            AILog.auth("❌ Провайдер отклонил авторизацию: HTTP \(http.statusCode) — \(message)")
            AILog.auth("Ответ: \(Self.snippet(of: data))")
            throw OpenRouterAuthError.provider(message)
        }

        guard let key = json["key"] as? String, !key.isEmpty else {
            AILog.auth("❌ В ответе нет поля key. Ответ: \(Self.snippet(of: data))")
            throw OpenRouterAuthError.missingKey
        }
        return key
    }

    /// Короткое безопасное представление тела ответа для логов.
    ///
    /// Ответ на обмен кода не содержит ключа в неуспешном случае, но обрезать
    /// всё равно обязаны: не даём случайному секрету утечь в лог.
    nonisolated private static func snippet(of data: Data, limit: Int = 300) -> String {
        let text = String(decoding: data, as: UTF8.self)
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard flat.count > limit else { return flat }
        return flat.prefix(limit) + "…"
    }

    /// Сбрасывает состояние после успеха, ошибки или отмены.
    private func reset() {
        isAuthorizing = false
        isUsingSystemBrowser = false
        callbackWaiter = nil
        session = nil
        server?.stop(reason: "сброс после завершения authorize()")
        server = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    // MARK: - Вспомогательное

    /// Достаёт читаемое сообщение об ошибке из JSON-ответа.
    private static func errorMessage(from json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty { return message }
        }
        if let description = json["error_description"] as? String, !description.isEmpty { return description }
        if let message = json["message"] as? String, !message.isEmpty { return message }
        if let error = json["error"] as? String, !error.isEmpty { return error }
        return nil
    }

    /// Понятное имя ошибки системной сессии — по коду, а не по тексту Apple.
    nonisolated private static func describe(_ error: Error?) -> String {
        guard let code = (error as? ASWebAuthenticationSessionError)?.code else {
            return error?.localizedDescription ?? "без ошибки"
        }
        switch code {
        case .canceledLogin: return "пользователь закрыл окно"
        case .presentationContextNotProvided: return "не передан контекст для показа окна"
        case .presentationContextInvalid: return "недействительное окно для показа"
        default: return "\(code)"
        }
    }

    /// Маскирует ключ для логов: показываем только начало и последние 4 символа.
    /// Метод вне MainActor, чтобы его можно было вызывать из сетевого слоя.
    nonisolated static func masked(_ key: String) -> String {
        guard key.count > 12 else { return "(\(key.count) символов)" }
        return "\(key.prefix(10))…\(key.suffix(4))"
    }
}

// MARK: - Одноразовое ожидание

/// Контейнер, который отдаёт ровно один результат ожидающему коду.
///
/// Нужен потому, что callback может прийти раньше, чем вызывающий код успеет
/// дойти до `await`: результат запоминается и отдаётся позже, а не теряется.
final class OneShot<T>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Error>?
    /// Результат, пришедший раньше, чем началось ожидание.
    private var pendingResult: Result<T, Error>?
    private let lock = NSLock()

    /// Отдаёт значение ожидающему коду. Повторные вызовы игнорируются.
    func resume(returning value: T) {
        resume(with: .success(value))
    }

    /// Отдаёт ошибку ожидающему коду. Повторные вызовы игнорируются.
    func resume(throwing error: Error) {
        resume(with: .failure(error))
    }

    /// Отменяет ожидание, если оно ещё не завершено.
    func cancel() {
        resume(throwing: CancellationError())
    }

    private func resume(with result: Result<T, Error>) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            if pendingResult == nil { pendingResult = result }
            lock.unlock()
        }
    }

    /// Асинхронно ждёт результата.
    func value() async throws -> T {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let ready = pendingResult {
                    pendingResult = nil
                    lock.unlock()
                    continuation.resume(with: ready)
                    return
                }
                self.continuation = continuation
                lock.unlock()
            }
        } onCancel: {
            [weak self] in
            self?.cancel()
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OpenRouterAuth: ASWebAuthenticationPresentationContextProviding {
    /// Окно, поверх которого показывается системный лист авторизации.
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            // `keyWindow` часто пуст: окно подключения открывается как sheet,
            // и на момент запроса ключевым может быть не то окно.
            if let keyWindow = NSApplication.shared.keyWindow, keyWindow.isVisible {
                return keyWindow
            }
            // Берём любое видимое окно приложения — лишь бы оно умело показать лист.
            if let visible = NSApplication.shared.windows.first(where: \.isVisible) {
                return visible
            }
            // Окна может не быть вовсе (например, запуск из фонового режима).
            // Тогда показываем системное окно поверх всего приложения.
            if let existing = NSApplication.shared.windows.first {
                return existing
            }
            let created = ASPresentationAnchor(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            created.title = "Вход в OpenRouter"
            created.center()
            created.makeKeyAndOrderFront(nil)
            return created
        }
    }
}
