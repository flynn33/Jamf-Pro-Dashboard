import Foundation
import Combine

@MainActor
/// SupportTechnicianViewModel declaration.
final class SupportTechnicianViewModel: ObservableObject {
    @Published var query = ""
    @Published var searchScope: SupportSearchScope = .all

    @Published private(set) var searchResults: [SupportSearchResult] = []
    @Published var selectedResultID: String?
    @Published private(set) var selectedDetail: SupportDeviceDetail?

    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var isPerformingAction = false
    @Published private(set) var isLoadingApplications = false
    @Published private(set) var isPerformingApplicationCommand = false

    @Published private(set) var availableApplications: [SupportManagedApplication] = []
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var actionResult: SupportActionResult?
    @Published private(set) var latestDeviceLogs: String?

    private let apiService: SupportTechnicianAPIService
    private let diagnosticsReporter: any DiagnosticsReporting
    private let moduleSource = "module.support-technician"

    /// Initializes the instance.
    init(
        apiGateway: JamfAPIGateway,
        diagnosticsReporter: any DiagnosticsReporting
    ) {
        self.apiService = SupportTechnicianAPIService(apiGateway: apiGateway)
        self.diagnosticsReporter = diagnosticsReporter
    }

    var selectedResult: SupportSearchResult? {
        guard let selectedResultID else {
            return nil
        }

        return searchResults.first(where: { $0.id == selectedResultID })
    }

    var availableActions: [SupportManagementAction] {
        guard let selectedDetail else {
            return []
        }

        return resolvedActions(for: selectedDetail)
    }

    /// Handles bootstrap.
    func bootstrap() async {
        // No bootstrapping required when ticket logging is disabled.
    }

    /// Handles executeSearch.
    func executeSearch() async {
        isSearching = true
        defer { isSearching = false }

        do {
            let results = try await self.apiService.searchAssets(query: query, scope: searchScope)
            searchResults = results
            errorMessage = nil
            actionResult = nil

            if let selectedResultID,
               results.contains(where: { $0.id == selectedResultID }) == false
            {
                self.selectedResultID = nil
                selectedDetail = nil
                availableApplications = []
            }

            let preview = results.prefix(5).map(\.serialNumber).joined(separator: ",")
            statusMessage = "Found \(results.count) matching assets."
            reportEvent(
                severity: .info,
                category: "search",
                message: "Support technician search completed.",
                metadata: [
                    "result_count": String(results.count),
                    "scope": searchScope.rawValue,
                    "ticket_reference": normalizedTicketReference
                ]
            )
            await logTechnicianActivity(
                category: "search",
                action: "support_search",
                detail: "Executed support search for query '\(query.trimmingCharacters(in: .whitespacesAndNewlines))'.",
                metadata: [
                    "result_count": String(results.count),
                    "scope": searchScope.rawValue,
                    "result_preview": preview
                ]
            )
        } catch {
            let description = describe(error)
            errorMessage = description
            statusMessage = nil
            reportError(
                category: "search",
                message: "Support technician search failed.",
                errorDescription: description,
                metadata: [
                    "scope": searchScope.rawValue,
                    "ticket_reference": normalizedTicketReference
                ]
            )
            await logTechnicianActivity(
                category: "search",
                action: "support_search_failed",
                detail: "Support search failed: \(description)",
                metadata: [
                    "scope": searchScope.rawValue
                ]
            )
        }
    }

