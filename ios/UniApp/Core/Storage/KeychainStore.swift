import Foundation
import Security

struct Credentials: Codable, Hashable, Sendable {
    var facultyNo: String
    var secret: String
    var method: LoginMethod
}

enum KeychainStore {
    private static let service = "com.fomzzer.uniapp.credentials"
    private static let account = "primary"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ credentials: Credentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        delete()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> Credentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
