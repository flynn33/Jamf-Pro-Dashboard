import Foundation
import Combine

@MainActor
/// ModulePackageManager declaration.
final class ModulePackageManager: ObservableObject {
    @Published private(set) var installedPackages: [ModulePackageManifest] = []

    private let moduleRegistry: ModuleRegistry
    private let diagnosticsReporter: any DiagnosticsReporting
    private let packageStore: ModulePackageStore

    /// Initializes the instance.
    init(
        moduleRegistry: ModuleRegistry,
        diagnosticsReporter: any DiagnosticsReporting,
        packageStore: ModulePackageStore = ModulePackageStore()
    ) {
        self.moduleRegistry = moduleRegistry
        self.diagnosticsReporter = diagnosticsReporter
        self.packageStore = packageStore
    }

    /// Handles bootstrap.
    func bootstrap() async {
        do {
            var loadedPackages = try await packageStore.loadPackages()
            let normalizedPackages = ensureBundledDefaultsPresent(in: loadedPackages)
            if normalizedPackages != loadedPackages {
                loadedPackages = normalizedPackages
                try await packageStore.savePackages(loadedPackages)
            }

            installedPackages = sortedPackages(loadedPackages)
            applyInstalledModules()

            await diagnosticsReporter.report(
                source: "framework.module-packages",
                category: "modules",
                severity: .info,
                message: "Module package bootstrap completed.",
                metadata: [
                    "package_count": String(installedPackages.count)
                ]
            )
        } catch {
            let fallbackPackages = sortedPackages(ModulePackageManifest.bundledDefaults.map { $0.withInstalledDate() })
            installedPackages = fallbackPackages
            moduleRegistry.setModules(fallbackPackages.compactMap(makeModule))

            try? await packageStore.savePackages(fallbackPackages)

            await diagnosticsReporter.reportError(
                source: "framework.module-packages",
                category: "modules",
                message: "Failed to bootstrap module packages.",
                errorDescription: describe(error)
            )
        }
    }

    /// Handles installPackage.
    func installPackage(from fileURL: URL) async throws -> ModulePackageManifest {
        let hasSecurityAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: fileURL)
        var package = try ModulePackageManifest.fromPackageFileData(data)

        if installedPackages.contains(where: { $0.packageID.caseInsensitiveCompare(package.packageID) == .orderedSame }) {
            throw JamfFrameworkError.duplicateModulePackage(packageID: package.packageID)
        }

        let existingPackages = installedPackages
        package = package.withInstalledDate()
        let updatedPackages = sortedPackages(existingPackages + [package])

        do {
            try await packageStore.savePackages(updatedPackages)
        } catch {
            installedPackages = existingPackages
            throw error
        }

        installedPackages = updatedPackages
        applyInstalledModules()

        await diagnosticsReporter.report(
            source: "framework.module-packages",
            category: "modules",
            severity: .info,
            message: "Installed module package.",
            metadata: [
                "package_id": package.packageID,
                "module_type": package.moduleType.rawValue
            ]
        )

        return package
    }

    /// Handles removePackages.
    func removePackages(at offsets: IndexSet) async {
        let existingPackages = installedPackages
        var updatedPackages = installedPackages
        var removedPackageIDs: [String] = []
        var skippedDefaultPackageIDs: [String] = []

        for index in offsets.sorted(by: >) {
            guard updatedPackages.indices.contains(index) else {
                continue
            }

            let package = updatedPackages[index]
            if package.isBundledDefault {
                skippedDefaultPackageIDs.append(package.packageID)
                continue
            }

            removedPackageIDs.append(package.packageID)
            updatedPackages.remove(at: index)
        }

        do {
            updatedPackages = ensureBundledDefaultsPresent(in: updatedPackages)
            try await packageStore.savePackages(updatedPackages)
            installedPackages = updatedPackages
            applyInstalledModules()

            await diagnosticsReporter.report(
                source: "framework.module-packages",
                category: "modules",
                severity: .warning,
                message: "Removed module packages.",
                metadata: [
                    "removed_package_count": String(removedPackageIDs.count)
                ]
            )

            if skippedDefaultPackageIDs.isEmpty == false {
                await diagnosticsReporter.report(
                    source: "framework.module-packages",
                    category: "modules",
                    severity: .info,
                    message: "Skipped removal of bundled default module packages.",
                    metadata: [
                        "skipped_package_count": String(skippedDefaultPackageIDs.count)
                    ]
                )
            }
        } catch {
            installedPackages = existingPackages
            await diagnosticsReporter.reportError(
                source: "framework.module-packages",
                category: "modules",
                message: "Failed to persist module package removal.",
                errorDescription: describe(error)
            )
        }
    }

    /// Handles applyInstalledModules.
    private func applyInstalledModules() {
        let modules = installedPackages.compactMap(makeModule)
        moduleRegistry.setModules(modules)
    }

    /// Handles makeModule.
    private func makeModule(from package: ModulePackageManifest) -> (any JamfModule)? {
        switch package.moduleType {
        case .computerSearch:
            return ComputerSearchModule(
                id: package.packageID,
                title: package.resolvedModuleTitle,
                subtitle: package.resolvedModuleSubtitle,
                iconSystemName: package.resolvedIconSystemName
            )
        case .mobileDeviceSearch:
            return MobileDeviceSearchModule(
                id: package.packageID,
                title: package.resolvedModuleTitle,
                subtitle: package.resolvedModuleSubtitle,
                iconSystemName: package.resolvedIconSystemName
            )
        case .supportTechnician:
            return SupportTechnicianModule(
                id: package.packageID,
                title: package.resolvedModuleTitle,
                subtitle: package.resolvedModuleSubtitle,
                iconSystemName: package.resolvedIconSystemName
            )
        case .prestageDirector:
            return PrestageDirectorModule(
                id: package.packageID,
                title: package.resolvedModuleTitle,
                subtitle: package.resolvedModuleSubtitle,
                iconSystemName: package.resolvedIconSystemName
            )
        }
    }

    /// Handles sortedPackages.
    private func sortedPackages(_ packages: [ModulePackageManifest]) -> [ModulePackageManifest] {
        packages.sorted {
            $0.resolvedModuleTitle.localizedCaseInsensitiveCompare($1.resolvedModuleTitle) == .orderedAscending
        }
    }

    /// Handles ensureBundledDefaultsPresent.
    private func ensureBundledDefaultsPresent(in packages: [ModulePackageManifest]) -> [ModulePackageManifest] {
        var updated = packages

        for bundledDefault in ModulePackageManifest.bundledDefaults {
            if updated.contains(where: { $0.packageID.caseInsensitiveCompare(bundledDefault.packageID) == .orderedSame }) {
                continue
            }

            updated.append(bundledDefault.withInstalledDate())
        }

        return sortedPackages(updated)
    }

    /// Handles describe.
    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

//endofline
