# Jamf Dashboard Wiki

Jamf Dashboard is a modular SwiftUI Jamf Pro operations app for **iOS and macOS**.

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
- Legacy baseline used for change tracking: `Dashboard-V1.4`

## 2. Technical Requirements

- Xcode 26+
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
  - App entry and framework container wiring
- `JamfDashboardApp/Framework/Core`
  - shared contracts, credentials model, framework errors
- `JamfDashboardApp/Framework/Networking`
  - authentication and API gateway
- `JamfDashboardApp/Framework/Security`
  - Keychain-backed secure data store
- `JamfDashboardApp/Framework/Diagnostics`
  - event reporting, export, persistent error logging
- `JamfDashboardApp/Framework/Modules`
  - module manifests, package manager, package persistence
- `JamfDashboardApp/Framework/UI`
  - dashboard, settings, diagnostics, server credential flows
- `JamfDashboardApp/Framework/Scanning`
  - shared scanner sheet and scan-to-text-field support
- `JamfDashboardApp/Modules`
  - `ComputerSearch`
  - `MobileDeviceSearch`
  - `SupportTechnician`
  - `PrestageDirector`
- `ModulePackageTemplates`
  - example module package manifests
- `docs/wiki`
  - comprehensive wiki pages

## 5. Core Framework Services

### `JamfFrameworkContainer`

Owns shared services:

- credentials store
- authentication service
- API gateway
- diagnostics center
- module registry
- module package manager

### `JamfAPIGateway`

Shared request layer used by all modules.

- Builds authenticated requests
- Retrieves tokens through `JamfAuthenticationService`
- Retries on `401` after token invalidation
- Converts non-2xx responses to framework errors
- Reports request failures to diagnostics

### `JamfAuthenticationService`

Authentication/token actor.

- Supports API client and username/password flows
- Caches token and expiration
- Invalidates token when credential signature changes
- Reports token/decode failures to diagnostics

### `JamfCredentialsStore`

Secure credential persistence using Keychain.

- Save/load/clear operations
- Tracks `hasStoredCredentials`

### `DiagnosticsCenter`

Structured diagnostics service.

- In-memory event stream (bounded)
- Persistent NDJSON error log
- JSON export support
- Full clear/reset support

## 6. Module System

All modules implement `JamfModule` with:

- `id`
- `title`
- `subtitle`
- `iconSystemName`
- `makeRootView(context:)`

`ModuleContext` injects:

- API gateway
- credentials store
- diagnostics reporter

### Module Package Management

`ModulePackageManager` provides:

- bootstrap of bundled defaults
- install/remove package manifests
- persisted package tracking
- duplicate package protection

Default bundled module types:

- `computer-search`
- `mobile-device-search`
- `support-technician`
- `prestage-director`

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
- App actions supported:
  - Install
  - Update
  - Reinstall
  - Remove

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
  - `JamfDashboard/installed-module-packages.json`
  - `JamfDashboard/computer-search-profiles.json`
  - `JamfDashboard/mobile-device-search-profiles.json`
- Documents:
  - `JamfDashboardDiagnostics/jamf-dashboard-diagnostics-<timestamp>.json`
  - `JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson`

## 12. Module Package Manifest Reference

Minimum fields:

```json
{
  "package_id": "com.jamftool.modules.example",
  "module_type": "computer-search",
  "package_version": "1.0.0"
}
```

Optional fields:

- `module_display_name`
- `module_subtitle`
- `icon_system_name`

Supported module types:

- `computer-search`
- `mobile-device-search`
- `support-technician`
- `prestage-director`
