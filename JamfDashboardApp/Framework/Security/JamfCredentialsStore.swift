import Foundation
import Combine

@MainActor
/// JamfCredentialsStore declaration.
final class JamfCredentialsStore: ObservableObject {
    @Published private(set) var hasStoredCredentials = false

    private let secureStore: SecureDataStore
    private let credentialsKey = "jamf.credentials"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Initializes the instance.
    init(secureStore: SecureDataStore) {
        self.secureStore = secureStore
        refreshState()
    }

    /// Initializes the instance.
    convenience init() {
        self.init(secureStore: KeychainSecureStore())
    }

    /// Handles refreshState.
    func refreshState() {
        do {
            hasStoredCredentials = try loadCredentials() != nil
        } catch {
            hasStoredCredentials = false
        }
    }

    /// Handles loadCredentials.
    func loadCredentials() throws -> JamfCredentials? {
        guard let data = try secureStore.loadData(for: credentialsKey) else {
            return nil
        }

        return try decoder.decode(JamfCredentials.self, from: data)
    }

    /// Handles saveCredentials.
    func saveCredentials(_ credentials: JamfCredentials) throws {
        let sanitizedCredentials = credentials.storageSanitized
        guard sanitizedCredentials.isComplete else {
            throw JamfFrameworkError.invalidCredentials
        }

        let payload = try encoder.encode(sanitizedCredentials)
        try secureStore.save(data: payload, for: credentialsKey)
        hasStoredCredentials = true
    }

    /// Handles clearCredentials.
    func clearCredentials() throws {
        try secureStore.deleteData(for: credentialsKey)
        hasStoredCredentials = false
    }
}

//endofline
