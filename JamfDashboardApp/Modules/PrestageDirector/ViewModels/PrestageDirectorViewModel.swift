import Foundation
import Combine

@MainActor
/// PrestageDirectorViewModel declaration.
final class PrestageDirectorViewModel: ObservableObject {
    @Published private(set) var prestages: [PrestageSummary] = []
    @Published var selectedPrestageID: String?

    @Published private(set) var scopedDevices: [PrestageAssignedDevice] = []
    @Published private(set) var globalSearchDevices: [PrestageAssignedDevice] = []
    @Published var deviceSerialSearchText = ""
    @Published var selectedDeviceKeys: Set<String> = []

    @Published private(set) var isLoadingPrestages = false
    @Published private(set) var isLoadingScopedDevices = false
    @Published private(set) var isSearchingAcrossPrestages = false
    @Published private(set) var isApplyingChanges = false

    @Published var isMoveDestinationPresented = false

    @Published private(set) var operationProgress: PrestageDirectorOperationProgress?
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let apiGateway: JamfAPIGateway
    private let diagnosticsReporter: any DiagnosticsReporting
    private let moduleSource = "module.prestage-director"
    private var globalSearchTask: Task<Void, Never>?

    /// Initializes the instance.
    init(
        apiGateway: JamfAPIGateway,
        diagnosticsReporter: any DiagnosticsReporting
    ) {
        self.apiGateway = apiGateway
        self.diagnosticsReporter = diagnosticsReporter
    }

    deinit {
        globalSearchTask?.cancel()
    }

    var selectedCount: Int {
        selectedSerialNumbers.count
    }

    var isGlobalSearchActive: Bool {
        normalizedSerialQuery(deviceSerialSearchText) != nil
    }

    var allDevicesSelected: Bool {
        guard isGlobalSearchActive == false else {
            return false
        }

        let visibleDeviceKeys = Set(visibleScopedDevices.map(\.selectionKey))
        guard visibleDeviceKeys.isEmpty == false else {
            return false
        }

        return visibleDeviceKeys.isSubset(of: selectedDeviceKeys)
    }

    var canRemoveSelection: Bool {
        selectedSerialNumbers.isEmpty == false &&
            isApplyingChanges == false &&
            isGlobalSearchActive == false
    }

    var canMoveSelection: Bool {
        selectedSerialNumbers.isEmpty == false &&
            moveDestinationPrestages.isEmpty == false &&
            isApplyingChanges == false &&
            isGlobalSearchActive == false
    }

    var moveDestinationPrestages: [PrestageSummary] {
        prestages.filter { $0.id != selectedPrestageID }
    }

    var filteredScopedDevices: [PrestageAssignedDevice] {
        if isGlobalSearchActive {
            return globalSearchDevices
        }

        guard let normalizedQuery = normalizedSerialQuery(deviceSerialSearchText) else {
            return scopedDevices
        }

        return scopedDevices.filter { device in
            guard let serial = device.normalizedSerialNumber else {
                return false
            }
            return serial.contains(normalizedQuery)
        }
    }

    /// Handles loadInitialState.
    func loadInitialState() async {
        await refreshPrestages()
    }

