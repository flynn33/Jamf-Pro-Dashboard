// MARK: - Forsetti Compliance
// Conforms to ForsettiUIModule with full lifecycle compliance:
// - descriptor: declares identity and version per Forsetti ModuleDescriptor contract
// - manifest: declares capabilities (networking, secureStorage, viewInjection) and entryPoint
// - uiContributions: registers a ViewInjectionDescriptor for the module.workspace slot
// - start(context:)/stop(context:): receives ForsettiContext for service resolution
// Discovered via manifest JSON in ForsettiManifests/ and instantiated by ModuleRegistry factory.

import Foundation
import ForsettiCore

/// MobileDeviceSearchModule declaration.
/// Forsetti-compliant UI module for searching Jamf Pro mobile device inventory.
final class MobileDeviceSearchModule: ForsettiUIModule {
    let descriptor = ModuleDescriptor(
        moduleID: "com.jamftool.modules.mobile-device-search",
        displayName: "Mobile Device Search",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui
    )

    let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.supportedSchemaVersion,
        moduleID: "com.jamftool.modules.mobile-device-search",
        displayName: "Mobile Device Search",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
        capabilitiesRequested: [.networking, .secureStorage, .viewInjection],
        entryPoint: "MobileDeviceSearchModule"
    )

    let uiContributions = UIContributions(
        viewInjections: [
            ViewInjectionDescriptor(
                injectionID: "mobile-device-search-root",
                slot: "module.workspace",
                viewID: "mobile-device-search-root-view",
                priority: 100
            )
        ]
    )

    let subtitle = "Search inventory and create reusable field-based profiles."
    let iconSystemName = "iphone.gen3"

    private var isStarted = false

    init() {}

    func start(context: ForsettiContext) throws {
        guard !isStarted else { return }
        isStarted = true
        context.moduleLogger(moduleID: descriptor.moduleID).info("MobileDeviceSearchModule started")
    }

    func stop(context: ForsettiContext) {
        guard isStarted else { return }
        isStarted = false
        context.moduleLogger(moduleID: descriptor.moduleID).info("MobileDeviceSearchModule stopped")
    }
}
