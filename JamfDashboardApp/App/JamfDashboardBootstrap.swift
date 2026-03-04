// MARK: - Forsetti Compliance
// Bootstrap replaces the original JamfFrameworkContainer with Forsetti runtime wiring.
//
// Forsetti integration points:
// 1. ForsettiServiceContainer — Registers both platform services (networking, storage) and
//    Jamf-specific services (JamfAPIGatewayProviding, JamfCredentialsProviding, DiagnosticsReporting)
//    so modules resolve dependencies via ForsettiContext.services.resolve().
// 2. ModuleRegistry — Each module factory is registered by entryPoint name, matching the
//    "entryPoint" field in the corresponding ForsettiManifests/*.json manifest file.
// 3. ForsettiRuntime — Orchestrates module discovery, compatibility checking, entitlement
//    validation, and activation lifecycle.
// 4. ForsettiHostController — Drives the dashboard UI with module state, selection, and
//    activation/deactivation.
// 5. ForsettiViewInjectionRegistry — Maps each module's declared viewID (from UIContributions)
//    to a SwiftUI view builder, enabling the host to render module workspace views.

import Foundation
import ForsettiCore
import ForsettiPlatform
import ForsettiHostTemplate

@MainActor
final class JamfDashboardBootstrap: ObservableObject {
    let controller: ForsettiHostController
    let injectionRegistry: ForsettiViewInjectionRegistry
    let credentialsStore: JamfCredentialsStore
    let diagnosticsCenter: DiagnosticsCenter

    init() {
        let diagnosticsCenter = DiagnosticsCenter()
        let credentialsStore = JamfCredentialsStore()
        let authenticationService = JamfAuthenticationService(diagnosticsReporter: diagnosticsCenter)
        let apiGateway = JamfAPIGateway(
            credentialsStore: credentialsStore,
            authenticationService: authenticationService,
            diagnosticsReporter: diagnosticsCenter
        )

        self.diagnosticsCenter = diagnosticsCenter
        self.credentialsStore = credentialsStore

        // Build Forsetti service container with platform defaults + Jamf-specific services
        let platformServices = DefaultForsettiPlatformServices()
        let serviceContainer = platformServices.container
        serviceContainer.register(JamfAPIGatewayProviding.self, service: apiGateway)
        serviceContainer.register(JamfCredentialsProviding.self, service: credentialsStore)
        serviceContainer.register(DiagnosticsReporting.self, service: diagnosticsCenter)

        // Register module factories
        let registry = ModuleRegistry()
        registry.register(entryPoint: "ComputerSearchModule") { ComputerSearchModule() }
        registry.register(entryPoint: "MobileDeviceSearchModule") { MobileDeviceSearchModule() }
        registry.register(entryPoint: "SupportTechnicianModule") { SupportTechnicianModule() }
        registry.register(entryPoint: "PrestageDirectorModule") { PrestageDirectorModule() }

        // Build Forsetti runtime
        let logger = JamfForsettiLogger(diagnosticsCenter: diagnosticsCenter)
        let uiSurfaceManager = UISurfaceManager()
        let router = ForsettiHostOverlayRouter(
            uiSurfaceManager: uiSurfaceManager,
            baseDestinationIDs: BaseDestinationCatalog.all,
            slotIDs: SlotCatalog.all
        )

        let runtime = ForsettiRuntime(
            services: serviceContainer,
            entitlementProvider: AllowAllEntitlementProvider(),
            router: router,
            moduleRegistry: registry,
            uiSurfaceManager: uiSurfaceManager
        )

        controller = ForsettiHostController(
            runtime: runtime,
            entitlementProvider: AllowAllEntitlementProvider(),
            manifestsBundle: .main,
            manifestsSubdirectory: "ForsettiManifests"
        )

        // Register view injections for module root views
        injectionRegistry = ForsettiViewInjectionRegistry()
        registerViewInjections(
            apiGateway: apiGateway,
            credentialsStore: credentialsStore,
            diagnosticsCenter: diagnosticsCenter
        )
    }

    private func registerViewInjections(
        apiGateway: JamfAPIGateway,
        credentialsStore: JamfCredentialsStore,
        diagnosticsCenter: DiagnosticsCenter
    ) {
        injectionRegistry.register(viewID: "computer-search-root-view") {
            let viewModel = ComputerSearchViewModel(
                apiGateway: apiGateway,
                diagnosticsReporter: diagnosticsCenter,
                profileStore: ComputerSearchProfileStore()
            )
            return ComputerSearchView(viewModel: viewModel)
        }

        injectionRegistry.register(viewID: "mobile-device-search-root-view") {
            let viewModel = MobileDeviceSearchViewModel(
                apiGateway: apiGateway,
                diagnosticsReporter: diagnosticsCenter,
                profileStore: MobileDeviceSearchProfileStore()
            )
            return MobileDeviceSearchView(viewModel: viewModel)
        }

        injectionRegistry.register(viewID: "support-technician-root-view") {
            let viewModel = SupportTechnicianViewModel(
                apiGateway: apiGateway,
                diagnosticsReporter: diagnosticsCenter
            )
            return SupportTechnicianView(viewModel: viewModel)
        }

        injectionRegistry.register(viewID: "prestage-director-root-view") {
            let viewModel = PrestageDirectorViewModel(
                apiGateway: apiGateway,
                diagnosticsReporter: diagnosticsCenter
            )
            return PrestageDirectorView(viewModel: viewModel)
        }
    }
}
