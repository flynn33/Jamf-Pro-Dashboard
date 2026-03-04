import Foundation
import Security

/// SecureDataStore declaration.
protocol SecureDataStore {
    /// Handles save.
    func save(data: Data, for key: String) throws
    /// Handles loadData.
    func loadData(for key: String) throws -> Data?
    /// Handles deleteData.
    func deleteData(for key: String) throws
}

/// KeychainSecureStore declaration.
final class KeychainSecureStore: SecureDataStore {
    private let service: String

    /// Initializes the instance.
    init(service: String = "com.jamfdashboard.app") {
        self.service = service
    }

    /// Handles save.
    func save(data: Data, for key: String) throws {
        let query = keychainQuery(for: key)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw JamfFrameworkError.keychainFailure(status: status)
        }
    }

    /// Handles loadData.
    func loadData(for key: String) throws -> Data? {
        var query = keychainQuery(for: key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw JamfFrameworkError.keychainFailure(status: status)
        }
    }

    /// Handles deleteData.
    func deleteData(for key: String) throws {
        let status = SecItemDelete(keychainQuery(for: key) as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw JamfFrameworkError.keychainFailure(status: status)
        }
    }

    /// Handles keychainQuery.
    private func keychainQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}

//endofline
