import Foundation
import Combine

@MainActor
/// ComputerSearchViewModel declaration.
final class ComputerSearchViewModel: ObservableObject {
    /// ComputerPrestageSummary declaration.
    private struct ComputerPrestageSummary: Sendable {
        let id: String
        let name: String
    }

    /// ComputerPrestageScopeAssociation declaration.
    private struct ComputerPrestageScopeAssociation: Sendable {
        let serialNumber: String
        let profileID: String
        let profileName: String
    }

    /// ComputerInventoryEndpointVersion declaration.
    private enum ComputerInventoryEndpointVersion: String, CaseIterable {
        case v3 = "v3"
        case v2 = "v2"
        case v1 = "v1"

        var path: String {
            "api/\(rawValue)/computers-inventory"
        }

        var supportedSections: Set<ComputerInventorySection> {
            switch self {
            case .v1:
                return Set(ComputerInventorySection.allCases)
            case .v2, .v3:
                return Set(ComputerInventorySection.allCases).subtracting([.plugins, .fonts])
            }
        }
    }

    @Published var query = ""
    @Published private(set) var profiles: [ComputerSearchProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var selectedFieldKeys: Set<String> = []

    @Published private(set) var searchResults: [ComputerRecord] = []
    @Published private(set) var isSearching = false

    @Published var isFieldCatalogPresented = false
    @Published var isSaveProfilePromptPresented = false
    @Published var pendingProfileName = ""

    @Published var errorMessage: String?

    private let apiGateway: JamfAPIGateway
    private let diagnosticsReporter: any DiagnosticsReporting
    private let profileStore: ComputerSearchProfileStore
    private let decoder = JSONDecoder()
    private let moduleSource = "module.computer-search"
    private let enrolledStatusLabel = "Enrolled"
    private let notEnrolledStatusLabel = "Not Enrolled"
    private var computerPrestageNameCache: [String: String] = [:]
    private let supportedInventoryFilterKeys: Set<String> = [
        "general.name",
        "udid",
        "id",
        "general.assetTag",
        "general.barcode1",
        "general.barcode2",
        "general.enrolledViaAutomatedDeviceEnrollment",
        "general.lastIpAddress",
        "general.jamfBinaryVersion",
        "general.lastContactTime",
        "general.lastEnrolledDate",
        "general.lastCloudBackupDate",
        "general.reportDate",
        "general.lastReportedIp",
        "general.lastReportedIpV4",
        "general.lastReportedIpV6",
        "general.managementId",
        "general.remoteManagement.managed",
        "general.mdmCapable.capable",
        "general.mdmCertificateExpiration",
        "general.platform",
        "general.supervised",
        "general.userApprovedMdm",
        "general.declarativeDeviceManagementEnabled",
        "general.lastLoggedInUsernameSelfService",
        "general.lastLoggedInUsernameSelfServiceTimestamp",
        "general.lastLoggedInUsernameBinary",
        "general.lastLoggedInUsernameBinaryTimestamp",
        "hardware.bleCapable",
        "hardware.macAddress",
        "hardware.make",
        "hardware.model",
        "hardware.modelIdentifier",
        "hardware.serialNumber",
        "hardware.supportsIosAppInstalls",
        "hardware.appleSilicon",
        "operatingSystem.activeDirectoryStatus",
        "operatingSystem.fileVault2Status",
        "operatingSystem.build",
        "operatingSystem.supplementalBuildVersion",
        "operatingSystem.rapidSecurityResponse",
        "operatingSystem.name",
        "operatingSystem.version",
        "security.activationLockEnabled",
        "security.recoveryLockEnabled",
        "security.firewallEnabled",
        "userAndLocation.buildingId",
        "userAndLocation.departmentId",
        "userAndLocation.email",
        "userAndLocation.realname",
        "userAndLocation.phone",
        "userAndLocation.position",
        "userAndLocation.room",
        "userAndLocation.username",
        "diskEncryption.fileVault2Enabled",
        "purchasing.appleCareId",
        "purchasing.lifeExpectancy",
        "purchasing.purchased",
        "purchasing.leased",
        "purchasing.vendor",
        "purchasing.warrantyDate"
    ]
    private let booleanInventoryFilterKeys: Set<String> = [
        "general.enrolledViaAutomatedDeviceEnrollment",
        "general.remoteManagement.managed",
        "general.mdmCapable.capable",
        "general.supervised",
        "general.userApprovedMdm",
        "general.declarativeDeviceManagementEnabled",
        "hardware.bleCapable",
        "hardware.supportsIosAppInstalls",
        "hardware.appleSilicon",
        "security.activationLockEnabled",
        "security.recoveryLockEnabled",
        "security.firewallEnabled",
        "diskEncryption.fileVault2Enabled",
        "purchasing.purchased",
        "purchasing.leased"
    ]
    private let numericInventoryFilterKeys: Set<String> = [
        "id",
        "userAndLocation.buildingId",
        "userAndLocation.departmentId",
        "purchasing.lifeExpectancy"
    ]
    private let textualInventoryFilterKeys: Set<String> = [
        "general.name",
        "udid",
        "general.assetTag",
        "general.barcode1",
        "general.barcode2",
        "general.lastIpAddress",
        "general.jamfBinaryVersion",
        "general.lastReportedIp",
        "general.lastReportedIpV4",
        "general.lastReportedIpV6",
        "general.managementId",
        "general.platform",
        "general.lastLoggedInUsernameSelfService",
        "general.lastLoggedInUsernameBinary",
        "hardware.macAddress",
        "hardware.make",
        "hardware.model",
        "hardware.modelIdentifier",
        "hardware.serialNumber",
        "operatingSystem.activeDirectoryStatus",
        "operatingSystem.fileVault2Status",
        "operatingSystem.build",
        "operatingSystem.supplementalBuildVersion",
        "operatingSystem.rapidSecurityResponse",
        "operatingSystem.name",
        "operatingSystem.version",
        "userAndLocation.email",
        "userAndLocation.realname",
        "userAndLocation.phone",
        "userAndLocation.position",
        "userAndLocation.room",
        "userAndLocation.username",
        "purchasing.appleCareId",
        "purchasing.vendor"
    ]
    private let privilegeFallbackFilterFieldKeys: [String] = [
        "general.name",
        "hardware.serialNumber",
        "udid",
        "general.assetTag",
        "general.barcode1",
        "general.barcode2",
        "general.lastIpAddress"
    ]
    private let defaultIdentityFilterFieldKeys: [String] = [
        "userAndLocation.username",
        "userAndLocation.realname",
        "userAndLocation.email",
        "hardware.serialNumber",
        "general.name"
    ]

    /// Initializes the instance.
    init(
        apiGateway: JamfAPIGateway,
        diagnosticsReporter: any DiagnosticsReporting,
        profileStore: ComputerSearchProfileStore = ComputerSearchProfileStore()
    ) {
        self.apiGateway = apiGateway
        self.diagnosticsReporter = diagnosticsReporter
        self.profileStore = profileStore
    }

    var selectedProfile: ComputerSearchProfile? {
        guard let selectedProfileID else {
            return nil
        }

        return profiles.first(where: { $0.id == selectedProfileID })
    }

    /// Handles loadProfiles.
    func loadProfiles() async {
        do {
            let loaded = try await profileStore.loadProfiles()
            profiles = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            if selectedProfileID == nil {
                selectedProfileID = profiles.first?.id
            }

            applySelectedProfileFields()
        } catch {
            let description = describe(error)
            errorMessage = "Failed to load saved profiles. \(description)"
            reportError(
                category: "profiles",
                message: "Failed to load saved search profiles.",
                errorDescription: description
            )
        }
    }

    /// Handles applySelectedProfileFields.
    func applySelectedProfileFields() {
        guard let selectedProfile else {
            return
        }

        selectedFieldKeys = Set(selectedProfile.fieldKeys)
    }

    /// Handles presentSaveProfilePrompt.
    func presentSaveProfilePrompt() {
        guard selectedFieldKeys.isEmpty == false else {
            errorMessage = "Select at least one field before saving a profile."
            reportEvent(
                severity: .warning,
                category: "profiles",
                message: "Profile save requested without selected fields."
            )
            return
        }

        pendingProfileName = ""
        isSaveProfilePromptPresented = true
    }

    /// Handles saveProfileFromPrompt.
    func saveProfileFromPrompt() async {
        let profileName = pendingProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard profileName.isEmpty == false else {
            errorMessage = "Provide a name for the profile."
            reportEvent(
                severity: .warning,
                category: "profiles",
                message: "Profile save attempted without a profile name."
            )
            return
        }

        let sortedFieldKeys = Array(selectedFieldKeys).sorted()

        if let index = profiles.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(profileName) == .orderedSame }) {
            profiles[index].fieldKeys = sortedFieldKeys
            selectedProfileID = profiles[index].id
        } else {
            let profile = ComputerSearchProfile(name: profileName, fieldKeys: sortedFieldKeys)
            profiles.append(profile)
            profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            selectedProfileID = profile.id
        }

