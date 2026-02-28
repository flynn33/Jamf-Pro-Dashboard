import Foundation
import Combine

@MainActor
/// JamfFrameworkContainer declaration.
final class JamfFrameworkContainer: ObservableObject {
    let diagnosticsCenter: DiagnosticsCenter
    let credentialsStore: JamfCredentialsStore
    let apiGateway: JamfAPIGateway
    let moduleRegistry: ModuleRegistry
    let modulePackageManager: ModulePackageManager

    /// Initializes the instance.
    init(
        credentialsStore: JamfCredentialsStore,
        authenticationService: JamfAuthenticationService,
        diagnosticsCenter: DiagnosticsCenter,
        modulePackageStore: ModulePackageStore
    ) {
        self.diagnosticsCenter = diagnosticsCenter
        self.credentialsStore = credentialsStore
        self.apiGateway = JamfAPIGateway(
            credentialsStore: credentialsStore,
            authenticationService: authenticationService,
            diagnosticsReporter: diagnosticsCenter
        )
        self.moduleRegistry = ModuleRegistry()
        self.modulePackageManager = ModulePackageManager(
            moduleRegistry: moduleRegistry,
            diagnosticsReporter: diagnosticsCenter,
            packageStore: modulePackageStore
        )

        Task { [modulePackageManager] in
            await modulePackageManager.bootstrap()
        }
    }

    /// Initializes the instance.
    convenience init() {
        let diagnosticsCenter = DiagnosticsCenter()
        let credentialsStore = JamfCredentialsStore()
        let authenticationService = JamfAuthenticationService(diagnosticsReporter: diagnosticsCenter)
        let modulePackageStore = ModulePackageStore()

        self.init(
            credentialsStore: credentialsStore,
            authenticationService: authenticationService,
            diagnosticsCenter: diagnosticsCenter,
            modulePackageStore: modulePackageStore
        )
    }

    var moduleContext: ModuleContext {
        ModuleContext(
            apiGateway: apiGateway,
            credentialsStore: credentialsStore,
            diagnosticsReporter: diagnosticsCenter
        )
    }
}

//endofline
