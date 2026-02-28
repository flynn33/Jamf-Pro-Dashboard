import Foundation
import Combine

@MainActor
/// MobileDeviceSearchViewModel declaration.
final class MobileDeviceSearchViewModel: ObservableObject {
    /// MobilePrestageSummary declaration.
    private struct MobilePrestageSummary: Sendable {
        let id: String
        let name: String
    }

    /// MobilePrestageScopeAssociation declaration.
    private struct MobilePrestageScopeAssociation: Sendable {
        let serialNumber: String
        let profileID: String
        let profileName: String
    }

    @Published var query = ""
    @Published private(set) var profiles: [MobileDeviceSearchProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var selectedFieldKeys: Set<String> = []

    @Published private(set) var searchResults: [MobileDeviceRecord] = []
    @Published private(set) var isSearching = false

    @Published var isFieldCatalogPresented = false
    @Published var isSaveProfilePromptPresented = false
    @Published var pendingProfileName = ""

    @Published var errorMessage: String?

    private let apiGateway: JamfAPIGateway
    private let diagnosticsReporter: any DiagnosticsReporting
    private let profileStore: MobileDeviceSearchProfileStore
    private let moduleSource = "module.mobile-device-search"
    private let prestageFieldKey = "prestageEnrollmentProfile"
    private let sortFieldKey = "displayName"
    private let sectionParameterName = "section"
    private let sectionParameterTypeErrorCode = "INVALID_REQUEST_PARAMETER_TYPE"
    private let enrolledStatusLabel = "Enrolled"
    private let notEnrolledStatusLabel = "Not Enrolled"
    private var prestageNameCache: [String: String] = [:]

    /// SectionEncodingMode declaration.
    private enum SectionEncodingMode {
        case modern
        case legacy
        case none
    }

    /// Initializes the instance.
    init(
        apiGateway: JamfAPIGateway,
        diagnosticsReporter: any DiagnosticsReporting,
        profileStore: MobileDeviceSearchProfileStore = MobileDeviceSearchProfileStore()
    ) {
        self.apiGateway = apiGateway
        self.diagnosticsReporter = diagnosticsReporter
        self.profileStore = profileStore
    }

    var selectedProfile: MobileDeviceSearchProfile? {
        guard let selectedProfileID else {
            return nil
        }

        return profiles.first(where: { $0.id == selectedProfileID })
    }

    var resultFields: [MobileDeviceField] {
        let selectedKeys = activeFieldKeys()
        return resolvedCatalogFields(from: selectedKeys)
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
            let profile = MobileDeviceSearchProfile(name: profileName, fieldKeys: sortedFieldKeys)
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

        let selectedKeys = activeFieldKeys()
        let activeFields = resolvedCatalogFields(from: selectedKeys)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sections = resolvedSections(from: activeFields, includesQuery: trimmedQuery.isEmpty == false)
        let shouldResolvePrestage =
            activeFields.contains(where: { $0.key == prestageFieldKey }) ||
            trimmedQuery.isEmpty == false

        do {
            let data = try await requestInventory(
                sections: sections,
                query: trimmedQuery,
                useWildcardFilter: true
            )

            let decodedResults = try decodeSearchResults(from: data, requestedFields: activeFields)
            let resolvedResults: [MobileDeviceRecord]
            if shouldResolvePrestage {
                resolvedResults = await resolvePrestageEnrollmentProfiles(
                    for: decodedResults,
                    query: trimmedQuery
                )
            } else {
                resolvedResults = decodedResults
            }

            searchResults = resolvedResults
            errorMessage = nil
            reportEvent(
                severity: .info,
                category: "search",
                message: "Mobile device search completed.",
                metadata: [
                    "result_count": String(searchResults.count),
                    "has_query": trimmedQuery.isEmpty ? "false" : "true",
                    "field_count": String(activeFields.count),
                    "section_count": String(sections.count),
                    "prestage_requested": shouldResolvePrestage ? "true" : "false"
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
                        useWildcardFilter: false
                    )

                    let fallbackResults = try decodeSearchResults(
                        from: fallbackData,
                        requestedFields: activeFields
                    )

                    let resolvedResults: [MobileDeviceRecord]
                    if shouldResolvePrestage {
                        resolvedResults = await resolvePrestageEnrollmentProfiles(
                            for: fallbackResults,
                            query: trimmedQuery
                        )
                    } else {
                        resolvedResults = fallbackResults
                    }

                    searchResults = resolvedResults
                    errorMessage = nil
                    reportEvent(
                        severity: .warning,
                        category: "search",
                        message: "Mobile device search completed using exact-match fallback.",
                        metadata: [
                            "result_count": String(searchResults.count),
                            "has_query": "true",
                            "field_count": String(activeFields.count),
                            "section_count": String(sections.count),
                            "prestage_requested": shouldResolvePrestage ? "true" : "false"
                        ]
                    )
                    return
                } catch {
                    let description = describe(error)
                    errorMessage = userFacingSearchErrorMessage(for: error)
                    reportError(
                        category: "search",
                        message: "Mobile device search failed after exact-match fallback.",
                        errorDescription: description,
                        metadata: [
                            "has_query": "true",
                            "field_count": String(activeFields.count),
                            "section_count": String(sections.count),
                            "prestage_requested": shouldResolvePrestage ? "true" : "false"
                        ]
                    )
                    return
                }
            }

            let description = describe(error)
            errorMessage = userFacingSearchErrorMessage(for: error)
            reportError(
                category: "search",
                message: "Mobile device search failed.",
                errorDescription: description,
                metadata: [
                    "has_query": trimmedQuery.isEmpty ? "false" : "true",
                    "field_count": String(activeFields.count),
                    "section_count": String(sections.count),
                    "prestage_requested": shouldResolvePrestage ? "true" : "false"
                ]
            )
        }
    }

