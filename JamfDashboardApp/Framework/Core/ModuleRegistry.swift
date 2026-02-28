import Foundation
import Combine

@MainActor
/// ModuleRegistry declaration.
final class ModuleRegistry: ObservableObject {
    @Published private(set) var modules: [any JamfModule] = []

    /// Handles setModules.
    func setModules(_ modules: [any JamfModule]) {
        var uniqueModules: [any JamfModule] = []

        for module in modules {
            guard uniqueModules.contains(where: { $0.id == module.id }) == false else {
                continue
            }
            uniqueModules.append(module)
        }

        self.modules = uniqueModules.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    /// Handles register.
    func register(_ module: any JamfModule) {
        guard modules.contains(where: { $0.id == module.id }) == false else {
            return
        }

        modules.append(module)
        modules.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Handles module.
    func module(withID id: String) -> (any JamfModule)? {
        modules.first(where: { $0.id == id })
    }
}

//endofline
