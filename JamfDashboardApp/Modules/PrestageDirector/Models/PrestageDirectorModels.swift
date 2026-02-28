import Foundation

/// PrestageSummary declaration.
struct PrestageSummary: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let versionLock: Int?
}

/// PrestageAssignedDevice declaration.
struct PrestageAssignedDevice: Identifiable, Hashable, Sendable {
    let id: String
    let serialNumber: String
    let deviceName: String
    let udid: String?
    let model: String?

    var selectionKey: String {
        normalizedSerialNumber ?? id
    }

    var normalizedSerialNumber: String? {
        let trimmed = serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        return trimmed.uppercased()
    }
}

/// PrestageDirectorOperationProgress declaration.
struct PrestageDirectorOperationProgress: Sendable {
    let title: String
    let detail: String
    let fractionCompleted: Double
}

//endofline
