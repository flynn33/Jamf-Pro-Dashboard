// MARK: - Forsetti Compliance
// JamfAPIGateway conforms to the JamfAPIGatewayProviding protocol, enabling
// registration in ForsettiServiceContainer and protocol-based resolution by modules
// via ForsettiContext.services.resolve(JamfAPIGatewayProviding.self).
// The actor isolation model aligns with Forsetti's Sendable service requirements.

import Foundation

/// JamfAPIGateway declaration.
/// Conforms to JamfAPIGatewayProviding for resolution via ForsettiContext.services.
actor JamfAPIGateway: JamfAPIGatewayProviding {
    private let credentialsStore: JamfCredentialsStore
    private let authenticationService: JamfAuthenticationService
    private let diagnosticsReporter: any DiagnosticsReporting
    private let session: URLSession

    init(
        credentialsStore: JamfCredentialsStore,
        authenticationService: JamfAuthenticationService,
        diagnosticsReporter: any DiagnosticsReporting,
        session: URLSession = .shared
    ) {
        self.credentialsStore = credentialsStore
        self.authenticationService = authenticationService
        self.diagnosticsReporter = diagnosticsReporter
        self.session = session
    }

    func request(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        do {
            let credentials = try await currentCredentials()
            guard let baseURL = credentials.normalizedServerURL else {
                throw JamfFrameworkError.invalidServerURL
            }

            let token = try await authenticationService.accessToken(for: credentials)
            var request = try buildRequest(
                baseURL: baseURL,
                path: path,
                method: method,
                queryItems: queryItems,
                body: body,
                token: token,
                additionalHeaders: additionalHeaders
            )

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JamfFrameworkError.authenticationFailed
            }

            if httpResponse.statusCode == 401 {
                await diagnosticsReporter.report(
                    source: "framework.api-gateway",
                    category: "authentication",
                    severity: .warning,
                    message: "Received 401 from Jamf API. Refreshing token.",
                    metadata: [
                        "method": method.rawValue,
                        "path": path
                    ]
                )

                await authenticationService.invalidateToken()

                let refreshedToken = try await authenticationService.accessToken(for: credentials)
                request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")

                let (retryData, retryResponse) = try await session.data(for: request)
                guard let retryHTTPResponse = retryResponse as? HTTPURLResponse else {
                    throw JamfFrameworkError.authenticationFailed
                }

                return try unwrapResponse(data: retryData, statusCode: retryHTTPResponse.statusCode)
            }

            return try unwrapResponse(data: data, statusCode: httpResponse.statusCode)
        } catch {
            await diagnosticsReporter.reportError(
                source: "framework.api-gateway",
                category: "request",
                message: "Jamf API request failed.",
                errorDescription: describe(error),
                metadata: [
                    "method": method.rawValue,
                    "path": path
                ]
            )
            throw error
        }
    }

    private func currentCredentials() async throws -> JamfCredentials {
        guard let credentials = try await MainActor.run(body: {
            try credentialsStore.loadCredentials()
        }) else {
            throw JamfFrameworkError.missingCredentials
        }

        return credentials
    }

    private func buildRequest(
        baseURL: URL,
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem],
        body: Data?,
        token: String,
        additionalHeaders: [String: String]
    ) throws -> URLRequest {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appending(path: normalizedPath)

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if queryItems.isEmpty == false {
            components?.queryItems = queryItems
        }

        guard let resolvedURL = components?.url else {
            throw JamfFrameworkError.invalidServerURL
        }

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if body != nil && additionalHeaders["Content-Type"] == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    private func unwrapResponse(data: Data, statusCode: Int) throws -> Data {
        guard (200 ... 299).contains(statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server response"
            throw JamfFrameworkError.networkFailure(statusCode: statusCode, message: message)
        }

        return data
    }

    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