    /// Handles handleDeviceSearchTextChanged.
    func handleDeviceSearchTextChanged() {
        globalSearchTask?.cancel()

        guard let normalizedQuery = normalizedSerialQuery(deviceSerialSearchText) else {
            isSearchingAcrossPrestages = false
            globalSearchDevices = []
            selectedDeviceKeys.formIntersection(Set(scopedDevices.map(\.selectionKey)))
            return
        }

        let querySnapshot = normalizedQuery
        globalSearchTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.searchAcrossAllPrestages(normalizedSerialQuery: querySnapshot)
        }
    }

    /// Handles refreshPrestages.
    func refreshPrestages() async {
        let previousSelection = selectedPrestageID
        isLoadingPrestages = true
        defer { isLoadingPrestages = false }

        do {
            let fetchedPrestages = try await fetchAllPrestages()
            prestages = fetchedPrestages.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            if prestages.isEmpty {
                globalSearchTask?.cancel()
                selectedPrestageID = nil
                scopedDevices = []
                globalSearchDevices = []
                selectedDeviceKeys = []
                isSearchingAcrossPrestages = false
                statusMessage = "No pre-stages returned by the Jamf Pro server."
                errorMessage = nil

                reportEvent(
                    severity: .warning,
                    category: "prestages",
                    message: "No pre-stages were returned by the server."
                )
                return
            }

            if let previousSelection,
               prestages.contains(where: { $0.id == previousSelection })
            {
                selectedPrestageID = previousSelection
            } else {
                selectedPrestageID = prestages.first?.id
            }

            statusMessage = "Loaded \(prestages.count) pre-stage profiles."
            errorMessage = nil
            reportEvent(
                severity: .info,
                category: "prestages",
                message: "Loaded pre-stage profile list.",
                metadata: [
                    "prestage_count": String(prestages.count)
                ]
            )

            await loadDevicesForSelectedPrestage()
            handleDeviceSearchTextChanged()
        } catch {
            let description = describe(error)
            errorMessage = "Failed to load pre-stages. \(description)"
            statusMessage = nil
            reportError(
                category: "prestages",
                message: "Failed loading pre-stage profile list.",
                errorDescription: description
            )
        }
    }

    /// Handles loadDevicesForSelectedPrestage.
    func loadDevicesForSelectedPrestage() async {
        guard let selectedPrestageID, selectedPrestageID.isEmpty == false else {
            globalSearchTask?.cancel()
            scopedDevices = []
            globalSearchDevices = []
            selectedDeviceKeys = []
            isSearchingAcrossPrestages = false
            return
        }

        let requestedPrestageID = selectedPrestageID
        isLoadingScopedDevices = true
        defer { isLoadingScopedDevices = false }

        do {
            let devices = try await fetchScopedDevices(for: requestedPrestageID)
            guard selectedPrestageID == requestedPrestageID else {
                return
            }

            scopedDevices = devices
            selectedDeviceKeys.formIntersection(Set(scopedDevices.map(\.selectionKey)))
            errorMessage = nil
            statusMessage = "Loaded \(scopedDevices.count) assigned devices."

            reportEvent(
                severity: .info,
                category: "scope",
                message: "Loaded pre-stage scope assignments.",
                metadata: [
                    "prestage_id": requestedPrestageID,
                    "device_count": String(scopedDevices.count)
                ]
            )

            if isGlobalSearchActive {
                handleDeviceSearchTextChanged()
            }
        } catch {
            guard selectedPrestageID == requestedPrestageID else {
                return
            }

            let description = describe(error)
            errorMessage = "Failed to load assigned devices. \(description)"
            statusMessage = nil
            scopedDevices = []
            selectedDeviceKeys = []

            reportError(
                category: "scope",
                message: "Failed loading pre-stage scope assignments.",
                errorDescription: description,
                metadata: [
                    "prestage_id": requestedPrestageID
                ]
            )
        }
    }

    /// Handles searchAcrossAllPrestages.
    private func searchAcrossAllPrestages(normalizedSerialQuery: String) async {
        guard prestages.isEmpty == false else {
            globalSearchDevices = []
            return
        }

        isSearchingAcrossPrestages = true
        defer { isSearchingAcrossPrestages = false }

        var matches: [PrestageAssignedDevice] = []
        var failedPrestageCount = 0

        for prestage in prestages {
            if Task.isCancelled {
                return
            }

            do {
                let scoped = try await fetchScopedDevices(for: prestage.id)
                let prestageMatches = scoped.filter { device in
                    guard let serial = device.normalizedSerialNumber else {
                        return false
                    }

                    return serial.contains(normalizedSerialQuery)
                }

                matches.append(contentsOf: prestageMatches)
            } catch {
                failedPrestageCount += 1
                let description = describe(error)
                await diagnosticsReporter.reportError(
                    source: moduleSource,
                    category: "scope-search",
                    message: "Failed searching a pre-stage scope.",
                    errorDescription: description,
                    metadata: [
                        "prestage_id": prestage.id
                    ]
                )
            }
        }

        if Task.isCancelled {
            return
        }

        let dedupedMatches = dedupeDevices(matches).sorted {
            let lhsName = $0.deviceName.localizedLowercase
            let rhsName = $1.deviceName.localizedLowercase
            if lhsName == rhsName {
                return $0.serialNumber.localizedLowercase < $1.serialNumber.localizedLowercase
            }
            return lhsName < rhsName
        }

        globalSearchDevices = dedupedMatches
        selectedDeviceKeys.removeAll()

        if failedPrestageCount == prestages.count {
            errorMessage = "Failed searching pre-stage scope assignments."
            statusMessage = nil
            return
        }

        errorMessage = nil
        statusMessage = "Found \(dedupedMatches.count) matching devices across \(prestages.count) pre-stage profiles."
    }

    /// Handles toggleSelection.
    func toggleSelection(for device: PrestageAssignedDevice) {
        guard isGlobalSearchActive == false else {
            return
        }

        let selectionKey = device.selectionKey
        guard selectedDeviceKeys.contains(selectionKey) == false else {
            selectedDeviceKeys.remove(selectionKey)
            return
        }

        selectedDeviceKeys.insert(selectionKey)
    }

    /// Handles toggleSelectAll.
    func toggleSelectAll() {
        guard isGlobalSearchActive == false else {
            return
        }

        let visibleSelectionKeys = Set(visibleScopedDevices.map(\.selectionKey))
        guard visibleSelectionKeys.isEmpty == false else {
            return
        }

        if allDevicesSelected {
            selectedDeviceKeys.subtract(visibleSelectionKeys)
            return
        }

        selectedDeviceKeys.formUnion(visibleSelectionKeys)
    }

    /// Handles presentMoveDestinationPicker.
    func presentMoveDestinationPicker() {
        guard selectedSerialNumbers.isEmpty == false else {
            errorMessage = "Select one or more devices before moving."
            return
        }

        guard moveDestinationPrestages.isEmpty == false else {
            errorMessage = "No destination pre-stage is available."
            return
        }

        isMoveDestinationPresented = true
    }

    /// Handles confirmRemoval.
    func confirmRemoval() async {
        guard let selectedPrestageID else {
            errorMessage = "Select a pre-stage first."
            return
        }

        let serialNumbers = selectedSerialNumbers
        guard serialNumbers.isEmpty == false else {
            errorMessage = "No valid serial numbers were selected."
            return
        }

        isApplyingChanges = true
        defer { isApplyingChanges = false }
        setOperationProgress(
            title: "Remove in progress",
            detail: "Removing selected devices from the current pre-stage...",
            fractionCompleted: 0.35
        )

        do {
            try await applyScopeMutation(
                .remove,
                prestageID: selectedPrestageID,
                serialNumbers: serialNumbers
            )

            setOperationProgress(
                title: "Remove in progress",
                detail: "Refreshing pre-stage assignments...",
                fractionCompleted: 0.80
            )
            selectedDeviceKeys.removeAll()
            errorMessage = nil
            statusMessage = "Removed \(serialNumbers.count) selected devices from the pre-stage."

            reportEvent(
                severity: .warning,
                category: "scope",
                message: "Removed selected devices from a pre-stage.",
                metadata: [
                    "prestage_id": selectedPrestageID,
                    "device_count": String(serialNumbers.count)
                ]
            )

            await loadDevicesForSelectedPrestage()
            setOperationProgress(
                title: "Remove complete",
                detail: "Finished removing selected devices.",
                fractionCompleted: 1.0
            )
        } catch {
            let description = describe(error)
            clearOperationProgress()
            errorMessage = "Device removal failed. \(description)"
            statusMessage = nil

            reportError(
                category: "scope",
                message: "Failed removing devices from pre-stage.",
                errorDescription: description,
                metadata: [
                    "prestage_id": selectedPrestageID,
                    "device_count": String(serialNumbers.count)
                ]
            )
        }
    }

    /// Handles moveSelection.
    func moveSelection(to destination: PrestageSummary) async {
        guard let sourcePrestageID = selectedPrestageID else {
            errorMessage = "Select a source pre-stage first."
            return
        }

        let serialNumbers = selectedSerialNumbers
        guard serialNumbers.isEmpty == false else {
            errorMessage = "No valid serial numbers were selected."
            return
        }

        guard sourcePrestageID != destination.id else {
            errorMessage = "Choose a different destination pre-stage."
            return
        }

        isApplyingChanges = true
        defer { isApplyingChanges = false }
        let sourceName = selectedPrestageName ?? "the current pre-stage"
        setOperationProgress(
            title: "Move in progress",
            detail: "Removing selected devices from \(sourceName)...",
            fractionCompleted: 0.20
        )

        var removedFromSource = false

        do {
            try await applyScopeMutation(
                .remove,
                prestageID: sourcePrestageID,
                serialNumbers: serialNumbers
            )
            removedFromSource = true

            setOperationProgress(
                title: "Move in progress",
                detail: "Adding selected devices to \(destination.name)...",
                fractionCompleted: 0.55
            )
            try await applyScopeMutation(
                .add,
                prestageID: destination.id,
                serialNumbers: serialNumbers
            )

            setOperationProgress(
                title: "Move in progress",
                detail: "Refreshing pre-stage assignments...",
                fractionCompleted: 0.85
            )
            selectedDeviceKeys.removeAll()
            errorMessage = nil
            statusMessage = "Moved \(serialNumbers.count) devices to \(destination.name)."

            reportEvent(
                severity: .warning,
                category: "scope",
                message: "Moved selected devices between pre-stages.",
                metadata: [
                    "source_prestage_id": sourcePrestageID,
                    "destination_prestage_id": destination.id,
                    "device_count": String(serialNumbers.count)
                ]
            )

            await loadDevicesForSelectedPrestage()
            setOperationProgress(
                title: "Move complete",
                detail: "Finished moving selected devices to \(destination.name).",
                fractionCompleted: 1.0
            )
        } catch {
            let description = describe(error)
            var rollbackDescription: String?

            if removedFromSource {
                setOperationProgress(
                    title: "Move in progress",
                    detail: "Move failed. Attempting rollback...",
                    fractionCompleted: 0.92
                )
                do {
                    try await applyScopeMutation(
                        .add,
                        prestageID: sourcePrestageID,
                        serialNumbers: serialNumbers
                    )
                    rollbackDescription = "Rollback succeeded and restored the original assignment."
                } catch {
                    rollbackDescription = "Rollback failed: \(describe(error))."
                }
            }

            clearOperationProgress()
            if let rollbackDescription {
                errorMessage = "Move failed. \(description) \(rollbackDescription)"
            } else {
                errorMessage = "Move failed. \(description)"
            }
            statusMessage = nil

            reportError(
                category: "scope",
                message: "Failed moving devices between pre-stages.",
                errorDescription: description,
                metadata: [
                    "source_prestage_id": sourcePrestageID,
                    "destination_prestage_id": destination.id,
                    "device_count": String(serialNumbers.count),
                    "rollback_result": rollbackDescription ?? "not_attempted"
                ]
            )
        }
    }

    private var selectedSerialNumbers: [String] {
        guard isGlobalSearchActive == false else {
            return []
        }

        let values = scopedDevices.compactMap { device -> String? in
            guard selectedDeviceKeys.contains(device.selectionKey) else {
                return nil
            }

            return device.normalizedSerialNumber
        }

        return Array(Set(values)).sorted()
    }

    private var selectedPrestageName: String? {
        guard let selectedPrestageID else {
            return nil
        }

        return prestages.first(where: { $0.id == selectedPrestageID })?.name
    }

    /// Handles setOperationProgress.
    private func setOperationProgress(
        title: String,
        detail: String,
        fractionCompleted: Double
    ) {
        let normalizedFraction = max(0, min(1, fractionCompleted))
        operationProgress = PrestageDirectorOperationProgress(
            title: title,
            detail: detail,
            fractionCompleted: normalizedFraction
        )
    }

    /// Handles clearOperationProgress.
    private func clearOperationProgress() {
        operationProgress = nil
    }

    /// Handles fetchAllPrestages.
    private func fetchAllPrestages() async throws -> [PrestageSummary] {
        var page = 0
        let pageSize = 200
        var aggregated: [PrestageSummary] = []
        var seenPrestageIDs = Set<String>()

        while true {
            let data = try await apiGateway.request(
                path: "api/v2/mobile-device-prestages",
                method: .get,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(pageSize))
                ]
            )

            let pagePrestages = parsePrestageSummaries(from: data)
            let newPrestages = pagePrestages.filter { seenPrestageIDs.insert($0.id).inserted }
            aggregated.append(contentsOf: newPrestages)

            if pagePrestages.isEmpty || pagePrestages.count < pageSize || newPrestages.isEmpty {
                break
            }

            page += 1
            if page > 200 {
                break
            }
        }

        return dedupePrestages(aggregated)
    }

    /// Handles fetchScopedDevices.
    private func fetchScopedDevices(for prestageID: String) async throws -> [PrestageAssignedDevice] {
        var page = 0
        let pageSize = 500
        var aggregated: [PrestageAssignedDevice] = []
        var seenSelectionKeys = Set<String>()

        while true {
            let data = try await apiGateway.request(
                path: "api/v2/mobile-device-prestages/\(prestageID)/scope",
                method: .get,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(pageSize))
                ]
            )

            let pageDevices = parseScopedDevices(from: data)
            let newDevices = pageDevices.filter { seenSelectionKeys.insert($0.selectionKey).inserted }
            aggregated.append(contentsOf: newDevices)

            if pageDevices.isEmpty || pageDevices.count < pageSize || newDevices.isEmpty {
                break
            }

            page += 1
            if page > 400 {
                break
            }
        }

        return dedupeDevices(aggregated).sorted {
            let lhsName = $0.deviceName.localizedLowercase
            let rhsName = $1.deviceName.localizedLowercase
            if lhsName == rhsName {
                return $0.serialNumber.localizedLowercase < $1.serialNumber.localizedLowercase
            }
            return lhsName < rhsName
        }
    }

    /// ScopeMutationAction declaration.
    private enum ScopeMutationAction {
        case add
        case remove

        var endpointSuffixCandidates: [String?] {
            switch self {
            case .add:
                return [
                    "add-multiple",
                    nil
                ]
            case .remove:
                return [
                    "delete-multiple"
                ]
            }
        }
    }

    /// Handles applyScopeMutation.
    private func applyScopeMutation(
        _ action: ScopeMutationAction,
        prestageID: String,
        serialNumbers: [String]
    ) async throws {
        let normalizedSerialNumbers = Array(Set(serialNumbers.compactMap(normalizeSerial))).sorted()
        guard normalizedSerialNumbers.isEmpty == false else {
            throw JamfFrameworkError.persistenceFailure(message: "No serial numbers available for scope mutation.")
        }

        let versionLock = try await resolveVersionLock(for: prestageID)
        let payloadCandidates: [[String: Any]] = [
            [
                "serialNumbers": normalizedSerialNumbers,
                "versionLock": versionLock
            ],
            [
                "serialNumbers": normalizedSerialNumbers,
                "versionLock": String(versionLock)
            ]
        ]

        var lastError: (any Error)?

        for endpointSuffix in action.endpointSuffixCandidates {
            let endpointPath: String
            if let endpointSuffix {
                endpointPath = "api/v2/mobile-device-prestages/\(prestageID)/scope/\(endpointSuffix)"
            } else {
                endpointPath = "api/v2/mobile-device-prestages/\(prestageID)/scope"
            }

            for payload in payloadCandidates {
                let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

                do {
                    _ = try await apiGateway.request(
                        path: endpointPath,
                        method: .post,
                        body: payloadData
                    )
                    return
                } catch {
                    lastError = error
                    if shouldTryAlternatePayload(after: error) {
                        continue
                    }

                    if shouldTryAlternateEndpoint(after: error) {
                        break
                    }

                    throw error
                }
            }
        }

        if let lastError {
            throw lastError
        }

        throw JamfFrameworkError.persistenceFailure(message: "Unable to apply pre-stage scope mutation.")
    }

    /// Handles resolveVersionLock.
    private func resolveVersionLock(for prestageID: String) async throws -> Int {
        do {
            let resolvedVersionLock = try await fetchPrestageVersionLock(for: prestageID)
            updateCachedPrestageVersionLock(id: prestageID, versionLock: resolvedVersionLock)
            return resolvedVersionLock
        } catch {
            if let cachedVersionLock = prestages.first(where: { $0.id == prestageID })?.versionLock {
                return cachedVersionLock
            }
            throw error
        }
    }

    /// Handles fetchPrestageVersionLock.
    private func fetchPrestageVersionLock(for prestageID: String) async throws -> Int {
        let data = try await apiGateway.request(
            path: "api/v2/mobile-device-prestages/\(prestageID)",
            method: .get
        )

        guard let versionLock = parseVersionLock(from: data) else {
            throw JamfFrameworkError.persistenceFailure(
                message: "Unable to resolve versionLock for pre-stage \(prestageID)."
            )
        }

        return versionLock
    }

    /// Handles updateCachedPrestageVersionLock.
    private func updateCachedPrestageVersionLock(id: String, versionLock: Int) {
        guard let index = prestages.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existing = prestages[index]
        guard existing.versionLock != versionLock else {
            return
        }

        prestages[index] = PrestageSummary(
            id: existing.id,
            name: existing.name,
            versionLock: versionLock
        )
    }

    /// Handles shouldTryAlternatePayload.
    private func shouldTryAlternatePayload(after error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, _) = error else {
            return false
        }

        return statusCode == 400 || statusCode == 415 || statusCode == 422
    }

    /// Handles shouldTryAlternateEndpoint.
    private func shouldTryAlternateEndpoint(after error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, _) = error else {
            return false
        }

        return statusCode == 404 || statusCode == 405
    }

    /// Handles parsePrestageSummaries.
    private func parsePrestageSummaries(from data: Data) -> [PrestageSummary] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        let objects: [[String: Any]]

        if let dictionary = jsonObject as? [String: Any] {
            objects =
                dictionaryArray(from: dictionary["results"]) ??
                dictionaryArray(from: dictionary["prestages"]) ??
                dictionaryArray(from: dictionary["mobileDevicePrestages"]) ??
                dictionaryArray(from: dictionary["items"]) ??
                dictionaryArray(from: dictionary["data"]) ??
                []
        } else {
            objects = dictionaryArray(from: jsonObject) ?? []
        }

        return objects.compactMap { item in
            guard let id =
                extractString(from: item["id"]) ??
                extractString(from: item["prestageId"])
            else {
                return nil
            }

            let name =
                extractString(from: item["displayName"]) ??
                extractString(from: item["name"]) ??
                extractString(from: item["profileName"]) ??
                "Pre-Stage \(id)"

            return PrestageSummary(
                id: id,
                name: name,
                versionLock: extractVersionLock(from: item)
            )
        }
    }

    /// Handles parseVersionLock.
    private func parseVersionLock(from data: Data) -> Int? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return extractVersionLock(from: jsonObject)
    }

    /// Handles parseScopedDevices.
    private func parseScopedDevices(from data: Data) -> [PrestageAssignedDevice] {
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

                let parsed = objects.compactMap(parseScopedDevice(from:))
                if parsed.isEmpty == false {
                    return dedupeDevices(parsed)
                }
            }

            for nestedValue in dictionary.values {
                guard let objects = dictionaryArray(from: nestedValue), objects.isEmpty == false else {
                    continue
                }

                let parsed = objects.compactMap(parseScopedDevice(from:))
                if parsed.isEmpty == false {
                    return dedupeDevices(parsed)
                }
            }

            if let serialNumbers =
                extractStringArray(from: dictionary["serialNumbers"]) ??
                extractStringArray(from: (dictionary["assignments"] as? [String: Any])?["serialNumbers"])
            {
                return dedupeDevices(serialNumbers.map(makeScopedDeviceFallback(from:)))
            }
        }

        if let objects = dictionaryArray(from: jsonObject), objects.isEmpty == false {
            return dedupeDevices(objects.compactMap(parseScopedDevice(from:)))
        }

        if let serialNumbers = extractStringArray(from: jsonObject) {
            return dedupeDevices(serialNumbers.map(makeScopedDeviceFallback(from:)))
        }

        return []
    }

    /// Handles parseScopedDevice.
    private func parseScopedDevice(from item: [String: Any]) -> PrestageAssignedDevice? {
        var serialNumber =
            extractString(from: item["serialNumber"]) ??
            extractString(from: item["serial"]) ??
            extractString(from: item["hardwareSerialNumber"])

        var deviceName =
            extractString(from: item["deviceName"]) ??
            extractString(from: item["name"]) ??
            extractString(from: item["displayName"])

        var udid = extractString(from: item["udid"])
        var model =
            extractString(from: item["model"]) ??
            extractString(from: item["modelIdentifier"])

        var assignmentID =
            extractString(from: item["id"]) ??
            extractString(from: item["assignmentId"]) ??
            extractString(from: item["deviceId"]) ??
            extractString(from: item["mobileDeviceId"])

        let nestedKeys = ["mobileDevice", "device", "inventoryRecord", "inventory", "item"]
        for key in nestedKeys {
            guard let nested = item[key] as? [String: Any] else {
                continue
            }

            serialNumber = serialNumber ??
                extractString(from: nested["serialNumber"]) ??
                extractString(from: nested["serial"])

            deviceName = deviceName ??
                extractString(from: nested["deviceName"]) ??
                extractString(from: nested["name"]) ??
                extractString(from: nested["displayName"])

            udid = udid ?? extractString(from: nested["udid"])

            model = model ??
                extractString(from: nested["model"]) ??
                extractString(from: nested["modelIdentifier"])

            assignmentID = assignmentID ??
                extractString(from: nested["id"]) ??
                extractString(from: nested["deviceId"]) ??
                extractString(from: nested["mobileDeviceId"])
        }

        if serialNumber == nil {
            serialNumber = extractValue(matching: "serial", in: item)
        }

        let normalizedSerial = normalizeSerial(serialNumber)
        let resolvedID = assignmentID ?? normalizedSerial ?? UUID().uuidString

        guard normalizedSerial != nil || assignmentID != nil else {
            return nil
        }

        let trimmedName = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String
        if let trimmedName, trimmedName.isEmpty == false {
            resolvedName = trimmedName
        } else {
            resolvedName = normalizedSerial ?? "Unknown Device"
        }

        return PrestageAssignedDevice(
            id: resolvedID,
            serialNumber: normalizedSerial ?? "",
            deviceName: resolvedName,
            udid: udid,
            model: model
        )
    }

    /// Handles makeScopedDeviceFallback.
    private func makeScopedDeviceFallback(from serialNumber: String) -> PrestageAssignedDevice {
        let normalizedSerial = normalizeSerial(serialNumber) ?? serialNumber
        return PrestageAssignedDevice(
            id: normalizedSerial,
            serialNumber: normalizedSerial,
            deviceName: normalizedSerial,
            udid: nil,
            model: nil
        )
    }

    /// Handles dedupePrestages.
    private func dedupePrestages(_ prestages: [PrestageSummary]) -> [PrestageSummary] {
        var uniqueByID: [String: PrestageSummary] = [:]

        for prestage in prestages {
            guard let existing = uniqueByID[prestage.id] else {
                uniqueByID[prestage.id] = prestage
                continue
            }

            if existing.versionLock == nil && prestage.versionLock != nil {
                uniqueByID[prestage.id] = prestage
            }
        }

        return Array(uniqueByID.values)
    }

    /// Handles dedupeDevices.
    private func dedupeDevices(_ devices: [PrestageAssignedDevice]) -> [PrestageAssignedDevice] {
        var uniqueBySelectionKey: [String: PrestageAssignedDevice] = [:]

        for device in devices {
            uniqueBySelectionKey[device.selectionKey] = device
        }

        return Array(uniqueBySelectionKey.values)
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
                dictionaryArray(from: dictionary["mobileDevices"]) ??
                dictionaryArray(from: dictionary["data"])
        }

        return nil
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

    /// Handles extractVersionLock.
    private func extractVersionLock(from value: Any) -> Int? {
        if let dictionary = value as? [String: Any] {
            let priorityKeys = [
                "versionLock",
                "version_lock",
                "lockVersion",
                "optimisticLockVersion"
            ]

            for key in priorityKeys {
                if let resolved = extractInt(from: dictionary[key]) {
                    return resolved
                }
            }

            for (key, nestedValue) in dictionary {
                let normalizedKey = key.replacingOccurrences(of: "_", with: "").lowercased()
                if normalizedKey.contains("versionlock"),
                   let resolved = extractInt(from: nestedValue)
                {
                    return resolved
                }
            }

            if let resolvedVersion = extractInt(from: dictionary["version"]) {
                return resolvedVersion
            }

            for nestedValue in dictionary.values {
                if let nestedDictionary = nestedValue as? [String: Any],
                   let resolved = extractVersionLock(from: nestedDictionary)
                {
                    return resolved
                }

                if let nestedArray = nestedValue as? [Any],
                   let resolved = extractVersionLock(from: nestedArray)
                {
                    return resolved
                }
            }
            return nil
        }

        if let array = value as? [Any] {
            for item in array {
                if let nestedDictionary = item as? [String: Any],
                   let resolved = extractVersionLock(from: nestedDictionary)
                {
                    return resolved
                }

                if let nestedArray = item as? [Any],
                   let resolved = extractVersionLock(from: nestedArray)
                {
                    return resolved
                }
            }
            return nil
        }

        return nil
    }

    /// Handles extractInt.
    private func extractInt(from value: Any?) -> Int? {
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

    /// Handles extractString.
    private func extractString(from value: Any?) -> String? {
        switch value {
        case let stringValue as String:
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let intValue as Int:
            return String(intValue)
        case let numberValue as NSNumber:
            return numberValue.stringValue
        default:
            return nil
        }
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

    /// Handles normalizedSerialQuery.
    private func normalizedSerialQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        return trimmed.uppercased()
    }

    private var visibleScopedDevices: [PrestageAssignedDevice] {
        filteredScopedDevices
    }

    /// Handles describe.
    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
