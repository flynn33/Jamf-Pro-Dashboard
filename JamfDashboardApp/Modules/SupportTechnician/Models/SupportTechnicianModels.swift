import Foundation

/// SupportSearchScope declaration.
enum SupportSearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case computers
    case mobileDevices

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .computers:
            return "Computers"
        case .mobileDevices:
            return "Mobile"
        }
    }
}

/// SupportAssetType declaration.
enum SupportAssetType: String, CaseIterable, Identifiable, Sendable {
    case computer
    case mobileDevice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .computer:
            return "Computer"
        case .mobileDevice:
            return "Mobile Device"
        }
    }

    var iconSystemName: String {
        switch self {
        case .computer:
            return "desktopcomputer"
        case .mobileDevice:
            return "iphone.gen3"
        }
    }
}

/// SupportSearchResult declaration.
struct SupportSearchResult: Identifiable, Hashable, Sendable {
    let assetType: SupportAssetType
    let inventoryID: String
    let managementID: String?
    let clientManagementID: String?
    let displayName: String
    let serialNumber: String
    let username: String?
    let email: String?
    let model: String?
    let osVersion: String?
    let lastInventoryUpdate: String?

    var id: String {
        "\(assetType.rawValue)-\(inventoryID)"
    }
}

/// SupportDetailItem declaration.
struct SupportDetailItem: Identifiable, Hashable, Sendable {
    let key: String
    let value: String

    var id: String { "\(key):\(value)" }
}

/// SupportDetailSection declaration.
struct SupportDetailSection: Identifiable, Hashable, Sendable {
    let title: String
    let items: [SupportDetailItem]

    var id: String { title }
}

/// SupportDiagnosticSeverity declaration.
enum SupportDiagnosticSeverity: String, Sendable {
    case info
    case warning
    case critical

    var iconSystemName: String {
        switch self {
        case .info:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "xmark.octagon"
        }
    }
}

/// SupportDiagnosticItem declaration.
struct SupportDiagnosticItem: Identifiable, Hashable, Sendable {
    let title: String
    let value: String
    let severity: SupportDiagnosticSeverity

    var id: String { "\(title):\(value)" }
}

/// SupportLocalUserAccount declaration.
struct SupportLocalUserAccount: Identifiable, Hashable, Sendable {
    let id: String
    let username: String
    let fullName: String?
    let userGuid: String?
    let uid: String?
    let isAdmin: Bool?
}

/// SupportCertificate declaration.
struct SupportCertificate: Identifiable, Hashable, Sendable {
    let id: String
    let commonName: String
    let subjectName: String?
    let serialNumber: String?
    let lifecycleStatus: String?
    let certificateStatus: String?
    let expirationDate: String?
    let issuedDate: String?
    let username: String?
}

/// SupportConfigurationProfile declaration.
struct SupportConfigurationProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let identifier: String?
    let profileStatus: String?
    let source: String?
}

/// SupportGroupMembership declaration.
struct SupportGroupMembership: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let groupType: String?
    let isSmartGroup: Bool?
    let source: String?
}

/// SupportDeviceDetail declaration.
struct SupportDeviceDetail: Identifiable, Hashable, Sendable {
    let summary: SupportSearchResult
    let diagnostics: [SupportDiagnosticItem]
    let sections: [SupportDetailSection]
    let localUserAccounts: [SupportLocalUserAccount]
    let certificates: [SupportCertificate]
    let configurationProfiles: [SupportConfigurationProfile]
    let groupMemberships: [SupportGroupMembership]
    let applications: [String]
    let rawJSON: String

    var id: String {
        summary.id
    }
}

/// SupportManagedApplication declaration.
struct SupportManagedApplication: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let appVersion: String?
    let source: String
    let isInstalled: Bool
    let appInstallerID: String?
}

/// SupportApplicationCommand declaration.
enum SupportApplicationCommand: String, CaseIterable, Identifiable, Sendable {
    case install
    case update
    case reinstall
    case remove

