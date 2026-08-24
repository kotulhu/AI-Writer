import Foundation
import Security

enum KeychainStore {
    private static let service = "khtulhu.AI-writer"

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, account: String) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let value, !value.isEmpty {
            let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
            let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
            if status == errSecSuccess {
                SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            } else {
                var addQuery = baseQuery
                addQuery[kSecValueData as String] = Data(value.utf8)
                SecItemAdd(addQuery as CFDictionary, nil)
            }
        } else {
            SecItemDelete(baseQuery as CFDictionary)
        }
    }
}
