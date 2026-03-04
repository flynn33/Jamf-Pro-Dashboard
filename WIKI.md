# Jamf Dashboard Wiki

Jamf Dashboard is a modular SwiftUI Jamf Pro operations app for **iOS and macOS**. Built on the **Forsetti Framework** for sealed modular runtime composition, manifest-based module discovery, entitlement governance, and protocol-first dependency injection.

**Attribution:** developed by Jim Daley

## Wiki Navigation

- [Getting Started](docs/wiki/Getting-Started.md)
- [Architecture](docs/wiki/Architecture.md)
- [Module Catalog](docs/wiki/Module-Catalog.md)
- [API Reference](docs/wiki/API-Reference.md)
- [Operations and Troubleshooting](docs/wiki/Operations-and-Troubleshooting.md)
- [Contributing](docs/wiki/Contributing.md)

## 1. Project Status

- `CURRENT_PROJECT_VERSION = 3`
- `MARKETING_VERSION = 3`

## 2. Technical Requirements

- Xcode 26+
- Forsetti Framework (local SPM dependency)
- iOS deployment target: 26.0+
- macOS deployment target: 14.0+
- Jamf Pro URL
- One authentication method:
  - API Client (`client_id` + `client_secret`)
  - Username/Password

## 3. Security and Distribution (macOS)

The macOS target is configured for distribution requirements:

- App Sandbox enabled
- Hardened Runtime enabled

Locations:

- Entitlements: `JamfDashboardApp/JamfDashboardApp.entitlements`
- Build settings: `Jamf Dashboard.xcodeproj/project.pbxproj`

## 4. Repository Structure

- `JamfDashboardApp/App`
  - App entry point and Forsetti bootstrap wiring
- `JamfDashboardApp/Services`
  - API gateway, authentication, credentials store, Forsetti logger bridge, Keychain store
- `JamfDashboardApp/Services/Protocols`
  - Protocol definitions for ForsettiServiceContainer registration
- `JamfDashboardApp/Diagnostics`
  - Event reporting, export, persistent error logging
- `JamfDashboardApp/Models`
  - Shared data models (credentials, framework errors)
- `JamfDashboardApp/DesignSystem`
  - Brand colors, theme, typography, button styles, platform compatibility
- `JamfDashboardApp/HostUI`
  - Branded dashboard host view, settings, credentials, diagnostics, about views
- `JamfDashboardApp/HostUI/Scanning`
  - Shared scanner sheet and scan-to-text-field support
- `JamfDashboardApp/Modules`
  - `ComputerSearch`
  - `MobileDeviceSearch`
  - `SupportTechnician`
  - `PrestageDirector`
- `JamfDashboardApp/Resources/ForsettiManifests`
  - Module manifest JSON files for Forsetti discovery
- `docs/wiki`
  - Comprehensive wiki pages

## 5. Core Architecture (Forsetti Framework)

### `JamfDashboardBootstrap`

Initializes the Forsetti runtime and wires all application services:

1. Creates `ForsettiRuntime` with manifest discovery from `ForsettiManifests/` bundle directory
2. Registers domain services in `ForsettiServiceContainer` (API gateway, credentials, diagnostics)
3. Registers module factories in `ModuleRegistry` mapping entryPoint strings to constructors
4. Creates `ForsettiHostController` for module lifecycle management
5. Registers view injections in `ForsettiViewInjectionRegistry` for slot-based UI rendering

### `JamfAPIGateway`

Shared request layer conforming to `JamfAPIGatewayProviding`:

- Builds authenticated requests
- Retrieves tokens through `JamfAuthenticationService`
- Retries on `401` after token invalidation
- Converts non-2xx responses to framework errors
- Reports request failures to diagnostics

### `JamfAuthenticationService`

Authentication/token actor:

- Supports API client and username/password flows
- Caches token and expiration
- Invalidates token when credential signature changes

### `JamfCredentialsStore`

Secure credential persistence conforming to `JamfCredentialsProviding`:

- Save/load/clear operations via Keychain
- Tracks `hasStoredCredentials`

### `DiagnosticsCenter`

Structured diagnostics service:

- In-memory event stream (bounded)
- Persistent NDJSON error log
- JSON export support
- Full clear/reset support
- Bridged to Forsetti runtime logging via `JamfForsettiLogger`

## 6. Module System (Forsetti)

All modules conform to `ForsettiUIModule` with:

- `descriptor` — identity and version via `ModuleDescriptor`
- `manifest` — capabilities, platforms, and entry point via `ModuleManifest`
- `uiContributions` — view injection descriptors for slot-based UI rendering
- `start(context:)` / `stop(context:)` — lifecycle methods receiving `ForsettiContext`

Modules receive services through `ForsettiContext`:

- `context.services.resolve(JamfAPIGatewayProviding.self)`
- `context.services.resolve(JamfCredentialsProviding.self)`
- `context.services.resolve(DiagnosticsReporting.self)`

### Module Discovery

Modules are declared via manifest JSON files in `JamfDashboardApp/Resources/ForsettiManifests/`. The Forsetti runtime discovers these at boot, reconciles entitlements, and activates modules through registered factories.

## 7. Credentials Workflow

1. Open `Settings -> Jamf Credentials`.
2. Enter Jamf URL.
3. Choose authentication method.
4. Enter credential fields.
5. Run `Verify Connection`.
6. Save credentials after successful verification.

Only selected auth-method fields are stored.

## 8. Built-In Module Behavior

### Computer Search

- Computer inventory lookup
- Field catalog and reusable profiles
- Endpoint and filter fallback behaviors

### Mobile Device Search

- Mobile inventory lookup
- Field catalog and reusable profiles
- Section/wildcard fallback behavior
- Pre-stage enrichment with caching/fallback

### Support Technician

- Unified computer/mobile support workflow
- Search by username or serial number
- Device details and diagnostics in one workflow
- Sensitive command confirmations
- Destructive remove-device command requires typed `Remove`
- Applications moved to dedicated **Manage Applications** view

### Prestage Director

- Lists pre-stage inventory/scope
- Multi-select remove/move operations
- Progress tracking and rollback handling

## 9. Navigation and Interaction Notes

- Shared top-left back behavior via reusable toolbar back button support
- Settings includes an in-view top-left Home button
- Command actions use explicit confirmation prompts

## 10. Scanner Integration

`CodeScannerSheet` is shared across modules.

- Handles camera permission states
- Handles unavailable/unsupported scanner states
- Supports barcode/QR scanning into bound text fields

## 11. Persistence and Outputs

- Keychain:
  - service `com.jamfdashboard.app`
  - key `jamf.credentials`
- Application Support:
  - `JamfDashboard/computer-search-profiles.json`
  - `JamfDashboard/mobile-device-search-profiles.json`
- Documents:
  - `JamfDashboardDiagnostics/jamf-dashboard-diagnostics-<timestamp>.json`
  - `JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson`

## 12. Forsetti Manifest Reference

Module manifests are JSON files in `JamfDashboardApp/Resources/ForsettiManifests/`.

```json
{
  "schemaVersion": "1.0",
  "moduleID": "com.jamftool.modules.example",
  "displayName": "Example Module",
  "moduleVersion": "1.0.0",
  "moduleType": "ui",
  "supportedPlatforms": ["iOS", "macOS"],
  "minForsettiVersion": "0.1.0",
  "capabilitiesRequested": ["networking", "secureStorage", "viewInjection"],
  "entryPoint": "ExampleModule"
}
```
