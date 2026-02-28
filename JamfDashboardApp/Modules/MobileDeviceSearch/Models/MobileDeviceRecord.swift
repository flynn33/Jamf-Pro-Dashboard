import Foundation

/// MobileDeviceRecord declaration.
struct MobileDeviceRecord: Identifiable, Decodable, Sendable {
    let id: String
    let deviceName: String
    let serialNumber: String
    let udid: String?
    let model: String?
    let osVersion: String?
    let prestageEnrollmentStatus: String?
    let prestageEnrollmentProfileName: String?
    let prestageEnrollmentProfileID: String?
    let fieldValues: [String: String]

    /// Initializes the instance.
    init(
        id: String,
        deviceName: String,
        serialNumber: String,
        udid: String?,
        model: String?,
        osVersion: String?,
        prestageEnrollmentStatus: String?,
        prestageEnrollmentProfileName: String?,
        prestageEnrollmentProfileID: String?,
        fieldValues: [String: String] = [:]
    ) {
        self.id = id
        self.deviceName = deviceName
        self.serialNumber = serialNumber
        self.udid = udid
        self.model = model
        self.osVersion = osVersion
        self.prestageEnrollmentStatus = prestageEnrollmentStatus
        self.prestageEnrollmentProfileName = prestageEnrollmentProfileName
        self.prestageEnrollmentProfileID = prestageEnrollmentProfileID
        self.fieldValues = fieldValues
    }

    /// Handles withPrestageEnrollment.
    func withPrestageEnrollment(
        profileName: String?,
        profileID: String?,
        status: String? = nil
    ) -> MobileDeviceRecord {
        let resolvedName = profileName ?? prestageEnrollmentProfileName
        let resolvedID = profileID ?? prestageEnrollmentProfileID
        let resolvedStatus = status ?? prestageEnrollmentStatus

        var updatedFieldValues = fieldValues
        if let displayValue = Self.prestageDisplayValue(
            status: resolvedStatus,
            profileName: resolvedName,
            profileID: resolvedID
        ) {
            updatedFieldValues["prestageEnrollmentProfile"] = displayValue
        }

        return MobileDeviceRecord(
            id: id,
            deviceName: deviceName,
            serialNumber: serialNumber,
            udid: udid,
            model: model,
            osVersion: osVersion,
            prestageEnrollmentStatus: resolvedStatus,
            prestageEnrollmentProfileName: resolvedName,
            prestageEnrollmentProfileID: resolvedID,
            fieldValues: updatedFieldValues
        )
    }

    /// Handles value.
    func value(for fieldKey: String) -> String? {
        if let mappedValue = fieldValues[fieldKey],
           mappedValue.isEmpty == false
        {
            return mappedValue
        }

        switch fieldKey {
        case "id":
            return id
        case "deviceName":
            return deviceName
        case "serialNumber":
            return serialNumber
        case "udid":
            return udid
        case "model":
            return model
        case "osVersion":
            return osVersion
        case "prestageEnrollmentProfile":
            return Self.prestageDisplayValue(
                status: prestageEnrollmentStatus,
                profileName: prestageEnrollmentProfileName,
                profileID: prestageEnrollmentProfileID
            )
        default:
            return nil
        }
    }

    /// Handles prestageDisplayValue.
    static func prestageDisplayValue(
        status: String? = nil,
        profileName: String?,
        profileID: String?
    ) -> String? {
        let normalizedStatus = normalizePrestageStatus(status)
        let normalizedName = normalizePrestageComponent(profileName)
        let normalizedID = normalizePrestageComponent(profileID)
        let profileDisplay: String?

        switch (normalizedName, normalizedID) {
        case let (name?, id?):
            profileDisplay = "\(name) (ID: \(id))"
        case let (name?, nil):
            profileDisplay = name
        case let (nil, id?):
            profileDisplay = id
        case (nil, nil):
            profileDisplay = nil
        }

        if let normalizedStatus, let profileDisplay {
            return "\(normalizedStatus) - \(profileDisplay)"
        }

        if let normalizedStatus {
            return normalizedStatus
        }

        return profileDisplay
    }

    /// CodingKeys declaration.
    private enum CodingKeys: String, CodingKey {
        case id
        case mobileDeviceId
        case deviceId
        case deviceName
        case displayName
        case name
        case serialNumber
        case udid
        case model
        case modelIdentifier
        case osVersion
        case operatingSystemVersion
        case prestageEnrollmentProfile
        case prestageEnrollmentStatus
        case enrollmentStatus
        case prestageEnrollmentProfileName
        case prestageEnrollmentProfileId
        case prestageId
        case general
    }

    /// GeneralKeys declaration.
    private enum GeneralKeys: String, CodingKey {
        case name
        case serialNumber
        case udid
        case model
        case osVersion
        case managementStatus
        case enrollmentStatus
        case managed
    }

    /// PrestageProfileKeys declaration.
    private enum PrestageProfileKeys: String, CodingKey {
        case id
        case name
        case profileName
        case displayName
        case prestageEnrollmentProfileName
    }

    /// Initializes the instance.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id =
            Self.decodeStringOrInt(from: container, key: .id) ??
            Self.decodeStringOrInt(from: container, key: .mobileDeviceId) ??
            Self.decodeStringOrInt(from: container, key: .deviceId) ??
            UUID().uuidString

