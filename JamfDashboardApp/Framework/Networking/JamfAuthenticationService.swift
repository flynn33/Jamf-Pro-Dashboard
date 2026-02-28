import Foundation

/// JamfAuthenticationService declaration.
actor JamfAuthenticationService {
    /// CachedToken declaration.
    private struct CachedToken: Sendable {
        let value: String
        let expirationDate: Date

        /// Handles isValid.
        func isValid(at referenceDate: Date = Date()) -> Bool {
            expirationDate > referenceDate.addingTimeInterval(60)
        }
    }

    /// TokenResponse declaration.
    private struct TokenResponse: Decodable {
        let accessToken: String
        let expirationDate: Date
        let expiresInSeconds: Int

        /// CodingKeys declaration.
        enum CodingKeys: String, CodingKey {
            case oauthAccessToken = "access_token"
            case oauthExpiresIn = "expires_in"
            case accountToken = "token"
            case accountExpires = "expires"
        }

        private static let defaultExpirationInterval: TimeInterval = 900
        private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        private static let isoFormatter: ISO8601DateFormatter = {
            ISO8601DateFormatter()
        }()

        /// Initializes the instance.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let oauthAccessToken = try container.decodeIfPresent(String.self, forKey: .oauthAccessToken) {
                let expiresIn = try container.decode(TimeInterval.self, forKey: .oauthExpiresIn)
                accessToken = oauthAccessToken
                expirationDate = Date().addingTimeInterval(expiresIn)
                expiresInSeconds = Int(expiresIn)
                return
            }

            if let accountToken = try container.decodeIfPresent(String.self, forKey: .accountToken) {
                accessToken = accountToken

                if let expires = try? container.decode(String.self, forKey: .accountExpires),
                   let parsedDate = Self.parseExpirationDate(rawValue: expires) {
                    expirationDate = parsedDate
                    expiresInSeconds = max(Int(parsedDate.timeIntervalSinceNow), 0)
                    return
                }

                if let unixTimestamp = try? container.decode(TimeInterval.self, forKey: .accountExpires) {
                    let parsedDate = Date(timeIntervalSince1970: unixTimestamp)
                    expirationDate = parsedDate
                    expiresInSeconds = max(Int(parsedDate.timeIntervalSinceNow), 0)
                    return
                }

                expirationDate = Date().addingTimeInterval(Self.defaultExpirationInterval)
                expiresInSeconds = Int(Self.defaultExpirationInterval)
                return
            }

            throw DecodingError.dataCorruptedError(
                forKey: .oauthAccessToken,
                in: container,
                debugDescription: "Token response was missing a supported token field."
            )
        }

        /// Handles parseExpirationDate.
        private static func parseExpirationDate(rawValue: String) -> Date? {
            isoFormatterWithFractionalSeconds.date(from: rawValue) ??
            isoFormatter.date(from: rawValue)
        }
    }

    private let session: URLSession
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private var cachedToken: CachedToken?
    private var cachedCredentialSignature: String?

    /// Initializes the instance.
    init(
        session: URLSession = .shared,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        self.session = session
        self.diagnosticsReporter = diagnosticsReporter
    }

    /// Handles accessToken.
    func accessToken(for credentials: JamfCredentials) async throws -> String {
        let credentialSignature = signature(for: credentials)
        if cachedCredentialSignature != credentialSignature {
            cachedToken = nil
            cachedCredentialSignature = credentialSignature
        }

        if let cachedToken, cachedToken.isValid() {
            return cachedToken.value
        }

        guard let baseURL = credentials.normalizedServerURL else {
            await diagnosticsReporter?.reportError(
                source: "framework.authentication",
                category: "configuration",
                message: "Cannot request access token because server URL is invalid."
            )
            throw JamfFrameworkError.invalidServerURL
        }

        guard credentials.selectedAuthenticationCredentialsAreComplete else {
            await diagnosticsReporter?.reportError(
                source: "framework.authentication",
                category: "configuration",
                message: "Cannot request access token because credentials are incomplete.",
                metadata: [
                    "auth_method": credentials.authenticationMethod.rawValue
                ]
            )
            throw JamfFrameworkError.invalidCredentials
        }

        let tokenURL: URL
        var request: URLRequest
        switch credentials.authenticationMethod {
        case .apiClient:
            tokenURL = baseURL.appending(path: "api/v1/oauth/token")
            request = URLRequest(url: tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            var formComponents = URLComponents()
            formComponents.queryItems = [
                URLQueryItem(name: "grant_type", value: "client_credentials"),
                URLQueryItem(
                    name: "client_id",
                    value: credentials.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                URLQueryItem(
                    name: "client_secret",
                    value: credentials.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            ]
            request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)
        case .usernamePassword:
            tokenURL = baseURL.appending(path: "api/v1/auth/token")
            request = URLRequest(url: tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let authSource = "\(credentials.accountUsername):\(credentials.accountPassword)"
            let authData = Data(authSource.utf8).base64EncodedString()
            request.setValue("Basic \(authData)", forHTTPHeaderField: "Authorization")
        }

        let data = try await performTokenRequest(request: request, endpoint: tokenURL)
        let payload = try await decodeTokenResponse(data: data)

        let token = CachedToken(value: payload.accessToken, expirationDate: payload.expirationDate)

        cachedToken = token
        cachedCredentialSignature = credentialSignature
        await diagnosticsReporter?.report(
            source: "framework.authentication",
            category: "token",
            severity: .info,
            message: "Successfully refreshed Jamf access token.",
            metadata: [
                "auth_method": credentials.authenticationMethod.rawValue,
                "expires_in_seconds": String(payload.expiresInSeconds)
            ]
        )
        return token.value
    }

    /// Handles invalidateToken.
    func invalidateToken() {
        cachedToken = nil
        cachedCredentialSignature = nil
    }

    /// Handles performTokenRequest.
    private func performTokenRequest(request: URLRequest, endpoint: URL) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            await diagnosticsReporter?.reportError(
                source: "framework.authentication",
                category: "network",
                message: "Token request failed while contacting Jamf Pro.",
                errorDescription: describe(error),
                metadata: [
                    "endpoint": endpoint.absoluteString
                ]
            )
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            await diagnosticsReporter?.reportError(
                source: "framework.authentication",
                category: "response",
                message: "Token response from Jamf Pro was not an HTTP response."
            )
            throw JamfFrameworkError.authenticationFailed
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server response"
            await diagnosticsReporter?.reportError(
                source: "framework.authentication",
                category: "response",
                message: "Token request returned an unsuccessful status code.",
                errorDescription: message,
                metadata: [
                    "status_code": String(httpResponse.statusCode),
                    "endpoint": endpoint.absoluteString
                ]
            )
            throw JamfFrameworkError.networkFailure(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }

    /// Handles decodeTokenResponse.
    private func decodeTokenResponse(data: Data) async throws -> TokenResponse {
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            await diagnosticsReporter?.reportError(
                source: "framework.authentication",
                category: "decoding",
                message: "Failed to decode Jamf token response.",
                errorDescription: describe(error)
            )
            throw JamfFrameworkError.decodingFailure
        }
    }

    /// Handles signature.
    private func signature(for credentials: JamfCredentials) -> String {
        switch credentials.authenticationMethod {
        case .apiClient:
            return [
                credentials.authenticationMethod.rawValue,
                credentials.serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                credentials.clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                credentials.clientSecret
            ].joined(separator: "|")
        case .usernamePassword:
            return [
                credentials.authenticationMethod.rawValue,
                credentials.serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                credentials.accountUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                credentials.accountPassword
            ].joined(separator: "|")
        }
    }

    /// Handles describe.
    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

//endofline