    /// Handles loadSelectedDeviceDetail.
    func loadSelectedDeviceDetail() async {
        guard let selectedResult else {
            selectedDetail = nil
            actionResult = nil
            availableApplications = []
            latestDeviceLogs = nil
            return
        }

        if selectedDetail?.id == selectedResult.id {
            return
        }

        isLoadingDetail = true
        defer { isLoadingDetail = false }

        do {
            let detail = try await self.apiService.fetchDeviceDetail(for: selectedResult)
            selectedDetail = detail
            actionResult = nil
            availableApplications = []
            latestDeviceLogs = nil
            errorMessage = nil
            statusMessage = "Loaded \(selectedResult.assetType.title.lowercased()) details for \(selectedResult.serialNumber)."
            reportEvent(
                severity: .info,
                category: "detail",
                message: "Loaded support device detail.",
                metadata: [
                    "asset_type": selectedResult.assetType.rawValue,
                    "inventory_id": selectedResult.inventoryID,
                    "serial_number": selectedResult.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
            await logTechnicianActivity(
                category: "detail",
                action: "load_device_detail",
                detail: "Loaded \(selectedResult.assetType.title.lowercased()) detail for \(selectedResult.serialNumber).",
                metadata: [
                    "asset_type": selectedResult.assetType.rawValue,
                    "inventory_id": selectedResult.inventoryID,
                    "serial_number": selectedResult.serialNumber
                ]
            )
        } catch {
            let description = describe(error)
            errorMessage = "Failed to load device detail. \(description)"
            statusMessage = nil
            reportError(
                category: "detail",
                message: "Failed loading support device detail.",
                errorDescription: description,
                metadata: [
                    "asset_type": selectedResult.assetType.rawValue,
                    "inventory_id": selectedResult.inventoryID,
                    "serial_number": selectedResult.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
            await logTechnicianActivity(
                category: "detail",
                action: "load_device_detail_failed",
                detail: "Failed loading detail for \(selectedResult.serialNumber): \(description)",
                metadata: [
                    "asset_type": selectedResult.assetType.rawValue,
                    "inventory_id": selectedResult.inventoryID,
                    "serial_number": selectedResult.serialNumber
                ]
            )
        }
    }

    /// Handles refreshSelectedDeviceDetail.
    func refreshSelectedDeviceDetail() async {
        selectedDetail = nil
        availableApplications = []
        await loadSelectedDeviceDetail()
    }

    /// Handles loadApplicationsForSelectedDevice.
    func loadApplicationsForSelectedDevice() async {
        guard let selectedDetail else {
            errorMessage = SupportTechnicianError.missingSelection.errorDescription
            return
        }

        isLoadingApplications = true
        defer { isLoadingApplications = false }

        do {
            let applications = try await self.apiService.fetchManagedApplications(for: selectedDetail)
            availableApplications = applications
            errorMessage = nil
            statusMessage = "Loaded \(applications.count) available applications for \(selectedDetail.summary.displayName)."

            reportEvent(
                severity: .info,
                category: "applications",
                message: "Loaded available application catalog.",
                metadata: [
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "application_count": String(applications.count),
                    "ticket_reference": normalizedTicketReference
                ]
            )
            await logTechnicianActivity(
                category: "applications",
                action: "load_application_catalog",
                detail: "Loaded application catalog for \(selectedDetail.summary.serialNumber).",
                metadata: [
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "application_count": String(applications.count)
                ]
            )
        } catch {
            let description = describe(error)
            errorMessage = userFacingApplicationCatalogErrorMessage(for: error, fallbackDescription: description)
            statusMessage = nil

            reportError(
                category: "applications",
                message: "Failed loading application catalog.",
                errorDescription: description,
                metadata: [
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "ticket_reference": normalizedTicketReference
                ]
            )
            await logTechnicianActivity(
                category: "applications",
                action: "load_application_catalog_failed",
                detail: "Failed loading application catalog for \(selectedDetail.summary.serialNumber): \(description)",
                metadata: [
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID
                ]
            )
        }
    }

    /// Handles applicationCommands.
    func applicationCommands(for application: SupportManagedApplication) -> [SupportApplicationCommand] {
        if application.appInstallerID?.isEmpty == false {
            if application.isInstalled {
                return [.update, .reinstall, .remove]
            }

            return [.install]
        }

        if application.bundleIdentifier?.isEmpty == false,
           application.isInstalled
        {
            return [.remove]
        }

        return []
    }

    /// Handles performApplicationCommand.
    func performApplicationCommand(
        _ command: SupportApplicationCommand,
        for application: SupportManagedApplication
    ) async {
        guard let selectedDetail else {
            errorMessage = SupportTechnicianError.missingSelection.errorDescription
            return
        }

        isPerformingApplicationCommand = true
        defer { isPerformingApplicationCommand = false }

        do {
            let result = try await self.apiService.performApplicationCommand(
                command,
                application: application,
                for: selectedDetail
            )
            actionResult = result
            errorMessage = nil
            statusMessage = result.detail

            reportEvent(
                severity: .warning,
                category: "application-command",
                message: "Executed support application command.",
                metadata: [
                    "command": command.rawValue,
                    "application": application.displayName,
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "serial_number": selectedDetail.summary.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
            await logTechnicianActivity(
                category: "application-command",
                action: command.rawValue,
                detail: result.detail,
                metadata: [
                    "application": application.displayName,
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "serial_number": selectedDetail.summary.serialNumber
                ]
            )

            await loadApplicationsForSelectedDevice()
        } catch {
            let description = describe(error)
            let detailMessage = userFacingApplicationCommandErrorMessage(
                for: error,
                command: command,
                applicationName: application.displayName,
                fallbackDescription: description
            )
            errorMessage = detailMessage
            statusMessage = nil

            reportError(
                category: "application-command",
                message: "Support application command failed.",
                errorDescription: description,
                metadata: [
                    "command": command.rawValue,
                    "application": application.displayName,
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "serial_number": selectedDetail.summary.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
            await logTechnicianActivity(
                category: "application-command",
                action: "\(command.rawValue)-failed",
                detail: "\(command.title) failed for \(application.displayName): \(description)",
                metadata: [
                    "application": application.displayName,
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "serial_number": selectedDetail.summary.serialNumber
                ]
            )
        }
    }

    /// Handles performAction.
    func performAction(_ action: SupportManagementAction) async {
        guard let selectedDetail else {
            errorMessage = SupportTechnicianError.missingSelection.errorDescription
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let result = try await self.apiService.perform(action, for: selectedDetail)
            actionResult = result
            errorMessage = nil
            statusMessage = result.detail

            reportEvent(
                severity: .warning,
                category: "management",
                message: "Executed support management action.",
                metadata: [
                    "action": action.rawValue,
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "serial_number": selectedDetail.summary.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
            await logTechnicianActivity(
                category: "management",
                action: action.rawValue,
                detail: result.detail,
                metadata: [
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "serial_number": selectedDetail.summary.serialNumber
                ]
            )

            if action == .refreshInventory || action == .discoverApplications || action == .updateOperatingSystem {
                await refreshSelectedDeviceDetail()
            }
        } catch {
            let description = describe(error)
            errorMessage = "\(action.title) failed. \(description)"
            statusMessage = nil

            reportError(
                category: "management",
                message: "Support management action failed.",
                errorDescription: description,
                metadata: [
                    "action": action.rawValue,
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "serial_number": selectedDetail.summary.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
            await logTechnicianActivity(
                category: "management",
                action: "\(action.rawValue)-failed",
                detail: "\(action.title) failed: \(description)",
                metadata: [
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "serial_number": selectedDetail.summary.serialNumber
                ]
            )
        }
    }

    /// Handles discoverApplicationsFromApplicationManager.
    func discoverApplicationsFromApplicationManager() async {
        await executeCustomDeviceAction(
            category: "applications",
            action: "discover_applications"
        ) { detail in
            try await self.apiService.discoverApplications(for: detail)
        }

        if errorMessage == nil {
            await refreshSelectedDeviceDetail()
            await loadApplicationsForSelectedDevice()
        }
    }

    /// Handles renewMDMProfileForSelectedDevice.
    func renewMDMProfileForSelectedDevice() async {
        await executeCustomDeviceAction(
            category: "certificate-manager",
            action: "renew_mdm_profile"
        ) { detail in
            try await self.apiService.renewMDMProfile(for: detail)
        }
    }

    /// Handles addCertificate.
    func addCertificate(certificateName: String, profileIdentifier: String?) async {
        await executeCustomDeviceAction(
            category: "certificate-manager",
            action: "add_certificate"
        ) { detail in
            try await self.apiService.addCertificate(
                certificateName: certificateName,
                profileIdentifier: profileIdentifier,
                for: detail
            )
        }

        if errorMessage == nil {
            await refreshSelectedDeviceDetail()
        }
    }

    /// Handles removeCertificate.
    func removeCertificate(_ certificate: SupportCertificate) async {
        await executeCustomDeviceAction(
            category: "certificate-manager",
            action: "remove_certificate"
        ) { detail in
            try await self.apiService.removeCertificate(certificate, for: detail)
        }

        if errorMessage == nil {
            await refreshSelectedDeviceDetail()
        }
    }

    /// Handles addConfigurationProfile.
    func addConfigurationProfile(profileName: String, profileIdentifier: String?) async {
        await executeCustomDeviceAction(
            category: "configuration-profile-manager",
            action: "add_configuration_profile"
        ) { detail in
            try await self.apiService.addConfigurationProfile(
                profileName: profileName,
                profileIdentifier: profileIdentifier,
                for: detail
            )
        }

        if errorMessage == nil {
            await refreshSelectedDeviceDetail()
        }
    }

    /// Handles removeConfigurationProfile.
    func removeConfigurationProfile(_ profile: SupportConfigurationProfile) async {
        await executeCustomDeviceAction(
            category: "configuration-profile-manager",
            action: "remove_configuration_profile"
        ) { detail in
            try await self.apiService.removeConfigurationProfile(profile, for: detail)
        }

        if errorMessage == nil {
            await refreshSelectedDeviceDetail()
        }
    }

    /// Handles addGroupMembership.
    func addGroupMembership(groupName: String, groupType: String?) async {
        await executeCustomDeviceAction(
            category: "group-membership-manager",
            action: "add_group_membership"
        ) { detail in
            try await self.apiService.addGroupMembership(
                groupName: groupName,
                groupType: groupType,
                for: detail
            )
        }

        if errorMessage == nil {
            await refreshSelectedDeviceDetail()
        }
    }

    /// Handles removeGroupMembership.
    func removeGroupMembership(_ group: SupportGroupMembership) async {
        await executeCustomDeviceAction(
            category: "group-membership-manager",
            action: "remove_group_membership"
        ) { detail in
            try await self.apiService.removeGroupMembership(group, for: detail)
        }

        if errorMessage == nil {
            await refreshSelectedDeviceDetail()
        }
    }

    /// Handles addLocalUserAccount.
    func addLocalUserAccount(username: String, fullName: String, password: String) async {
        await executeCustomDeviceAction(
            category: "local-user-control",
            action: "add_local_user"
        ) { detail in
            try await self.apiService.addLocalUserAccount(
                username: username,
                fullName: fullName,
                password: password,
                for: detail
            )
        }
    }

    /// Handles editLocalUserAccount.
    func editLocalUserAccount(
        username: String,
        fullName: String,
        accountGUID: String?,
        newPassword: String
    ) async {
        await executeCustomDeviceAction(
            category: "local-user-control",
            action: "edit_local_user"
        ) { detail in
            try await self.apiService.editLocalUserAccount(
                username: username,
                fullName: fullName,
                accountGUID: accountGUID,
                newPassword: newPassword,
                for: detail
            )
        }

        if errorMessage == nil {
            await refreshSelectedDeviceDetail()
        }
    }

    /// Handles deleteLocalUserAccount.
    func deleteLocalUserAccount(username: String) async {
        await executeCustomDeviceAction(
            category: "local-user-control",
            action: "delete_local_user"
        ) { detail in
            try await self.apiService.deleteLocalUserAccount(username: username, for: detail)
        }
    }

    /// Handles resetLocalUserPassword.
    func resetLocalUserPassword(accountGUID: String, newPassword: String) async {
        await executeCustomDeviceAction(
            category: "local-user-control",
            action: "reset_local_user_password"
        ) { detail in
            try await self.apiService.resetLocalUserPassword(
                accountGUID: accountGUID,
                newPassword: newPassword,
                for: detail
            )
        }
    }

    /// Handles unlockLocalUserAccount.
    func unlockLocalUserAccount(username: String) async {
        await executeCustomDeviceAction(
            category: "local-user-control",
            action: "unlock_local_user"
        ) { detail in
            try await self.apiService.unlockLocalUserAccount(username: username, for: detail)
        }
    }

    /// Handles setMobileDevicePIN.
    func setMobileDevicePIN(pin: String, message: String?, phoneNumber: String?) async {
        await executeCustomDeviceAction(
            category: "mobile-pin-control",
            action: "set_mobile_pin"
        ) { detail in
            try await self.apiService.setMobileDevicePIN(
                pin: pin,
                message: message,
                phoneNumber: phoneNumber,
                for: detail
            )
        }
    }

    /// Handles clearMobileDevicePIN.
    func clearMobileDevicePIN(unlockToken: String) async {
        await executeCustomDeviceAction(
            category: "mobile-pin-control",
            action: "clear_mobile_pin"
        ) { detail in
            try await self.apiService.clearMobileDevicePIN(unlockToken: unlockToken, for: detail)
        }
    }

    /// Handles clearRestrictionsPIN.
    func clearRestrictionsPIN() async {
        await executeCustomDeviceAction(
            category: "mobile-pin-control",
            action: "clear_restrictions_pin"
        ) { detail in
            try await self.apiService.clearRestrictionsPIN(for: detail)
        }
    }

    /// Handles clearActionResult.
    func clearActionResult() {
        actionResult = nil
    }

    /// Handles requestDeviceErrorLogs.
    func requestDeviceErrorLogs() async {
        latestDeviceLogs = nil
        await executeCustomDeviceAction(
            category: "diagnostics",
            action: "request_device_error_logs"
        ) { detail in
            try await self.apiService.requestDeviceErrorLogs(for: detail)
        }

        latestDeviceLogs = actionResult?.sensitiveValue
    }

    /// Handles executeCustomDeviceAction.
    private func executeCustomDeviceAction(
        category: String,
        action: String,
        operation: @escaping (SupportDeviceDetail) async throws -> SupportActionResult
    ) async {
        guard let selectedDetail else {
            errorMessage = SupportTechnicianError.missingSelection.errorDescription
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let result = try await operation(selectedDetail)
            actionResult = result
            errorMessage = nil
            statusMessage = result.detail

            reportEvent(
                severity: .warning,
                category: category,
                message: "Executed support custom action.",
                metadata: [
                    "action": action,
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "serial_number": selectedDetail.summary.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
            await logTechnicianActivity(
                category: category,
                action: action,
                detail: result.detail,
                metadata: [
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "serial_number": selectedDetail.summary.serialNumber
                ]
            )
        } catch {
            let description = describe(error)
            errorMessage = description
            statusMessage = nil

            reportError(
                category: category,
                message: "Support custom action failed.",
                errorDescription: description,
                metadata: [
                    "action": action,
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "inventory_id": selectedDetail.summary.inventoryID,
                    "serial_number": selectedDetail.summary.serialNumber,
                    "ticket_reference": normalizedTicketReference
                ]
            )
            await logTechnicianActivity(
                category: category,
                action: "\(action)-failed",
                detail: "\(action) failed: \(description)",
                metadata: [
                    "asset_type": selectedDetail.summary.assetType.rawValue,
                    "serial_number": selectedDetail.summary.serialNumber
                ]
            )
        }
    }

    /// Handles resolvedActions.
    private func resolvedActions(for detail: SupportDeviceDetail) -> [SupportManagementAction] {
        var actions: [SupportManagementAction] = [
            .refreshInventory,
            .updateOperatingSystem,
            .restartDevice,
            .removeManagementProfile,
            .eraseDevice
        ]

        switch detail.summary.assetType {
        case .computer:
            actions.append(contentsOf: [
                .viewFileVaultPersonalRecoveryKey,
                .viewRecoveryLockPassword,
                .viewDeviceLockPIN,
                .viewLAPSAccountPassword,
                .rotateLAPSPassword
            ])
        case .mobileDevice:
            break
        }

        if detail.summary.managementID == nil {
            actions.removeAll { action in
                action == .refreshInventory ||
                action == .updateOperatingSystem ||
                action == .restartDevice ||
                (action == .eraseDevice && detail.summary.assetType == .mobileDevice)
            }
        }

        if detail.summary.clientManagementID == nil {
            actions.removeAll { action in
                action == .viewLAPSAccountPassword || action == .rotateLAPSPassword
            }
        }

        return actions
    }

    /// Handles normalizedTicketReference.
    private var normalizedTicketReference: String { "none" }

    /// Handles describe.
    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Handles userFacingApplicationCatalogErrorMessage.
    private func userFacingApplicationCatalogErrorMessage(
        for error: any Error,
        fallbackDescription: String
    ) -> String {
        if isForbidden(error) {
            return "Failed to load applications. API access was denied. Grant Jamf Pro App Installer read privileges to this API role."
        }

        return "Failed to load applications. \(fallbackDescription)"
    }

    /// Handles userFacingApplicationCommandErrorMessage.
    private func userFacingApplicationCommandErrorMessage(
        for error: any Error,
        command: SupportApplicationCommand,
        applicationName: String,
        fallbackDescription: String
    ) -> String {
        if isForbidden(error) {
            return "\(command.title) failed for \(applicationName). API access was denied. Grant Jamf Pro App Installer deployment privileges to this API role."
        }

        return "\(command.title) failed for \(applicationName). \(fallbackDescription)"
    }

    /// Handles isForbidden.
    private func isForbidden(_ error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, _) = error else {
            return false
        }

        return statusCode == 403
    }

    /// Handles reportEvent.
    private func reportEvent(
        severity: DiagnosticSeverity,
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        Task {
            await diagnosticsReporter.report(
                source: moduleSource,
                category: category,
                severity: severity,
                message: message,
                metadata: metadata
            )
        }
    }

    /// Handles reportError.
    private func reportError(
        category: String,
        message: String,
        errorDescription: String,
        metadata: [String: String] = [:]
    ) {
        Task {
            await diagnosticsReporter.reportError(
                source: moduleSource,
                category: category,
                message: message,
                errorDescription: errorDescription,
                metadata: metadata
            )
        }
    }

    /// Handles logTechnicianActivity.
    private func logTechnicianActivity(
        category: String,
        action: String,
        detail: String,
        metadata: [String: String] = [:]
    ) async {
        // Ticket logging is disabled for this module.
        _ = category
        _ = action
        _ = detail
        _ = metadata
    }
}

//endofline
