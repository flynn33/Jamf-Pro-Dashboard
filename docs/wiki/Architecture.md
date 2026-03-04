# Architecture

Jamf Dashboard is a SwiftUI iOS/macOS app built on the Forsetti Framework. Modules stay lightweight by relying on protocol-based services resolved through `ForsettiContext` for authentication, networking, diagnostics, and persistence.

## Repository layout

```
JamfDashboardApp/
  App/                        # Entry point and Forsetti bootstrap wiring
  Services/                   # API gateway, authentication, credentials, Forsetti logger, Keychain
    Protocols/                # Protocol definitions for ForsettiServiceContainer registration
  Diagnostics/                # Event reporting, NDJSON error log, JSON export
  Models/                     # Shared credentials model, error types
  DesignSystem/               # Shared visual and theming components
  HostUI/                     # Branded dashboard host, settings, credentials, diagnostics, about views
    Scanning/                 # Shared barcode/QR scanner sheet
  Modules/
    ComputerSearch/           # Computer inventory search module
    MobileDeviceSearch/       # Mobile inventory search module
    SupportTechnician/        # Help-desk unified workflow module
    PrestageDirector/         # Prestage enrollment management module
  Resources/
    ForsettiManifests/        # Module manifest JSON files for Forsetti discovery
docs/wiki/                    # Wiki documentation pages
```

## Application shell

`JamfDashboardApp.swift` creates `JamfDashboardBootstrap` and renders `JamfDashboardHostView` as the root scene.

`JamfDashboardBootstrap` initializes the Forsetti runtime and is the single source of truth for the app's dependencies:

```
JamfDashboardBootstrap
  ├── ForsettiRuntime (manifest discovery + entitlement reconciliation)
  ├── ForsettiServiceContainer
  │     ├── JamfAPIGateway (JamfAPIGatewayProviding)
  │     │     ├── JamfCredentialsStore (ref)
  │     │     ├── JamfAuthenticationService
  │     │     │     └── DiagnosticsCenter (ref)
  │     │     └── DiagnosticsCenter (ref)
  │     ├── JamfCredentialsStore (JamfCredentialsProviding)
  │     └── DiagnosticsCenter (DiagnosticsReporting)
  ├── ModuleRegistry (factory-based module instantiation)
  ├── ForsettiHostController (module lifecycle + activation state)
  └── ForsettiViewInjectionRegistry (viewID → SwiftUI view builders)
```

## Service descriptions

### JamfDashboardBootstrap

`@MainActor final class` that initializes the Forsetti runtime and wires all application services. Creates the full dependency graph including `ForsettiRuntime`, `ForsettiServiceContainer`, `ModuleRegistry`, `ForsettiHostController`, and `ForsettiViewInjectionRegistry`. Exposes the controller, injection registry, credentials store, and diagnostics center for the host view.

### JamfAPIGateway

`actor` conforming to `JamfAPIGatewayProviding` — the single HTTP request layer for all modules.

- Loads credentials from `JamfCredentialsStore` on every call.
- Retrieves a valid token from `JamfAuthenticationService` before building the request.
- Automatically retries once on `401` after invalidating the cached token.
- Normalizes all non-2xx responses to `JamfFrameworkError.networkFailure`.
- Records every failure in `DiagnosticsCenter` with method, path, and error description.
- Registered in `ForsettiServiceContainer` for protocol-based resolution by modules.

### JamfAuthenticationService

`actor` for token acquisition and caching.

- Supports two flows: **API Client** (`POST /api/v1/oauth/token` with `client_credentials` grant) and **Username & Password** (`POST /api/v1/auth/token` with Basic auth).
- Caches the token with a 60-second safety margin before actual expiration.
- Invalidates cache when the credential signature changes (URL, client ID, or secret differ from the cached value).
- Reports token fetch success and failure to diagnostics.

### JamfCredentialsStore

`@MainActor final class` conforming to `JamfCredentialsProviding` for Keychain-backed secure credential persistence.

