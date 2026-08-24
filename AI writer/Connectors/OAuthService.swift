import AppKit
import CryptoKit
import Foundation
import Network

final class OAuthCallbackServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.khtulhu.ai-writer.oauth")
    private var portContinuation: CheckedContinuation<Void, Error>?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var receivedCode: String?
    private(set) var port: UInt16 = 0

    deinit {
        listener?.cancel()
        portContinuation?.resume(throwing: CancellationError())
        codeContinuation?.resume(throwing: CancellationError())
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            portContinuation = continuation
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let newListener: NWListener
            do {
                newListener = try NWListener(using: parameters, on: .any)
            } catch {
                portContinuation = nil
                continuation.resume(throwing: error)
                return
            }
            listener = newListener
            newListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let self else { return }
                    self.port = newListener.port?.rawValue ?? 0
                    self.portContinuation?.resume(returning: ())
                    self.portContinuation = nil
                case .failed(let error):
                    self?.portContinuation?.resume(throwing: error)
                    self?.portContinuation = nil
                case .cancelled:
                    let error = CancellationError()
                    self?.portContinuation?.resume(throwing: error)
                    self?.portContinuation = nil
                    self?.codeContinuation?.resume(throwing: error)
                    self?.codeContinuation = nil
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            newListener.start(queue: queue)
        }
    }

    func nextCode(timeout seconds: UInt64 = 300) async throws -> String {
        let outcome: String?? = try await withThrowingTaskGroup(of: String??.self) { [weak self] group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self?.queue.async {
                        if let code = self?.receivedCode {
                            continuation.resume(returning: code)
                        } else {
                            self?.codeContinuation = continuation
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                self?.stop()
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next().flatMap { $0 }
        }

        switch outcome {
        case .some(.some(let code)):
            return code
        case .some(.none):
            throw OAuthError.timeout
        case .none:
            throw CancellationError()
        }
    }

    func stop() {
        listener?.cancel()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self, error == nil, let data else {
                connection.cancel()
                return
            }
            defer { self.stop() }

            let head = String(decoding: data.prefix(8_192), as: UTF8.self)
            guard let requestLine = head.split(separator: "\r\n", maxSplits: 1).first,
                  let rawTarget = requestLine.split(separator: " ").dropFirst().first.map(String.init),
                  let url = URL(string: "http://localhost" + rawTarget),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            else {
                self.send(connection, html: "<h2>Не удалось получить код авторизации</h2>")
                DispatchQueue.main.async {
                    self.codeContinuation?.resume(throwing: OAuthError.missingCode)
                    self.codeContinuation = nil
                }
                return
            }

            self.receivedCode = code
            self.send(
                connection,
                html: "<h2>Вход выполнен</h2><p>Вернитесь в приложение AI Writer.</p><script>window.close()</script>"
            )
            DispatchQueue.main.async {
                self.codeContinuation?.resume(returning: code)
                self.codeContinuation = nil
            }
        }
    }

    private func send(_ connection: NWConnection, html body: String) {
        let response = """
        HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

enum OAuthError: LocalizedError {
    case timeout
    case missingCode
    case emptyKey

    var errorDescription: String? {
        switch self {
        case .timeout:
            "Время ожидания входа через браузер истекло"
        case .missingCode:
            "Браузер не вернул код авторизации"
        case .emptyKey:
            "Провайдер не вернул API-ключ"
        }
    }
}

enum OAuthService {
    static func connectOpenRouter() async throws -> String {
        let verifier = randomVerifier()
        let challenge = s256Challenge(verifier)

        let server = OAuthCallbackServer()
        try await server.start()

        var components = URLComponents(string: "https://openrouter.ai/auth")!
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: "http://localhost:\(server.port)/callback"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "key_label", value: "AI Writer"),
        ]
        guard let authorizeURL = components.url else {
            server.stop()
            throw URLError(.badURL)
        }

        await MainActor.run {
            NSWorkspace.shared.open(authorizeURL)
        }

        let code: String
        do {
            code = try await server.nextCode()
        } catch {
            server.stop()
            throw error
        }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "code": code,
            "code_verifier": verifier,
            "code_challenge_method": "S256",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try ChatCompletionsClient.ensureOK(response, data: data)

        struct KeyResponse: Decodable {
            let key: String?
        }

        let decoded = try JSONDecoder().decode(KeyResponse.self, from: data)
        guard let key = decoded.key, !key.isEmpty else {
            throw OAuthError.emptyKey
        }
        return key
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64url(Data(bytes))
    }

    private static func s256Challenge(_ verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64url(Data(digest))
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
