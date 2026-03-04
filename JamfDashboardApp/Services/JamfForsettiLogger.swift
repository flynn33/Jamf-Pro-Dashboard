// MARK: - Forsetti Compliance
// Implements ForsettiLogger to bridge Forsetti's structured logging into the Jamf
// DiagnosticsCenter. ForsettiRuntime and ForsettiHostController emit log events through
// this logger, unifying framework-level and application-level diagnostics in one stream.

import Foundation
import ForsettiCore

/// Bridges Forsetti's logging system to the Jamf DiagnosticsCenter.
/// All Forsetti runtime log messages flow through DiagnosticsCenter for unified diagnostics.
struct JamfForsettiLogger: ForsettiLogger {
    private let diagnosticsCenter: DiagnosticsCenter

    init(diagnosticsCenter: DiagnosticsCenter) {
        self.diagnosticsCenter = diagnosticsCenter
    }

    func log(_ level: LogLevel, message: String) {
        let severity = mapSeverity(level)
        Task {
            await diagnosticsCenter.report(
                source: "forsetti.runtime",
                category: "runtime",
                severity: severity,
                message: message
            )
        }
    }

    private func mapSeverity(_ level: LogLevel) -> DiagnosticSeverity {
        switch level {
        case .debug, .info:
            return .info
        case .warning:
            return .warning
        case .error:
            return .error
        }
    }
}
