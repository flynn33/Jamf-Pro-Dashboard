import Foundation
import Combine

@MainActor
/// DiagnosticsViewModel declaration.
final class DiagnosticsViewModel: ObservableObject {
    @Published private(set) var entries: [DiagnosticEvent] = []
    @Published private(set) var exportedFileURL: URL?
    @Published private(set) var persistentErrorLogFileURL: URL?
    @Published private(set) var hasPersistentErrorLogEntries = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let diagnosticsReporter: any DiagnosticsReporting

    /// Initializes the instance.
    init(diagnosticsReporter: any DiagnosticsReporting) {
        self.diagnosticsReporter = diagnosticsReporter
    }

    /// Handles refresh.
    func refresh() async {
        entries = await diagnosticsReporter.currentEvents()
        await refreshPersistentErrorLogState()
    }

    /// Handles exportJSON.
    func exportJSON() async {
        do {
            let fileURL = try await diagnosticsReporter.exportToJSONFile()
            entries = await diagnosticsReporter.currentEvents()
            exportedFileURL = fileURL
            statusMessage = "Exported \(entries.count) events to \(fileURL.lastPathComponent)."
            errorMessage = nil
        } catch {
            statusMessage = nil
            errorMessage = "Failed to export diagnostics JSON: \(error.localizedDescription)"
        }
    }

    /// Handles clearLog.
    func clearLog() async {
        let hadPersistentErrors = hasPersistentErrorLogEntries
        await diagnosticsReporter.clear()
        exportedFileURL = nil
        statusMessage = hadPersistentErrors ? "Diagnostic log and persistent error log cleared." : "Diagnostic log cleared."
        errorMessage = nil
        await refresh()
    }

    /// Handles refreshPersistentErrorLogState.
    private func refreshPersistentErrorLogState() async {
        let resolvedURL = await diagnosticsReporter.persistentErrorLogFileURL()
        persistentErrorLogFileURL = resolvedURL
        hasPersistentErrorLogEntries = persistentLogFileHasContents(url: resolvedURL)
    }

    /// Handles persistentLogFileHasContents.
    private func persistentLogFileHasContents(url: URL?) -> Bool {
        guard let url else {
            return false
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return false
        }

        return fileSize.int64Value > 0
    }
}

//endofline
