// MARK: - Forsetti Compliance
// Conforms to ForsettiUIModule with full lifecycle compliance:
// - descriptor: declares identity and version per Forsetti ModuleDescriptor contract
// - manifest: declares capabilities (networking, secureStorage, viewInjection) and entryPoint
// - uiContributions: registers a ViewInjectionDescriptor for the module.workspace slot
// - start(context:)/stop(context:): receives ForsettiContext for service resolution
// Discovered via manifest JSON in ForsettiManifests/ and instantiated by ModuleRegistry factory.

import Foundation
import ForsettiCore

/// PrestageDirectorModule declaration.
/// Forsetti-compliant UI module for managing Jamf Pro prestage assignments.
final class PrestageDirectorModule: ForsettiUIModule {
    let descriptor = ModuleDescriptor(
        moduleID: "com.jamftool.modules.prestage-director",
        displayName: "Prestage Director",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui
    )

    let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.supportedSchemaVersion,
        moduleID: "com.jamftool.modules.prestage-director",
        displayName: "Prestage Director",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
        capabilitiesRequested: [.networking, .secureStorage, .viewInjection],
        entryPoint: "PrestageDirectorModule"
    )

    let uiContributions = UIContributions(
        viewInjections: [
            ViewInjectionDescriptor(
                injectionID: "prestage-director-root",
                slot: "module.workspace",
                viewID: "prestage-director-root-view",
                priority: 100
            )
        ]
    )

    let subtitle = "View prestages and move or remove assigned devices."
    let iconSystemName = "arrow.left.arrow.right.square"

    private var isStarted = false

    init() {}

    func start(context: ForsettiContext) throws {
        guard !isStarted else { return }
        isStarted = true
        context.moduleLogger(moduleID: descriptor.moduleID).info("PrestageDirectorModule started")
    }

    func stop(context: ForsettiContext) {
        guard isStarted else { return }
        isStarted = false
        context.moduleLogger(moduleID: descriptor.moduleID).info("PrestageDirectorModule stopped")
    }
}