- Operations: `saveCredentials`, `loadCredentials`, `clearCredentials`.
- Publishes `hasStoredCredentials` for UI binding.
- Only stores credential fields for the selected auth method (`storageSanitized`); unused fields are cleared before save.
- Delegates raw Keychain I/O to `KeychainSecureStore`.
- Registered in `ForsettiServiceContainer` for protocol-based resolution.

### DiagnosticsCenter

`@MainActor final class` implementing `DiagnosticsReporting`.

- Maintains a bounded in-memory `DiagnosticEvent` stream for UI display.
- Appends error-severity events to a persistent NDJSON file at `Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson`.
- Exports the full in-memory event array as a JSON bundle to `Documents/JamfDashboardDiagnostics/`.
- Supports full clear/reset of both the in-memory stream and the NDJSON log.
- Bridged to Forsetti runtime logging via `JamfForsettiLogger`.

`DiagnosticEvent` fields: `id` (UUID), `timestamp`, `source`, `category`, `severity` (`info`/`warning`/`error`), `message`, `metadata` (string dictionary).

### JamfForsettiLogger

Implements Forsetti's `ForsettiLogger` protocol and forwards all runtime log messages to `DiagnosticsCenter`. Unifies framework-level events (module lifecycle, entitlement checks, boot sequence) with application-level diagnostics.

### ForsettiHostController

Manages module boot, activation, deactivation lifecycle. Tracks the selected module for navigation and provides `uiModules` list for dashboard rendering.

### ForsettiViewInjectionRegistry

Maps viewID strings to SwiftUI view builders. Used by `JamfDashboardHostView` to resolve module workspace views via the `module.workspace` slot.

## Module contract (Forsetti)

All modules conform to `ForsettiUIModule`:

```swift
protocol ForsettiUIModule {
    var descriptor: ModuleDescriptor { get }
    var manifest: ModuleManifest { get }
    var uiContributions: UIContributions { get }
    func start(context: ForsettiContext) throws
    func stop(context: ForsettiContext)
}
```

Modules receive services through `ForsettiContext`:

```swift
// In start(context:):
let gateway = context.services.resolve(JamfAPIGatewayProviding.self)
let credentials = context.services.resolve(JamfCredentialsProviding.self)
let diagnostics = context.services.resolve(DiagnosticsReporting.self)
```

## Module manifests (Forsetti)

Modules are discovered via JSON manifest files in `JamfDashboardApp/Resources/ForsettiManifests/`. Each manifest declares the module identity, capabilities, platforms, and entry point class name. The Forsetti runtime reads these at boot, reconciles requested capabilities against the entitlement provider, and activates modules through registered factories in `ModuleRegistry`.

| Manifest field | Description |
|---|---|
| `schemaVersion` | Manifest format version (`"1.0"`) |
| `moduleID` | Unique reverse-domain identifier |
| `displayName` | Human-readable name |
| `moduleVersion` | Semantic version string |
| `moduleType` | `"ui"` for dashboard modules |
| `supportedPlatforms` | Array: `"iOS"`, `"macOS"` |
| `minForsettiVersion` | Minimum framework version |
| `capabilitiesRequested` | Array of capability strings |
| `entryPoint` | Class name matching the `ModuleRegistry` factory key |

## Request and diagnostics flow

```
Module
  └─► JamfAPIGatewayProviding.request(path:method:queryItems:body:)
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

## Security and platform

- macOS target uses **App Sandbox** (`com.apple.security.app-sandbox = true`) and **Hardened Runtime**.
- Entitlements file: `JamfDashboardApp/JamfDashboardApp.entitlements`.
- Build settings are in `Jamf Dashboard.xcodeproj/project.pbxproj`.
- Credential storage uses the system Keychain via `KeychainSecureStore`; the service identifier is `com.jamfdashboard.app`.
- Scanner integration is centralized in `HostUI/Scanning/CodeScannerSheet.swift` to uniformly handle camera permission states and unavailable/unsupported scanner hardware.
