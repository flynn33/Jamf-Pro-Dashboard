import Foundation

/// DiagnosticsCenter declaration.
actor DiagnosticsCenter: DiagnosticsReporting {
    /// DiagnosticExportPayload declaration.
    private struct DiagnosticExportPayload: Codable {
        let appName: String
        let exportedAt: Date
        let eventCount: Int
        let events: [DiagnosticEvent]
    }

    private let fileManager = FileManager.default
    private let maxEventCount = 2000
    private let persistentErrorLogFileName = "jamf-dashboard-errors.ndjson"
    private var events: [DiagnosticEvent] = []

    /// Handles report.
    func report(
        source: String,
        category: String,
        severity: DiagnosticSeverity,
        message: String,
        metadata: [String: String]
    ) async {
        let event = DiagnosticEvent(
            source: source,
            category: category,
            severity: severity,
            message: message,
            metadata: metadata
        )

        events.append(event)
        if events.count > maxEventCount {
            events.removeFirst(events.count - maxEventCount)
        }

        if severity == .error {
            persistErrorEvent(event)
        }
    }

    /// Handles currentEvents.
    func currentEvents() async -> [DiagnosticEvent] {
        events.sorted { $0.timestamp > $1.timestamp }
    }

    /// Handles exportToJSONFile.
    func exportToJSONFile() async throws -> URL {
        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let exportDirectoryURL = try diagnosticsExportDirectoryURL()
        let fileURL = exportDirectoryURL.appending(path: exportFileName())

        let payload = DiagnosticExportPayload(
            appName: "Jamf Dashboard",
            exportedAt: Date(),
            eventCount: sortedEvents.count,
            events: sortedEvents
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    /// Handles persistentErrorLogFileURL.
    func persistentErrorLogFileURL() async -> URL? {
        try? resolvedPersistentErrorLogFileURL(createDirectoryIfNeeded: true)
    }

    /// Handles clear.
    func clear() async {
        events.removeAll()
        clearPersistentErrorLog()
    }

    /// Handles diagnosticsExportDirectoryURL.
    private func diagnosticsExportDirectoryURL(createDirectoryIfNeeded: Bool = true) throws -> URL {
        let baseDirectoryURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let exportDirectoryURL = baseDirectoryURL.appending(path: "JamfDashboardDiagnostics", directoryHint: .isDirectory)
        if createDirectoryIfNeeded && fileManager.fileExists(atPath: exportDirectoryURL.path) == false {
            try fileManager.createDirectory(at: exportDirectoryURL, withIntermediateDirectories: true)
        }

        return exportDirectoryURL
    }

    /// Handles resolvedPersistentErrorLogFileURL.
    private func resolvedPersistentErrorLogFileURL(createDirectoryIfNeeded: Bool) throws -> URL {
        let exportDirectoryURL = try diagnosticsExportDirectoryURL(createDirectoryIfNeeded: createDirectoryIfNeeded)
        return exportDirectoryURL.appending(path: persistentErrorLogFileName)
    }

    /// Handles persistErrorEvent.
    private func persistErrorEvent(_ event: DiagnosticEvent) {
        do {
            let fileURL = try resolvedPersistentErrorLogFileURL(createDirectoryIfNeeded: true)
            let data = try encodeErrorEvent(event)
            try append(data: data, to: fileURL)
        } catch {
            // Best-effort persistence for diagnostics. In-memory diagnostics continue regardless of file I/O failures.
        }
    }

    /// Handles clearPersistentErrorLog.
    private func clearPersistentErrorLog() {
        do {
            let fileURL = try resolvedPersistentErrorLogFileURL(createDirectoryIfNeeded: false)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return
            }
            try fileManager.removeItem(at: fileURL)
        } catch {
            // Best-effort cleanup only.
        }
    }

    /// Handles encodeErrorEvent.
    private func encodeErrorEvent(_ event: DiagnosticEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(event)
        data.append(0x0A)
        return data
    }

    /// Handles append.
    private func append(data: Data, to fileURL: URL) throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return
        }

        try data.write(to: fileURL, options: [.atomic])
    }

    /// Handles exportFileName.
    private func exportFileName(referenceDate: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "jamf-dashboard-diagnostics-\(formatter.string(from: referenceDate)).json"
    }
}

//endofline
