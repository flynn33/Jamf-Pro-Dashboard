import Foundation

/// DiagnosticsReporting declaration.
protocol DiagnosticsReporting: Sendable {
    /// Handles report.
    func report(
        source: String,
        category: String,
        severity: DiagnosticSeverity,
        message: String,
        metadata: [String: String]
    ) async

    /// Handles currentEvents.
    func currentEvents() async -> [DiagnosticEvent]
    /// Handles exportToJSONFile.
    func exportToJSONFile() async throws -> URL
    /// Handles persistentErrorLogFileURL.
    func persistentErrorLogFileURL() async -> URL?
    /// Handles clear.
    func clear() async
}

extension DiagnosticsReporting {
    /// Handles persistentErrorLogFileURL.
    func persistentErrorLogFileURL() async -> URL? {
        nil
    }

    /// Handles report.
    func report(
        source: String,
        category: String,
        severity: DiagnosticSeverity,
        message: String
    ) async {
        await report(
            source: source,
            category: category,
            severity: severity,
            message: message,
            metadata: [:]
        )
    }

    /// Handles reportError.
    func reportError(
        source: String,
        category: String,
        message: String,
        errorDescription: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        var enrichedMetadata = metadata
        if let errorDescription {
            enrichedMetadata["error_description"] = errorDescription
        }

        await report(
            source: source,
            category: category,
            severity: .error,
            message: message,
            metadata: enrichedMetadata
        )
    }
}

//endofline
