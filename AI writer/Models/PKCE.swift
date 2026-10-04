import Foundation
import CryptoKit

/// Генерация параметров PKCE для OAuth (RFC 7636).
///
/// PKCE (Proof Key for Code Exchange) защищает обмен кода: перехватчик кода из
/// redirect-запроса не сможет обменять его на токен, не зная `code_verifier`.
enum PKCE {
    /// Символы, разрешённые в `code_verifier`: подмножество unreserved из RFC 3986.
    /// Набор фиксирован, чтобы генерируемые значения всегда были валидны.
    static let allowedCharacters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// Случайный `code_verifier` длиной `length` символов (по RFC 7636 — 43…128).
    static func makeCodeVerifier(length: Int = 64) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in
            allowedCharacters[Int.random(in: 0..<allowedCharacters.count, using: &generator)]
        })
    }

    /// `code_challenge` = BASE64URL(SHA256(code_verifier)), без символов padding.
    static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Кодирование Base64URL: `+` → `-`, `/` → `_`, padding `=` отбрасывается.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
