import Foundation

/// ModulePackageType declaration.
enum ModulePackageType: String, Codable, CaseIterable, Sendable {
    case computerSearch = "computer-search"
    case mobileDeviceSearch = "mobile-device-search"
    case supportTechnician = "support-technician"
    case prestageDirector = "prestage-director"

    var defaultTitle: String {
        switch self {
        case .computerSearch:
            return "Computer Search"
        case .mobileDeviceSearch:
            return "Mobile Device Search"
        case .supportTechnician:
            return "Support Technician"
        case .prestageDirector:
            return "Prestage Director"
        }
    }

    var defaultSubtitle: String {
        switch self {
        case .computerSearch:
            return "Search computer inventory and create reusable field-based profiles."
        case .mobileDeviceSearch:
            return "Search inventory and create reusable field-based profiles."
        case .supportTechnician:
            return "Unified support workflow for computers and mobile devices."
        case .prestageDirector:
            return "View prestages and move or remove assigned devices."
        }
    }

    var defaultIconSystemName: String {
        switch self {
        case .computerSearch:
            return "desktopcomputer"
        case .mobileDeviceSearch:
            return "iphone.gen3"
        case .supportTechnician:
            return "wrench.and.screwdriver"
        case .prestageDirector:
            return "arrow.left.arrow.right.square"
        }
    }
}

/// ModulePackageManifest declaration.
struct ModulePackageManifest: Identifiable, Codable, Hashable, Sendable {
    let packageID: String
    let moduleType: ModulePackageType
    let packageVersion: String
    let moduleDisplayName: String?
    let moduleSubtitle: String?
    let iconSystemName: String?
    let installedAt: Date

    /// Initializes the instance.
    init(
        packageID: String,
        moduleType: ModulePackageType,
        packageVersion: String,
        moduleDisplayName: String?,
        moduleSubtitle: String?,
        iconSystemName: String?,
        installedAt: Date
    ) {
        self.packageID = packageID
        self.moduleType = moduleType
        self.packageVersion = packageVersion
        self.moduleDisplayName = moduleDisplayName
        self.moduleSubtitle = moduleSubtitle
        self.iconSystemName = iconSystemName
        self.installedAt = installedAt
    }

    /// CodingKeys declaration.
    private enum CodingKeys: String, CodingKey {
        case packageID
        case moduleType
        case packageVersion
        case moduleDisplayName
        case moduleSubtitle
        case iconSystemName
        case installedAt
    }

