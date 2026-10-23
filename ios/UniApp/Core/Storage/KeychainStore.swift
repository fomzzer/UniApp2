import Foundation
import Security

struct Credentials: Codable, Hashable, Sendable {
    var facultyNo: String
    var secret: String
    var method: LoginMethod
}

enum KeychainStore {
    private static let service = "com.fomzzer.uniapp.credentials"
    private static let primaryAccount = "primary"
    private static let mailAccount = "mail"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ credentials: Credentials) {
        write(credentials, account: primaryAccount)
    }

    static func load() -> Credentials? {
        read(Credentials.self, account: primaryAccount)
    }

    static func delete() {
        SecItemDelete(baseQuery(primaryAccount) as CFDictionary)
    }

    static func saveMail(_ credentials: MailAccount) {
        write(credentials, account: mailAccount)
    }

    static func loadMail() -> MailAccount? {
        read(MailAccount.self, account: mailAccount)
    }

    static func deleteMail() {
        SecItemDelete(baseQuery(mailAccount) as CFDictionary)
    }

    private static func write<T: Encodable>(_ value: T, account: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        SecItemDelete(baseQuery(account) as CFDictionary)
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func read<T: Decodable>(_ type: T.Type, account: String) -> T? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}
