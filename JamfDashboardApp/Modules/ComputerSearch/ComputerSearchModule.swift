import SwiftUI

/// ComputerSearchModule declaration.
final class ComputerSearchModule: JamfModule {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String

    /// Initializes the instance.
    init(
        id: String = "com.jamftool.modules.computer-search",
        title: String = "Computer Search",
        subtitle: String = "Search computer inventory and create reusable field-based profiles.",
        iconSystemName: String = "desktopcomputer"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
    }

    /// Handles makeRootView.
    func makeRootView(context: ModuleContext) -> AnyView {
        let viewModel = ComputerSearchViewModel(
            apiGateway: context.apiGateway,
            diagnosticsReporter: context.diagnosticsReporter,
            profileStore: ComputerSearchProfileStore()
        )

        return AnyView(ComputerSearchView(viewModel: viewModel))
    }
}

//endofline