    /// Handles requestInventory.
    private func requestInventory(
        sections: [MobileDeviceInventorySection],
        query: String,
        useWildcardFilter: Bool
    ) async throws -> Data {
        let filterExpressions = buildFilterExpressions(
            for: query,
            useWildcard: useWildcardFilter
        )
        if filterExpressions.isEmpty {
            return try await requestInventoryWithSectionFallback(
                sections: sections,
                filterExpression: nil,
            )
        }

        var lastError: (any Error)?
        for filterExpression in filterExpressions {
            do {
                return try await requestInventoryWithSectionFallback(
                    sections: sections,
                    filterExpression: filterExpression
                )
            } catch {
                lastError = error
                guard shouldRetryWithNextFilter(after: error) else {
                    throw error
                }

                reportEvent(
                    severity: .warning,
                    category: "search",
                    message: "Retrying mobile device search with alternate filter fields.",
                    metadata: [
                        "filter_length": String(filterExpression.count)
                    ]
                )
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Handles requestInventoryWithSectionFallback.
    private func requestInventoryWithSectionFallback(
        sections: [MobileDeviceInventorySection],
        filterExpression: String?
    ) async throws -> Data {
        do {
            return try await requestInventory(
                sections: sections,
                filterExpression: filterExpression,
                sectionEncodingMode: .modern
            )
        } catch {
            guard isSectionParameterError(error) else {
                throw error
            }

            do {
                reportEvent(
                    severity: .warning,
                    category: "search",
                    message: "Retrying mobile device search with legacy inventory section names.",
                    metadata: [
                        "section_count": String(sections.count)
                    ]
                )

                return try await requestInventory(
                    sections: sections,
                    filterExpression: filterExpression,
                    sectionEncodingMode: .legacy
                )
            } catch {
                guard isSectionParameterError(error) else {
                    throw error
                }

                reportEvent(
                    severity: .warning,
                    category: "search",
                    message: "Retrying mobile device search without inventory section parameters.",
                    metadata: [
                        "section_count": String(sections.count)
                    ]
                )

                return try await requestInventory(
                    sections: sections,
                    filterExpression: filterExpression,
                    sectionEncodingMode: .none
                )
            }
        }
    }

    /// Handles requestInventory.
    private func requestInventory(
        sections: [MobileDeviceInventorySection],
        filterExpression: String?,
        sectionEncodingMode: SectionEncodingMode
    ) async throws -> Data {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "page-size", value: "100"),
            URLQueryItem(name: "sort", value: "\(sortFieldKey):asc")
        ]

        if sectionEncodingMode != .none {
            queryItems.append(
                contentsOf: sectionQueryItems(
                    for: sections,
                    useLegacyNames: sectionEncodingMode == .legacy
                )
            )
        }

        if let filterExpression {
            queryItems.append(URLQueryItem(name: "filter", value: filterExpression))
        }

        return try await apiGateway.request(
            path: "api/v2/mobile-devices/detail",
            method: .get,
            queryItems: queryItems
        )
    }

    /// Handles sectionQueryItems.
    private func sectionQueryItems(
        for sections: [MobileDeviceInventorySection],
        useLegacyNames: Bool
    ) -> [URLQueryItem] {
        sections.map { section in
            let value = useLegacyNames ? legacySectionParameterValue(for: section) : section.rawValue
            return URLQueryItem(name: sectionParameterName, value: value)
        }
    }

    /// Handles legacySectionParameterValue.
    private func legacySectionParameterValue(for section: MobileDeviceInventorySection) -> String {
        switch section {
        case .general:
            return "GENERAL"
        case .location:
            return "LOCATION"
        case .hardware:
            return "HARDWARE"
        case .purchasing:
            return "PURCHASING"
        case .security:
            return "SECURITY"
        case .applications:
            return "APPLICATIONS"
        case .ebooks:
            return "EBOOKS"
        case .network:
            return "NETWORK"
        case .serviceSubscriptions:
            return "SERVICE_SUBSCRIPTIONS"
        case .certificates:
            return "CERTIFICATES"
        case .configurationProfiles:
            return "CONFIGURATION_PROFILES"
        case .userProfiles:
            return "USER_PROFILES"
        case .provisioningProfiles:
            return "PROVISIONING_PROFILES"
        case .sharedUsers:
            return "SHARED_USERS"
        case .extensionAttributes:
            return "EXTENSION_ATTRIBUTES"
        case .mobileDeviceGroups:
            return "MOBILE_DEVICE_GROUPS"
        }
    }

    /// Handles resolvedCatalogFields.
    private func resolvedCatalogFields(from selectedKeys: [String]) -> [MobileDeviceField] {
        let defaultFields = MobileDeviceField.defaultResultFieldKeys.compactMap { MobileDeviceField.keyLookup[$0] }

        guard selectedKeys.isEmpty == false else {
            return defaultFields
        }

        let resolved = selectedKeys.compactMap { MobileDeviceField.keyLookup[$0] }
        if resolved.isEmpty {
            return defaultFields
        }

        return resolved
    }

    /// Handles activeFieldKeys.
    private func activeFieldKeys() -> [String] {
        let liveSelection = Array(selectedFieldKeys).sorted()
        if liveSelection.isEmpty == false {
            return liveSelection
        }

        return selectedProfile?.fieldKeys ?? []
    }

    /// Handles resolvedSections.
    private func resolvedSections(
        from fields: [MobileDeviceField],
        includesQuery: Bool
    ) -> [MobileDeviceInventorySection] {
        var sections = Set(fields.map(\.section))
        sections.insert(.general)

        if includesQuery {
            sections.insert(.location)
        }

        return sections.sorted { $0.rawValue < $1.rawValue }
    }

    /// Handles buildFilterExpressions.
    private func buildFilterExpressions(for query: String, useWildcard: Bool) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return []
        }

