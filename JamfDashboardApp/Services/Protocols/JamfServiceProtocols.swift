// MARK: - Forsetti Compliance
// These protocols define the domain-specific service contracts for the Jamf Dashboard.
// They are registered as custom types in ForsettiServiceContainer during bootstrap and
// resolved by modules via ForsettiContext.services.resolve(). This follows Forsetti's
// protocol-first dependency injection pattern — modules depend on abstractions, not
// concrete implementations, preserving testability and layer isolation.

import Foundation

/// HTTP method declaration for API requests.
enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Protocol for Jamf API gateway operations.
/// Modules resolve this from ForsettiContext.services to make authenticated Jamf Pro API requests.
protocol JamfAPIGatewayProviding: Sendable {
    func request(
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem],
        body: Data?,
        additionalHeaders: [String: String]
    ) async throws -> Data
}

extension JamfAPIGatewayProviding {
    func request(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        try await request(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body,
            additionalHeaders: additionalHeaders
        )
    }
}

/// Protocol for Jamf credentials management.
/// Modules resolve this from ForsettiContext.services to access credential state.
@MainActor
protocol JamfCredentialsProviding: AnyObject {
    var hasStoredCredentials: Bool { get }
    func loadCredentials() throws -> JamfCredentials?
    func saveCredentials(_ credentials: JamfCredentials) throws
    func clearCredentials() throws
}
