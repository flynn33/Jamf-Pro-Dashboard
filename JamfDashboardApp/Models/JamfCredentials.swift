import Foundation

/// JamfCredentials declaration.
struct JamfCredentials: Codable, Equatable, Sendable {
    /// AuthenticationMethod declaration.
    enum AuthenticationMethod: String, Codable, CaseIterable, Sendable {
        case apiClient
        case usernamePassword

        var displayName: String {
            switch self {
            case .apiClient:
                return "API Client"
            case .usernamePassword:
                return "Username & Password"
            }
        }
    }

    var serverURL: String
    var authenticationMethod: AuthenticationMethod
    var clientID: String
    var clientSecret: String
    var accountUsername: String
    var accountPassword: String

    /// CodingKeys declaration.
    private enum CodingKeys: String, CodingKey {
        case serverURL
        case authenticationMethod
        case clientID
        case clientSecret
        case accountUsername
        case accountPassword
    }

    /// Initializes the instance.
    nonisolated init(
        serverURL: String,
        authenticationMethod: AuthenticationMethod,
        clientID: String,
        clientSecret: String,
        accountUsername: String,
        accountPassword: String
    ) {
        self.serverURL = serverURL
        self.authenticationMethod = authenticationMethod
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.accountUsername = accountUsername
        self.accountPassword = accountPassword
    }

    /// Initializes the instance.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decode(String.self, forKey: .serverURL)
        clientID = try container.decode(String.self, forKey: .clientID)
        clientSecret = try container.decode(String.self, forKey: .clientSecret)
        accountUsername = try container.decode(String.self, forKey: .accountUsername)
        accountPassword = try container.decode(String.self, forKey: .accountPassword)

        if let decodedMethod = try container.decodeIfPresent(AuthenticationMethod.self, forKey: .authenticationMethod) {
            authenticationMethod = decodedMethod
        } else {
            authenticationMethod = Self.inferAuthenticationMethod(
                clientID: clientID,
                clientSecret: clientSecret,
                accountUsername: accountUsername,
                accountPassword: accountPassword
            )
        }
    }

    nonisolated var normalizedServerURL: URL? {
        var rawValue = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawValue.isEmpty == false else {
            return nil
        }

        if rawValue.hasPrefix("http://") == false && rawValue.hasPrefix("https://") == false {
            rawValue = "https://\(rawValue)"
        }

        return URL(string: rawValue)
    }

    nonisolated var apiClientCredentialsAreComplete: Bool {
        clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    nonisolated var accountCredentialsAreComplete: Bool {
        accountUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        accountPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    nonisolated var selectedAuthenticationCredentialsAreComplete: Bool {
        switch authenticationMethod {
        case .apiClient:
            return apiClientCredentialsAreComplete
        case .usernamePassword:
            return accountCredentialsAreComplete
        }
    }

    nonisolated var isComplete: Bool {
        serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        selectedAuthenticationCredentialsAreComplete
    }

    nonisolated var storageSanitized: JamfCredentials {
        switch authenticationMethod {
        case .apiClient:
            return JamfCredentials(
                serverURL: serverURL,
                authenticationMethod: .apiClient,
                clientID: clientID,
                clientSecret: clientSecret,
                accountUsername: "",
                accountPassword: ""
            )
        case .usernamePassword:
            return JamfCredentials(
                serverURL: serverURL,
                authenticationMethod: .usernamePassword,
                clientID: "",
                clientSecret: "",
                accountUsername: accountUsername,
                accountPassword: accountPassword
            )
        }
    }

    /// Handles inferAuthenticationMethod.
    nonisolated private static func inferAuthenticationMethod(
        clientID: String,
        clientSecret: String,
        accountUsername: String,
        accountPassword: String
    ) -> AuthenticationMethod {
        let isAPIClientComplete = clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let isAccountComplete = accountUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        accountPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        if isAccountComplete && isAPIClientComplete == false {
            return .usernamePassword
        }

        return .apiClient
    }
}

//endofline
