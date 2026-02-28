# Architecture

Jamf Dashboard is a SwiftUI iOS/macOS app built around a shared framework container. Modules stay lightweight by relying on injected services for authentication, networking, diagnostics, and persistence.

## Repository layout

```
JamfDashboardApp/
  App/                        # Entry point and framework container wiring
  Framework/
    Core/                     # Shared contracts, credentials model, error types, module registry
    Networking/               # Authentication service and API gateway
    Security/                 # Keychain-backed credential store
    Diagnostics/              # Event reporting, NDJSON error log, JSON export
    Modules/                  # Module manifest model, package manager, package persistence
    UI/                       # Dashboard, settings, credentials, diagnostics views
    Scanning/                 # Shared barcode/QR scanner sheet
  DesignSystem/               # Shared visual and theming components
  Modules/
    ComputerSearch/           # Computer inventory search module
    MobileDeviceSearch/       # Mobile inventory search module
    SupportTechnician/        # Help-desk unified workflow module
    PrestageDirector/         # Prestage enrollment management module
ModulePackageTemplates/       # Example module package JSON manifests
docs/wiki/                    # Wiki documentation pages
```

## Application shell

`JamfDashboardApp.swift` creates `JamfFrameworkContainer` and passes `moduleContext` into module views.

`JamfFrameworkContainer` owns all shared services and is the single source of truth for the app's dependencies:

```
JamfFrameworkContainer
  ├── DiagnosticsCenter
  ├── JamfCredentialsStore
  ├── JamfAPIGateway
  │     ├── JamfCredentialsStore (ref)
  │     ├── JamfAuthenticationService
  │     │     └── DiagnosticsCenter (ref)
  │     └── DiagnosticsCenter (ref)
  ├── ModuleRegistry
  └── ModulePackageManager
        ├── ModuleRegistry (ref)
        ├── DiagnosticsCenter (ref)
        └── ModulePackageStore
```

## Service descriptions

### JamfFrameworkContainer

`@MainActor final class` that bootstraps and vends all shared services. The convenience initializer constructs the full dependency graph. A `moduleContext` computed property packages gateway, credentials store, and diagnostics for injection into modules.

### JamfAPIGateway

`actor` that is the single HTTP request layer for all modules.

- Loads credentials from `JamfCredentialsStore` on every call.
- Retrieves a valid token from `JamfAuthenticationService` before building the request.
- Automatically retries once on `401` after invalidating the cached token.
- Normalizes all non-2xx responses to `JamfFrameworkError.networkFailure`.
- Records every failure in `DiagnosticsCenter` with method, path, and error description.

### JamfAuthenticationService

`actor` for token acquisition and caching.

- Supports two flows: **API Client** (`POST /api/v1/oauth/token` with `client_credentials` grant) and **Username & Password** (`POST /api/v1/auth/token` with Basic auth).
- Caches the token with a 60-second safety margin before actual expiration.
- Invalidates cache when the credential signature changes (URL, client ID, or secret differ from the cached value).
- Reports token fetch success and failure to diagnostics.

### JamfCredentialsStore

`@MainActor final class` for Keychain-backed secure credential persistence.

- Operations: `saveCredentials`, `loadCredentials`, `clearCredentials`.
- Publishes `hasStoredCredentials` for UI binding.
- Only stores credential fields for the selected auth method (`storageSanitized`); unused fields are cleared before save.
- Delegates raw Keychain I/O to `KeychainSecureStore`.

### DiagnosticsCenter

`@MainActor final class` implementing `DiagnosticsReporting`.

- Maintains a bounded in-memory `DiagnosticEvent` stream for UI display.
- Appends error-severity events to a persistent NDJSON file at `Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson`.
- Exports the full in-memory event array as a JSON bundle to `Documents/JamfDashboardDiagnostics/`.
- Supports full clear/reset of both the in-memory stream and the NDJSON log.

`DiagnosticEvent` fields: `id` (UUID), `timestamp`, `source`, `category`, `severity` (`info`/`warning`/`error`), `message`, `metadata` (string dictionary).