    var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .install:
            return "Install"
        case .update:
            return "Update"
        case .reinstall:
            return "Reinstall"
        case .remove:
            return "Remove"
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .install:
            return "Add/install or deploy the selected app to this device"
        case .update:
            return "Request the latest available app version"
        case .reinstall:
            return "Reinstall the selected app on this device"
        case .remove:
            return "Uninstall/remove the selected app from this device"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .install:
            return "square.and.arrow.down"
        case .update:
            return "arrow.triangle.2.circlepath"
        case .reinstall:
            return "arrow.clockwise"
        case .remove:
            return "trash"
        }
    }

    nonisolated var requiresConfirmation: Bool {
        self == .remove
    }

    nonisolated var confirmationTitle: String {
        switch self {
        case .remove:
            return "Uninstall / Remove Application?"
        default:
            return title
        }
    }

    nonisolated var confirmationMessage: String {
        switch self {
        case .remove:
            return "This removes the selected application from the target device."
        default:
            return subtitle
        }
    }
}

/// SupportManagementAction declaration.
enum SupportManagementAction: String, CaseIterable, Identifiable, Sendable {
    case refreshInventory
    case updateOperatingSystem
    case discoverApplications
    case restartDevice
    case removeManagementProfile
    case eraseDevice
    case viewFileVaultPersonalRecoveryKey
    case viewRecoveryLockPassword
    case viewDeviceLockPIN
    case viewLAPSAccountPassword
    case rotateLAPSPassword

    var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .refreshInventory:
            return "Update Inventory"
        case .updateOperatingSystem:
            return "Update OS"
        case .discoverApplications:
            return "Discover Applications"
        case .restartDevice:
            return "Restart Device"
        case .removeManagementProfile:
            return "Remove Management"
        case .eraseDevice:
            return "Erase Device"
        case .viewFileVaultPersonalRecoveryKey:
            return "View FileVault Key"
        case .viewRecoveryLockPassword:
            return "View Recovery Lock"
        case .viewDeviceLockPIN:
            return "View Device Lock PIN"
        case .viewLAPSAccountPassword:
            return "View LAPS Password"
        case .rotateLAPSPassword:
            return "Rotate LAPS Password"
        }
    }

    var subtitle: String {
        switch self {
        case .refreshInventory:
            return "Queue MDM inventory collection"
        case .updateOperatingSystem:
            return "Send managed OS update plan"
        case .discoverApplications:
            return "Queue installed application discovery"
        case .restartDevice:
            return "Queue remote restart command"
        case .removeManagementProfile:
            return "Unmanage or remove MDM profile"
        case .eraseDevice:
            return "Send erase command"
        case .viewFileVaultPersonalRecoveryKey:
            return "Retrieve personal recovery key"
        case .viewRecoveryLockPassword:
            return "Retrieve recovery lock password"
        case .viewDeviceLockPIN:
            return "Retrieve lock PIN from Jamf"
        case .viewLAPSAccountPassword:
            return "Retrieve local admin account password"
        case .rotateLAPSPassword:
            return "Rotate local admin account password"
        }
    }

    var systemImage: String {
        switch self {
        case .refreshInventory:
            return "arrow.clockwise"
        case .updateOperatingSystem:
            return "square.and.arrow.down.on.square"
        case .discoverApplications:
            return "square.stack.3d.up"
        case .restartDevice:
            return "restart"
        case .removeManagementProfile:
            return "minus.circle"
        case .eraseDevice:
            return "trash"
        case .viewFileVaultPersonalRecoveryKey:
            return "key"
        case .viewRecoveryLockPassword:
            return "lock.shield"
        case .viewDeviceLockPIN:
            return "number"
        case .viewLAPSAccountPassword:
            return "person.badge.key"
        case .rotateLAPSPassword:
            return "arrow.triangle.2.circlepath"
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .eraseDevice, .removeManagementProfile:
            return true
        default:
            return false
        }
    }

    var confirmationTitle: String {
        switch self {
        case .eraseDevice:
            return "Erase Device?"
        case .removeManagementProfile:
            return "Remove Management?"
        default:
            return title
        }
    }

    var confirmationMessage: String {
        switch self {
        case .eraseDevice:
            return "This command is destructive and may not be reversible."
        case .removeManagementProfile:
            return "This will unmanage the selected asset from Jamf Pro."
        default:
            return subtitle
        }
    }
}

