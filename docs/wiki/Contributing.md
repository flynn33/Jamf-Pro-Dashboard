# Contributing

This page describes how to set up a development environment and how to add a new module to Jamf Dashboard.

## Development environment

- **Xcode 26+** is required.
- No additional package managers or external dependencies are needed; the project uses no Swift Package Manager dependencies beyond the Swift standard library and SwiftUI.
- Open `Jamf Dashboard.xcodeproj` directly.

## Project conventions

### Swift style

- Types, properties, and functions use `camelCase`; types use `UpperCamelCase`.
- `actor` is used for all service types that manage mutable state concurrently (`JamfAPIGateway`, `JamfAuthenticationService`).
- `@MainActor` is used on observable objects bound to the UI (`JamfFrameworkContainer`, `JamfCredentialsStore`, `DiagnosticsCenter`).
- `nonisolated` is applied where explicit concurrency boundaries are needed on value types.
- Trailing comments on closing braces are not used; `//endofline` is placed at the end of each source file instead.

### Error handling

- All public API errors are expressed as `JamfFrameworkError` cases.
- Every failure path that may affect operator visibility is reported to `DiagnosticsCenter` before re-throwing.
- Never swallow errors silently in service or gateway code.

### Diagnostics

- Use the `DiagnosticsReporting` protocol (`reportError`, `report`) rather than `print` or `os_log` for framework-level events.
- Always provide a `source` (component path, e.g. `framework.api-gateway`) and a `category` (e.g. `authentication`, `request`).

## Adding a new module type

### 1. Define the module type

Add a new case to `ModulePackageType` in `JamfDashboardApp/Framework/Modules/ModulePackageManifest.swift`:

```swift
case myNewModule = "my-new-module"
```

Implement the three computed properties: `defaultTitle`, `defaultSubtitle`, and `defaultIconSystemName`.

### 2. Implement the module

Create a folder under `JamfDashboardApp/Modules/MyNewModule/` with at minimum:

```
MyNewModule/
  MyNewModuleModule.swift    # JamfModule conformance
  Models/                    # Data models
  ViewModels/                # ObservableObject view models
  Views/                     # SwiftUI views
  Services/                  # API service layer (optional)
```

The module file must conform to `JamfModule`:

```swift
import SwiftUI

struct MyNewModuleModule: JamfModule {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String

    func makeRootView(context: ModuleContext) -> AnyView {
        AnyView(MyNewModuleRootView(context: context))
    }
}
```

### 3. Register the module in ModulePackageManager

In `ModulePackageManager.swift`, add a case to the `makeModule(for:manifest:)` function (or the equivalent factory switch) that instantiates your new module type.

### 4. Add a bundled default (optional)

If the module should ship as a built-in default, add an entry to `ModulePackageManifest.bundledDefaults` in `ModulePackageManifest.swift`.

### 5. Add a package template

Create a JSON manifest in `ModulePackageTemplates/my-new-module.json`:

```json
{
  "package_id": "com.jamftool.modules.my-new-module",
  "module_type": "my-new-module",
  "package_version": "1.0.0",
  "module_display_name": "My New Module",
  "module_subtitle": "Description of what the module does.",
  "icon_system_name": "square.grid.2x2"
}
```

### 6. Update the wiki

Add an entry for the new module in [Module Catalog](Module-Catalog.md) covering its features, typical workflow, and any required Jamf API privileges.

## Networking guidelines

- All HTTP calls must go through `JamfAPIGateway.request(path:method:queryItems:body:additionalHeaders:)`.
- Do not create `URLSession` instances or craft authenticated requests directly in module code.
- Implement compatibility fallback strategies: try the preferred endpoint first, then retry with a legacy alternative on `400`, `403`, or unexpected response shape.
- Report all significant failures to `diagnosticsReporter` before propagating errors to the UI.

## Adding a Jamf API endpoint

When integrating a new Jamf Pro API endpoint:

1. Verify the endpoint version status at [Jamf Developer Privileges and Deprecations](https://developer.jamf.com/jamf-pro/docs/privileges-and-deprecations).
2. Use the highest stable version as the primary endpoint.
3. Implement a fallback to the previous version for tenants running older Jamf Pro releases.
4. Document the endpoint and its privilege requirements in the module's service file and, if applicable, in a research notes markdown file alongside the module (following the pattern of `SupportTechnicianModernAPIResearch.md`).

## Pull request checklist

- [ ] New module type added to `ModulePackageType` with all three default property implementations.
- [ ] `JamfModule` conformance is complete (`id`, `title`, `subtitle`, `iconSystemName`, `makeRootView`).
- [ ] Module factory in `ModulePackageManager` handles the new type.
- [ ] All network calls go through `JamfAPIGateway`.
- [ ] Failures are reported to `DiagnosticsCenter` before propagating.
- [ ] A manifest template is added to `ModulePackageTemplates/`.
- [ ] `Module-Catalog.md` is updated with the new module entry.