### ModuleRegistry

Holds the registered `JamfModule` instances. `ModulePackageManager` adds and removes modules from the registry in response to package installs and removals.

### ModulePackageManager

Manages the full lifecycle of module packages.

- `bootstrap()` — re-applies all bundled default packages that are not currently installed.
- `installPackage(from:)` — parses a JSON manifest, rejects duplicates and unsupported types, then registers the module.
- `removePackage(id:)` — removes a custom package from the registry and persists the change.
- Delegates persistence to `ModulePackageStore`.

## Module contract

All modules conform to `JamfModule`:

```swift
protocol JamfModule {
    var id: String { get }
    var title: String { get }
    var subtitle: String { get }
    var iconSystemName: String { get }
    func makeRootView(context: ModuleContext) -> AnyView
}
```

`ModuleContext` injects services:

```swift
struct ModuleContext {
    let apiGateway: JamfAPIGateway
    let credentialsStore: JamfCredentialsStore
    let diagnosticsReporter: any DiagnosticsReporting
}
```

## Module packages

Modules are registered through JSON manifests parsed by `ModulePackageManifest.fromPackageFileData(_:)`. The parser accepts multiple key aliases (e.g. `package_id`, `packageID`, `id`) to be permissive about manifest authoring.

| JSON field | Aliases | Required |
|---|---|---|
| `package_id` | `packageID`, `id` | Yes |
| `module_type` | `moduleType` | Yes |
| `package_version` | `packageVersion`, `version` | No (defaults to `1.0.0`) |
| `module_display_name` | `moduleDisplayName`, `displayName`, `name` | No |
| `module_subtitle` | `moduleSubtitle`, `subtitle`, `description` | No |
| `icon_system_name` | `iconSystemName` | No |

Resolved values (display name, subtitle, icon) fall back to module-type defaults when the manifest field is absent or blank.

Persisted state: `Application Support/JamfDashboard/installed-module-packages.json` (array of `ModulePackageManifest` objects encoded by `ModulePackageStore`).

## Request and diagnostics flow

```
Module
  └─► JamfAPIGateway.request(path:method:queryItems:body:)
        ├─► JamfCredentialsStore.loadCredentials()
        ├─► JamfAuthenticationService.accessToken(for:)
        │     └─► POST /api/v1/oauth/token   (or /api/v1/auth/token)
        ├─► URLSession.data(for:)
        │     └─► [401] invalidateToken() → re-authenticate → retry
        └─► DiagnosticsCenter.reportError(...)  (on failure)
```

## Error model

`JamfFrameworkError` covers all expected failure cases:

| Case | Trigger |
|---|---|
| `invalidServerURL` | URL string cannot be parsed |
| `missingCredentials` | No credentials in Keychain |
| `invalidCredentials` | Credential fields are incomplete |
| `authenticationFailed` | Token request returned a non-HTTP response |
| `networkFailure(statusCode:message:)` | Non-2xx HTTP response |
| `decodingFailure` | Token or API response JSON cannot be decoded |
| `keychainFailure(status:)` | Keychain operation returned a non-zero OSStatus |
| `persistenceFailure(message:)` | File-system read/write error |
| `invalidModulePackage(message:)` | Manifest is missing required fields or is malformed |
| `duplicateModulePackage(packageID:)` | Package with this ID is already installed |
| `unsupportedModulePackageType(type:)` | `module_type` value is not recognized |

## Security and platform

- macOS target uses **App Sandbox** (`com.apple.security.app-sandbox = true`) and **Hardened Runtime**.
- Entitlements file: `JamfDashboardApp/JamfDashboardApp.entitlements`.
- Build settings are in `Jamf Dashboard.xcodeproj/project.pbxproj`.
- Credential storage uses the system Keychain via `KeychainSecureStore`; the service identifier is `com.jamfdashboard.app`.
- Scanner integration is centralized in `Framework/Scanning/CodeScannerSheet.swift` to uniformly handle camera permission states and unavailable/unsupported scanner hardware.
