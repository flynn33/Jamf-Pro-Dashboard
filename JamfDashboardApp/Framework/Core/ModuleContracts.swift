import SwiftUI

/// ModuleContext declaration.
struct ModuleContext {
    let apiGateway: JamfAPIGateway
    let credentialsStore: JamfCredentialsStore
    let diagnosticsReporter: any DiagnosticsReporting
}

/// JamfModule declaration.
protocol JamfModule {
    var id: String { get }
    var title: String { get }
    var subtitle: String { get }
    var iconSystemName: String { get }

    /// Handles makeRootView.
    func makeRootView(context: ModuleContext) -> AnyView
}

//endofline