/// SupportActionResult declaration.
struct SupportActionResult: Sendable {
    let title: String
    let detail: String
    let sensitiveValue: String?
}

/// SupportTechnicianError declaration.
enum SupportTechnicianError: LocalizedError {
    case invalidSearchQuery
    case invalidCommandInput
    case missingManagementID
    case missingClientManagementID
    case missingUDID
    case missingSelection
    case unsupportedAction
    case unsupportedCapability
    case noLAPSAccounts
    case unsupportedResponseShape
    case unsupportedSecretPayload
    case applicationCatalogUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidSearchQuery:
            return "Enter a username or serial number before searching."
        case .invalidCommandInput:
            return "Enter all required values for this command."
        case .missingManagementID:
            return "Selected device is missing a management identifier required for this action."
        case .missingClientManagementID:
            return "Selected computer is missing the client management identifier required for LAPS."
        case .missingUDID:
            return "Selected device is missing a UDID required for this command."
        case .missingSelection:
            return "Select a device from search results first."
        case .unsupportedAction:
            return "The selected action is not supported for this device type."
        case .unsupportedCapability:
            return "This operation is not exposed by the Jamf Pro Modern API for this device type."
        case .noLAPSAccounts:
            return "No local admin password accounts were returned by Jamf Pro."
        case .unsupportedResponseShape:
            return "Jamf Pro returned an unexpected payload shape."
        case .unsupportedSecretPayload:
            return "Jamf Pro returned an unexpected secret payload."
        case .applicationCatalogUnavailable:
            return "No available application catalog was returned by Jamf Pro for this device."
        }
    }
}

/// TechnicianTicketRecord declaration.
struct TechnicianTicketRecord: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var reference: String
    var createdAt: Date
    var updatedAt: Date
    var notes: String
    var entryCount: Int
    var isActiveSession: Bool
}

/// TechnicianLogEntryRecord declaration.
struct TechnicianLogEntryRecord: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let timestamp: Date
    let category: String
    let action: String
    let detail: String
    let metadata: [String: String]?

    nonisolated init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: String,
        action: String,
        detail: String,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.action = action
        self.detail = detail
        self.metadata = metadata
    }

    var metadataJSON: String? {
        guard let metadata, metadata.isEmpty == false else {
            return nil
        }

        guard JSONSerialization.isValidJSONObject(metadata),
              let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return text
    }
}

/// TechnicianTicketDetailRecord declaration.
struct TechnicianTicketDetailRecord: Hashable, Sendable, Codable {
    var ticket: TechnicianTicketRecord
    var entries: [TechnicianLogEntryRecord]
}

/// TechnicianActivityLoggerError declaration.
enum TechnicianActivityLoggerError: LocalizedError {
    case ticketNotFound

    var errorDescription: String? {
        switch self {
        case .ticketNotFound:
            return "The selected ticket could not be found."
        }
    }
}

