import Foundation
import Security

enum KeychainStore {
    private static func query(_ provider: AIProvider) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.hjkim24.clipboard-ai-solver", kSecAttrAccount as String: provider.keyAccount] }
    static func load(provider: AIProvider = .openai) throws -> String {
        var attributes = query(provider)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw SolverFailure(message: "Keychain에서 API 키를 읽지 못했습니다. 설정에서 접근 권한을 확인하세요.") }
        return key
    }
    static func save(_ key: String, provider: AIProvider = .openai) throws {
        let query = query(provider)
        let status: OSStatus
        if key.isEmpty { status = SecItemDelete(query as CFDictionary) }
        else {
            let values = [kSecValueData as String: Data(key.utf8)]
            let updated = SecItemUpdate(query as CFDictionary, values as CFDictionary)
            if updated == errSecItemNotFound {
                var attributes = query.merging(values) { _, new in new }
                attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                status = SecItemAdd(attributes as CFDictionary, nil)
            } else { status = updated }
        }
        guard status == errSecSuccess || (key.isEmpty && status == errSecItemNotFound) else { throw SolverFailure(message: "Keychain에 API 키를 저장하지 못했습니다.") }
    }
}
