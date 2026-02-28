import SwiftUI

/// MobileDeviceSearchModule declaration.
final class MobileDeviceSearchModule: JamfModule {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String

    /// Initializes the instance.
    init(
        id: String = "com.jamftool.modules.mobile-device-search",
        title: String = "Mobile Device Search",
        subtitle: String = "Search inventory and create reusable field-based profiles.",
        iconSystemName: String = "iphone.gen3"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
    }

    /// Handles makeRootView.
    func makeRootView(context: ModuleContext) -> AnyView {
        let viewModel = MobileDeviceSearchViewModel(
            apiGateway: context.apiGateway,
            diagnosticsReporter: context.diagnosticsReporter,
            profileStore: MobileDeviceSearchProfileStore()
        )

        return AnyView(MobileDeviceSearchView(viewModel: viewModel))
    }
}

//endofline
