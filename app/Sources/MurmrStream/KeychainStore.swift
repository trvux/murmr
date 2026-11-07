import Foundation
import Security

/// The macOS Keychain, for API keys: generic passwords in the user's login keychain, which belongs to this Mac
/// and is not synced through iCloud (an item syncs only if it is marked synchronizable, and these are not).
/// Not the data-protection keychain: that one needs entitlements a self-signed app does not have, which is also
/// why kSecAttrAccessible would be ignored here (the self-test showed the attribute is not stored).
/// Nothing here touches the network.
enum KeychainStore {
    static let defaultService = "dev.trvux.murmr-stream"

    private static func baseQuery(_ account: String, _ service: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    static func read(_ account: String, service: String = defaultService) -> String? {
        var query = baseQuery(account, service)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Every account stored under the service: the engine is handed all of them as environment variables, so the
    /// app never needs to know which providers exist.
    static func allAccounts(service: String = defaultService) -> [String] {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                      kSecReturnAttributes: true, kSecMatchLimit: kSecMatchLimitAll]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess, let list = items as? [[String: Any]] else { return [] }
        return list.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    @discardableResult
    static func write(_ value: String, account: String, service: String = defaultService) -> Bool {
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery(account, service) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(account, service)
            add[kSecValueData] = data
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    @discardableResult
    static func delete(_ account: String, service: String = defaultService) -> Bool {
        let status = SecItemDelete(baseQuery(account, service) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
