import Foundation

/// ModulePackageStore declaration.
actor ModulePackageStore {
    private let fileManager: FileManager
    private let fileURL: URL

    /// Initializes the instance.
    init() {
        let fileManager = FileManager.default
        self.fileManager = fileManager

        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let documentURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first

        let baseDirectoryURL = appSupportURL
            ?? documentURL
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let moduleDirectoryURL = baseDirectoryURL.appending(path: "JamfDashboard", directoryHint: .isDirectory)
        fileURL = moduleDirectoryURL.appending(path: "installed-module-packages.json")
    }

    /// Handles loadPackages.
    func loadPackages() throws -> [ModulePackageManifest] {
        try ensureDirectoryExists()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode([ModulePackageManifest].self, from: data)
    }

    /// Handles savePackages.
    func savePackages(_ packages: [ModulePackageManifest]) throws {
        try ensureDirectoryExists()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(packages)
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