        var decodedPrestageStatus: String?
        if let generalContainer = try? container.nestedContainer(keyedBy: GeneralKeys.self, forKey: .general) {
            deviceName = Self.decodeLossyString(from: generalContainer, key: .name) ?? "Unknown Device"
            serialNumber = Self.decodeLossyString(from: generalContainer, key: .serialNumber) ?? "Unknown"
            udid = Self.decodeLossyString(from: generalContainer, key: .udid)
            model = Self.decodeLossyString(from: generalContainer, key: .model)
            osVersion = Self.decodeLossyString(from: generalContainer, key: .osVersion)

            decodedPrestageStatus =
                Self.decodeLossyString(from: generalContainer, key: .managementStatus) ??
                Self.decodeLossyString(from: generalContainer, key: .enrollmentStatus) ??
                Self.decodeLossyString(from: generalContainer, key: .managed)
        } else {
            deviceName =
                Self.decodeLossyString(from: container, key: .deviceName) ??
                Self.decodeLossyString(from: container, key: .name) ??
                Self.decodeLossyString(from: container, key: .displayName) ??
                "Unknown Device"

            serialNumber = Self.decodeLossyString(from: container, key: .serialNumber) ?? "Unknown"
            udid = Self.decodeLossyString(from: container, key: .udid)

            model =
                Self.decodeLossyString(from: container, key: .model) ??
                Self.decodeLossyString(from: container, key: .modelIdentifier)

            osVersion =
                Self.decodeLossyString(from: container, key: .osVersion) ??
                Self.decodeLossyString(from: container, key: .operatingSystemVersion)
        }

        decodedPrestageStatus =
            decodedPrestageStatus ??
            Self.decodeLossyString(from: container, key: .prestageEnrollmentStatus) ??
            Self.decodeLossyString(from: container, key: .enrollmentStatus)

        var decodedPrestageName = Self.decodeLossyString(from: container, key: .prestageEnrollmentProfileName)
        var decodedPrestageID = Self.decodeStringOrInt(from: container, key: .prestageEnrollmentProfileId)
            ?? Self.decodeStringOrInt(from: container, key: .prestageId)

        if let nestedPrestage = try? container.nestedContainer(keyedBy: PrestageProfileKeys.self, forKey: .prestageEnrollmentProfile) {
            decodedPrestageName =
                decodedPrestageName ??
                Self.decodeLossyString(from: nestedPrestage, key: .name) ??
                Self.decodeLossyString(from: nestedPrestage, key: .profileName) ??
                Self.decodeLossyString(from: nestedPrestage, key: .displayName) ??
                Self.decodeLossyString(from: nestedPrestage, key: .prestageEnrollmentProfileName)

            decodedPrestageID =
                decodedPrestageID ??
                Self.decodeStringOrInt(from: nestedPrestage, key: .id)
        } else if decodedPrestageName == nil {
            decodedPrestageName = Self.decodeLossyString(from: container, key: .prestageEnrollmentProfile)
        }

        prestageEnrollmentStatus = Self.normalizePrestageStatus(decodedPrestageStatus)
        prestageEnrollmentProfileName = decodedPrestageName
        prestageEnrollmentProfileID = decodedPrestageID

        var decodedFieldValues: [String: String] = [
            "id": id,
            "deviceName": deviceName,
            "serialNumber": serialNumber
        ]

        if let udid, udid.isEmpty == false {
            decodedFieldValues["udid"] = udid
        }

        if let model, model.isEmpty == false {
            decodedFieldValues["model"] = model
        }

        if let osVersion, osVersion.isEmpty == false {
            decodedFieldValues["osVersion"] = osVersion
        }

        if let displayValue = Self.prestageDisplayValue(
            status: prestageEnrollmentStatus,
            profileName: decodedPrestageName,
            profileID: decodedPrestageID
        ) {
            decodedFieldValues["prestageEnrollmentProfile"] = displayValue
        }

        fieldValues = decodedFieldValues
    }

    private static func normalizePrestageComponent(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizePrestageStatus(_ value: String?) -> String? {
        guard let normalized = normalizePrestageComponent(value) else {
            return nil
        }

        switch normalized.lowercased() {
        case "true", "managed", "enrolled":
            return "Enrolled"
        case "false", "unmanaged", "not enrolled":
            return "Not Enrolled"
        default:
            if normalized.lowercased().contains("not enrolled") ||
                normalized.lowercased().contains("unmanaged")
            {
                return "Not Enrolled"
            }

            if normalized.lowercased().contains("enrolled") ||
                normalized.lowercased().contains("managed")
            {
                return "Enrolled"
            }

            return normalized
        }
    }

    private static func decodeStringOrInt<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        key: K
    ) -> String? {
        if let stringValue = try? container.decode(String.self, forKey: key) {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let intValue = try? container.decode(Int.self, forKey: key) {
            return String(intValue)
        }

        return nil
    }

    private static func decodeLossyString<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        key: K
    ) -> String? {
        if let stringValue = try? container.decode(String.self, forKey: key) {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let intValue = try? container.decode(Int.self, forKey: key) {
            return String(intValue)
        }

        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            return String(doubleValue)
        }

        if let boolValue = try? container.decode(Bool.self, forKey: key) {
            return boolValue ? "true" : "false"
        }

        return nil
    }
}

//endofline
