import Foundation
import Security

/// Обёртка над Keychain Services API. Хранит секреты (API-ключи) вне SwiftData.
/// Единственная сущность, которая работает с Keychain напрямую.
enum KeychainStore {
    private static let service = "AIWriter"

    /// Ключ из keychain становится значением `apiKeyRef` у конфигурации провайдера.
    static func account(for ref: String) -> String {
        "ai-provider-" + ref
    }

    /// Сохраняет (или обновляет) секрет и возвращает ссылку-идентификатор записи.
    @discardableResult
    static func save(secret: String, ref: String) -> Bool {
        let account = account(for: ref)
        let data = Data(secret.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateQuery = baseQuery.merging([
            kSecValueData as String: data,
        ], uniquingKeysWith: { a, _ in a })
        let status = SecItemUpdate(baseQuery as CFDictionary, updateQuery as CFDictionary)
        if status == errSecItemNotFound {
            let addQuery = baseQuery.merging([
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ], uniquingKeysWith: { a, _ in a })
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func read(ref: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: ref),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(ref: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: ref),
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}