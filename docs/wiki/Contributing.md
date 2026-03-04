# Contributing

This page describes how to set up a development environment and how to add a new module to Jamf Dashboard.

## Development environment

- **Xcode 26+** is required.
- **Forsetti Framework** must be available as a local SPM dependency.
- Open `Jamf Dashboard.xcodeproj` directly.

## Project conventions

### Swift style

- Types, properties, and functions use `camelCase`; types use `UpperCamelCase`.
- `actor` is used for all service types that manage mutable state concurrently (`JamfAPIGateway`, `JamfAuthenticationService`).
- `@MainActor` is used on observable objects bound to the UI (`JamfDashboardBootstrap`, `JamfCredentialsStore`, `DiagnosticsCenter`).
- `nonisolated` is applied where explicit concurrency boundaries are needed on value types.
- Trailing comments on closing braces are not used; `//endofline` is placed at the end of each source file instead.

### Error handling

- All public API errors are expressed as `JamfFrameworkError` cases.
- Every failure path that may affect operator visibility is reported to `DiagnosticsCenter` before re-throwing.
- Never swallow errors silently in service or gateway code.

### Diagnostics

- Use the `DiagnosticsReporting` protocol (`reportError`, `report`) rather than `print` or `os_log` for framework-level events.
- Always provide a `source` (component path, e.g. `framework.api-gateway`) and a `category` (e.g. `authentication`, `request`).

## Adding a new module

### 1. Create the module class

Create a folder under `JamfDashboardApp/Modules/MyNewModule/` with at minimum:

```
MyNewModule/
  MyNewModuleModule.swift    # ForsettiUIModule conformance
  Models/                    # Data models
  ViewModels/                # ObservableObject view models
  Views/                     # SwiftUI views
  Services/                  # API service layer (optional)
```

The module file must conform to `ForsettiUIModule`:

```swift
import Foundation
import ForsettiCore

final class MyNewModuleModule: ForsettiUIModule {
    let descriptor = ModuleDescriptor(
        moduleID: "com.jamftool.modules.my-new-module",
        displayName: "My New Module",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui
    )

    let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.supportedSchemaVersion,
        moduleID: "com.jamftool.modules.my-new-module",
        displayName: "My New Module",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
        capabilitiesRequested: [.networking, .secureStorage, .viewInjection],
        entryPoint: "MyNewModuleModule"
    )

    let uiContributions = UIContributions(
        viewInjections: [
            ViewInjectionDescriptor(
                injectionID: "my-new-module-root",
                slot: "module.workspace",
                viewID: "my-new-module-root-view",
                priority: 100
            )
        ]
    )

    func start(context: ForsettiContext) throws {
        // Resolve services from context.services
    }

    func stop(context: ForsettiContext) {
        // Cleanup
    }
}
```

### 2. Create a manifest JSON

Add a manifest file in `JamfDashboardApp/Resources/ForsettiManifests/my-new-module.json`:

```json
{
  "schemaVersion": "1.0",
  "moduleID": "com.jamftool.modules.my-new-module",
  "displayName": "My New Module",
  "moduleVersion": "1.0.0",
  "moduleType": "ui",
  "supportedPlatforms": ["iOS", "macOS"],
  "minForsettiVersion": "0.1.0",
  "capabilitiesRequested": ["networking", "secureStorage", "viewInjection"],
  "entryPoint": "MyNewModuleModule"
}
```

### 3. Register the module factory

In `JamfDashboardBootstrap.swift`, register the factory in `ModuleRegistry`:

```swift
registry.registerFactory(entryPoint: "MyNewModuleModule") { MyNewModuleModule() }
```

### 4. Register the view injection

In `JamfDashboardBootstrap.swift`, register the view builder in `ForsettiViewInjectionRegistry`:

```swift
injectionRegistry.register(viewID: "my-new-module-root-view") {
    AnyView(MyNewModuleRootView(...))
}
```

### 5. Update the wiki

Add an entry for the new module in [Module Catalog](Module-Catalog.md) covering its features, typical workflow, and any required Jamf API privileges.

## Networking guidelines

- All HTTP calls must go through `JamfAPIGatewayProviding` resolved from `ForsettiContext.services`.
- Do not create `URLSession` instances or craft authenticated requests directly in module code.
- Implement compatibility fallback strategies: try the preferred endpoint first, then retry with a legacy alternative on `400`, `403`, or unexpected response shape.
- Report all significant failures to `diagnosticsReporter` before propagating errors to the UI.

## Adding a Jamf API endpoint

When integrating a new Jamf Pro API endpoint:

1. Verify the endpoint version status at [Jamf Developer Privileges and Deprecations](https://developer.jamf.com/jamf-pro/docs/privileges-and-deprecations).
2. Use the highest stable version as the primary endpoint.
3. Implement a fallback to the previous version for tenants running older Jamf Pro releases.
4. Document the endpoint and its privilege requirements in the module's service file.

## Pull request checklist

- [ ] `ForsettiUIModule` conformance is complete (`descriptor`, `manifest`, `uiContributions`, `start`, `stop`).
- [ ] Manifest JSON added to `Resources/ForsettiManifests/`.
- [ ] Module factory registered in `JamfDashboardBootstrap`.
- [ ] View injection registered in `JamfDashboardBootstrap`.
- [ ] All network calls go through `JamfAPIGatewayProviding`.
- [ ] Failures are reported to `DiagnosticsCenter` before propagating.
- [ ] `Module-Catalog.md` is updated with the new module entry.
