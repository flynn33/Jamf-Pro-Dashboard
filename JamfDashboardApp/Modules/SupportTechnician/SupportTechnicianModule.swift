// MARK: - Forsetti Compliance
// Conforms to ForsettiUIModule with full lifecycle compliance:
// - descriptor: declares identity and version per Forsetti ModuleDescriptor contract
// - manifest: declares capabilities (networking, secureStorage, viewInjection) and entryPoint
// - uiContributions: registers a ViewInjectionDescriptor for the module.workspace slot
// - start(context:)/stop(context:): receives ForsettiContext for service resolution
// Discovered via manifest JSON in ForsettiManifests/ and instantiated by ModuleRegistry factory.

import Foundation
import ForsettiCore

/// SupportTechnicianModule declaration.
/// Forsetti-compliant UI module for unified support workflow across computers and mobile devices.
final class SupportTechnicianModule: ForsettiUIModule {
    let descriptor = ModuleDescriptor(
        moduleID: "com.jamftool.modules.support-technician",
        displayName: "Support Technician",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui
    )

    let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.supportedSchemaVersion,
        moduleID: "com.jamftool.modules.support-technician",
        displayName: "Support Technician",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
        capabilitiesRequested: [.networking, .secureStorage, .viewInjection],
        entryPoint: "SupportTechnicianModule"
    )

    let uiContributions = UIContributions(
        viewInjections: [
            ViewInjectionDescriptor(
                injectionID: "support-technician-root",
                slot: "module.workspace",
                viewID: "support-technician-root-view",
                priority: 100
            )
        ]
    )

    let subtitle = "Unified support workflow for computers and mobile devices."
    let iconSystemName = "wrench.and.screwdriver"

    private var isStarted = false

    init() {}

    func start(context: ForsettiContext) throws {
        guard !isStarted else { return }
        isStarted = true
        context.moduleLogger(moduleID: descriptor.moduleID).info("SupportTechnicianModule started")
    }

    func stop(context: ForsettiContext) {
        guard isStarted else { return }
        isStarted = false
        context.moduleLogger(moduleID: descriptor.moduleID).info("SupportTechnicianModule stopped")
    }
}
