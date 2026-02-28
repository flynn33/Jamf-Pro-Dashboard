import SwiftUI

/// SupportTechnicianModule declaration.
final class SupportTechnicianModule: JamfModule {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String

    /// Initializes the instance.
    init(
        id: String = "com.jamftool.modules.support-technician",
        title: String = "Support Technician",
        subtitle: String = "Unified support workflow for computers and mobile devices.",
        iconSystemName: String = "wrench.and.screwdriver"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
    }

    /// Handles makeRootView.
    func makeRootView(context: ModuleContext) -> AnyView {
        let viewModel = SupportTechnicianViewModel(
            apiGateway: context.apiGateway,
            diagnosticsReporter: context.diagnosticsReporter
        )

        return AnyView(SupportTechnicianView(viewModel: viewModel))
    }
}

//endofline