/// TechnicianActivityLogger declaration.
actor TechnicianActivityLogger {
    static let shared = TechnicianActivityLogger()

    private struct StoredTicket: Codable, Sendable {
        var ticket: TechnicianTicketRecord
        var entries: [TechnicianLogEntryRecord]
    }

    private let fileManager: FileManager
    private let fileURL: URL
    private var storedTickets: [UUID: StoredTicket] = [:]
    private var hasLoaded = false

    /// Initializes the instance.
    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())

            let directoryURL = appSupportURL.appending(path: "JamfDashboard", directoryHint: .isDirectory)
            self.fileURL = directoryURL.appending(path: "support-technician-tickets.json")
        }
    }

    /// Handles fetchTickets.
    func fetchTickets() throws -> [TechnicianTicketRecord] {
        try loadStateIfNeeded()
        return sortedTickets()
    }

    /// Handles fetchTicketDetail.
    func fetchTicketDetail(ticketID: UUID) throws -> TechnicianTicketDetailRecord {
        try loadStateIfNeeded()

        guard let stored = storedTickets[ticketID] else {
            throw TechnicianActivityLoggerError.ticketNotFound
        }

        return TechnicianTicketDetailRecord(ticket: stored.ticket, entries: stored.entries.sorted(by: { $0.timestamp > $1.timestamp }))
    }

    /// Handles upsertDraftTicket.
    @discardableResult
    func upsertDraftTicket(reference: String) throws -> TechnicianTicketRecord {
        try loadStateIfNeeded()

        let normalizedReference = normalizeReference(reference)
        let now = Date()

        if let existingID = storedTickets.values.first(where: { $0.ticket.reference.caseInsensitiveCompare(normalizedReference) == .orderedSame })?.ticket.id,
           var existing = storedTickets[existingID] {
            existing.ticket.reference = normalizedReference
            existing.ticket.updatedAt = now
            storedTickets[existingID] = existing
            try saveState()
            return existing.ticket
        }

        let ticket = TechnicianTicketRecord(
            id: UUID(),
            reference: normalizedReference,
            createdAt: now,
            updatedAt: now,
            notes: "",
            entryCount: 0,
            isActiveSession: false
        )
        storedTickets[ticket.id] = StoredTicket(ticket: ticket, entries: [])
        try saveState()

        return ticket
    }

    /// Handles initiateLoggedSession.
    @discardableResult
    func initiateLoggedSession(ticketID: UUID, isResume: Bool) throws -> TechnicianTicketRecord {
        try loadStateIfNeeded()

        let now = Date()
        for id in storedTickets.keys {
            guard var stored = storedTickets[id] else {
                continue
            }

            stored.ticket.isActiveSession = id == ticketID
            storedTickets[id] = stored
        }

        guard var target = storedTickets[ticketID] else {
            throw TechnicianActivityLoggerError.ticketNotFound
        }

        let action = isResume ? "resume_logged_session" : "initiate_logged_session"
        let detail = isResume ? "Resumed logged session." : "Initiated logged session."

        target.entries.append(
            TechnicianLogEntryRecord(
                timestamp: now,
                category: "session",
                action: action,
                detail: detail
            )
        )
        target.ticket.isActiveSession = true
        target.ticket.updatedAt = now
        target.ticket.entryCount = target.entries.count
        storedTickets[ticketID] = target
        try saveState()

        return target.ticket
    }

    /// Handles saveForLater.
    @discardableResult
    func saveForLater(ticketID: UUID) throws -> TechnicianTicketRecord {
        try loadStateIfNeeded()

        guard var stored = storedTickets[ticketID] else {
            throw TechnicianActivityLoggerError.ticketNotFound
        }

        let now = Date()
        stored.ticket.isActiveSession = false
        stored.ticket.updatedAt = now
        stored.entries.append(
            TechnicianLogEntryRecord(
                timestamp: now,
                category: "session",
                action: "save_for_later",
                detail: "Saved ticket session for later."
            )
        )
        stored.ticket.entryCount = stored.entries.count
        storedTickets[ticketID] = stored
        try saveState()

        return stored.ticket
    }

    /// Handles stopActiveSession.
    func stopActiveSession() throws -> TechnicianTicketRecord? {
        try loadStateIfNeeded()

        guard let activeTicketID = storedTickets.values.first(where: { $0.ticket.isActiveSession })?.ticket.id,
              var stored = storedTickets[activeTicketID] else {
            return nil
        }

        let now = Date()
        stored.ticket.isActiveSession = false
        stored.ticket.updatedAt = now
        stored.entries.append(
            TechnicianLogEntryRecord(
                timestamp: now,
                category: "session",
                action: "stop_logged_session",
                detail: "Stopped logged session."
            )
        )
        stored.ticket.entryCount = stored.entries.count
        storedTickets[activeTicketID] = stored
        try saveState()

        return stored.ticket
    }

    /// Handles saveTicketNotes.
    @discardableResult
    func saveTicketNotes(ticketID: UUID, notes: String) throws -> TechnicianTicketRecord {
        try loadStateIfNeeded()

        guard var stored = storedTickets[ticketID] else {
            throw TechnicianActivityLoggerError.ticketNotFound
        }

        let now = Date()
        stored.ticket.notes = notes
        stored.ticket.updatedAt = now
        storedTickets[ticketID] = stored
        try saveState()

        return stored.ticket
    }

    /// Handles logManualNote.
    func logManualNote(ticketID: UUID, note: String) throws -> TechnicianLogEntryRecord? {
        try loadStateIfNeeded()

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNote.isEmpty == false else {
            return nil
        }

        guard var stored = storedTickets[ticketID] else {
            throw TechnicianActivityLoggerError.ticketNotFound
        }

        let now = Date()
        let entry = TechnicianLogEntryRecord(
            timestamp: now,
            category: "manual-note",
            action: "add_note",
            detail: trimmedNote
        )

        stored.entries.append(entry)
        stored.ticket.updatedAt = now
        stored.ticket.entryCount = stored.entries.count
        storedTickets[ticketID] = stored
        try saveState()

        return entry
    }

    /// Handles logActivity.
    func logActivity(
        category: String,
        action: String,
        detail: String,
        metadata: [String: String]
    ) throws {
        try loadStateIfNeeded()

        guard let targetTicketID = storedTickets.values.first(where: { $0.ticket.isActiveSession })?.ticket.id
            ?? sortedTickets().first?.id,
            var stored = storedTickets[targetTicketID] else {
            return
        }

        let now = Date()
        stored.entries.append(
            TechnicianLogEntryRecord(
                timestamp: now,
                category: category,
                action: action,
                detail: detail,
                metadata: metadata.isEmpty ? nil : metadata
            )
        )
        stored.ticket.updatedAt = now
        stored.ticket.entryCount = stored.entries.count
        storedTickets[targetTicketID] = stored
        try saveState()
    }

    /// Handles normalizeReference.
    private func normalizeReference(_ reference: String) -> String {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            return trimmed
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "UNFILED-\(formatter.string(from: Date()))"
    }

    /// Handles sortedTickets.
    private func sortedTickets() -> [TechnicianTicketRecord] {
        storedTickets.values
            .map(\.ticket)
            .sorted {
                if $0.updatedAt == $1.updatedAt {
                    return $0.createdAt > $1.createdAt
                }

                return $0.updatedAt > $1.updatedAt
            }
    }

    /// Handles loadStateIfNeeded.
    private func loadStateIfNeeded() throws {
        guard hasLoaded == false else {
            return
        }

        hasLoaded = true
        try ensureDirectoryExists()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            storedTickets = [:]
            return
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loadedTickets = try decoder.decode([StoredTicket].self, from: data)
        storedTickets = Dictionary(uniqueKeysWithValues: loadedTickets.map { ($0.ticket.id, $0) })
    }

    /// Handles saveState.
    private func saveState() throws {
        try ensureDirectoryExists()

        let tickets = storedTickets.values
            .sorted { $0.ticket.updatedAt > $1.ticket.updatedAt }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(tickets)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// Handles ensureDirectoryExists.
    private func ensureDirectoryExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) == false {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}

//endofline