        let escapedQuery = escapeRSQLString(trimmedQuery)
        let queryValue = useWildcard ? "*\(escapedQuery)*" : escapedQuery

        let fieldCandidates: [[String]] = [
            // Denormalized fields are required by /api/v2/mobile-devices/detail on newer tenants.
            [
                "serialNumber",
                "displayName",
                "username",
                "fullName",
                "emailAddress"
            ],
            // Compatibility fallback for tenants returning nested structures.
            [
                "hardware.serialNumber",
                "general.displayName",
                "userAndLocation.username",
                "userAndLocation.emailAddress"
            ]
        ]

        return fieldCandidates.map { fields in
            let conditions = fields.map { "\($0)=='\(queryValue)'" }
            return "(\(conditions.joined(separator: ",")))"
        }
    }

    /// Handles escapeRSQLString.
    private func escapeRSQLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    /// Handles decodeSearchResults.
    private func decodeSearchResults(
        from data: Data,
        requestedFields: [MobileDeviceField]
    ) throws -> [MobileDeviceRecord] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let objects = dictionaryArray(from: jsonObject)
        else {
            throw JamfFrameworkError.decodingFailure
        }

        return objects.map { dictionary in
            parseRecord(from: dictionary, requestedFields: requestedFields)
        }
    }

    /// Handles parseRecord.
    private func parseRecord(
        from dictionary: [String: Any],
        requestedFields: [MobileDeviceField]
    ) -> MobileDeviceRecord {
        let id =
            extractValue(using: ["id", "mobileDeviceId", "deviceId", "hardware.deviceId"], from: dictionary) ??
            UUID().uuidString

        let deviceName =
            extractValue(
                using: [
                    "general.displayName",
                    "general.deviceName",
                    "general.name",
                    "deviceName",
                    "displayName",
                    "name"
                ],
                from: dictionary
            ) ??
            "Unknown Device"

        let serialNumber =
            extractValue(using: ["hardware.serialNumber", "general.serialNumber", "serialNumber"], from: dictionary) ??
            "Unknown"

        let udid = extractValue(using: ["general.udid", "udid"], from: dictionary)
        let model = extractValue(
            using: [
                "hardware.model",
                "general.model",
                "model",
                "hardware.modelIdentifier",
                "general.modelIdentifier",
                "modelIdentifier"
            ],
            from: dictionary
        )
        let osVersion = extractValue(using: ["general.osVersion", "osVersion"], from: dictionary)

        let prestage = extractPrestageNameAndID(from: dictionary)
        let prestageStatus =
            normalizePrestageStatus(extractPrestageEnrollmentStatus(from: dictionary)) ??
            enrolledStatusLabel
        let prestageDisplayValue = MobileDeviceRecord.prestageDisplayValue(
            status: prestageStatus,
            profileName: prestage.name,
            profileID: prestage.id
        )

        var fieldValues: [String: String] = [:]

        for field in requestedFields {
            let resolvedValue: String?
            if field.key == prestageFieldKey {
                resolvedValue = prestageDisplayValue
            } else {
                resolvedValue = extractValue(using: field.responsePaths, from: dictionary)
            }

            if let resolvedValue, resolvedValue.isEmpty == false {
                fieldValues[field.key] = resolvedValue
            }
        }

        fieldValues["id"] = fieldValues["id"] ?? id
        fieldValues["deviceName"] = fieldValues["deviceName"] ?? deviceName
        fieldValues["serialNumber"] = fieldValues["serialNumber"] ?? serialNumber

        if let udid, udid.isEmpty == false {
            fieldValues["udid"] = fieldValues["udid"] ?? udid
        }

        if let model, model.isEmpty == false {
            fieldValues["model"] = fieldValues["model"] ?? model
        }

        if let osVersion, osVersion.isEmpty == false {
            fieldValues["osVersion"] = fieldValues["osVersion"] ?? osVersion
        }

        if let prestageDisplayValue, prestageDisplayValue.isEmpty == false {
            fieldValues[prestageFieldKey] = fieldValues[prestageFieldKey] ?? prestageDisplayValue
        }

        return MobileDeviceRecord(
            id: id,
            deviceName: deviceName,
            serialNumber: serialNumber,
            udid: udid,
            model: model,
            osVersion: osVersion,
            prestageEnrollmentStatus: prestageStatus,
            prestageEnrollmentProfileName: prestage.name,
            prestageEnrollmentProfileID: prestage.id,
            fieldValues: fieldValues
        )
    }

    /// Handles dictionaryArray.
    private func dictionaryArray(from value: Any?) -> [[String: Any]]? {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }

        if let array = value as? [Any] {
            let dictionaries = array.compactMap { $0 as? [String: Any] }
            if dictionaries.isEmpty == false {
                return dictionaries
            }

            for element in array {
                if let nested = dictionaryArray(from: element), nested.isEmpty == false {
                    return nested
                }
            }

            return []
        }

        if let dictionary = value as? [String: Any] {
            let candidateKeys = ["results", "mobileDevices", "devices", "items", "data"]

            for key in candidateKeys {
                guard dictionary.keys.contains(key) else {
                    continue
                }

                if let nested = dictionaryArray(from: dictionary[key]) {
                    return nested
                }
            }

            for nestedValue in dictionary.values {
                if let nested = dictionaryArray(from: nestedValue), nested.isEmpty == false {
                    return nested
                }
            }
        }

        return nil
    }

    /// Handles extractValue.
    private func extractValue(using paths: [String], from dictionary: [String: Any]) -> String? {
        for path in paths {
            guard let resolved = resolveValue(atPath: path, in: dictionary),
                  let stringValue = extractString(from: resolved)
            else {
                continue
            }

            return stringValue
        }

        return nil
    }

    /// Handles resolveValue.
    private func resolveValue(atPath path: String, in dictionary: [String: Any]) -> Any? {
        let components = path
            .split(separator: ".")
            .map(String.init)

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
                let mappedValues = currentArray.compactMap { element -> Any? in
                    (element as? [String: Any])?[component]
                }

                guard mappedValues.isEmpty == false else {
                    return nil
                }

                current = mappedValues.count == 1 ? mappedValues[0] : mappedValues
                continue
            }

            return nil
        }

        return current
    }

    /// Handles resolvePrestageEnrollmentProfiles.
    private func resolvePrestageEnrollmentProfiles(
        for records: [MobileDeviceRecord],
        query: String
    ) async -> [MobileDeviceRecord] {
        let normalizedQuerySerial = normalizeSerial(query)
        let inventorySerials = Set(records.compactMap { normalizeSerial($0.serialNumber) })
        let scopeAssociations = await fetchMobilePrestageScopeAssociations(
            targetSerials: inventorySerials,
            querySerial: normalizedQuerySerial
        )

        var resolvedRecords: [MobileDeviceRecord] = []
        resolvedRecords.reserveCapacity(records.count + scopeAssociations.count)
        var existingSerials = Set<String>()

        for record in records {
            let normalizedSerial = normalizeSerial(record.serialNumber)
            if let normalizedSerial {
                existingSerials.insert(normalizedSerial)
            }

            let scopeAssociation = normalizedSerial.flatMap { scopeAssociations[$0] }
            let resolved = await resolvePrestageEnrollmentProfile(
                for: record,
                scopeAssociation: scopeAssociation
            )
            resolvedRecords.append(resolved)
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

    /// Handles resolvePrestageEnrollmentProfile.
    private func resolvePrestageEnrollmentProfile(
        for record: MobileDeviceRecord,
        scopeAssociation: MobilePrestageScopeAssociation?
    ) async -> MobileDeviceRecord {
        var resolvedStatus = normalizePrestageStatus(record.prestageEnrollmentStatus) ?? enrolledStatusLabel
        var resolvedName = normalizePrestageComponent(record.prestageEnrollmentProfileName)
        var resolvedID = normalizePrestageComponent(record.prestageEnrollmentProfileID)

        if let scopeAssociation {
            resolvedName = resolvedName ?? scopeAssociation.profileName
            resolvedID = resolvedID ?? scopeAssociation.profileID
        }

        if resolvedName == nil, let resolvedID, resolvedID.isEmpty == false {
            resolvedName = await resolvePrestageName(forProfileID: resolvedID)
        }

        if resolvedName != nil || resolvedID != nil {
            return record.withPrestageEnrollment(
                profileName: resolvedName,
                profileID: resolvedID,
                status: resolvedStatus
            )
        }

        let deviceID = record.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard deviceID.isEmpty == false else {
            return record.withPrestageEnrollment(profileName: nil, profileID: nil, status: resolvedStatus)
        }

        do {
            let detailData = try await apiGateway.request(
                path: "api/v2/mobile-devices/\(deviceID)/detail",
                method: .get
            )

            let extracted = extractPrestageNameAndID(from: detailData)
            let detailStatus = normalizePrestageStatus(extractPrestageEnrollmentStatus(from: detailData))

            resolvedStatus = detailStatus ?? resolvedStatus
            resolvedName = resolvedName ?? extracted.name
            resolvedID = resolvedID ?? extracted.id

            if resolvedName == nil, let resolvedID, resolvedID.isEmpty == false {
                resolvedName = await resolvePrestageName(forProfileID: resolvedID)
            }

            return record.withPrestageEnrollment(
                profileName: resolvedName,
                profileID: resolvedID,
                status: resolvedStatus
            )
        } catch {
            let description = describe(error)
            await diagnosticsReporter.reportError(
                source: moduleSource,
                category: "prestage",
                message: "Failed to resolve Pre-Stage Enrollment profile for a device.",
                errorDescription: description,
                metadata: [
                    "device_id": deviceID
                ]
            )
            return record.withPrestageEnrollment(profileName: nil, profileID: nil, status: resolvedStatus)
        }
    }

    /// Handles makeScopeOnlyRecord.
    private func makeScopeOnlyRecord(from association: MobilePrestageScopeAssociation) -> MobileDeviceRecord {
        let recordID = "prestage-scope-\(association.serialNumber)-\(association.profileID)"
        var fieldValues: [String: String] = [
            "id": recordID,
            "deviceName": association.serialNumber,
            "serialNumber": association.serialNumber
        ]

        if let displayValue = MobileDeviceRecord.prestageDisplayValue(
            status: notEnrolledStatusLabel,
            profileName: association.profileName,
            profileID: association.profileID
        ) {
            fieldValues[prestageFieldKey] = displayValue
        }

        return MobileDeviceRecord(
            id: recordID,
            deviceName: association.serialNumber,
            serialNumber: association.serialNumber,
            udid: nil,
            model: nil,
            osVersion: nil,
            prestageEnrollmentStatus: notEnrolledStatusLabel,
            prestageEnrollmentProfileName: association.profileName,
            prestageEnrollmentProfileID: association.profileID,
            fieldValues: fieldValues
        )
    }

    /// Handles fetchMobilePrestageScopeAssociations.
    private func fetchMobilePrestageScopeAssociations(
        targetSerials: Set<String>,
        querySerial: String?
    ) async -> [String: MobilePrestageScopeAssociation] {
        guard targetSerials.isEmpty == false || querySerial != nil else {
            return [:]
        }

        do {
            let prestages = try await fetchAllMobilePrestages()
            var associations: [String: MobilePrestageScopeAssociation] = [:]

            for prestage in prestages {
                do {
                    let scopedSerials = try await fetchMobilePrestageScopeSerials(forPrestageID: prestage.id)
                    for serial in scopedSerials {
                        let matchesTarget = targetSerials.contains(serial)
                        let matchesQuery = querySerial.map { serial.contains($0) } ?? false
                        guard matchesTarget || matchesQuery else {
                            continue
                        }

                        if associations[serial] == nil {
                            associations[serial] = MobilePrestageScopeAssociation(
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
                        message: "Failed reading mobile pre-stage scope assignments.",
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
                message: "Failed reading mobile pre-stage inventory.",
                errorDescription: description
            )
            return [:]
        }
    }

    /// Handles fetchAllMobilePrestages.
    private func fetchAllMobilePrestages() async throws -> [MobilePrestageSummary] {
        let pageSize = 100
        var page = 0
        var prestages: [MobilePrestageSummary] = []
        var seenIDs = Set<String>()

        while true {
            let data = try await apiGateway.request(
                path: "api/v2/mobile-device-prestages",
                method: .get,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(pageSize))
                ]
            )

            let pagePrestages = parseMobilePrestageSummaries(from: data)
            let uniquePrestages = pagePrestages.filter { seenIDs.insert($0.id).inserted }
            prestages.append(contentsOf: uniquePrestages)

            if pagePrestages.isEmpty || pagePrestages.count < pageSize || uniquePrestages.isEmpty {
                break
            }

            page += 1
        }

        return prestages
    }

    /// Handles fetchMobilePrestageScopeSerials.
    private func fetchMobilePrestageScopeSerials(forPrestageID prestageID: String) async throws -> Set<String> {
        let pageSize = 100
        var page = 0
        var serials = Set<String>()

        while true {
            let data = try await apiGateway.request(
                path: "api/v2/mobile-device-prestages/\(prestageID)/scope",
                method: .get,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(pageSize))
                ]
            )

            let pageSerials = parseMobileScopeSerials(from: data)
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

    /// Handles parseMobilePrestageSummaries.
    private func parseMobilePrestageSummaries(from data: Data) -> [MobilePrestageSummary] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let dictionary = jsonObject as? [String: Any] {
            let candidateArrays: [Any?] = [
                dictionary["results"],
                dictionary["prestages"],
                dictionary["mobileDevicePrestages"],
                dictionary["items"],
                dictionary["data"]
            ]

            for candidate in candidateArrays {
                guard let objects = dictionaryArray(from: candidate), objects.isEmpty == false else {
                    continue
                }

                let parsed = objects.compactMap(parseMobilePrestageSummary(from:))
                if parsed.isEmpty == false {
                    return parsed
                }
            }

            for nestedValue in dictionary.values {
                guard let objects = dictionaryArray(from: nestedValue), objects.isEmpty == false else {
                    continue
                }

                let parsed = objects.compactMap(parseMobilePrestageSummary(from:))
                if parsed.isEmpty == false {
                    return parsed
                }
            }
        }

        guard let objects = dictionaryArray(from: jsonObject) else {
            return []
        }

        return objects.compactMap(parseMobilePrestageSummary(from:))
    }

    /// Handles parseMobilePrestageSummary.
    private func parseMobilePrestageSummary(from item: [String: Any]) -> MobilePrestageSummary? {
        guard let id = extractString(from: item["id"]) ?? extractString(from: item["prestageId"]) else {
            return nil
        }

        let name =
            extractString(from: item["displayName"]) ??
            extractString(from: item["name"]) ??
            extractString(from: item["profileName"]) ??
            "Pre-Stage \(id)"

        return MobilePrestageSummary(id: id, name: name)
    }

    /// Handles parseMobileScopeSerials.
    private func parseMobileScopeSerials(from data: Data) -> [String] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let dictionary = jsonObject as? [String: Any] {
            let objectCandidates: [Any?] = [
                dictionary["assignments"],
                dictionary["results"],
                dictionary["devices"],
                dictionary["mobileDevices"],
                dictionary["items"],
                dictionary["data"]
            ]

            for candidate in objectCandidates {
                guard let objects = dictionaryArray(from: candidate), objects.isEmpty == false else {
                    continue
                }

                let serials = objects.compactMap(parseMobileScopeSerial(from:))
                if serials.isEmpty == false {
                    return serials
                }
            }

            for nestedValue in dictionary.values {
                guard let objects = dictionaryArray(from: nestedValue), objects.isEmpty == false else {
                    continue
                }

                let serials = objects.compactMap(parseMobileScopeSerial(from:))
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
            return objects.compactMap(parseMobileScopeSerial(from:))
        }

        if let serialNumbers = extractStringArray(from: jsonObject) {
            return serialNumbers.compactMap(normalizeSerial)
        }

        return []
    }

    /// Handles parseMobileScopeSerial.
    private func parseMobileScopeSerial(from item: [String: Any]) -> String? {
        var serial =
            extractString(from: item["serialNumber"]) ??
            extractString(from: item["serial"]) ??
            extractString(from: item["hardwareSerialNumber"])

        let nestedKeys = ["mobileDevice", "device", "inventoryRecord", "inventory", "item"]
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

    /// Handles resolvePrestageName.
    private func resolvePrestageName(forProfileID profileID: String) async -> String? {
        if let cached = prestageNameCache[profileID] {
            return cached
        }

        do {
            let profileData = try await apiGateway.request(
                path: "api/v2/mobile-device-prestages/\(profileID)",
                method: .get
            )

            if let profileName = extractProfileName(fromPrestageDetails: profileData) {
                prestageNameCache[profileID] = profileName
                return profileName
            }
        } catch {
            let description = describe(error)
            await diagnosticsReporter.reportError(
                source: moduleSource,
                category: "prestage",
                message: "Failed reading Pre-Stage Enrollment profile details.",
                errorDescription: description,
                metadata: [
                    "prestage_profile_id": profileID
                ]
            )
        }

        return nil
    }

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

    /// Handles extractPrestageEnrollmentStatus.
    private func extractPrestageEnrollmentStatus(from data: Data) -> String? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return extractPrestageEnrollmentStatus(from: jsonObject)
    }

    /// Handles extractPrestageEnrollmentStatus.
    private func extractPrestageEnrollmentStatus(from value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            let preferredKeys = [
                "prestageEnrollmentStatus",
                "managementStatus",
                "enrollmentStatus",
                "managed",
                "isManaged",
                "enrolled",
                "isEnrolled"
            ]

            for key in preferredKeys {
                if let normalized = normalizePrestageStatus(extractString(from: dictionary[key])) {
                    return normalized
                }
            }

            for (key, nestedValue) in dictionary {
                let normalizedKey = key.lowercased()
                if normalizedKey.contains("enroll") || normalizedKey.contains("managed") {
                    if let normalized = normalizePrestageStatus(extractString(from: nestedValue)) {
                        return normalized
                    }
                }

                if let nested = extractPrestageEnrollmentStatus(from: nestedValue) {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            for element in array {
                if let nested = extractPrestageEnrollmentStatus(from: element) {
                    return nested
                }
            }
        }

        return nil
    }

    /// Handles extractPrestageNameAndID.
    private func extractPrestageNameAndID(from data: Data) -> (name: String?, id: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return (nil, nil)
        }

        return extractPrestageNameAndID(from: json)
    }

    /// Handles extractPrestageNameAndID.
    private func extractPrestageNameAndID(from value: Any) -> (name: String?, id: String?) {
        if let dictionary = value as? [String: Any] {
            var foundName = extractString(from: dictionary["prestageEnrollmentProfileName"])
            var foundID =
                extractString(from: dictionary["prestageEnrollmentProfileId"]) ??
                extractString(from: dictionary["prestageId"])

            if let prestageObject = dictionary["prestageEnrollmentProfile"] {
                let nested = extractPrestageNameAndID(from: prestageObject)
                foundName = foundName ?? nested.name
                foundID = foundID ?? nested.id
            }

            for (key, nestedValue) in dictionary where key.lowercased().contains("prestage") {
                let lowerKey = key.lowercased()

                if foundName == nil && lowerKey.contains("name") {
                    foundName = extractString(from: nestedValue)
                }

                if foundID == nil && lowerKey.contains("id") {
                    foundID = extractString(from: nestedValue)
                }

                if foundName == nil || foundID == nil {
                    let nested = extractPrestageNameAndID(from: nestedValue)
                    foundName = foundName ?? nested.name
                    foundID = foundID ?? nested.id
                }
            }

            if foundName != nil || foundID != nil {
                return (foundName, foundID)
            }

            for nestedValue in dictionary.values {
                let nested = extractPrestageNameAndID(from: nestedValue)
                if nested.name != nil || nested.id != nil {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            for element in array {
                let nested = extractPrestageNameAndID(from: element)
                if nested.name != nil || nested.id != nil {
                    return nested
                }
            }
        }

        return (nil, nil)
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

            guard flattened.isEmpty == false else {
                return nil
            }

            return flattened.joined(separator: ", ")
        default:
            return nil
        }
    }

    /// Handles describe.
    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Handles userFacingSearchErrorMessage.
    private func userFacingSearchErrorMessage(for error: any Error) -> String {
        if case let JamfFrameworkError.networkFailure(statusCode, message) = error,
           statusCode == 403,
           message.localizedCaseInsensitiveContains("INVALID_PRIVILEGE")
        {
            return "Mobile device search was denied by Jamf. Verify API Role privileges for Mobile Device Inventory sections and Read Mobile Devices access."
        }

        if isSectionParameterError(error) {
            return "Mobile device search failed because the server rejected inventory section parameters."
        }

        return describe(error)
    }

    /// Handles isSectionParameterError.
    private func isSectionParameterError(_ error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, message) = error else {
            return false
        }

        guard statusCode == 400 else {
            return false
        }

        let normalizedMessage = message.lowercased()
        guard normalizedMessage.contains(sectionParameterName) else {
            return false
        }

        if normalizedMessage.contains(sectionParameterTypeErrorCode.lowercased()) {
            return true
        }

        return normalizedMessage.contains("invalid value of request parameter") ||
            normalizedMessage.contains("required type: java.util.set")
    }

    /// Handles shouldRetryWithNextFilter.
    private func shouldRetryWithNextFilter(after error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, message) = error else {
            return false
        }

        guard statusCode == 400 else {
            return false
        }

        let normalized = message.lowercased()
        return normalized.contains("cannot filter by field") ||
            normalized.contains("invalid_field") ||
            normalized.contains("no property")
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
