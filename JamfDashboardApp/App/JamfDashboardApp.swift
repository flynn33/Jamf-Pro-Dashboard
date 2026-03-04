// MARK: - Forsetti Compliance
// App entry point for the Forsetti-based Jamf Dashboard.
// Uses JamfDashboardBootstrap to initialize the ForsettiRuntime and ForsettiHostController,
// then renders the branded JamfDashboardHostView as the root scene.
// Follows Forsetti Pattern D: dashboard host with multiple independently-activated UI modules.

import SwiftUI
import ForsettiHostTemplate

@main
struct JamfDashboardApp: App {
    @StateObject private var bootstrap = JamfDashboardBootstrap()

    var body: some Scene {
        WindowGroup {
            JamfDashboardHostView(
                controller: bootstrap.controller,
                injectionRegistry: bootstrap.injectionRegistry,
                credentialsStore: bootstrap.credentialsStore,
                diagnosticsCenter: bootstrap.diagnosticsCenter
            )
            .tint(BrandColors.bluePrimary)
            .appRoundedTypography()
            .appBackground()
#if os(macOS)
            .frame(minWidth: 1200, minHeight: 820)
#endif
        }
#if os(macOS)
        .defaultSize(width: 1360, height: 860)
#endif
    }
}