    /// Initializes the instance.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        packageID = try container.decode(String.self, forKey: .packageID)
        moduleType = try container.decode(ModulePackageType.self, forKey: .moduleType)
        packageVersion = try container.decode(String.self, forKey: .packageVersion)
        moduleDisplayName = try container.decodeIfPresent(String.self, forKey: .moduleDisplayName)
        moduleSubtitle = try container.decodeIfPresent(String.self, forKey: .moduleSubtitle)
        iconSystemName = try container.decodeIfPresent(String.self, forKey: .iconSystemName)
        installedAt = try container.decodeIfPresent(Date.self, forKey: .installedAt) ?? Date()
    }

    /// Handles encode.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packageID, forKey: .packageID)
        try container.encode(moduleType, forKey: .moduleType)
        try container.encode(packageVersion, forKey: .packageVersion)
        try container.encode(moduleDisplayName, forKey: .moduleDisplayName)
        try container.encode(moduleSubtitle, forKey: .moduleSubtitle)
        try container.encode(iconSystemName, forKey: .iconSystemName)
        try container.encode(installedAt, forKey: .installedAt)
    }

    var id: String { packageID }

    var resolvedModuleTitle: String {
        let fallback = moduleType.defaultTitle
        guard let moduleDisplayName else {
            return fallback
        }

        let trimmed = moduleDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    var resolvedModuleSubtitle: String {
        let fallback = moduleType.defaultSubtitle
        guard let moduleSubtitle else {
            return fallback
        }

        let trimmed = moduleSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    var resolvedIconSystemName: String {
        let fallback = moduleType.defaultIconSystemName
        guard let iconSystemName else {
            return fallback
        }

        let trimmed = iconSystemName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Handles withInstalledDate.
    func withInstalledDate(_ date: Date = Date()) -> ModulePackageManifest {
        ModulePackageManifest(
            packageID: packageID,
            moduleType: moduleType,
            packageVersion: packageVersion,
            moduleDisplayName: moduleDisplayName,
            moduleSubtitle: moduleSubtitle,
            iconSystemName: iconSystemName,
            installedAt: date
        )
    }
}

extension ModulePackageManifest {
    static let bundledDefaults: [ModulePackageManifest] = [
        ModulePackageManifest(
            packageID: "com.jamftool.modules.computer-search",
            moduleType: .computerSearch,
            packageVersion: "1.0.0",
            moduleDisplayName: nil,
            moduleSubtitle: nil,
            iconSystemName: nil,
            installedAt: Date()
        ),
        ModulePackageManifest(
            packageID: "com.jamftool.modules.mobile-device-search",
            moduleType: .mobileDeviceSearch,
            packageVersion: "1.0.0",
            moduleDisplayName: nil,
            moduleSubtitle: nil,
            iconSystemName: nil,
            installedAt: Date()
        ),
        ModulePackageManifest(
            packageID: "com.jamftool.modules.support-technician",
            moduleType: .supportTechnician,
            packageVersion: "1.0.0",
            moduleDisplayName: nil,
            moduleSubtitle: nil,
            iconSystemName: nil,
            installedAt: Date()
        ),
        ModulePackageManifest(
            packageID: "com.jamftool.modules.prestage-director",
            moduleType: .prestageDirector,
            packageVersion: "1.0.0",
            moduleDisplayName: nil,
            moduleSubtitle: nil,
            iconSystemName: nil,
            installedAt: Date()
        )
    ]

    static var bundledDefaultPackageIDs: Set<String> {
        Set(bundledDefaults.map(\.packageID))
    }

    var isBundledDefault: Bool {
        Self.bundledDefaultPackageIDs.contains(packageID)
    }

    /// Handles fromPackageFileData.
    static func fromPackageFileData(_ data: Data) throws -> ModulePackageManifest {
        let rawObject = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = rawObject as? [String: Any] else {
            throw JamfFrameworkError.invalidModulePackage(message: "Module package JSON must be an object.")
        }

        let packageID = try requiredString(
            in: dictionary,
            keys: ["package_id", "packageID", "id"],
            fieldDescription: "package_id"
        )

        let moduleTypeValue = try requiredString(
            in: dictionary,
            keys: ["module_type", "moduleType"],
            fieldDescription: "module_type"
        )

        guard let moduleType = ModulePackageType(rawValue: moduleTypeValue) else {
            throw JamfFrameworkError.unsupportedModulePackageType(type: moduleTypeValue)
        }

        let packageVersion = optionalString(
            in: dictionary,
            keys: ["package_version", "packageVersion", "version"]
        ) ?? "1.0.0"

        let moduleDisplayName = optionalString(
            in: dictionary,
            keys: ["module_display_name", "moduleDisplayName", "displayName", "name"]
        )

        let moduleSubtitle = optionalString(
            in: dictionary,
            keys: ["module_subtitle", "moduleSubtitle", "subtitle", "description"]
        )

        let iconSystemName = optionalString(
            in: dictionary,
            keys: ["icon_system_name", "iconSystemName"]
        )

        return ModulePackageManifest(
            packageID: packageID,
            moduleType: moduleType,
            packageVersion: packageVersion,
            moduleDisplayName: moduleDisplayName,
            moduleSubtitle: moduleSubtitle,
            iconSystemName: iconSystemName,
            installedAt: Date()
        )
    }

    /// Handles requiredString.
    private static func requiredString(
        in dictionary: [String: Any],
        keys: [String],
        fieldDescription: String
    ) throws -> String {
        if let value = optionalString(in: dictionary, keys: keys) {
            return value
        }

        throw JamfFrameworkError.invalidModulePackage(
            message: "Missing required field '\(fieldDescription)' in module package."
        )
    }

    /// Handles optionalString.
    private static func optionalString(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
        }

        return nil
    }
}

//endofline
