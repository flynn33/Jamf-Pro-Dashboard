import Foundation

/// SupportTechnicianAPIService declaration.
actor SupportTechnicianAPIService {
    /// ComputerInventoryEndpointVersion declaration.
    private enum ComputerInventoryEndpointVersion: String, CaseIterable {
        case v3 = "v3"
        case v2 = "v2"
        case v1 = "v1"

        var searchPath: String {
            "api/\(rawValue)/computers-inventory"
        }

        var detailPathPrefix: String {
            "api/\(rawValue)/computers-inventory-detail"
        }

        var inventoryPathPrefix: String {
            "api/\(rawValue)/computers-inventory"
        }
    }

    /// SectionEncodingMode declaration.
    private enum SectionEncodingMode: CaseIterable {
        case modern
        case legacy
        case none
    }

    /// ApplicationCatalogPaginationMode declaration.
    private enum ApplicationCatalogPaginationMode: CaseIterable {
        case jamfPageSize
        case camelCasePageSize
        case none
    }

    private let apiGateway: JamfAPIGateway
    private let iso8601Formatter = ISO8601DateFormatter()
    private let iso8601FractionalFormatter = ISO8601DateFormatter()
    private let applicationCatalogPageSize = 200
    private let applicationCatalogPageLimit = 50

    /// Initializes the instance.
    init(apiGateway: JamfAPIGateway) {
        self.apiGateway = apiGateway

        iso8601Formatter.formatOptions = [.withInternetDateTime]
        iso8601FractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    /// Handles searchAssets.
    func searchAssets(
        query: String,
        scope: SupportSearchScope
    ) async throws -> [SupportSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            throw SupportTechnicianError.invalidSearchQuery
        }

        let results: [SupportSearchResult]
        switch scope {
        case .all:
            async let computerSearch: Result<[SupportSearchResult], Error> = {
                do {
                    return .success(try await searchComputers(query: trimmedQuery))
                } catch {
                    return .failure(error)
                }
            }()
            async let mobileSearch: Result<[SupportSearchResult], Error> = {
                do {
                    return .success(try await searchMobileDevices(query: trimmedQuery))
                } catch {
                    return .failure(error)
                }
            }()

            let computerResult = await computerSearch
            let mobileResult = await mobileSearch

            var merged: [SupportSearchResult] = []
            var lastError: (any Error)?

            switch computerResult {
            case let .success(computers):
                merged.append(contentsOf: computers)
            case let .failure(error):
                lastError = error
            }

            switch mobileResult {
            case let .success(mobileDevices):
                merged.append(contentsOf: mobileDevices)
            case let .failure(error):
                lastError = error
            }

            if merged.isEmpty, let lastError {
                throw lastError
            }

            results = merged
        case .computers:
            results = try await searchComputers(query: trimmedQuery)
        case .mobileDevices:
            results = try await searchMobileDevices(query: trimmedQuery)
        }

        return dedupe(results).sorted(by: sortByAssetAndName)
    }

    /// Handles fetchDeviceDetail.
    func fetchDeviceDetail(for result: SupportSearchResult) async throws -> SupportDeviceDetail {
        let payload = try await fetchRawDetailPayload(for: result)
        let rawJSON = prettyJSONString(from: payload)
        let sections = buildSections(from: payload)
        let localUserAccounts = extractLocalUserAccounts(from: payload)
        let certificates = extractCertificates(from: payload)
        let configurationProfiles = extractConfigurationProfiles(from: payload)
        let groupMemberships = extractGroupMemberships(from: payload)
        let applications = extractApplicationNames(from: payload)
        let flattenedValues = flattenForDiagnostics(from: payload)
        let diagnostics = buildDiagnostics(for: result, flattenedValues: flattenedValues, applications: applications)

        return SupportDeviceDetail(
            summary: result,
            diagnostics: diagnostics,
            sections: sections,
            localUserAccounts: localUserAccounts,
            certificates: certificates,
            configurationProfiles: configurationProfiles,
            groupMemberships: groupMemberships,
            applications: applications,
            rawJSON: rawJSON
        )
    }


    /// Handles fetchManagedApplications.
    func fetchManagedApplications(for detail: SupportDeviceDetail) async throws -> [SupportManagedApplication] {
        var applications: [SupportManagedApplication] = []
        let installedApplications = normalizedApplicationNames(detail.applications)
        let installedApplicationNames = Set(installedApplications.map { $0.lowercased() })

        if let catalog = try? await fetchServerApplicationCatalog(),
           catalog.isEmpty == false
        {
            applications = buildManagedApplications(
                from: catalog,
                installedApplications: installedApplications,
                installedApplicationNames: installedApplicationNames
            )
        }

        if applications.isEmpty {
            applications = installedApplications.map { applicationName in
                SupportManagedApplication(
                    id: "inventory-\(applicationName.lowercased())",
                    displayName: applicationName,
                    bundleIdentifier: nil,
                    appVersion: nil,
                    source: "Device Inventory",
                    isInstalled: true,
                    appInstallerID: nil
                )
            }
        }

        guard applications.isEmpty == false else {
            throw SupportTechnicianError.applicationCatalogUnavailable
        }

        return applications.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Handles performApplicationCommand.
    func performApplicationCommand(
        _ command: SupportApplicationCommand,
        application: SupportManagedApplication,
        for detail: SupportDeviceDetail
    ) async throws -> SupportActionResult {
        let managementID = try resolveManagementID(from: detail)

        switch command {
        case .install, .update, .reinstall:
            guard let appInstallerID = application.appInstallerID,
                  appInstallerID.isEmpty == false
            else {
                throw SupportTechnicianError.unsupportedAction
            }

            _ = try await deployApplication(
                appInstallerID: appInstallerID,
                managementID: managementID,
                command: command
            )

            return SupportActionResult(
                title: "\(command.title) \(application.displayName)",
                detail: "\(command.title) command submitted for \(application.displayName).",
                sensitiveValue: nil
            )

        case .remove:
            _ = try await removeApplication(
                application,
                from: detail,
                managementID: managementID
            )

            return SupportActionResult(
                title: "Remove \(application.displayName)",
                detail: "Remove command submitted for \(application.displayName).",
                sensitiveValue: nil
            )
        }
    }

    /// Handles discoverApplications.
    func discoverApplications(for detail: SupportDeviceDetail) async throws -> SupportActionResult {
        let managementID = try resolveManagementID(from: detail)
        _ = try await queueMDMCommand(commandType: "INSTALLED_APPLICATION_LIST", managementID: managementID)
        return SupportActionResult(
            title: "Discover Applications",
            detail: "Application discovery command queued in Jamf Pro.",
            sensitiveValue: nil
        )
    }

    /// Handles sendOperatingSystemUpdate.
    func sendOperatingSystemUpdate(for detail: SupportDeviceDetail) async throws -> SupportActionResult {
        _ = try await sendManagedSoftwareUpdatePlan(for: detail)
        return SupportActionResult(
            title: "Update OS",
            detail: "Managed OS update plan submitted for this device.",
            sensitiveValue: nil
        )
    }

    /// Handles renewMDMProfile.
    func renewMDMProfile(for detail: SupportDeviceDetail) async throws -> SupportActionResult {
        let udid = try resolveUDID(from: detail)
        let body = try JSONSerialization.data(withJSONObject: ["udids": [udid]], options: [])
        _ = try await apiGateway.request(
            path: "api/v1/mdm/renew-profile",
            method: .post,
            body: body
        )

        return SupportActionResult(
            title: "Renew MDM Profile",
            detail: "Queued MDM profile renewal (including identity certificate renewal).",
            sensitiveValue: nil
        )
    }

    /// Handles addCertificate.
    func addCertificate(
        certificateName: String,
        profileIdentifier: String?,
        for detail: SupportDeviceDetail
    ) async throws -> SupportActionResult {
        _ = detail
        let trimmedName = certificateName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw SupportTechnicianError.invalidCommandInput
        }

        let resolvedProfileIdentifier = profileIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detailMessage: String
        if resolvedProfileIdentifier.isEmpty {
            detailMessage = "Jamf Pro Modern API does not provide a direct add-certificate command for a targeted device. Use certificate-bearing configuration profile deployment, then refresh inventory."
        } else {
            detailMessage = "Jamf Pro Modern API does not expose direct certificate install by profile identifier (\(resolvedProfileIdentifier)) from this workflow. Use profile deployment workflows, then refresh inventory."
        }

        return SupportActionResult(
            title: "Add Certificate",
            detail: detailMessage,
            sensitiveValue: nil
        )
    }

    /// Handles removeCertificate.
    func removeCertificate(_ certificate: SupportCertificate, for detail: SupportDeviceDetail) async throws -> SupportActionResult {
        _ = detail
        let detailMessage = "Jamf Pro Modern API does not provide a direct remove-certificate command for a targeted device. Remove the owning configuration profile or renew/remove management profile as needed."
        return SupportActionResult(
            title: "Remove Certificate",
            detail: "\(detailMessage) Target: \(certificate.commonName).",
            sensitiveValue: nil
        )
    }

    /// Handles addConfigurationProfile.
    func addConfigurationProfile(
        profileName: String,
        profileIdentifier: String?,
        for detail: SupportDeviceDetail
    ) async throws -> SupportActionResult {
        _ = detail
        let trimmedProfileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedProfileName.isEmpty == false else {
            throw SupportTechnicianError.invalidCommandInput
        }

        let trimmedIdentifier = profileIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let identifierDescription = trimmedIdentifier.isEmpty ? "n/a" : trimmedIdentifier

        return SupportActionResult(
            title: "Add Configuration Profile",
            detail: "Jamf Pro Modern API does not provide a direct add-configuration-profile command for a targeted device in this workflow. Use profile deployment/scoping workflows, then refresh inventory. Requested profile: \(trimmedProfileName) (\(identifierDescription)).",
            sensitiveValue: nil
        )
    }

    /// Handles removeConfigurationProfile.
    func removeConfigurationProfile(
        _ profile: SupportConfigurationProfile,
        for detail: SupportDeviceDetail
    ) async throws -> SupportActionResult {
        _ = detail
        return SupportActionResult(
            title: "Remove Configuration Profile",
            detail: "Jamf Pro Modern API does not provide a direct remove-configuration-profile command for a targeted device in this workflow. Remove the profile via profile management scope changes, then refresh inventory. Target: \(profile.name).",
            sensitiveValue: nil
        )
    }

    /// Handles addGroupMembership.
    func addGroupMembership(
        groupName: String,
        groupType: String?,
        for detail: SupportDeviceDetail
    ) async throws -> SupportActionResult {
        _ = detail
        let trimmedGroupName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedGroupName.isEmpty == false else {
            throw SupportTechnicianError.invalidCommandInput
        }

        let trimmedGroupType = groupType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let groupTypeDescription = trimmedGroupType.isEmpty ? "unspecified type" : trimmedGroupType

        return SupportActionResult(
            title: "Add Group Membership",
            detail: "Jamf Pro Modern API does not provide a universal direct add-to-group command for arbitrary group names in this workflow. Use static group membership workflows, then refresh inventory. Target group: \(trimmedGroupName) (\(groupTypeDescription)).",
            sensitiveValue: nil
        )
    }

    /// Handles removeGroupMembership.
    func removeGroupMembership(
        _ group: SupportGroupMembership,
        for detail: SupportDeviceDetail
    ) async throws -> SupportActionResult {
        if isSmartGroup(group) {
            return SupportActionResult(
                title: "Remove Group Membership",
                detail: "The selected group is a Smart Group. Smart Group memberships are criteria-driven and cannot be directly removed from a device in this workflow.",
                sensitiveValue: nil
            )
        }

        try await removeStaticGroupMembership(group, for: detail)

        return SupportActionResult(
            title: "Remove Group Membership",
            detail: "Requested removal from group '\(group.name)' for device \(detail.summary.displayName). Refresh inventory to confirm membership changes.",
            sensitiveValue: nil
        )
    }

    /// Handles addLocalUserAccount.
    func addLocalUserAccount(
        username: String,
        fullName: String,
        password: String,
        for detail: SupportDeviceDetail
    ) async throws -> SupportActionResult {
        _ = detail
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedUsername.isEmpty == false, trimmedPassword.isEmpty == false else {
            throw SupportTechnicianError.invalidCommandInput
        }

        _ = trimmedFullName
        return SupportActionResult(
            title: "Add Account",
            detail: "Jamf Pro Modern API does not expose a direct create-local-user command for a managed device in this module workflow. Use enrollment/policy-based account provisioning, then refresh inventory.",
            sensitiveValue: nil
        )
    }

    /// Handles editLocalUserAccount.
    func editLocalUserAccount(
        username: String,
        fullName: String,
        accountGUID: String?,
        newPassword: String,
        for detail: SupportDeviceDetail
    ) async throws -> SupportActionResult {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccountGUID = accountGUID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard trimmedUsername.isEmpty == false else {
            throw SupportTechnicianError.invalidCommandInput
        }

        guard trimmedFullName.isEmpty == false || trimmedPassword.isEmpty == false else {
            throw SupportTechnicianError.invalidCommandInput
        }

        var detailMessages: [String] = []

        if trimmedFullName.isEmpty == false {
            detailMessages.append(
                "Jamf Pro Modern API does not expose a direct local-user profile rename/edit command in this workflow. Requested full-name update for '\(trimmedUsername)' was recorded for technician follow-up."
            )
        }

        if trimmedPassword.isEmpty == false {
            guard trimmedAccountGUID.isEmpty == false else {
                throw SupportTechnicianError.invalidCommandInput
            }

            let managementID = try resolveManagementID(from: detail)
            _ = try await queueCustomMDMCommand(
                commandData: [
                    "commandType": "SET_AUTO_ADMIN_PASSWORD",
                    "guid": trimmedAccountGUID,
                    "password": trimmedPassword
                ],
                managementID: managementID
            )
            detailMessages.append("Password edit/reset command queued for '\(trimmedUsername)'.")
        }

        return SupportActionResult(
            title: "Edit Account",
            detail: detailMessages.joined(separator: " "),
            sensitiveValue: nil
        )
    }

    /// Handles deleteLocalUserAccount.
    func deleteLocalUserAccount(username: String, for detail: SupportDeviceDetail) async throws -> SupportActionResult {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedUsername.isEmpty == false else {
            throw SupportTechnicianError.invalidCommandInput
        }

        let managementID = try resolveManagementID(from: detail)
        _ = try await queueCustomMDMCommand(
            commandData: [
                "commandType": "DELETE_USER",
                "userName": trimmedUsername,
                "forceDeletion": true
            ],
            managementID: managementID
        )

        return SupportActionResult(
            title: "Delete Account",
            detail: "Delete account command queued for '\(trimmedUsername)'.",
            sensitiveValue: nil
        )
    }

    /// Handles resetLocalUserPassword.
    func resetLocalUserPassword(
        accountGUID: String,
        newPassword: String,
        for detail: SupportDeviceDetail
    ) async throws -> SupportActionResult {
        let trimmedGUID = accountGUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedGUID.isEmpty == false, trimmedPassword.isEmpty == false else {
            throw SupportTechnicianError.invalidCommandInput
        }

        let managementID = try resolveManagementID(from: detail)
        _ = try await queueCustomMDMCommand(
            commandData: [
                "commandType": "SET_AUTO_ADMIN_PASSWORD",
                "guid": trimmedGUID,
                "password": trimmedPassword
            ],
            managementID: managementID
        )

        return SupportActionResult(
            title: "Reset Password",
            detail: "Password reset command queued for local account GUID \(trimmedGUID).",
            sensitiveValue: nil
        )
    }

    /// Handles unlockLocalUserAccount.
    func unlockLocalUserAccount(username: String, for detail: SupportDeviceDetail) async throws -> SupportActionResult {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedUsername.isEmpty == false else {
            throw SupportTechnicianError.invalidCommandInput
        }

        let managementID = try resolveManagementID(from: detail)
        _ = try await queueCustomMDMCommand(
            commandData: [
                "commandType": "UNLOCK_USER_ACCOUNT",
                "userName": trimmedUsername
            ],
            managementID: managementID
        )

        return SupportActionResult(
            title: "Unlock Account",
            detail: "Unlock account command queued for '\(trimmedUsername)'.",
            sensitiveValue: nil
        )
    }

    /// Handles setMobileDevicePIN.
    func setMobileDevicePIN(
        pin: String,
        message: String?,
        phoneNumber: String?,
        for detail: SupportDeviceDetail
    ) async throws -> SupportActionResult {
        guard detail.summary.assetType == .mobileDevice else {
            throw SupportTechnicianError.unsupportedAction
        }

        let trimmedPIN = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPIN.isEmpty == false else {
            throw SupportTechnicianError.invalidCommandInput
        }

        let managementID = try resolveManagementID(from: detail)
        var commandData: [String: Any] = [
            "commandType": "DEVICE_LOCK",
            "pin": trimmedPIN
        ]

        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedMessage.isEmpty == false {
            commandData["message"] = trimmedMessage
        }

        let trimmedPhone = phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedPhone.isEmpty == false {
            commandData["phoneNumber"] = trimmedPhone
        }

        _ = try await queueCustomMDMCommand(commandData: commandData, managementID: managementID)
        return SupportActionResult(
            title: "Set Mobile PIN",
            detail: "Device lock command with PIN queued for this mobile device.",
            sensitiveValue: nil
        )
    }

    /// Handles clearMobileDevicePIN.
    func clearMobileDevicePIN(unlockToken: String, for detail: SupportDeviceDetail) async throws -> SupportActionResult {
        guard detail.summary.assetType == .mobileDevice else {
            throw SupportTechnicianError.unsupportedAction
        }

        let trimmedToken = unlockToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedToken.isEmpty == false else {
            throw SupportTechnicianError.invalidCommandInput
        }

        let managementID = try resolveManagementID(from: detail)
        _ = try await queueCustomMDMCommand(
            commandData: [
                "commandType": "CLEAR_PASSCODE",
                "unlockToken": trimmedToken
            ],
            managementID: managementID
        )

        return SupportActionResult(
            title: "Clear Mobile PIN",
            detail: "Clear passcode command queued for this mobile device.",
            sensitiveValue: nil
        )
    }

    /// Handles clearRestrictionsPIN.
    func clearRestrictionsPIN(for detail: SupportDeviceDetail) async throws -> SupportActionResult {
        guard detail.summary.assetType == .mobileDevice else {
            throw SupportTechnicianError.unsupportedAction
        }

        let managementID = try resolveManagementID(from: detail)
        _ = try await queueCustomMDMCommand(
            commandData: ["commandType": "CLEAR_RESTRICTIONS_PASSWORD"],
            managementID: managementID
        )

        return SupportActionResult(
            title: "Clear Restrictions PIN",
            detail: "Clear restrictions password command queued for this mobile device.",
            sensitiveValue: nil
        )
    }

    /// Handles requestDeviceErrorLogs.
    func requestDeviceErrorLogs(for detail: SupportDeviceDetail) async throws -> SupportActionResult {
        if let resolvedLogs = try await fetchDeviceErrorLogs(for: detail) {
            return SupportActionResult(
                title: "Device Error Logs",
                detail: "Retrieved available device logs from Jamf Pro.",
                sensitiveValue: resolvedLogs
            )
        }

        let managementID = try resolveManagementID(from: detail)
        let commandTypes: [String]
        switch detail.summary.assetType {
        case .computer:
            commandTypes = [
                "DEVICE_LOG",
                "DEVICE_INFORMATION"
            ]
        case .mobileDevice:
            commandTypes = [
                "DEVICE_LOG",
                "DIAGNOSTICS_SUBMISSION",
                "DEVICE_INFORMATION"
            ]
        }

        var queuedCommandType: String?
        var lastError: (any Error)?
        for commandType in commandTypes {
            do {
                _ = try await queueCustomMDMCommand(
                    commandData: ["commandType": commandType],
                    managementID: managementID
                )
                queuedCommandType = commandType
                break
            } catch {
                lastError = error
                if shouldTryNextPath(after: error) || isNetworkFailure(error, statusCode: 422) {
                    continue
                }

                throw error
            }
        }

        guard queuedCommandType != nil else {
            throw lastError ?? SupportTechnicianError.unsupportedAction
        }

        if let resolvedLogs = try await fetchDeviceErrorLogs(for: detail) {
            return SupportActionResult(
                title: "Device Error Logs",
                detail: "Requested and retrieved available device logs from Jamf Pro.",
                sensitiveValue: resolvedLogs
            )
        }

        return SupportActionResult(
            title: "Device Error Logs Request",
            detail: "Device log request was queued. Run Get Logs again after the device checks in.",
            sensitiveValue: nil
        )
    }

    /// Handles perform.
    func perform(_ action: SupportManagementAction, for detail: SupportDeviceDetail) async throws -> SupportActionResult {
        switch action {
        case .refreshInventory:
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "DEVICE_INFORMATION", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Inventory update command queued in Jamf Pro.",
                sensitiveValue: nil
            )

        case .updateOperatingSystem:
            return try await sendOperatingSystemUpdate(for: detail)

        case .discoverApplications:
            return try await discoverApplications(for: detail)

        case .restartDevice:
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "RESTART_DEVICE", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Restart command queued in Jamf Pro.",
                sensitiveValue: nil
            )

        case .removeManagementProfile:
            switch detail.summary.assetType {
            case .computer:
                _ = try await requestWithPathFallback(
                    paths: [
                        "api/v1/computer-inventory/\(detail.summary.inventoryID)/remove-mdm-profile"
                    ],
                    method: .post,
                    bodyCandidates: [nil, Data("{}".utf8)]
                )

                return SupportActionResult(
                    title: action.title,
                    detail: "Remove MDM profile command submitted for the selected computer.",
                    sensitiveValue: nil
                )
            case .mobileDevice:
                _ = try await requestWithPathFallback(
                    paths: [
                        "api/v2/mobile-devices/\(detail.summary.inventoryID)/unmanage"
                    ],
                    method: .post,
                    bodyCandidates: [nil, Data("{}".utf8)]
                )

                return SupportActionResult(
                    title: action.title,
                    detail: "Unmanage command submitted for the selected mobile device.",
                    sensitiveValue: nil
                )
            }

        case .eraseDevice:
            switch detail.summary.assetType {
            case .computer:
                _ = try await requestWithPathFallback(
                    paths: [
                        "api/v1/computer-inventory/\(detail.summary.inventoryID)/erase"
                    ],
                    method: .post,
                    bodyCandidates: [nil, Data("{}".utf8)]
                )

                return SupportActionResult(
                    title: action.title,
                    detail: "Erase command submitted for the selected computer.",
                    sensitiveValue: nil
                )
            case .mobileDevice:
                let managementID = try resolveManagementID(from: detail)
                _ = try await queueMDMCommand(commandType: "ERASE_DEVICE", managementID: managementID)
                return SupportActionResult(
                    title: action.title,
                    detail: "Erase command queued for the selected mobile device.",
                    sensitiveValue: nil
                )
            }

        case .viewFileVaultPersonalRecoveryKey:
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }

            let data = try await requestWithPathFallback(
                paths: ComputerInventoryEndpointVersion.allCases.map {
                    "\($0.inventoryPathPrefix)/\(detail.summary.inventoryID)/filevault"
                },
                method: .get
            )

            let key = try extractSecretValue(
                from: data,
                preferredKeyFragments: [
                    "personalRecoveryKey",
                    "recoveryKey",
                    "individualRecoveryKey"
                ]
            )

            return SupportActionResult(
                title: action.title,
                detail: "Retrieved FileVault personal recovery key.",
                sensitiveValue: key
            )

        case .viewRecoveryLockPassword:
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }

            let data = try await requestWithPathFallback(
                paths: ComputerInventoryEndpointVersion.allCases.map {
                    "\($0.inventoryPathPrefix)/\(detail.summary.inventoryID)/view-recovery-lock-password"
                },
                method: .get
            )

            let password = try extractSecretValue(
                from: data,
                preferredKeyFragments: [
                    "recoveryLockPassword",
                    "password"
                ]
            )

            return SupportActionResult(
                title: action.title,
                detail: "Retrieved recovery lock password.",
                sensitiveValue: password
            )

        case .viewDeviceLockPIN:
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }

            var lastError: (any Error)?
            let paths = ComputerInventoryEndpointVersion.allCases.map {
                "\($0.inventoryPathPrefix)/\(detail.summary.inventoryID)/view-device-lock-pin"
            }

            for path in paths {
                do {
                    let responseData = try await apiGateway.request(
                        path: path,
                        method: .get
                    )

                    let pin = try extractSecretValue(
                        from: responseData,
                        preferredKeyFragments: [
                            "pin",
                            "deviceLockPin"
                        ]
                    )

                    return SupportActionResult(
                        title: action.title,
                        detail: "Retrieved device lock PIN.",
                        sensitiveValue: pin
                    )
                } catch let JamfFrameworkError.networkFailure(statusCode, message) {
                    lastError = JamfFrameworkError.networkFailure(statusCode: statusCode, message: message)

                    if statusCode == 404 {
                        if isNoDeviceLockCommandResponse(Data(message.utf8)) {
                            return SupportActionResult(
                                title: action.title,
                                detail: "Jamf Pro does not have a stored device lock PIN for this computer yet. Send a device lock command first, then retry View Device Lock PIN.",
                                sensitiveValue: nil
                            )
                        }

                        continue
                    }
                } catch {
                    lastError = error
                    if shouldTryNextPath(after: error) {
                        continue
                    }

                    throw error
                }
            }

            throw lastError ?? JamfFrameworkError.authenticationFailed

        case .viewLAPSAccountPassword:
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }

            let clientManagementID = try resolveClientManagementID(from: detail)
            let account = try await resolvePreferredLAPSAccount(for: clientManagementID)
            let password = try await fetchLAPSPassword(
                clientManagementID: clientManagementID,
                accountName: account.username,
                passwordGUID: account.passwordGUID
            )

            return SupportActionResult(
                title: action.title,
                detail: "Retrieved LAPS password for \(account.username).",
                sensitiveValue: password
            )

        case .rotateLAPSPassword:
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }

            let clientManagementID = try resolveClientManagementID(from: detail)
            _ = try await requestWithPathFallback(
                paths: [
                    "api/v2/local-admin-password/\(clientManagementID)/set-password"
                ],
                method: .put,
                bodyCandidates: [nil, Data("{}".utf8)]
            )

            return SupportActionResult(
                title: action.title,
                detail: "Requested LAPS password rotation for this computer.",
                sensitiveValue: nil
            )
        }
    }

    /// Handles fetchDeviceErrorLogs.
    private func fetchDeviceErrorLogs(for detail: SupportDeviceDetail) async throws -> String? {
        let candidatePaths: [String]
        switch detail.summary.assetType {
        case .computer:
            candidatePaths = [
                "api/v3/computers-inventory/\(detail.summary.inventoryID)/logs",
                "api/v2/computers-inventory/\(detail.summary.inventoryID)/logs",
                "api/v1/computer-inventory/\(detail.summary.inventoryID)/logs",
                "api/v1/computer-inventory-detail/\(detail.summary.inventoryID)/logs",
                "api/v3/computers-inventory/\(detail.summary.inventoryID)/error-logs",
                "api/v2/computers-inventory/\(detail.summary.inventoryID)/error-logs",
                "api/v1/computer-inventory/\(detail.summary.inventoryID)/error-logs",
                "api/v3/computers-inventory-detail/\(detail.summary.inventoryID)",
                "api/v2/computers-inventory-detail/\(detail.summary.inventoryID)",
                "api/v1/computers-inventory-detail/\(detail.summary.inventoryID)",
                "api/v3/computers-inventory/\(detail.summary.inventoryID)",
                "api/v2/computers-inventory/\(detail.summary.inventoryID)",
                "api/v1/computers-inventory/\(detail.summary.inventoryID)"
            ]
        case .mobileDevice:
            candidatePaths = [
                "api/v2/mobile-devices/\(detail.summary.inventoryID)/logs",
                "api/v1/mobile-device-inventory/\(detail.summary.inventoryID)/logs",
                "api/v2/mobile-devices/\(detail.summary.inventoryID)/error-logs",
                "api/v1/mobile-device-inventory/\(detail.summary.inventoryID)/error-logs",
                "api/v2/mobile-devices/\(detail.summary.inventoryID)/detail",
                "api/v2/mobile-devices/\(detail.summary.inventoryID)",
                "api/v2/mobile-devices/detail/\(detail.summary.inventoryID)"
            ]
        }

        var lastError: (any Error)?
        for path in candidatePaths {
            do {
                let data = try await apiGateway.request(path: path, method: .get)
                if let extractedLogs = extractDeviceLogOutput(from: data) {
                    return extractedLogs
                }
            } catch {
                lastError = error
                if shouldTryNextPath(after: error) {
                    continue
                }

                if isNetworkFailure(error, statusCode: 500) {
                    continue
                }

                throw error
            }
        }

        if let lastError,
           isNetworkFailure(lastError, statusCode: 403)
        {
            throw lastError
        }

        return nil
    }

    /// Handles extractDeviceLogOutput.
    private func extractDeviceLogOutput(from data: Data) -> String? {
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
            var lines: [String] = []
            collectLogLines(in: jsonObject, currentPath: nil, output: &lines)
            if lines.isEmpty == false {
                return truncateLogOutput(lines.joined(separator: "\n"))
            }
        }

        if let rawText = String(data: data, encoding: .utf8) {
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                return nil
            }

            return truncateLogOutput(trimmed)
        }

        return nil
    }

    /// Handles collectLogLines.
    private func collectLogLines(
        in value: Any,
        currentPath: String?,
        output: inout [String]
    ) {
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                let nextPath = currentPath.map { "\($0).\(key)" } ?? key
                collectLogLines(in: nestedValue, currentPath: nextPath, output: &output)
            }
            return
        }

        if let array = value as? [Any] {
            for (index, element) in array.prefix(80).enumerated() {
                let nextPath = currentPath.map { "\($0)[\(index)]" } ?? "[\(index)]"
                collectLogLines(in: element, currentPath: nextPath, output: &output)
            }
            return
        }

        guard let currentPath,
              let text = extractStringValue(from: value)
        else {
            return
        }

        let normalizedPath = currentPath.lowercased()
        let likelyLogField = normalizedPath.contains("log") ||
            normalizedPath.contains("error") ||
            normalizedPath.contains("crash") ||
            normalizedPath.contains("diagnostic")

        guard likelyLogField else {
            return
        }

        output.append("\(currentPath): \(text)")
    }

    /// Handles truncateLogOutput.
    private func truncateLogOutput(_ value: String, maxLength: Int = 12_000) -> String {
        guard value.count > maxLength else {
            return value
        }

        let endIndex = value.index(value.startIndex, offsetBy: maxLength)
        return "\(value[..<endIndex])\n\n...[truncated]"
    }

    /// Handles searchComputers.
    private func searchComputers(query: String) async throws -> [SupportSearchResult] {
        let escapedQuery = escapeRSQLString(query)
        let wildcardFilters = buildComputerFilters(withEscapedQuery: escapedQuery, useWildcard: true)
        let exactFilters = buildComputerFilters(withEscapedQuery: escapedQuery, useWildcard: false)
        let candidateFilters = wildcardFilters + exactFilters

        var lastError: (any Error)?

        for endpointVersion in ComputerInventoryEndpointVersion.allCases {
            for filter in candidateFilters {
                do {
                    let data = try await requestComputerInventory(
                        endpointVersion: endpointVersion,
                        filter: filter,
                        includeSections: true
                    )
                    let results = try parseComputerSearchResults(from: data)
                    if results.isEmpty == false {
                        return results
                    }
                } catch {
                    lastError = error

                    if isNetworkFailure(error, statusCode: 400) {
                        continue
                    }

                    if shouldTryNextComputerEndpoint(after: error) {
                        break
                    }
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Handles requestComputerInventory.
    private func requestComputerInventory(
        endpointVersion: ComputerInventoryEndpointVersion,
        filter: String,
        includeSections: Bool
    ) async throws -> Data {
        let sections = [
            "GENERAL",
            "HARDWARE",
            "OPERATING_SYSTEM",
            "USER_AND_LOCATION",
            "SECURITY",
            "DISK_ENCRYPTION"
        ]

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "page-size", value: "100"),
            URLQueryItem(name: "sort", value: "general.name:asc"),
            URLQueryItem(name: "filter", value: filter)
        ]

        if includeSections {
            queryItems.append(contentsOf: sections.map { URLQueryItem(name: "section", value: $0) })
        }

        do {
            return try await apiGateway.request(
                path: endpointVersion.searchPath,
                method: .get,
                queryItems: queryItems
            )
        } catch {
            if includeSections,
               isNetworkFailure(error, statusCode: 400)
            {
                return try await requestComputerInventory(
                    endpointVersion: endpointVersion,
                    filter: filter,
                    includeSections: false
                )
            }

            throw error
        }
    }

    /// Handles parseComputerSearchResults.
    private func parseComputerSearchResults(from data: Data) throws -> [SupportSearchResult] {
        let object = try jsonObject(from: data)
        let dictionaries = dictionaryArray(from: object)

        return dictionaries.compactMap { dictionary in
            let inventoryID = extractString(
                using: ["id", "general.id", "computerId"],
                from: dictionary
            )

            let serialNumber = extractString(
                using: ["hardware.serialNumber", "serialNumber", "general.serialNumber"],
                from: dictionary
            )

            guard let inventoryID, let serialNumber else {
                return nil
            }

            let displayName =
                extractString(using: ["general.name", "general.displayName", "computerName", "displayName", "name"], from: dictionary) ??
                serialNumber

            let managementID = extractString(
                using: ["general.managementId", "managementId", "clientManagementId"],
                from: dictionary
            )

            return SupportSearchResult(
                assetType: .computer,
                inventoryID: inventoryID,
                managementID: managementID,
                clientManagementID: managementID,
                displayName: displayName,
                serialNumber: serialNumber,
                username: extractString(using: ["userAndLocation.username", "username"], from: dictionary),
                email: extractString(using: ["userAndLocation.email", "email"], from: dictionary),
                model: extractString(using: ["hardware.model", "model", "hardware.modelIdentifier"], from: dictionary),
                osVersion: extractString(using: ["operatingSystem.version", "osVersion"], from: dictionary),
                lastInventoryUpdate: extractString(
                    using: ["general.reportDate", "general.lastContactTime", "reportDate", "lastContactTime"],
                    from: dictionary
                )
            )
        }
    }

    /// Handles searchMobileDevices.
    private func searchMobileDevices(query: String) async throws -> [SupportSearchResult] {
        let escapedQuery = escapeRSQLString(query)
        let wildcardFilters = buildMobileDeviceFilters(withEscapedQuery: escapedQuery, useWildcard: true)
        let exactFilters = buildMobileDeviceFilters(withEscapedQuery: escapedQuery, useWildcard: false)

        var lastError: (any Error)?

        for filter in (wildcardFilters + exactFilters) {
            do {
                let data = try await requestMobileInventory(filter: filter)
                let results = try parseMobileSearchResults(from: data)
                if results.isEmpty {
                    continue
                }

                return results
            } catch {
                lastError = error

                if isNetworkFailure(error, statusCode: 400)
                {
                    continue
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Handles requestMobileInventory.
    private func requestMobileInventory(filter: String) async throws -> Data {
        var lastError: (any Error)?

        for mode in SectionEncodingMode.allCases {
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "page", value: "0"),
                URLQueryItem(name: "page-size", value: "100"),
                URLQueryItem(name: "sort", value: "displayName:asc"),
                URLQueryItem(name: "filter", value: filter)
            ]

            switch mode {
            case .modern:
                queryItems.append(contentsOf: [
                    URLQueryItem(name: "section", value: "GENERAL"),
                    URLQueryItem(name: "section", value: "USER_AND_LOCATION"),
                    URLQueryItem(name: "section", value: "HARDWARE"),
                    URLQueryItem(name: "section", value: "APPLICATIONS")
                ])
            case .legacy:
                queryItems.append(contentsOf: [
                    URLQueryItem(name: "section", value: "GENERAL"),
                    URLQueryItem(name: "section", value: "LOCATION"),
                    URLQueryItem(name: "section", value: "HARDWARE"),
                    URLQueryItem(name: "section", value: "APPLICATIONS")
                ])
            case .none:
                break
            }

            do {
                return try await apiGateway.request(
                    path: "api/v2/mobile-devices/detail",
                    method: .get,
                    queryItems: queryItems
                )
            } catch {
                lastError = error

                if mode == .none || isSectionParameterError(error) == false {
                    throw error
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Handles parseMobileSearchResults.
    private func parseMobileSearchResults(from data: Data) throws -> [SupportSearchResult] {
        let object = try jsonObject(from: data)
        let dictionaries = dictionaryArray(from: object)

        return dictionaries.compactMap { dictionary in
            let inventoryID = extractString(
                using: ["id", "mobileDeviceId", "deviceId", "general.id"],
                from: dictionary
            )

            let serialNumber = extractString(
                using: ["serialNumber", "hardware.serialNumber", "general.serialNumber"],
                from: dictionary
            )

            guard let inventoryID, let serialNumber else {
                return nil
            }

            let displayName =
                extractString(
                    using: ["general.displayName", "general.name", "deviceName", "displayName", "name"],
                    from: dictionary
                ) ??
                serialNumber

            let managementID = extractString(
                using: ["general.managementId", "managementId", "clientManagementId"],
                from: dictionary
            )

            return SupportSearchResult(
                assetType: .mobileDevice,
                inventoryID: inventoryID,
                managementID: managementID,
                clientManagementID: managementID,
                displayName: displayName,
                serialNumber: serialNumber,
                username: extractString(using: ["userAndLocation.username", "username", "location.username"], from: dictionary),
                email: extractString(using: ["userAndLocation.emailAddress", "emailAddress", "location.email"], from: dictionary),
                model: extractString(using: ["hardware.model", "model", "modelIdentifier"], from: dictionary),
                osVersion: extractString(using: ["general.osVersion", "osVersion"], from: dictionary),
                lastInventoryUpdate: extractString(
                    using: [
                        "general.lastInventoryUpdateDate",
                        "general.lastInventoryUpdate",
                        "lastInventoryUpdateDate",
                        "lastInventoryUpdate"
                    ],
                    from: dictionary
                )
            )
        }
    }

    /// Handles fetchRawDetailPayload.
    private func fetchRawDetailPayload(for result: SupportSearchResult) async throws -> [String: Any] {
        switch result.assetType {
        case .computer:
            let detailPaths = ComputerInventoryEndpointVersion.allCases.flatMap { endpointVersion in
                [
                    "\(endpointVersion.detailPathPrefix)/\(result.inventoryID)",
                    "\(endpointVersion.inventoryPathPrefix)/\(result.inventoryID)"
                ]
            }

            let data = try await requestWithPathFallback(paths: detailPaths, method: .get)
            return try rootDictionary(from: data)

        case .mobileDevice:
            let data = try await requestWithPathFallback(
                paths: [
                    "api/v2/mobile-devices/\(result.inventoryID)/detail",
                    "api/v2/mobile-devices/\(result.inventoryID)",
                    "api/v2/mobile-devices/detail/\(result.inventoryID)"
                ],
                method: .get
            )

            return try rootDictionary(from: data)
        }
    }

    /// Handles requestWithPathFallback.
    private func requestWithPathFallback(
        paths: [String],
        method: HTTPMethod,
        queryItems: [URLQueryItem] = [],
        bodyCandidates: [Data?] = [nil],
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        var lastError: (any Error)?

        for path in paths {
            for body in bodyCandidates {
                do {
                    return try await apiGateway.request(
                        path: path,
                        method: method,
                        queryItems: queryItems,
                        body: body,
                        additionalHeaders: additionalHeaders
                    )
                } catch {
                    lastError = error

                    if shouldTryNextPath(after: error) {
                        continue
                    }

                    throw error
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Handles queueMDMCommand.
    private func queueMDMCommand(commandType: String, managementID: String) async throws -> Data {
        try await queueCustomMDMCommand(
            commandData: [
                "commandType": commandType
            ],
            managementID: managementID
        )
    }

    /// Handles queueCustomMDMCommand.
    private func queueCustomMDMCommand(
        commandData: [String: Any],
        managementID: String
    ) async throws -> Data {
        let endpoints = [
            "api/v2/mdm/commands",
            "api/v1/mdm/commands"
        ]

        let payloadCandidates: [[String: Any]] = [
            [
                "clientData": [
                    [
                        "managementId": managementID
                    ]
                ],
                "commandData": commandData
            ],
            [
                "clientData": [
                    [
                        "clientManagementId": managementID
                    ]
                ],
                "commandData": commandData
            ],
            [
                "managementId": managementID,
                "commandData": commandData
            ]
        ]

        var lastError: (any Error)?

        for endpoint in endpoints {
            for payload in payloadCandidates {
                let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

                do {
                    return try await apiGateway.request(
                        path: endpoint,
                        method: .post,
                        body: payloadData
                    )
                } catch {
                    lastError = error

                    if isNetworkFailure(error, statusCode: 400) {
                        continue
                    }

                    if isNetworkFailure(error, statusCode: 404) || isNetworkFailure(error, statusCode: 405) {
                        break
                    }

                    throw error
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Handles sendManagedSoftwareUpdatePlan.
    private func sendManagedSoftwareUpdatePlan(for detail: SupportDeviceDetail) async throws -> Data {
        let objectType: String
        switch detail.summary.assetType {
        case .computer:
            objectType = "COMPUTER"
        case .mobileDevice:
            objectType = "MOBILE_DEVICE"
        }

        let planPayloadCandidates: [[String: Any]] = [
            [
                "devices": [
                    [
                        "deviceId": detail.summary.inventoryID,
                        "objectType": objectType
                    ]
                ],
                "config": [
                    "updateAction": "DOWNLOAD_INSTALL",
                    "versionType": "LATEST_ANY"
                ]
            ],
            [
                "devices": [
                    [
                        "deviceId": detail.summary.inventoryID,
                        "objectType": objectType
                    ]
                ],
                "config": [
                    "updateAction": "DOWNLOAD_INSTALL_RESTART",
                    "versionType": "LATEST_ANY"
                ]
            ],
            [
                "devices": [
                    [
                        "deviceId": detail.summary.inventoryID,
                        "objectType": objectType
                    ]
                ],
                "config": [
                    "updateAction": "DOWNLOAD_INSTALL_ALLOW_DEFERRAL",
                    "versionType": "LATEST_ANY",
                    "maxDeferrals": 3
                ]
            ]
        ]

        var lastError: (any Error)?

        for payload in planPayloadCandidates {
            do {
                let body = try JSONSerialization.data(withJSONObject: payload, options: [])
                return try await apiGateway.request(
                    path: "api/v1/managed-software-updates/plans",
                    method: .post,
                    body: body
                )
            } catch {
                lastError = error
                if shouldTryNextDeploymentPath(after: error) {
                    continue
                }

                throw error
            }
        }

        if detail.summary.assetType == .computer {
            let fallbackPayload: [String: Any] = [
                "deviceIds": [detail.summary.inventoryID],
                "updateAction": "DOWNLOAD_AND_INSTALL",
                "skipVersionVerification": false,
                "applyMajorUpdate": false,
                "forceRestart": false
            ]

            do {
                let fallbackBody = try JSONSerialization.data(withJSONObject: fallbackPayload, options: [])
                return try await apiGateway.request(
                    path: "api/v1/macos-managed-software-updates/send-updates",
                    method: .post,
                    body: fallbackBody
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// LAPSAccount declaration.
    private struct LAPSAccount {
        let username: String
        let passwordGUID: String?
    }

    /// Handles resolvePreferredLAPSAccount.
    private func resolvePreferredLAPSAccount(for clientManagementID: String) async throws -> LAPSAccount {
        let data = try await requestWithPathFallback(
            paths: [
                "api/v2/local-admin-password/\(clientManagementID)/accounts"
            ],
            method: .get
        )

        let object = try jsonObject(from: data)
        let accountDictionaries = dictionaryArray(from: object)

        for dictionary in accountDictionaries {
            guard let username =
                extractString(using: ["username", "accountName", "name", "localAdminAccount"], from: dictionary)
            else {
                continue
            }

            let passwordGUID = extractString(using: ["passwordGuid", "guid", "accountGuid"], from: dictionary)
            return LAPSAccount(username: username, passwordGUID: passwordGUID)
        }

        throw SupportTechnicianError.noLAPSAccounts
    }

    /// Handles fetchLAPSPassword.
    private func fetchLAPSPassword(
        clientManagementID: String,
        accountName: String,
        passwordGUID: String?
    ) async throws -> String {
        let encodedAccountName = accountName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? accountName
        var paths = [String]()

        if let passwordGUID,
           passwordGUID.isEmpty == false
        {
            let encodedGUID = passwordGUID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? passwordGUID
            paths.append(
                "api/v2/local-admin-password/\(clientManagementID)/account/\(encodedAccountName)/\(encodedGUID)/password"
            )
        }

        paths.append(
            "api/v2/local-admin-password/\(clientManagementID)/account/\(encodedAccountName)/password"
        )

        let data = try await requestWithPathFallback(paths: paths, method: .get)

        return try extractSecretValue(
            from: data,
            preferredKeyFragments: [
                "password",
                "plainTextPassword"
            ]
        )
    }


    /// Handles fetchServerApplicationCatalog.
    private func fetchServerApplicationCatalog() async throws -> [[String: Any]] {
        let paths = [
            "api/v1/app-installers",
            "api/v2/app-installers"
        ]

        var lastError: (any Error)?
        for path in paths {
            do {
                let catalog = try await fetchServerApplicationCatalog(path: path)
                if catalog.isEmpty == false {
                    return catalog
                }
            } catch {
                lastError = error
                if shouldTryNextPath(after: error) {
                    continue
                }

                throw error
            }
        }

        if let lastError {
            throw lastError
        }

        return []
    }

    /// Handles fetchServerApplicationCatalog(path:).
    private func fetchServerApplicationCatalog(path: String) async throws -> [[String: Any]] {
        var lastError: (any Error)?

        for mode in ApplicationCatalogPaginationMode.allCases {
            do {
                return try await fetchServerApplicationCatalog(
                    path: path,
                    paginationMode: mode
                )
            } catch {
                lastError = error
                if mode != .none, isNetworkFailure(error, statusCode: 400) {
                    continue
                }

                throw error
            }
        }

        throw lastError ?? SupportTechnicianError.applicationCatalogUnavailable
    }

    /// Handles fetchServerApplicationCatalog(path:paginationMode:).
    private func fetchServerApplicationCatalog(
        path: String,
        paginationMode: ApplicationCatalogPaginationMode
    ) async throws -> [[String: Any]] {
        var allItems: [[String: Any]] = []

        for page in 0..<applicationCatalogPageLimit {
            let queryItems = applicationCatalogQueryItems(
                for: page,
                paginationMode: paginationMode
            )

            let data = try await apiGateway.request(
                path: path,
                method: .get,
                queryItems: queryItems
            )
            let object = try jsonObject(from: data)
            let chunk = dictionaryArray(from: object)
            allItems.append(contentsOf: chunk)

            let shouldContinue = shouldContinueApplicationCatalogPagination(
                paginationMode: paginationMode,
                object: object,
                page: page,
                chunkCount: chunk.count,
                totalLoaded: allItems.count
            )
            if shouldContinue == false {
                break
            }
        }

        return allItems
    }

    /// Handles applicationCatalogQueryItems.
    private func applicationCatalogQueryItems(
        for page: Int,
        paginationMode: ApplicationCatalogPaginationMode
    ) -> [URLQueryItem] {
        switch paginationMode {
        case .jamfPageSize:
            return [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page-size", value: String(applicationCatalogPageSize))
            ]
        case .camelCasePageSize:
            return [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "pageSize", value: String(applicationCatalogPageSize))
            ]
        case .none:
            return []
        }
    }

    /// Handles shouldContinueApplicationCatalogPagination.
    private func shouldContinueApplicationCatalogPagination(
        paginationMode: ApplicationCatalogPaginationMode,
        object: Any,
        page: Int,
        chunkCount: Int,
        totalLoaded: Int
    ) -> Bool {
        guard paginationMode != .none else {
            return false
        }

        guard chunkCount > 0 else {
            return false
        }

        if let totalCount = extractTotalCount(from: object) {
            return totalLoaded < totalCount && page + 1 < applicationCatalogPageLimit
        }

        return chunkCount >= applicationCatalogPageSize && page + 1 < applicationCatalogPageLimit
    }

    /// Handles extractTotalCount.
    private func extractTotalCount(from object: Any) -> Int? {
        if let dictionary = object as? [String: Any] {
            for key in ["totalCount", "total", "totalResults", "recordCount"] {
                if let count = extractIntegerValue(from: dictionary[key]) {
                    return count
                }
            }

            for key in ["metadata", "paging", "pagination", "page", "resultInfo"] {
                if let nested = dictionary[key],
                   let count = extractTotalCount(from: nested)
                {
                    return count
                }
            }
        }

        if let array = object as? [Any] {
            for element in array {
                if let count = extractTotalCount(from: element) {
                    return count
                }
            }
        }

        return nil
    }

    /// Handles extractIntegerValue.
    private func extractIntegerValue(from value: Any?) -> Int? {
        switch value {
        case let intValue as Int:
            return intValue
        case let numberValue as NSNumber:
            return numberValue.intValue
        case let stringValue as String:
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed)
        default:
            return nil
        }
    }

    /// Handles buildManagedApplications.
    private func buildManagedApplications(
        from dictionaries: [[String: Any]],
        installedApplications: [String],
        installedApplicationNames: Set<String>
    ) -> [SupportManagedApplication] {
        var uniqueIDs = Set<String>()
        var matchedInstalledApplicationNames = Set<String>()
        var applications: [SupportManagedApplication] = []

        for dictionary in dictionaries {
            guard let displayName = extractString(
                using: ["displayName", "name", "title", "bundleId", "bundleIdentifier", "identifier"],
                from: dictionary
            ) else {
                continue
            }

            let bundleIdentifier = extractString(
                using: ["bundleId", "bundleIdentifier", "identifier", "bundle_id"],
                from: dictionary
            )
            let appVersion = extractString(
                using: ["latestVersion", "version", "appVersion", "shortVersionString"],
                from: dictionary
            )
            let appInstallerID = extractString(
                using: ["id", "appInstallerId", "appInstallerID", "app_id"],
                from: dictionary
            )

            let identity = (appInstallerID ?? bundleIdentifier ?? displayName).lowercased()
            guard uniqueIDs.insert(identity).inserted else {
                continue
            }

            let normalizedName = displayName.lowercased()
            let normalizedBundle = bundleIdentifier?.lowercased()
            let isInstalled = installedApplicationNames.contains(normalizedName) ||
                (normalizedBundle.map { installedApplicationNames.contains($0) } ?? false)

            if isInstalled {
                matchedInstalledApplicationNames.insert(normalizedName)
                if let normalizedBundle {
                    matchedInstalledApplicationNames.insert(normalizedBundle)
                }
            }

            applications.append(
                SupportManagedApplication(
                    id: identity,
                    displayName: displayName,
                    bundleIdentifier: bundleIdentifier,
                    appVersion: appVersion,
                    source: "Jamf Catalog",
                    isInstalled: isInstalled,
                    appInstallerID: appInstallerID
                )
            )
        }

        for installedApplication in installedApplications {
            let normalizedName = installedApplication.lowercased()
            guard matchedInstalledApplicationNames.contains(normalizedName) == false else {
                continue
            }

            let identity = "inventory-\(normalizedName)"
            guard uniqueIDs.insert(identity).inserted else {
                continue
            }

            applications.append(
                SupportManagedApplication(
                    id: identity,
                    displayName: installedApplication,
                    bundleIdentifier: nil,
                    appVersion: nil,
                    source: "Device Inventory",
                    isInstalled: true,
                    appInstallerID: nil
                )
            )
        }

        return applications
    }

    /// Handles normalizedApplicationNames.
    private func normalizedApplicationNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in names {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                continue
            }

            let normalized = trimmed.lowercased()
            guard seen.insert(normalized).inserted else {
                continue
            }

            output.append(trimmed)
        }

        return output
    }

    /// Handles deployApplication.
    private func deployApplication(
        appInstallerID: String,
        managementID: String,
        command: SupportApplicationCommand
    ) async throws -> Data {
        let paths = [
            "api/v1/app-installers/deploy",
            "api/v1/app-installers/deployment",
            "api/v1/app-installers/deployments",
            "api/v2/app-installers/deployments"
        ]

        let actionValue = command.rawValue.uppercased()
        let payloadCandidates: [[String: Any]] = [
            [
                "appInstallerId": appInstallerID,
                "managementId": managementID,
                "action": actionValue
            ],
            [
                "appInstallerId": appInstallerID,
                "deviceId": managementID,
                "action": actionValue
            ],
            [
                "appInstallerId": appInstallerID,
                "clientManagementId": managementID,
                "action": actionValue
            ],
            [
                "appInstallerId": appInstallerID,
                "deviceIds": [managementID],
                "action": actionValue
            ],
            [
                "appInstallerId": appInstallerID,
                "managementIds": [managementID],
                "action": actionValue
            ],
            [
                "appInstallerId": appInstallerID,
                "targets": [
                    ["managementId": managementID]
                ],
                "action": actionValue
            ],
            [
                "appInstallerId": appInstallerID,
                "managementId": managementID
            ]
        ]

        var lastError: (any Error)?

        for path in paths {
            for payload in payloadCandidates {
                do {
                    let body = try JSONSerialization.data(withJSONObject: payload, options: [])
                    return try await apiGateway.request(
                        path: path,
                        method: .post,
                        body: body
                    )
                } catch {
                    lastError = error

                    if shouldTryNextDeploymentPath(after: error) {
                        continue
                    }

                    throw error
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Handles removeApplication.
    private func removeApplication(
        _ application: SupportManagedApplication,
        from detail: SupportDeviceDetail,
        managementID: String
    ) async throws -> Data {
        var lastError: (any Error)?

        if let appInstallerID = application.appInstallerID,
           appInstallerID.isEmpty == false
        {
            do {
                return try await deployApplication(
                    appInstallerID: appInstallerID,
                    managementID: managementID,
                    command: .remove
                )
            } catch {
                lastError = error

                if shouldTryNextDeploymentPath(after: error) == false {
                    throw error
                }
            }

            let encodedAppInstallerID = encodedPathComponent(appInstallerID)
            let encodedManagementID = encodedPathComponent(managementID)

            do {
                return try await requestWithPathFallback(
                    paths: [
                        "api/v1/app-installers/\(encodedAppInstallerID)/devices/\(encodedManagementID)",
                        "api/v1/app-installers/\(encodedAppInstallerID)/management/\(encodedManagementID)"
                    ],
                    method: .delete
                )
            } catch {
                lastError = error

                if shouldTryNextDeploymentPath(after: error) == false {
                    throw error
                }
            }
        }

        if let bundleIdentifier = application.bundleIdentifier,
           bundleIdentifier.isEmpty == false
        {
            let encodedBundleIdentifier = encodedPathComponent(bundleIdentifier)

            do {
                return try await requestWithPathFallback(
                    paths: [
                        "api/v2/mobile-devices/\(detail.summary.inventoryID)/applications/\(encodedBundleIdentifier)/remove",
                        "api/v1/mobile-device-inventory/\(detail.summary.inventoryID)/applications/\(encodedBundleIdentifier)/remove",
                        "api/v1/computer-inventory/\(detail.summary.inventoryID)/applications/\(encodedBundleIdentifier)/remove"
                    ],
                    method: .post,
                    bodyCandidates: [nil, Data("{}".utf8)]
                )
            } catch {
                lastError = error

                if shouldTryNextDeploymentPath(after: error) == false {
                    throw error
                }
            }
        }

        throw lastError ?? SupportTechnicianError.unsupportedAction
    }

    /// Handles encodedPathComponent.
    private func encodedPathComponent(_ value: String) -> String {
        let allowedCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
    }

    /// Handles shouldTryNextDeploymentPath.
    private func shouldTryNextDeploymentPath(after error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, _) = error else {
            return false
        }

        return statusCode == 400 || statusCode == 404 || statusCode == 405 || statusCode == 409 || statusCode == 422
    }

    /// Handles isNoDeviceLockCommandResponse.
    private func isNoDeviceLockCommandResponse(_ data: Data) -> Bool {
        let message = String(data: data, encoding: .utf8) ?? ""
        return message.localizedCaseInsensitiveContains("No Device Lock command found")
    }
    /// Handles resolveManagementID.
    private func resolveManagementID(from detail: SupportDeviceDetail) throws -> String {
        if let managementID = detail.summary.managementID,
           managementID.isEmpty == false
        {
            return managementID
        }

        if let clientManagementID = detail.summary.clientManagementID,
           clientManagementID.isEmpty == false
        {
            return clientManagementID
        }

        throw SupportTechnicianError.missingManagementID
    }

    /// Handles resolveClientManagementID.
    private func resolveClientManagementID(from detail: SupportDeviceDetail) throws -> String {
        if let clientManagementID = detail.summary.clientManagementID,
           clientManagementID.isEmpty == false
        {
            return clientManagementID
        }

        if let managementID = detail.summary.managementID,
           managementID.isEmpty == false
        {
            return managementID
        }

        throw SupportTechnicianError.missingClientManagementID
    }

    /// Handles resolveUDID.
    private func resolveUDID(from detail: SupportDeviceDetail) throws -> String {
        guard let data = detail.rawJSON.data(using: .utf8),
              let dictionary = try jsonObject(from: data) as? [String: Any]
        else {
            throw SupportTechnicianError.unsupportedResponseShape
        }

        if let udid = extractString(
            using: [
                "udid",
                "general.udid",
                "hardware.udid",
                "device.udid"
            ],
            from: dictionary
        ) {
            return udid
        }

        throw SupportTechnicianError.missingUDID
    }

    /// Handles extractSecretValue.
    private func extractSecretValue(
        from data: Data,
        preferredKeyFragments: [String]
    ) throws -> String {
        let object = try jsonObject(from: data)

        if let directValue = recursivelyExtractFirstString(
            in: object,
            matchingAnyKeyFragment: preferredKeyFragments
        ) {
            return directValue
        }

        if let fallbackValue = extractStringValue(from: object) {
            return fallbackValue
        }

        throw SupportTechnicianError.unsupportedSecretPayload
    }

    /// Handles recursivelyExtractFirstString.
    private func recursivelyExtractFirstString(
        in value: Any,
        matchingAnyKeyFragment keyFragments: [String]
    ) -> String? {
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                if keyFragments.contains(where: { key.localizedCaseInsensitiveContains($0) }),
                   let extracted = extractStringValue(from: nestedValue)
                {
                    return extracted
                }

                if let recursive = recursivelyExtractFirstString(
                    in: nestedValue,
                    matchingAnyKeyFragment: keyFragments
                ) {
                    return recursive
                }
            }
        }

        if let array = value as? [Any] {
            for element in array {
                if let recursive = recursivelyExtractFirstString(
                    in: element,
                    matchingAnyKeyFragment: keyFragments
                ) {
                    return recursive
                }
            }
        }

        return nil
    }

    /// Handles rootDictionary.
    private func rootDictionary(from data: Data) throws -> [String: Any] {
        let object = try jsonObject(from: data)

        if let dictionary = object as? [String: Any] {
            for key in ["results", "result", "item", "inventory", "computer", "mobileDevice", "device", "data"] {
                if let nestedDictionary = dictionary[key] as? [String: Any] {
                    return nestedDictionary
                }

                if let nestedArray = dictionary[key] as? [Any],
                   let first = nestedArray.first as? [String: Any]
                {
                    return first
                }
            }

            return dictionary
        }

        if let array = object as? [Any],
           let first = array.first as? [String: Any]
        {
            return first
        }

        throw SupportTechnicianError.unsupportedResponseShape
    }

    /// Handles jsonObject.
    private func jsonObject(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Handles dictionaryArray.
    private func dictionaryArray(from value: Any?) -> [[String: Any]] {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }

        if let array = value as? [Any] {
            let directDictionaries = array.compactMap { $0 as? [String: Any] }
            if directDictionaries.isEmpty == false {
                return directDictionaries
            }

            for element in array {
                let nested = dictionaryArray(from: element)
                if nested.isEmpty == false {
                    return nested
                }
            }

            return []
        }

        if let dictionary = value as? [String: Any] {
            for key in ["results", "items", "devices", "computers", "mobileDevices", "data", "inventory"] {
                let nested = dictionaryArray(from: dictionary[key])
                if nested.isEmpty == false {
                    return nested
                }
            }

            return [dictionary]
        }

        return []
    }

    /// Handles extractString.
    private func extractString(
        using paths: [String],
        from dictionary: [String: Any]
    ) -> String? {
        for path in paths {
            guard let resolvedValue = resolveValue(atPath: path, in: dictionary),
                  let extracted = extractStringValue(from: resolvedValue)
            else {
                continue
            }

            return extracted
        }

        return nil
    }

    /// Handles resolveValue.
    private func resolveValue(atPath path: String, in dictionary: [String: Any]) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        guard components.isEmpty == false else {
            return nil
        }

        var current: Any = dictionary

        for component in components {
            if let currentDictionary = current as? [String: Any] {
                guard let next = currentDictionary[component] else {
                    return nil
                }

                current = next
                continue
            }

            if let currentArray = current as? [Any] {
                let mapped = currentArray.compactMap { element -> Any? in
                    (element as? [String: Any])?[component]
                }

                guard mapped.isEmpty == false else {
                    return nil
                }

                current = mapped.count == 1 ? mapped[0] : mapped
                continue
            }

            return nil
        }

        return current
    }

    /// Handles extractStringValue.
    private func extractStringValue(from value: Any?) -> String? {
        switch value {
        case let stringValue as String:
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let boolValue as Bool:
            return boolValue ? "true" : "false"
        case let intValue as Int:
            return String(intValue)
        case let doubleValue as Double:
            return String(doubleValue)
        case let number as NSNumber:
            return number.stringValue
        case let dictionary as [String: Any]:
            if let preferred =
                extractStringValue(from: dictionary["displayName"]) ??
                extractStringValue(from: dictionary["name"]) ??
                extractStringValue(from: dictionary["value"]) ??
                extractStringValue(from: dictionary["id"])
            {
                return preferred
            }

            let flattened = dictionary
                .keys
                .sorted()
                .compactMap { key -> String? in
                    guard let nestedValue = extractStringValue(from: dictionary[key]) else {
                        return nil
                    }

                    return "\(key): \(nestedValue)"
                }

            guard flattened.isEmpty == false else {
                return nil
            }

            return flattened.joined(separator: ", ")

        case let array as [Any]:
            let values = array.compactMap { extractStringValue(from: $0) }
            guard values.isEmpty == false else {
                return nil
            }

            return values.joined(separator: ", ")
        default:
            return nil
        }
    }

    /// Handles prettyJSONString.
    private func prettyJSONString(from dictionary: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }

    /// Handles buildSections.
    private func buildSections(from dictionary: [String: Any]) -> [SupportDetailSection] {
        var sections: [SupportDetailSection] = []

        for key in dictionary.keys.sorted() {
            guard let value = dictionary[key] else {
                continue
            }

            if let nestedDictionary = value as? [String: Any] {
                let items = nestedDictionary
                    .keys
                    .sorted()
                    .compactMap { nestedKey -> SupportDetailItem? in
                        guard let nestedValue = nestedDictionary[nestedKey],
                              let displayValue = displayString(for: nestedValue)
                        else {
                            return nil
                        }

                        return SupportDetailItem(key: humanReadableLabel(for: nestedKey), value: displayValue)
                    }

                if items.isEmpty == false {
                    sections.append(
                        SupportDetailSection(title: sectionTitle(for: key), items: items)
                    )
                }

                continue
            }

            if let array = value as? [Any] {
                var items: [SupportDetailItem] = [
                    SupportDetailItem(key: "Count", value: String(array.count))
                ]

                for (index, element) in array.prefix(5).enumerated() {
                    if let preview = displayString(for: element) {
                        items.append(
                            SupportDetailItem(
                                key: "Item \(index + 1)",
                                value: preview
                            )
                        )
                    }
                }

                sections.append(
                    SupportDetailSection(title: sectionTitle(for: key), items: items)
                )
                continue
            }

            if let scalar = displayString(for: value) {
                sections.append(
                    SupportDetailSection(
                        title: sectionTitle(for: key),
                        items: [SupportDetailItem(key: humanReadableLabel(for: key), value: scalar)]
                    )
                )
            }
        }

        return sections
    }

    /// Handles sectionTitle.
    private func sectionTitle(for value: String) -> String {
        humanReadableLabel(for: value)
    }

    /// Handles humanReadableLabel.
    private func humanReadableLabel(for value: String) -> String {
        let acronymMap: [String: String] = [
            "api": "API",
            "cpu": "CPU",
            "id": "ID",
            "imei": "IMEI",
            "ip": "IP",
            "laps": "LAPS",
            "mac": "MAC",
            "mdm": "MDM",
            "os": "OS",
            "pin": "PIN",
            "ram": "RAM",
            "udid": "UDID",
            "url": "URL",
            "uuid": "UUID"
        ]

        let normalized = value
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.isEmpty == false else {
            return value
        }

        return normalized
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                if let acronym = acronymMap[lower] {
                    return acronym
                }

                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    /// Handles displayString.
    private func displayString(for value: Any?) -> String? {
        guard let value else {
            return nil
        }

        if let stringValue = extractStringValue(from: value) {
            if stringValue.count > 280 {
                let endIndex = stringValue.index(stringValue.startIndex, offsetBy: 280)
                return "\(stringValue[..<endIndex])..."
            }

            return stringValue
        }

        return nil
    }

    /// Handles flattenForDiagnostics.
    private func flattenForDiagnostics(from dictionary: [String: Any]) -> [String: String] {
        var output: [String: String] = [:]
        flatten(value: dictionary, currentPath: nil, output: &output)
        return output
    }

    /// Handles flatten.
    private func flatten(
        value: Any,
        currentPath: String?,
        output: inout [String: String]
    ) {
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                let nextPath = currentPath.map { "\($0).\(key)" } ?? key
                flatten(value: nestedValue, currentPath: nextPath, output: &output)
            }
            return
        }

        if let array = value as? [Any] {
            if let path = currentPath {
                output[path + ".count"] = String(array.count)
            }

            for (index, nestedValue) in array.prefix(5).enumerated() {
                let nextPath = currentPath.map { "\($0)[\(index)]" } ?? "[\(index)]"
                flatten(value: nestedValue, currentPath: nextPath, output: &output)
            }
            return
        }

        guard let currentPath,
              let resolved = extractStringValue(from: value)
        else {
            return
        }

        output[currentPath] = resolved
    }

    /// Handles extractApplicationNames.
    private func extractApplicationNames(from dictionary: [String: Any]) -> [String] {
        let applicationPathCandidates = [
            "applications",
            "applicationList",
            "general.applications",
            "hardware.applications",
            "software.applications",
            "softwareUpdates",
            "licensedSoftware",
            "software"
        ]

        var names = Set<String>()
        var applicationDictionaries: [[String: Any]] = []

        for path in applicationPathCandidates {
            guard let value = resolveValue(atPath: path, in: dictionary) else {
                continue
            }

            let dictionaries = dictionaryArray(from: value)
            applicationDictionaries.append(contentsOf: dictionaries)
            for dictionary in dictionaries {
                if let name =
                    extractString(
                        using: [
                            "name",
                            "displayName",
                            "appName",
                            "applicationName",
                            "bundleId",
                            "bundleIdentifier",
                            "identifier"
                        ],
                        from: dictionary
                    )
                {
                    names.insert(name)
                }
            }

            if let values = value as? [Any] {
                for element in values {
                    if let scalar = extractStringValue(from: element) {
                        names.insert(scalar)
                    }
                }
            }
        }

        collectDictionaryArrays(
            in: dictionary,
            matchingAnyKeyFragments: ["application", "applications", "bundleId", "bundleIdentifier"],
            output: &applicationDictionaries
        )

        for applicationDictionary in applicationDictionaries {
            if let name =
                extractString(
                    using: [
                        "name",
                        "displayName",
                        "appName",
                        "applicationName",
                        "bundleId",
                        "bundleIdentifier",
                        "identifier"
                    ],
                    from: applicationDictionary
                )
            {
                names.insert(name)
            }
        }

        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Handles extractLocalUserAccounts.
    private func extractLocalUserAccounts(from dictionary: [String: Any]) -> [SupportLocalUserAccount] {
        let pathCandidates = [
            "localUserAccounts",
            "userAndLocation.localUserAccounts",
            "hardware.localUserAccounts",
            "general.localUserAccounts"
        ]

        var accountDictionaries: [[String: Any]] = []
        for path in pathCandidates {
            guard let value = resolveValue(atPath: path, in: dictionary) else {
                continue
            }

            accountDictionaries.append(contentsOf: dictionaryArray(from: value))
        }

        collectDictionaryArrays(
            in: dictionary,
            matchingAnyKeyFragments: ["localuseraccount", "local_user", "localUserAccounts"],
            output: &accountDictionaries
        )

        var uniqueAccounts: [String: SupportLocalUserAccount] = [:]
        for accountDictionary in accountDictionaries {
            let username = extractString(
                using: ["username", "userName", "name", "shortName", "userShortName"],
                from: accountDictionary
            ) ?? ""

            let userGuid = extractString(using: ["userGuid", "guid", "accountGuid"], from: accountDictionary)
            let uid = extractString(using: ["uid", "userId", "id"], from: accountDictionary)

            if username.isEmpty && userGuid == nil && uid == nil {
                continue
            }

            let accountID = userGuid ?? "\(username)-\(uid ?? "unknown")"
            uniqueAccounts[accountID] = SupportLocalUserAccount(
                id: accountID,
                username: username.isEmpty ? (uid ?? "Unknown User") : username,
                fullName: extractString(using: ["fullName", "realName", "displayName"], from: accountDictionary),
                userGuid: userGuid,
                uid: uid,
                isAdmin: extractBoolean(using: ["admin", "isAdmin"], from: accountDictionary)
            )
        }

        return uniqueAccounts.values.sorted {
            $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
        }
    }

    /// Handles extractCertificates.
    private func extractCertificates(from dictionary: [String: Any]) -> [SupportCertificate] {
        let pathCandidates = [
            "certificates",
            "security.certificates",
            "general.certificates",
            "network.certificates"
        ]

        var certificateDictionaries: [[String: Any]] = []
        for path in pathCandidates {
            guard let value = resolveValue(atPath: path, in: dictionary) else {
                continue
            }

            certificateDictionaries.append(contentsOf: dictionaryArray(from: value))
        }

        collectDictionaryArrays(
            in: dictionary,
            matchingAnyKeyFragments: ["certificate", "certificates"],
            output: &certificateDictionaries
        )

        var uniqueCertificates: [String: SupportCertificate] = [:]
        for certificateDictionary in certificateDictionaries {
            let commonName = extractString(
                using: ["commonName", "name", "displayName", "subjectName"],
                from: certificateDictionary
            ) ?? ""

            let serialNumber = extractString(using: ["serialNumber", "serial"], from: certificateDictionary)
            let certificateStatus = extractString(using: ["certificateStatus", "status"], from: certificateDictionary)
            let lifecycleStatus = extractString(using: ["lifecycleStatus", "lifecycle"], from: certificateDictionary)
            let expirationDate = extractString(
                using: ["expirationDate", "expirationDateEpoch", "expires", "validUntil"],
                from: certificateDictionary
            )

            if commonName.isEmpty && serialNumber == nil && certificateStatus == nil && expirationDate == nil {
                continue
            }

            let certificateID = serialNumber ?? commonName.lowercased()
            uniqueCertificates[certificateID] = SupportCertificate(
                id: certificateID,
                commonName: commonName.isEmpty ? (serialNumber ?? "Unknown Certificate") : commonName,
                subjectName: extractString(using: ["subjectName", "subject", "issuer"], from: certificateDictionary),
                serialNumber: serialNumber,
                lifecycleStatus: lifecycleStatus,
                certificateStatus: certificateStatus,
                expirationDate: expirationDate,
                issuedDate: extractString(using: ["issuedDate", "issuedDateEpoch"], from: certificateDictionary),
                username: extractString(using: ["username", "userName"], from: certificateDictionary)
            )
        }

        return uniqueCertificates.values.sorted {
            $0.commonName.localizedCaseInsensitiveCompare($1.commonName) == .orderedAscending
        }
    }

    /// Handles extractConfigurationProfiles.
    private func extractConfigurationProfiles(from dictionary: [String: Any]) -> [SupportConfigurationProfile] {
        let pathCandidates = [
            "configurationProfiles",
            "profiles",
            "security.configurationProfiles",
            "general.configurationProfiles",
            "configuration.configurationProfiles"
        ]

        var profileDictionaries: [[String: Any]] = []
        var profileNames = Set<String>()

        for path in pathCandidates {
            guard let value = resolveValue(atPath: path, in: dictionary) else {
                continue
            }

            profileDictionaries.append(contentsOf: dictionaryArray(from: value))

            if let values = value as? [Any] {
                for element in values {
                    if let scalar = extractStringValue(from: element),
                       scalar.isEmpty == false
                    {
                        profileNames.insert(scalar)
                    }
                }
            }
        }

        collectDictionaryArrays(
            in: dictionary,
            matchingAnyKeyFragments: [
                "configurationprofile",
                "configurationprofiles",
                "installedprofile",
                "installedprofiles",
                "managedprofile",
                "managedprofiles"
            ],
            output: &profileDictionaries
        )

        var uniqueProfiles: [String: SupportConfigurationProfile] = [:]
        for profileDictionary in profileDictionaries {
            let name = extractString(
                using: ["name", "displayName", "profileName", "identifier", "payloadIdentifier"],
                from: profileDictionary
            ) ?? ""

            let identifier = extractString(
                using: ["identifier", "payloadIdentifier", "profileIdentifier", "id", "uuid"],
                from: profileDictionary
            )

            let status = extractString(
                using: ["status", "state", "profileStatus"],
                from: profileDictionary
            )

            let source = extractString(
                using: ["source", "scope", "origin", "distributionMethod"],
                from: profileDictionary
            )

            if name.isEmpty && identifier == nil {
                continue
            }

            let profileID = identifier ?? name.lowercased()
            uniqueProfiles[profileID] = SupportConfigurationProfile(
                id: profileID,
                name: name.isEmpty ? (identifier ?? "Unknown Profile") : name,
                identifier: identifier,
                profileStatus: status,
                source: source
            )
        }

        for profileName in profileNames {
            let profileID = profileName.lowercased()
            if uniqueProfiles[profileID] == nil {
                uniqueProfiles[profileID] = SupportConfigurationProfile(
                    id: profileID,
                    name: profileName,
                    identifier: nil,
                    profileStatus: nil,
                    source: nil
                )
            }
        }

        return uniqueProfiles.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Handles extractGroupMemberships.
    private func extractGroupMemberships(from dictionary: [String: Any]) -> [SupportGroupMembership] {
        let pathCandidates = [
            "groupMemberships",
            "groups",
            "general.groupMemberships",
            "userAndLocation.groupMemberships"
        ]

        var groupDictionaries: [[String: Any]] = []
        var groupNames = Set<String>()

        for path in pathCandidates {
            guard let value = resolveValue(atPath: path, in: dictionary) else {
                continue
            }

            groupDictionaries.append(contentsOf: dictionaryArray(from: value))

            if let values = value as? [Any] {
                for element in values {
                    if let scalar = extractStringValue(from: element),
                       scalar.isEmpty == false
                    {
                        groupNames.insert(scalar)
                    }
                }
            }
        }

        collectDictionaryArrays(
            in: dictionary,
            matchingAnyKeyFragments: [
                "groupmembership",
                "groupmemberships",
                "smartgroup",
                "smartgroups",
                "staticgroup",
                "staticgroups",
                "devicegroup"
            ],
            output: &groupDictionaries
        )

        var uniqueGroups: [String: SupportGroupMembership] = [:]
        for groupDictionary in groupDictionaries {
            let name = extractString(
                using: ["name", "displayName", "groupName", "group", "smartGroupName", "staticGroupName"],
                from: groupDictionary
            ) ?? ""

            let groupID = extractString(
                using: ["id", "groupId", "smartGroupId", "staticGroupId", "uuid"],
                from: groupDictionary
            )

            let groupType = extractString(
                using: ["groupType", "type", "membershipType", "smartOrStatic"],
                from: groupDictionary
            )

            let source = extractString(
                using: ["source", "origin", "scope"],
                from: groupDictionary
            )

            let isSmart = extractBoolean(
                using: ["isSmart", "smart", "smartGroup"],
                from: groupDictionary
            )

            if name.isEmpty && groupID == nil {
                continue
            }

            let resolvedGroupID = groupID ?? name.lowercased()
            uniqueGroups[resolvedGroupID] = SupportGroupMembership(
                id: resolvedGroupID,
                name: name.isEmpty ? (groupID ?? "Unknown Group") : name,
                groupType: groupType,
                isSmartGroup: isSmart,
                source: source
            )
        }

        for groupName in groupNames {
            let groupID = groupName.lowercased()
            if uniqueGroups[groupID] == nil {
                uniqueGroups[groupID] = SupportGroupMembership(
                    id: groupID,
                    name: groupName,
                    groupType: nil,
                    isSmartGroup: nil,
                    source: nil
                )
            }
        }

        return uniqueGroups.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Handles collectDictionaryArrays.
    private func collectDictionaryArrays(
        in value: Any,
        matchingAnyKeyFragments keyFragments: [String],
        output: inout [[String: Any]]
    ) {
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                let normalizedKey = key.lowercased()
                if keyFragments.contains(where: { normalizedKey.contains($0.lowercased()) }) {
                    output.append(contentsOf: dictionaryArray(from: nestedValue))
                }

                collectDictionaryArrays(
                    in: nestedValue,
                    matchingAnyKeyFragments: keyFragments,
                    output: &output
                )
            }
            return
        }

        if let array = value as? [Any] {
            for element in array {
                collectDictionaryArrays(
                    in: element,
                    matchingAnyKeyFragments: keyFragments,
                    output: &output
                )
            }
        }
    }

    /// Handles extractBoolean.
    private func extractBoolean(using paths: [String], from dictionary: [String: Any]) -> Bool? {
        for path in paths {
            guard let resolved = resolveValue(atPath: path, in: dictionary) else {
                continue
            }

            if let boolValue = resolved as? Bool {
                return boolValue
            }

            if let stringValue = resolved as? String {
                let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalized == "true" || normalized == "yes" || normalized == "1" {
                    return true
                }
                if normalized == "false" || normalized == "no" || normalized == "0" {
                    return false
                }
            }

            if let number = resolved as? NSNumber {
                return number.boolValue
            }
        }

        return nil
    }

    /// Handles buildDiagnostics.
    private func buildDiagnostics(
        for result: SupportSearchResult,
        flattenedValues: [String: String],
        applications: [String]
    ) -> [SupportDiagnosticItem] {
        var diagnostics: [SupportDiagnosticItem] = []

        if result.managementID == nil {
            diagnostics.append(
                SupportDiagnosticItem(
                    title: "Management Identifier",
                    value: "Missing",
                    severity: .critical
                )
            )
        } else {
            diagnostics.append(
                SupportDiagnosticItem(
                    title: "Management Identifier",
                    value: "Present",
                    severity: .info
                )
            )
        }

        if let username = result.username,
           username.isEmpty == false
        {
            diagnostics.append(
                SupportDiagnosticItem(
                    title: "Assigned User",
                    value: username,
                    severity: .info
                )
            )
        } else {
            diagnostics.append(
                SupportDiagnosticItem(
                    title: "Assigned User",
                    value: "Not assigned",
                    severity: .warning
                )
            )
        }

        if let inventoryDate = resolveInventoryDate(from: result, flattenedValues: flattenedValues) {
            let ageInDays = Int(Date().timeIntervalSince(inventoryDate) / 86_400)
            let severity: SupportDiagnosticSeverity = ageInDays > 14 ? .warning : .info
            diagnostics.append(
                SupportDiagnosticItem(
                    title: "Inventory Age",
                    value: "\(max(ageInDays, 0)) day(s)",
                    severity: severity
                )
            )
        }

        switch result.assetType {
        case .computer:
            if let fileVaultValue =
                flattenedValues["diskEncryption.fileVault2Enabled"] ??
                flattenedValues["general.fileVault2Enabled"]
            {
                let isEnabled = boolValue(from: fileVaultValue)
                diagnostics.append(
                    SupportDiagnosticItem(
                        title: "FileVault",
                        value: isEnabled ? "Enabled" : "Disabled",
                        severity: isEnabled ? .info : .warning
                    )
                )
            }

        case .mobileDevice:
            if let supervisedValue =
                flattenedValues["general.supervised"] ??
                flattenedValues["supervised"]
            {
                let isSupervised = boolValue(from: supervisedValue)
                diagnostics.append(
                    SupportDiagnosticItem(
                        title: "Supervision",
                        value: isSupervised ? "Supervised" : "Not supervised",
                        severity: isSupervised ? .info : .warning
                    )
                )
            }
        }

        diagnostics.append(
            SupportDiagnosticItem(
                title: "Discovered Applications",
                value: "\(applications.count)",
                severity: applications.isEmpty ? .warning : .info
            )
        )

        return diagnostics
    }

    /// Handles resolveInventoryDate.
    private func resolveInventoryDate(
        from result: SupportSearchResult,
        flattenedValues: [String: String]
    ) -> Date? {
        let candidates = [
            result.lastInventoryUpdate,
            flattenedValues["general.lastInventoryUpdateDate"],
            flattenedValues["general.lastInventoryUpdate"],
            flattenedValues["general.reportDate"],
            flattenedValues["general.lastContactTime"],
            flattenedValues["lastInventoryUpdateDate"],
            flattenedValues["reportDate"],
            flattenedValues["lastContactTime"]
        ]

        for candidate in candidates {
            guard let candidate else {
                continue
            }

            if let parsed = parseDate(candidate) {
                return parsed
            }
        }

        return nil
    }

    /// Handles parseDate.
    private func parseDate(_ value: String) -> Date? {
        if let date = iso8601FractionalFormatter.date(from: value) {
            return date
        }

        if let date = iso8601Formatter.date(from: value) {
            return date
        }

        if let unixSeconds = Double(value) {
            if unixSeconds > 100_000_000_000 {
                return Date(timeIntervalSince1970: unixSeconds / 1000)
            }

            return Date(timeIntervalSince1970: unixSeconds)
        }

        return nil
    }

    /// Handles boolValue.
    private func boolValue(from value: String) -> Bool {
        switch value.lowercased() {
        case "true", "yes", "1", "managed", "enabled":
            return true
        default:
            return false
        }
    }

    /// Handles dedupe.
    private func dedupe(_ results: [SupportSearchResult]) -> [SupportSearchResult] {
        var seen = Set<String>()
        var deduped: [SupportSearchResult] = []

        for result in results {
            let dedupeKey = "\(result.assetType.rawValue)-\(result.inventoryID)"
            guard seen.insert(dedupeKey).inserted else {
                continue
            }

            deduped.append(result)
        }

        return deduped
    }

    /// Handles sortByAssetAndName.
    private func sortByAssetAndName(lhs: SupportSearchResult, rhs: SupportSearchResult) -> Bool {
        if lhs.assetType != rhs.assetType {
            return lhs.assetType.rawValue.localizedCaseInsensitiveCompare(rhs.assetType.rawValue) == .orderedAscending
        }

        let nameComparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.serialNumber.localizedCaseInsensitiveCompare(rhs.serialNumber) == .orderedAscending
    }

    /// Handles buildComputerFilters.
    private func buildComputerFilters(withEscapedQuery query: String, useWildcard: Bool) -> [String] {
        let value = useWildcard ? "*\(query)*" : query
        let fieldCandidates: [[String]] = [
            [
                "general.name==\"\(value)\"",
                "hardware.serialNumber==\"\(value)\"",
                "userAndLocation.username==\"\(value)\"",
                "userAndLocation.email==\"\(value)\""
            ],
            [
                "displayName==\"\(value)\"",
                "serialNumber==\"\(value)\"",
                "username==\"\(value)\"",
                "email==\"\(value)\""
            ],
            [
                "general.displayName==\"\(value)\"",
                "general.serialNumber==\"\(value)\"",
                "general.assetTag==\"\(value)\"",
                "general.udid==\"\(value)\""
            ]
        ]

        return fieldCandidates.map { "(\($0.joined(separator: ",")))" }
    }

    /// Handles buildMobileDeviceFilters.
    private func buildMobileDeviceFilters(withEscapedQuery query: String, useWildcard: Bool) -> [String] {
        let value = useWildcard ? "*\(query)*" : query
        let fieldCandidates: [[String]] = [
            [
                "serialNumber==\"\(value)\"",
                "displayName==\"\(value)\"",
                "username==\"\(value)\"",
                "fullName==\"\(value)\"",
                "emailAddress==\"\(value)\""
            ],
            [
                "serialNumber==\"\(value)\"",
                "displayName==\"\(value)\"",
                "userPhoneNumber==\"\(value)\"",
                "imei==\"\(value)\"",
                "udid==\"\(value)\""
            ],
            // Compatibility fallback for older payload schemas.
            [
                "hardware.serialNumber==\"\(value)\"",
                "general.displayName==\"\(value)\"",
                "userAndLocation.username==\"\(value)\"",
                "userAndLocation.emailAddress==\"\(value)\""
            ]
        ]

        return fieldCandidates.map { "(\($0.joined(separator: ",")))" }
    }

    /// Handles removeStaticGroupMembership.
    private func removeStaticGroupMembership(
        _ group: SupportGroupMembership,
        for detail: SupportDeviceDetail
    ) async throws {
        let resourceName: String
        let xmlPayload: Data

        switch detail.summary.assetType {
        case .computer:
            resourceName = "computergroups"
            xmlPayload = xmlData(
                for: """
                <computer_group>
                  <computer_deletions>
                    <computer>
                      <id>\(xmlEscaped(detail.summary.inventoryID))</id>
                    </computer>
                  </computer_deletions>
                </computer_group>
                """
            )
        case .mobileDevice:
            resourceName = "mobiledevicegroups"
            xmlPayload = xmlData(
                for: """
                <mobile_device_group>
                  <mobile_device_deletions>
                    <mobile_device>
                      <id>\(xmlEscaped(detail.summary.inventoryID))</id>
                    </mobile_device>
                  </mobile_device_deletions>
                </mobile_device_group>
                """
            )
        }

        let candidatePaths = classicGroupPaths(resourceName: resourceName, group: group)
        guard candidatePaths.isEmpty == false else {
            throw SupportTechnicianError.invalidCommandInput
        }

        _ = try await requestWithPathFallback(
            paths: candidatePaths,
            method: .put,
            bodyCandidates: [xmlPayload],
            additionalHeaders: [
                "Content-Type": "application/xml",
                "Accept": "application/xml,application/json"
            ]
        )
    }

    /// Handles classicGroupPaths.
    private func classicGroupPaths(resourceName: String, group: SupportGroupMembership) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()

        let trimmedGroupID = group.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedGroupID.isEmpty == false {
            let numericID = trimmedGroupID.allSatisfy(\.isNumber)
            if numericID {
                let path = "JSSResource/\(resourceName)/id/\(trimmedGroupID)"
                if seen.insert(path).inserted {
                    paths.append(path)
                }
            }
        }

        let trimmedGroupName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedGroupName.isEmpty == false {
            let encodedName = encodedPathComponent(trimmedGroupName)
            let path = "JSSResource/\(resourceName)/name/\(encodedName)"
            if seen.insert(path).inserted {
                paths.append(path)
            }
        }

        return paths
    }

    /// Handles isSmartGroup.
    private func isSmartGroup(_ group: SupportGroupMembership) -> Bool {
        if group.isSmartGroup == true {
            return true
        }

        guard let groupType = group.groupType?.lowercased() else {
            return false
        }

        return groupType.contains("smart")
    }

    /// Handles xmlData.
    private func xmlData(for value: String) -> Data {
        Data(value.utf8)
    }

    /// Handles xmlEscaped.
    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Handles escapeRSQLString.
    private func escapeRSQLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Handles shouldTryNextComputerEndpoint.
    private func shouldTryNextComputerEndpoint(after error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, _) = error else {
            return false
        }

        return statusCode == 400 || statusCode == 403 || statusCode == 404
    }

    /// Handles shouldTryNextPath.
    private func shouldTryNextPath(after error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, _) = error else {
            return false
        }

        return statusCode == 400 || statusCode == 403 || statusCode == 404 || statusCode == 405
    }

    /// Handles isSectionParameterError.
    private func isSectionParameterError(_ error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, message) = error else {
            return false
        }

        guard statusCode == 400 else {
            return false
        }

        let normalized = message.lowercased()
        if normalized.contains("section") == false {
            return false
        }

        return normalized.contains("invalid") ||
            normalized.contains("java.util.set") ||
            normalized.contains("request parameter")
    }

    /// Handles isNetworkFailure.
    private func isNetworkFailure(_ error: any Error, statusCode: Int) -> Bool {
        guard case let JamfFrameworkError.networkFailure(code, _) = error else {
            return false
        }

        return code == statusCode
    }
}

//endofline
