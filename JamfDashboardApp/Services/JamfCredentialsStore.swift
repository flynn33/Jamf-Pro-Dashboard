// MARK: - Forsetti Compliance
// JamfCredentialsStore conforms to JamfCredentialsProviding, enabling protocol-keyed
// registration in ForsettiServiceContainer. Modules resolve credentials through
// ForsettiContext.services.resolve(JamfCredentialsProviding.self) rather than
// depending on the concrete class, following Forsetti's protocol-first DI pattern.

import Foundation
import Combine

@MainActor
/// JamfCredentialsStore declaration.
/// Conforms to JamfCredentialsProviding for resolution via ForsettiContext.services.
final class JamfCredentialsStore: ObservableObject, JamfCredentialsProviding {
    @Published private(set) var hasStoredCredentials = false

    private let secureStore: SecureDataStore
    private let credentialsKey = "jamf.credentials"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(secureStore: SecureDataStore) {
        self.secureStore = secureStore
        refreshState()
    }

    convenience init() {
        self.init(secureStore: KeychainSecureStore())
    }

    func refreshState() {
        do {
            hasStoredCredentials = try loadCredentials() != nil
        } catch {
            hasStoredCredentials = false
        }
    }

    func loadCredentials() throws -> JamfCredentials? {
        guard let data = try secureStore.loadData(for: credentialsKey) else {
            return nil
        }

        return try decoder.decode(JamfCredentials.self, from: data)
    }

    func saveCredentials(_ credentials: JamfCredentials) throws {
        let sanitizedCredentials = credentials.storageSanitized
        guard sanitizedCredentials.isComplete else {
            throw JamfFrameworkError.invalidCredentials
        }

        let payload = try encoder.encode(sanitizedCredentials)
        try secureStore.save(data: payload, for: credentialsKey)
        hasStoredCredentials = true
    }

    func clearCredentials() throws {
        try secureStore.deleteData(for: credentialsKey)
        hasStoredCredentials = false
    }
}
