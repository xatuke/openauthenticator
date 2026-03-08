import Foundation
import Security
import LocalAuthentication

enum Keychain {
    private static let service = "com.openauthenticator.accounts"

    /// Create an access control requiring biometric or device passcode
    private static func makeAccessControl() -> SecAccessControl? {
        SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            nil
        )
    }

    static func save(accounts: [Account], context: LAContext? = nil) throws {
        let data = try JSONEncoder().encode(accounts)

        // Delete existing item first (pass context so ACL-protected items can be deleted)
        var deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "accounts",
        ]
        if let context = context {
            deleteQuery[kSecUseAuthenticationContext as String] = context
        }
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "accounts",
            kSecValueData as String: data,
        ]

        // Use biometric-protected ACL if available, else fall back to basic protection
        if let acl = makeAccessControl() {
            addQuery[kSecAttrAccessControl as String] = acl
        } else {
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(context: LAContext? = nil) throws -> [Account] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "accounts",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        // Pass authenticated LAContext so Keychain doesn't re-prompt
        if let context = context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }

        return try JSONDecoder().decode([Account].self, from: data)
    }

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain save failed (status \(s))"
        case .loadFailed(let s): return "Keychain load failed (status \(s))"
        }
    }
}
