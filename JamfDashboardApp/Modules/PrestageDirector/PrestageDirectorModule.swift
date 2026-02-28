import SwiftUI

/// PrestageDirectorModule declaration.
final class PrestageDirectorModule: JamfModule {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String

    /// Initializes the instance.
    init(
        id: String = "com.jamftool.modules.prestage-director",
        title: String = "Prestage Director",
        subtitle: String = "View prestages and move or remove assigned devices.",
        iconSystemName: String = "arrow.left.arrow.right.square"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
    }

    /// Handles makeRootView.
    func makeRootView(context: ModuleContext) -> AnyView {
        let viewModel = PrestageDirectorViewModel(
            apiGateway: context.apiGateway,
            diagnosticsReporter: context.diagnosticsReporter
        )

        return AnyView(PrestageDirectorView(viewModel: viewModel))
    }
}

//endofline
