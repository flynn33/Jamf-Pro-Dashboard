import Foundation

/// MobileDeviceInventorySection declaration.
enum MobileDeviceInventorySection: String, CaseIterable, Sendable {
    case general = "GENERAL"
    case location = "USER_AND_LOCATION"
    case hardware = "HARDWARE"
    case purchasing = "PURCHASING"
    case security = "SECURITY"
    case applications = "APPLICATIONS"
    case ebooks = "EBOOKS"
    case network = "NETWORK"
    case serviceSubscriptions = "SERVICE_SUBSCRIPTIONS"
    case certificates = "CERTIFICATES"
    case configurationProfiles = "PROFILES"
    case userProfiles = "USER_PROFILES"
    case provisioningProfiles = "PROVISIONING_PROFILES"
    case sharedUsers = "SHARED_USERS"
    case extensionAttributes = "EXTENSION_ATTRIBUTES"
    case mobileDeviceGroups = "GROUPS"
}

/// MobileDeviceField declaration.
struct MobileDeviceField: Identifiable, Hashable, Sendable {
    let key: String
    let displayName: String
    let description: String
    let section: MobileDeviceInventorySection
    let responsePaths: [String]

    var id: String { key }
}

extension MobileDeviceField {
    static let catalog: [MobileDeviceField] = [
        .init(
            key: "id",
            displayName: "Record ID",
            description: "Internal Jamf mobile device record id.",
            section: .general,
            responsePaths: ["id", "mobileDeviceId", "deviceId", "hardware.deviceId"]
        ),
        .init(
            key: "deviceName",
            displayName: "Device Name",
            description: "User friendly device name.",
            section: .general,
            responsePaths: [
                "general.displayName",
                "general.deviceName",
                "general.name",
                "deviceName",
                "displayName",
                "name"
            ]
        ),
        .init(
            key: "serialNumber",
            displayName: "Serial Number",
            description: "Hardware serial number.",
            section: .hardware,
            responsePaths: ["hardware.serialNumber", "general.serialNumber", "serialNumber"]
        ),
        .init(
            key: "udid",
            displayName: "UDID",
            description: "Unique device identifier.",
            section: .general,
            responsePaths: ["general.udid", "udid"]
        ),
        .init(
            key: "assetTag",
            displayName: "Asset Tag",
            description: "Assigned inventory asset tag.",
            section: .general,
            responsePaths: ["general.assetTag", "assetTag"]
        ),
        .init(
            key: "model",
            displayName: "Model",
            description: "Device model string.",
            section: .hardware,
            responsePaths: ["hardware.model", "general.model", "model"]
        ),
        .init(
            key: "modelIdentifier",
            displayName: "Model Identifier",
            description: "Apple model identifier.",
            section: .hardware,
            responsePaths: ["hardware.modelIdentifier", "general.modelIdentifier", "modelIdentifier"]
        ),
        .init(
            key: "osVersion",
            displayName: "OS Version",
            description: "Installed iOS/iPadOS version.",
            section: .general,
            responsePaths: ["general.osVersion", "osVersion"]
        ),
        .init(
            key: "osBuild",
            displayName: "OS Build",
            description: "OS build number.",
            section: .general,
            responsePaths: ["general.osBuild", "osBuild"]
        ),
        .init(
            key: "managedAppleId",
            displayName: "Managed Apple ID",
            description: "Managed Apple ID assigned to the user.",
            section: .general,
            responsePaths: ["general.managedAppleId", "managedAppleId"]
        ),
        .init(
            key: "username",
            displayName: "Assigned Username",
            description: "Account username associated with the device.",
            section: .location,
            responsePaths: ["userAndLocation.username", "location.username", "username"]
        ),
        .init(
            key: "emailAddress",
            displayName: "Email Address",
            description: "Primary user email for the device.",
            section: .location,
            responsePaths: [
                "userAndLocation.emailAddress",
                "location.emailAddress",
                "location.email",
                "emailAddress",
                "email"
            ]
        ),
        .init(
            key: "phoneNumber",
            displayName: "Phone Number",
            description: "Associated phone number.",
            section: .location,
            responsePaths: ["userAndLocation.phoneNumber", "location.phoneNumber", "phoneNumber"]
        ),
        .init(
            key: "department",
            displayName: "Department",
            description: "Assigned department field.",
            section: .location,
            responsePaths: ["userAndLocation.department", "location.department", "department"]
        ),
        .init(
            key: "building",
            displayName: "Building",
            description: "Assigned building field.",
            section: .location,
            responsePaths: ["userAndLocation.building", "location.building", "building"]
        ),
        .init(
            key: "site",
            displayName: "Site",
            description: "Jamf site assignment.",
            section: .location,
            responsePaths: [
                "general.site.name",
                "general.siteId",
                "siteId",
                "location.site.name",
                "location.site",
                "site.name",
                "site"
            ]
        ),
        .init(
            key: "lastInventoryUpdate",
            displayName: "Last Inventory Update",
            description: "Most recent inventory sync timestamp.",
            section: .general,
            responsePaths: [
                "general.lastInventoryUpdateDate",
                "general.lastInventoryUpdate",
                "lastInventoryUpdateDate",
                "lastInventoryUpdate"
            ]
        ),
        .init(
            key: "enrollmentMethod",
            displayName: "Enrollment Method",
            description: "Method used to enroll the device.",
            section: .general,
            responsePaths: [
                "general.deviceOwnershipType",
                "general.enrollmentMethod",
                "enrollmentMethod",
                "deviceOwnershipType"
            ]
        ),
        .init(
            key: "prestageEnrollmentProfile",
            displayName: "Pre-Stage Enrollment",
            description: "Assigned Pre-Stage Enrollment profile for the device.",
            section: .general,
            responsePaths: [
                "general.enrollmentMethodPrestage.profileName",
                "general.enrollmentMethodPrestage.mobileDevicePrestageId",
                "general.prestageEnrollmentProfile.displayName",
                "general.prestageEnrollmentProfile.name",
                "general.prestageEnrollmentProfileName",
                "prestageEnrollmentProfileName",
                "general.prestageEnrollmentProfileId",
                "prestageEnrollmentProfileId",
                "prestageId",
                "prestageEnrollmentProfile"
            ]
        ),
        .init(
            key: "managementId",
            displayName: "Management ID",
            description: "Management identifier from Jamf Pro.",
            section: .general,
            responsePaths: ["general.managementId", "managementId"]
        ),
        .init(
            key: "supervised",
            displayName: "Supervised",
            description: "Whether device is in supervised mode.",
            section: .general,
            responsePaths: ["general.supervised", "supervised"]
        )
    ]

    static let defaultResultFieldKeys: [String] = [
        "deviceName",
        "serialNumber",
        "username",
        "model",
        "osVersion"
    ]

    static let keyLookup: [String: MobileDeviceField] = Dictionary(
        uniqueKeysWithValues: catalog.map { ($0.key, $0) }
    )
}

//endofline