        do {
            try await profileStore.saveProfiles(profiles)
            isSaveProfilePromptPresented = false
            errorMessage = nil
            reportEvent(
                severity: .info,
                category: "profiles",
                message: "Saved search profile.",
                metadata: [
                    "profile_name": profileName,
                    "field_count": String(sortedFieldKeys.count)
                ]
            )
        } catch {
            let description = describe(error)
            errorMessage = "Failed to save profile. \(description)"
            reportError(
                category: "profiles",
                message: "Failed to save search profile.",
                errorDescription: description,
                metadata: [
                    "profile_name": profileName
                ]
            )
        }
    }

    /// Handles deleteProfiles.
    func deleteProfiles(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard profiles.indices.contains(index) else {
                continue
            }

            profiles.remove(at: index)
        }

        if let selectedProfileID, profiles.contains(where: { $0.id == selectedProfileID }) == false {
            self.selectedProfileID = profiles.first?.id
            applySelectedProfileFields()
        }

        Task {
            do {
                try await profileStore.saveProfiles(profiles)
                await diagnosticsReporter.report(
                    source: moduleSource,
                    category: "profiles",
                    severity: .warning,
                    message: "Deleted one or more search profiles.",
                    metadata: [:]
                )
            } catch {
                let description = describe(error)
                errorMessage = "Failed to persist profile deletion. \(description)"
                await diagnosticsReporter.reportError(
                    source: moduleSource,
                    category: "profiles",
                    message: "Failed to persist profile deletion.",
                    errorDescription: description
                )
            }
        }
    }


    /// Handles executeSearch.
    func executeSearch() async {
        isSearching = true
        defer { isSearching = false }

        let selectedKeys = selectedProfile?.fieldKeys ?? Array(selectedFieldKeys).sorted()
        let activeFields = resolvedCatalogFields(from: selectedKeys)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections = resolvedSections(from: activeFields)
        if trimmedQuery.isEmpty == false {
            sections = Array(Set(sections).union([.userAndLocation])).sorted { $0.rawValue < $1.rawValue }
        }

        do {
            let data = try await requestInventory(
                sections: sections,
                query: trimmedQuery,
                fields: activeFields,
                useWildcardFilter: true
            )

            let decodedResults = try decodeSearchResults(from: data)
            searchResults = await resolvePrestageEnrollment(for: decodedResults, query: trimmedQuery)
            errorMessage = nil
            reportEvent(
                severity: .info,
                category: "search",
                message: "Computer search completed.",
                metadata: [
                    "result_count": String(searchResults.count),
                    "has_query": trimmedQuery.isEmpty ? "false" : "true",
                    "field_count": String(activeFields.count),
                    "section_count": String(sections.count)
                ]
            )
        } catch {
            if case let JamfFrameworkError.networkFailure(statusCode, _) = error,
               statusCode == 400,
               trimmedQuery.isEmpty == false
            {
                do {
                    let fallbackData = try await requestInventory(
                        sections: sections,
                        query: trimmedQuery,
                        fields: activeFields,
                        useWildcardFilter: false
                    )

                    let fallbackResults = try decodeSearchResults(from: fallbackData)
                    searchResults = await resolvePrestageEnrollment(for: fallbackResults, query: trimmedQuery)
                    errorMessage = nil
                    reportEvent(
                        severity: .warning,
                        category: "search",
                        message: "Computer search completed using exact-match fallback.",
                        metadata: [
                            "result_count": String(searchResults.count),
                            "has_query": "true",
                            "field_count": String(activeFields.count),
                            "section_count": String(sections.count)
                        ]
                    )
                    return
                } catch {
                    if case let JamfFrameworkError.networkFailure(fallbackStatusCode, _) = error,
                       fallbackStatusCode == 400
                    {
                        let defaultFields = ComputerField.defaultRSQLQueryFieldKeys.compactMap { ComputerField.keyLookup[$0] }

                        do {
                            let defaultData = try await requestInventory(
                                sections: resolvedSections(from: defaultFields),
                                query: trimmedQuery,
                                fields: defaultFields,
                                useWildcardFilter: false
                            )

                            let defaultResults = try decodeSearchResults(from: defaultData)
                            searchResults = await resolvePrestageEnrollment(for: defaultResults, query: trimmedQuery)
                            errorMessage = nil
                            reportEvent(
                                severity: .warning,
                                category: "search",
                                message: "Computer search completed using default-field fallback.",
                                metadata: [
                                    "result_count": String(searchResults.count),
                                    "has_query": "true",
                                    "field_count": String(defaultFields.count)
                                ]
                            )
                            return
                        } catch {
                            let description = describe(error)
                            self.errorMessage = description
                            reportError(
                                category: "search",
                                message: "Computer search failed after all fallback strategies.",
                                errorDescription: description,
                                metadata: [
                                    "has_query": "true",
                                    "field_count": String(activeFields.count)
                                ]
                            )
                            return
                        }
                    }

                    let description = describe(error)
                    self.errorMessage = description
                    reportError(
                        category: "search",
                        message: "Computer search failed after exact-match fallback.",
                        errorDescription: description,
                        metadata: [
                            "has_query": "true",
                            "field_count": String(activeFields.count)
                        ]
                    )
                    return
                }
            }

            let description = describe(error)
            errorMessage = userFacingSearchErrorMessage(for: error)
            reportError(
                category: "search",
                message: "Computer search failed.",
                errorDescription: description,
                metadata: [
                    "has_query": trimmedQuery.isEmpty ? "false" : "true",
                    "field_count": String(activeFields.count),
                    "section_count": String(sections.count)
                ]
            )
        }
    }

    /// Handles requestInventory.
    private func requestInventory(
        sections: [ComputerInventorySection],
        query: String,
        fields: [ComputerField],
        useWildcardFilter: Bool
    ) async throws -> Data {
        var lastError: (any Error)?

        for endpointVersion in ComputerInventoryEndpointVersion.allCases {
            let versionSections = sections
                .filter { endpointVersion.supportedSections.contains($0) }
                .sorted { $0.rawValue < $1.rawValue }

            do {
                return try await requestInventory(
                    endpointVersion: endpointVersion,
                    sections: versionSections,
                    query: query,
                    fields: fields,
                    useWildcardFilter: useWildcardFilter
                )
            } catch {
                lastError = error

                if isInvalidPrivilegeError(error) {
                    do {
                        return try await requestInventory(
                            endpointVersion: endpointVersion,
                            sections: [],
                            query: query,
                            fields: privilegeFallbackFields(),
                            useWildcardFilter: false
                        )
                    } catch {
                        lastError = error
                    }
                }

                if shouldTryNextEndpointVersion(for: error) == false {
                    throw error
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Handles requestInventory.
    private func requestInventory(
        endpointVersion: ComputerInventoryEndpointVersion,
        sections: [ComputerInventorySection],
        query: String,
        fields: [ComputerField],
        useWildcardFilter: Bool
    ) async throws -> Data {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "page-size", value: "100"),
            URLQueryItem(name: "sort", value: "general.name:asc")
        ]

        for section in sections {
            queryItems.append(URLQueryItem(name: "section", value: section.rawValue))
        }

        let allowedSections = sections.isEmpty
            ? Set(ComputerInventorySection.allCases)
            : Set(sections)
        if query.isEmpty == false,
           let filter = buildFilterExpression(
               for: query,
               fields: fields,
               useWildcard: useWildcardFilter,
               allowedSections: allowedSections
           )
        {
            queryItems.append(URLQueryItem(name: "filter", value: filter))
        }

        return try await apiGateway.request(
            path: endpointVersion.path,
            method: .get,
            queryItems: queryItems
        )
    }

    /// Handles resolvedCatalogFields.
    private func resolvedCatalogFields(from selectedKeys: [String]) -> [ComputerField] {
        if selectedKeys.isEmpty {
            return ComputerField.defaultRSQLQueryFieldKeys.compactMap { ComputerField.keyLookup[$0] }
        }

        let resolved = selectedKeys.compactMap { ComputerField.keyLookup[$0] }
        if resolved.isEmpty {
            return ComputerField.defaultRSQLQueryFieldKeys.compactMap { ComputerField.keyLookup[$0] }
        }

        return resolved
    }

    /// Handles resolvedSections.
    private func resolvedSections(from fields: [ComputerField]) -> [ComputerInventorySection] {
        var sections = Set(fields.map(\.section))
        sections.insert(.general)
        return sections.sorted { $0.rawValue < $1.rawValue }
    }

    /// Handles buildFilterExpression.
    private func buildFilterExpression(
        for query: String,
        fields: [ComputerField],
        useWildcard: Bool,
        allowedSections: Set<ComputerInventorySection>
    ) -> String? {
        let candidateKeys = fields
            .filter { field in
                field.supportsRSQLSearch &&
                allowedSections.contains(field.section) &&
                supportedInventoryFilterKeys.contains(field.key)
            }
            .map(\.key)
        var prioritizedSourceKeys = candidateKeys.isEmpty ? privilegeFallbackFilterFieldKeys : candidateKeys

        for key in defaultIdentityFilterFieldKeys where prioritizedSourceKeys.contains(key) == false {
            prioritizedSourceKeys.append(key)
        }

        let prioritizedKeys = Array(prioritizedSourceKeys.prefix(12))
        let conditions = filterConditions(
            for: prioritizedKeys,
            query: query,
            useWildcard: useWildcard
        )

        if conditions.isEmpty == false {
            return "(\(conditions.joined(separator: ",")))"
        }

        if candidateKeys.isEmpty == false {
            var fallbackKeys = privilegeFallbackFilterFieldKeys
            for key in defaultIdentityFilterFieldKeys where fallbackKeys.contains(key) == false {
                fallbackKeys.append(key)
            }

            let fallbackConditions = filterConditions(
                for: Array(fallbackKeys.prefix(12)),
                query: query,
                useWildcard: useWildcard
            )

            if fallbackConditions.isEmpty == false {
                return "(\(fallbackConditions.joined(separator: ",")))"
            }
        }

        return nil
    }

    /// Handles privilegeFallbackFields.
    private func privilegeFallbackFields() -> [ComputerField] {
        privilegeFallbackFilterFieldKeys.compactMap { ComputerField.keyLookup[$0] }
    }

    /// Handles decodeSearchResults.
    private func decodeSearchResults(from data: Data) throws -> [ComputerRecord] {
        if let payload = try? decoder.decode(ComputerSearchResponse.self, from: data) {
            return payload.results
        }

        if let records = try? decoder.decode([ComputerRecord].self, from: data) {
            return records
        }

        throw JamfFrameworkError.decodingFailure
    }

    /// Handles resolvePrestageEnrollment.
    private func resolvePrestageEnrollment(
        for records: [ComputerRecord],
        query: String
    ) async -> [ComputerRecord] {
        let normalizedQuerySerial = normalizeSerial(query)
        let inventorySerials = Set(records.compactMap { normalizeSerial($0.serialNumber) })
        let scopeAssociations = await fetchComputerPrestageScopeAssociations(
            targetSerials: inventorySerials,
            querySerial: normalizedQuerySerial
        )

        var resolvedRecords: [ComputerRecord] = []
        resolvedRecords.reserveCapacity(records.count + scopeAssociations.count)
        var existingSerials = Set<String>()

        for record in records {
            let normalizedSerial = normalizeSerial(record.serialNumber)
            if let normalizedSerial {
                existingSerials.insert(normalizedSerial)
            }

            let association = normalizedSerial.flatMap { scopeAssociations[$0] }
            let resolvedRecord = await resolvePrestageEnrollment(for: record, scopeAssociation: association)
            resolvedRecords.append(resolvedRecord)
        }

        if let normalizedQuerySerial {
            let scopeOnlyAssociations = scopeAssociations.values
                .filter { association in
                    existingSerials.contains(association.serialNumber) == false &&
                        association.serialNumber.contains(normalizedQuerySerial)
                }
                .sorted { $0.serialNumber < $1.serialNumber }

            for association in scopeOnlyAssociations {
                resolvedRecords.append(makeScopeOnlyRecord(from: association))
            }
        }

        return resolvedRecords
    }

    /// Handles resolvePrestageEnrollment.
    private func resolvePrestageEnrollment(
        for record: ComputerRecord,
        scopeAssociation: ComputerPrestageScopeAssociation?
    ) async -> ComputerRecord {
        let resolvedStatus = normalizePrestageStatus(record.prestageEnrollmentStatus) ?? enrolledStatusLabel
        var resolvedName = normalizePrestageComponent(record.prestageEnrollmentProfileName)
        var resolvedID = normalizePrestageComponent(record.prestageEnrollmentProfileID)

        if let scopeAssociation {
            resolvedName = resolvedName ?? scopeAssociation.profileName
            resolvedID = resolvedID ?? scopeAssociation.profileID
        }

        if resolvedName == nil, let resolvedID, resolvedID.isEmpty == false {
            resolvedName = await resolveComputerPrestageName(forProfileID: resolvedID)
        }

        return record.withPrestageEnrollment(
            status: resolvedStatus,
            profileName: resolvedName,
            profileID: resolvedID
        )
    }

    /// Handles makeScopeOnlyRecord.
    private func makeScopeOnlyRecord(from association: ComputerPrestageScopeAssociation) -> ComputerRecord {
        ComputerRecord(
            id: "prestage-scope-\(association.serialNumber)-\(association.profileID)",
            computerName: association.serialNumber,
            serialNumber: association.serialNumber,
            udid: nil,
            model: nil,
            modelIdentifier: nil,
            osVersion: nil,
            osBuild: nil,
            lastIpAddress: nil,
            username: nil,
            email: nil,
            assetTag: nil,
            departmentID: nil,
            buildingID: nil,
            prestageEnrollmentStatus: notEnrolledStatusLabel,
            prestageEnrollmentProfileName: association.profileName,
            prestageEnrollmentProfileID: association.profileID
        )
    }

    /// Handles fetchComputerPrestageScopeAssociations.
    private func fetchComputerPrestageScopeAssociations(
        targetSerials: Set<String>,
        querySerial: String?
    ) async -> [String: ComputerPrestageScopeAssociation] {
        guard targetSerials.isEmpty == false || querySerial != nil else {
            return [:]
        }

        do {
            let prestages = try await fetchAllComputerPrestages()
            var associations: [String: ComputerPrestageScopeAssociation] = [:]

            for prestage in prestages {
                do {
                    let scopedSerials = try await fetchComputerPrestageScopeSerials(forPrestageID: prestage.id)
                    for serial in scopedSerials {
                        let matchesTarget = targetSerials.contains(serial)
                        let matchesQuery = querySerial.map { serial.contains($0) } ?? false
                        guard matchesTarget || matchesQuery else {
                            continue
                        }

                        if associations[serial] == nil {
                            associations[serial] = ComputerPrestageScopeAssociation(
                                serialNumber: serial,
                                profileID: prestage.id,
                                profileName: prestage.name
                            )
                        }
                    }
                } catch {
                    let description = describe(error)
                    await diagnosticsReporter.reportError(
                        source: moduleSource,
                        category: "prestage",
                        message: "Failed reading computer pre-stage scope assignments.",
                        errorDescription: description,
                        metadata: [
                            "prestage_profile_id": prestage.id
                        ]
                    )
                }
            }

            return associations
        } catch {
            let description = describe(error)
            await diagnosticsReporter.reportError(
                source: moduleSource,
                category: "prestage",
                message: "Failed reading computer pre-stage inventory.",
                errorDescription: description
            )
            return [:]
        }
    }

    /// Handles fetchAllComputerPrestages.
    private func fetchAllComputerPrestages() async throws -> [ComputerPrestageSummary] {
        let pageSize = 100
        var page = 0
        var prestages: [ComputerPrestageSummary] = []
        var seenIDs = Set<String>()

        while true {
            let data = try await apiGateway.request(
                path: "api/v2/computer-prestages",
                method: .get,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(pageSize))
                ]
            )

            let pagePrestages = parseComputerPrestageSummaries(from: data)
            let uniquePrestages = pagePrestages.filter { seenIDs.insert($0.id).inserted }
            prestages.append(contentsOf: uniquePrestages)

            if pagePrestages.isEmpty || pagePrestages.count < pageSize || uniquePrestages.isEmpty {
                break
            }

            page += 1
        }

        return prestages
    }

    /// Handles fetchComputerPrestageScopeSerials.
    private func fetchComputerPrestageScopeSerials(forPrestageID prestageID: String) async throws -> Set<String> {
        let pageSize = 100
        var page = 0
        var serials = Set<String>()

        while true {
            let data = try await apiGateway.request(
                path: "api/v2/computer-prestages/\(prestageID)/scope",
                method: .get,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(pageSize))
                ]
            )

            let pageSerials = parseComputerScopeSerials(from: data)
            let previousCount = serials.count
            serials.formUnion(pageSerials.compactMap(normalizeSerial))
            let appendedCount = serials.count - previousCount

            if pageSerials.isEmpty || pageSerials.count < pageSize || appendedCount == 0 {
                break
            }

            page += 1
        }

        return serials
    }

    /// Handles parseComputerPrestageSummaries.
    private func parseComputerPrestageSummaries(from data: Data) -> [ComputerPrestageSummary] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let dictionary = jsonObject as? [String: Any] {
            let candidateArrays: [Any?] = [
                dictionary["results"],
                dictionary["prestages"],
                dictionary["computerPrestages"],
                dictionary["items"],
                dictionary["data"]
            ]

            for candidate in candidateArrays {
                guard let objects = dictionaryArray(from: candidate), objects.isEmpty == false else {
                    continue
                }

                let parsed = objects.compactMap(parseComputerPrestageSummary(from:))
                if parsed.isEmpty == false {
                    return parsed
                }
            }

            for nestedValue in dictionary.values {
                guard let objects = dictionaryArray(from: nestedValue), objects.isEmpty == false else {
                    continue
                }

                let parsed = objects.compactMap(parseComputerPrestageSummary(from:))
                if parsed.isEmpty == false {
                    return parsed
                }
            }
        }

        guard let objects = dictionaryArray(from: jsonObject) else {
            return []
        }

        return objects.compactMap(parseComputerPrestageSummary(from:))
    }

    /// Handles parseComputerPrestageSummary.
    private func parseComputerPrestageSummary(from item: [String: Any]) -> ComputerPrestageSummary? {
        guard let id = extractString(from: item["id"]) ?? extractString(from: item["prestageId"]) else {
            return nil
        }

        let name =
            extractString(from: item["displayName"]) ??
            extractString(from: item["name"]) ??
            extractString(from: item["profileName"]) ??
            "Pre-Stage \(id)"

        return ComputerPrestageSummary(id: id, name: name)
    }

    /// Handles parseComputerScopeSerials.
    private func parseComputerScopeSerials(from data: Data) -> [String] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let dictionary = jsonObject as? [String: Any] {
            let objectCandidates: [Any?] = [
                dictionary["assignments"],
                dictionary["results"],
                dictionary["devices"],
                dictionary["computers"],
                dictionary["items"],
                dictionary["data"]
            ]

            for candidate in objectCandidates {
                guard let objects = dictionaryArray(from: candidate), objects.isEmpty == false else {
                    continue
                }

                let serials = objects.compactMap(parseComputerScopeSerial(from:))
                if serials.isEmpty == false {
                    return serials
                }
            }

            for nestedValue in dictionary.values {
                guard let objects = dictionaryArray(from: nestedValue), objects.isEmpty == false else {
                    continue
                }

                let serials = objects.compactMap(parseComputerScopeSerial(from:))
                if serials.isEmpty == false {
                    return serials
                }
            }

            if let serialNumbers =
                extractStringArray(from: dictionary["serialNumbers"]) ??
                extractStringArray(from: (dictionary["assignments"] as? [String: Any])?["serialNumbers"])
            {
                return serialNumbers.compactMap(normalizeSerial)
            }
        }

        if let objects = dictionaryArray(from: jsonObject), objects.isEmpty == false {
            return objects.compactMap(parseComputerScopeSerial(from:))
        }

        if let serialNumbers = extractStringArray(from: jsonObject) {
            return serialNumbers.compactMap(normalizeSerial)
        }

        return []
    }

    /// Handles parseComputerScopeSerial.
    private func parseComputerScopeSerial(from item: [String: Any]) -> String? {
        var serial =
            extractString(from: item["serialNumber"]) ??
            extractString(from: item["serial"]) ??
            extractString(from: item["hardwareSerialNumber"])

        let nestedKeys = ["computer", "device", "inventoryRecord", "inventory", "item"]
        for key in nestedKeys {
            guard let nested = item[key] as? [String: Any] else {
                continue
            }

            serial = serial ??
                extractString(from: nested["serialNumber"]) ??
                extractString(from: nested["serial"])
        }

        if serial == nil {
            serial = extractValue(matching: "serial", in: item)
        }

        return normalizeSerial(serial)
    }

    /// Handles resolveComputerPrestageName.
    private func resolveComputerPrestageName(forProfileID profileID: String) async -> String? {
        if let cached = computerPrestageNameCache[profileID] {
            return cached
        }

        do {
            let profileData = try await apiGateway.request(
                path: "api/v2/computer-prestages/\(profileID)",
                method: .get
            )

            if let profileName = extractProfileName(fromPrestageDetails: profileData) {
                computerPrestageNameCache[profileID] = profileName
                return profileName
            }
        } catch {
            let description = describe(error)
            await diagnosticsReporter.reportError(
                source: moduleSource,
                category: "prestage",
                message: "Failed reading computer pre-stage profile details.",
                errorDescription: description,
                metadata: [
                    "prestage_profile_id": profileID
                ]
            )
        }

        return nil
    }

    /// Handles filterConditions.
    private func filterConditions(
        for keys: [String],
        query: String,
        useWildcard: Bool
    ) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return []
        }

        let escapedQuery = escapeRSQLString(trimmedQuery)
        let queryValue = useWildcard ? "*\(escapedQuery)*" : escapedQuery
        let booleanLiteral = booleanLiteral(from: trimmedQuery)
        let numericLiteral = numericLiteral(from: trimmedQuery)

        return keys.compactMap { key in
            if textualInventoryFilterKeys.contains(key) {
                return "\(key)==\"\(queryValue)\""
            }

            if booleanInventoryFilterKeys.contains(key),
               let booleanLiteral
            {
                return "\(key)==\(booleanLiteral)"
            }

            if numericInventoryFilterKeys.contains(key),
               let numericLiteral
            {
                return "\(key)==\(numericLiteral)"
            }

            return nil
        }
    }

    /// Handles escapeRSQLString.
    private func escapeRSQLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Handles booleanLiteral.
    private func booleanLiteral(from value: String) -> String? {
        switch value.lowercased() {
        case "true", "yes", "1":
            return "true"
        case "false", "no", "0":
            return "false"
        default:
            return nil
        }
    }

    /// Handles numericLiteral.
    private func numericLiteral(from value: String) -> String? {
        guard value.isEmpty == false,
              value.allSatisfy({ $0.isNumber }) else {
            return nil
        }

        return value
    }

    /// Handles normalizePrestageComponent.
    private func normalizePrestageComponent(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Handles normalizePrestageStatus.
    private func normalizePrestageStatus(_ value: String?) -> String? {
        guard let normalized = normalizePrestageComponent(value) else {
            return nil
        }

        switch normalized.lowercased() {
        case "true", "managed", "enrolled":
            return enrolledStatusLabel
        case "false", "unmanaged", "not enrolled":
            return notEnrolledStatusLabel
        default:
            if normalized.lowercased().contains("not enrolled") ||
                normalized.lowercased().contains("unmanaged")
            {
                return notEnrolledStatusLabel
            }

            if normalized.lowercased().contains("enrolled") ||
                normalized.lowercased().contains("managed")
            {
                return enrolledStatusLabel
            }

            return normalized
        }
    }

    /// Handles normalizeSerial.
    private func normalizeSerial(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        return trimmed.uppercased()
    }

    /// Handles dictionaryArray.
    private func dictionaryArray(from value: Any?) -> [[String: Any]]? {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }

        if let array = value as? [Any] {
            let dictionaries = array.compactMap { $0 as? [String: Any] }
            return dictionaries.isEmpty ? nil : dictionaries
        }

        if let dictionary = value as? [String: Any] {
            return
                dictionaryArray(from: dictionary["results"]) ??
                dictionaryArray(from: dictionary["items"]) ??
                dictionaryArray(from: dictionary["assignments"]) ??
                dictionaryArray(from: dictionary["devices"]) ??
                dictionaryArray(from: dictionary["computers"]) ??
                dictionaryArray(from: dictionary["data"])
        }

        return nil
    }

    /// Handles extractString.
    private func extractString(from value: Any?) -> String? {
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
        case let numberValue as NSNumber:
            return numberValue.stringValue
        case let dictionary as [String: Any]:
            return
                extractString(from: dictionary["displayName"]) ??
                extractString(from: dictionary["name"]) ??
                extractString(from: dictionary["value"]) ??
                extractString(from: dictionary["id"])
        case let array as [Any]:
            let flattened = array.compactMap { extractString(from: $0) }
                .filter { $0.isEmpty == false }
            return flattened.isEmpty ? nil : flattened.joined(separator: ", ")
        default:
            return nil
        }
    }

    /// Handles extractStringArray.
    private func extractStringArray(from value: Any?) -> [String]? {
        if let strings = value as? [String] {
            let cleaned = strings.compactMap { extractString(from: $0) }
            return cleaned.isEmpty ? nil : cleaned
        }

        if let array = value as? [Any] {
            let cleaned = array.compactMap { extractString(from: $0) }
            return cleaned.isEmpty ? nil : cleaned
        }

        if let dictionary = value as? [String: Any] {
            return
                extractStringArray(from: dictionary["serialNumbers"]) ??
                extractStringArray(from: dictionary["serials"]) ??
                extractStringArray(from: dictionary["items"]) ??
                extractStringArray(from: dictionary["values"])
        }

        return nil
    }

    /// Handles extractValue.
    private func extractValue(matching keyFragment: String, in dictionary: [String: Any]) -> String? {
        for (key, value) in dictionary {
            if key.localizedCaseInsensitiveContains(keyFragment),
               let extracted = extractString(from: value)
            {
                return extracted
            }

            if let nestedDictionary = value as? [String: Any],
               let nestedValue = extractValue(matching: keyFragment, in: nestedDictionary)
            {
                return nestedValue
            }
        }

        return nil
    }

    /// Handles extractProfileName.
    private func extractProfileName(fromPrestageDetails data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return extractProfileName(from: json)
    }

    /// Handles extractProfileName.
    private func extractProfileName(from value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if let directName =
                extractString(from: dictionary["displayName"]) ??
                extractString(from: dictionary["name"]) ??
                extractString(from: dictionary["profileName"])
            {
                return directName
            }

            for nestedValue in dictionary.values {
                if let nestedName = extractProfileName(from: nestedValue) {
                    return nestedName
                }
            }
        }

        if let array = value as? [Any] {
            for element in array {
                if let nestedName = extractProfileName(from: element) {
                    return nestedName
                }
            }
        }

        return nil
    }

    /// Handles describe.
    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Handles userFacingSearchErrorMessage.
    private func userFacingSearchErrorMessage(for error: any Error) -> String {
        if case let JamfFrameworkError.networkFailure(statusCode, message) = error,
           statusCode == 403,
           message.localizedCaseInsensitiveContains("INVALID_PRIVILEGE") {
            return "Computer search was denied by Jamf for at least one requested inventory section. Verify API Role privileges for Computer Inventory sections and Read Computers access."
        }

        return describe(error)
    }

    /// Handles isInvalidPrivilegeError.
    private func isInvalidPrivilegeError(_ error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, message) = error else {
            return false
        }

        return statusCode == 403 && message.localizedCaseInsensitiveContains("INVALID_PRIVILEGE")
    }

    /// Handles shouldTryNextEndpointVersion.
    private func shouldTryNextEndpointVersion(for error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, _) = error else {
            return false
        }

        return statusCode == 400 || statusCode == 403 || statusCode == 404
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

}

//endofline
