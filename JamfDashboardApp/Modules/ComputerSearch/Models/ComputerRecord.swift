import Foundation

/// ComputerRecord declaration.
struct ComputerRecord: Identifiable, Decodable, Sendable {
    let id: String
    let computerName: String
    let serialNumber: String
    let udid: String?
    let model: String?
    let modelIdentifier: String?
    let osVersion: String?
    let osBuild: String?
    let lastIpAddress: String?
    let username: String?
    let email: String?
    let assetTag: String?
    let departmentID: String?
    let buildingID: String?
    let prestageEnrollmentStatus: String?
    let prestageEnrollmentProfileName: String?
    let prestageEnrollmentProfileID: String?

    var prestageDisplayValue: String? {
        Self.prestageDisplayValue(
            status: prestageEnrollmentStatus,
            profileName: prestageEnrollmentProfileName,
            profileID: prestageEnrollmentProfileID
        )
    }

    /// CodingKeys declaration.
    private enum CodingKeys: String, CodingKey {
        case id
        case udid
        case general
        case hardware
        case operatingSystem
        case userAndLocation
        case computerName
        case serialNumber
        case prestageEnrollmentStatus
        case prestageEnrollmentProfile
        case prestageEnrollmentProfileName
        case prestageEnrollmentProfileId
        case prestageId
    }

    /// GeneralKeys declaration.
    private enum GeneralKeys: String, CodingKey {
        case name
        case lastIpAddress
        case assetTag
        case managementStatus
        case enrollmentStatus
        case managed
        case prestageEnrollmentProfile
        case prestageEnrollmentProfileName
        case prestageEnrollmentProfileId
        case prestageId
    }

    /// HardwareKeys declaration.
    private enum HardwareKeys: String, CodingKey {
        case serialNumber
        case model
        case modelIdentifier
    }

    /// OperatingSystemKeys declaration.
    private enum OperatingSystemKeys: String, CodingKey {
        case version
        case build
    }

    /// UserAndLocationKeys declaration.
    private enum UserAndLocationKeys: String, CodingKey {
        case username
        case email
        case departmentId
        case buildingId
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
    init(
        id: String,
        computerName: String,
        serialNumber: String,
        udid: String? = nil,
        model: String? = nil,
        modelIdentifier: String? = nil,
        osVersion: String? = nil,
        osBuild: String? = nil,
        lastIpAddress: String? = nil,
        username: String? = nil,
        email: String? = nil,
        assetTag: String? = nil,
        departmentID: String? = nil,
        buildingID: String? = nil,
        prestageEnrollmentStatus: String? = nil,
        prestageEnrollmentProfileName: String? = nil,
        prestageEnrollmentProfileID: String? = nil
    ) {
        self.id = id
        self.computerName = computerName
        self.serialNumber = serialNumber
        self.udid = udid
        self.model = model
        self.modelIdentifier = modelIdentifier
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.lastIpAddress = lastIpAddress
        self.username = username
        self.email = email
        self.assetTag = assetTag
        self.departmentID = departmentID
        self.buildingID = buildingID
        self.prestageEnrollmentStatus = prestageEnrollmentStatus
        self.prestageEnrollmentProfileName = prestageEnrollmentProfileName
        self.prestageEnrollmentProfileID = prestageEnrollmentProfileID
    }

    /// Initializes the instance.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id =
            Self.decodeStringOrInt(from: container, key: .id) ??
            UUID().uuidString

        if let general = try? container.nestedContainer(keyedBy: GeneralKeys.self, forKey: .general) {
            computerName = try general.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Computer"
            lastIpAddress = try general.decodeIfPresent(String.self, forKey: .lastIpAddress)
            assetTag = try general.decodeIfPresent(String.self, forKey: .assetTag)
        } else {
            computerName = try container.decodeIfPresent(String.self, forKey: .computerName) ?? "Unknown Computer"
            lastIpAddress = nil
            assetTag = nil
        }

        var decodedPrestageStatus: String?
        var decodedPrestageName: String?
        var decodedPrestageID: String?

        if let hardware = try? container.nestedContainer(keyedBy: HardwareKeys.self, forKey: .hardware) {
            serialNumber = try hardware.decodeIfPresent(String.self, forKey: .serialNumber) ??
                (try container.decodeIfPresent(String.self, forKey: .serialNumber)) ??
                "Unknown"
            model = try hardware.decodeIfPresent(String.self, forKey: .model)
            modelIdentifier = try hardware.decodeIfPresent(String.self, forKey: .modelIdentifier)
        } else {
            serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber) ?? "Unknown"
            model = nil
            modelIdentifier = nil
        }

        if let operatingSystem = try? container.nestedContainer(keyedBy: OperatingSystemKeys.self, forKey: .operatingSystem) {
            osVersion = try operatingSystem.decodeIfPresent(String.self, forKey: .version)
            osBuild = try operatingSystem.decodeIfPresent(String.self, forKey: .build)
        } else {
            osVersion = nil
            osBuild = nil
        }

