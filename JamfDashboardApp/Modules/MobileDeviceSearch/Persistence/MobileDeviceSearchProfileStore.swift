import Foundation

/// MobileDeviceSearchProfileStore declaration.
actor MobileDeviceSearchProfileStore {
    private let fileManager: FileManager
    private let fileURL: URL

    /// Initializes the instance.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let directoryURL = appSupportURL.appending(path: "JamfDashboard", directoryHint: .isDirectory)
        self.fileURL = directoryURL.appending(path: "mobile-device-search-profiles.json")
    }

    /// Handles loadProfiles.
    func loadProfiles() throws -> [MobileDeviceSearchProfile] {
        try ensureDirectoryExists()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode([MobileDeviceSearchProfile].self, from: data)
    }

    /// Handles saveProfiles.
    func saveProfiles(_ profiles: [MobileDeviceSearchProfile]) throws {
        try ensureDirectoryExists()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(profiles)
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
