import SwiftUI

@main
/// JamfDashboardApp declaration.
struct JamfDashboardApp: App {
    @StateObject private var container = JamfFrameworkContainer()

    var body: some Scene {
        WindowGroup {
            DashboardView(container: container)
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

//endofline