        if let userAndLocation = try? container.nestedContainer(keyedBy: UserAndLocationKeys.self, forKey: .userAndLocation) {
            username = try userAndLocation.decodeIfPresent(String.self, forKey: .username)
            email = try userAndLocation.decodeIfPresent(String.self, forKey: .email)
            departmentID = Self.decodeStringOrInt(from: userAndLocation, key: .departmentId)
            buildingID = Self.decodeStringOrInt(from: userAndLocation, key: .buildingId)
        } else {
            username = nil
            email = nil
            departmentID = nil
            buildingID = nil
        }

        if let general = try? container.nestedContainer(keyedBy: GeneralKeys.self, forKey: .general) {
            decodedPrestageStatus =
                Self.decodeLossyString(from: general, key: .managementStatus) ??
                Self.decodeLossyString(from: general, key: .enrollmentStatus) ??
                Self.decodeLossyString(from: general, key: .managed)

            decodedPrestageName = Self.decodeLossyString(from: general, key: .prestageEnrollmentProfileName)
            decodedPrestageID =
                Self.decodeStringOrInt(from: general, key: .prestageEnrollmentProfileId) ??
                Self.decodeStringOrInt(from: general, key: .prestageId)

            if let nested = try? general.nestedContainer(keyedBy: PrestageProfileKeys.self, forKey: .prestageEnrollmentProfile) {
                decodedPrestageName =
                    decodedPrestageName ??
                    Self.decodeLossyString(from: nested, key: .name) ??
                    Self.decodeLossyString(from: nested, key: .profileName) ??
                    Self.decodeLossyString(from: nested, key: .displayName) ??
                    Self.decodeLossyString(from: nested, key: .prestageEnrollmentProfileName)

                decodedPrestageID =
                    decodedPrestageID ??
                    Self.decodeStringOrInt(from: nested, key: .id)
            }
        }

        decodedPrestageStatus =
            decodedPrestageStatus ??
            Self.decodeLossyString(from: container, key: .prestageEnrollmentStatus)

        decodedPrestageName =
            decodedPrestageName ??
            Self.decodeLossyString(from: container, key: .prestageEnrollmentProfileName)
        decodedPrestageID =
            decodedPrestageID ??
            Self.decodeStringOrInt(from: container, key: .prestageEnrollmentProfileId) ??
            Self.decodeStringOrInt(from: container, key: .prestageId)

        if decodedPrestageName == nil,
           let directValue = Self.decodeLossyString(from: container, key: .prestageEnrollmentProfile)
        {
            decodedPrestageName = directValue
        }

        prestageEnrollmentStatus = Self.normalizePrestageStatus(decodedPrestageStatus)
        prestageEnrollmentProfileName = Self.normalizePrestageComponent(decodedPrestageName)
        prestageEnrollmentProfileID = Self.normalizePrestageComponent(decodedPrestageID)

        udid = try container.decodeIfPresent(String.self, forKey: .udid)
    }

    /// Handles withPrestageEnrollment.
    func withPrestageEnrollment(
        status: String?,
        profileName: String?,
        profileID: String?
    ) -> ComputerRecord {
        ComputerRecord(
            id: id,
            computerName: computerName,
            serialNumber: serialNumber,
            udid: udid,
            model: model,
            modelIdentifier: modelIdentifier,
            osVersion: osVersion,
            osBuild: osBuild,
            lastIpAddress: lastIpAddress,
            username: username,
            email: email,
            assetTag: assetTag,
            departmentID: departmentID,
            buildingID: buildingID,
            prestageEnrollmentStatus: Self.normalizePrestageStatus(status) ?? prestageEnrollmentStatus,
            prestageEnrollmentProfileName: Self.normalizePrestageComponent(profileName) ?? prestageEnrollmentProfileName,
            prestageEnrollmentProfileID: Self.normalizePrestageComponent(profileID) ?? prestageEnrollmentProfileID
        )
    }

    /// Handles prestageDisplayValue.
    static func prestageDisplayValue(
        status: String?,
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
}

/// ComputerSearchResponse declaration.
struct ComputerSearchResponse: Decodable {
    let results: [ComputerRecord]

    /// CodingKeys declaration.
    private enum CodingKeys: String, CodingKey {
        case results
        case computers
        case items
    }

    /// Initializes the instance.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let records = try container.decodeIfPresent([ComputerRecord].self, forKey: .results) {
            results = records
            return
        }

        if let records = try container.decodeIfPresent([ComputerRecord].self, forKey: .computers) {
            results = records
            return
        }

        if let records = try container.decodeIfPresent([ComputerRecord].self, forKey: .items) {
            results = records
            return
        }

        results = []
    }
}

//endofline
