# Architecture

Jamf Dashboard is a SwiftUI iOS/macOS app built around a shared framework container. Modules stay lightweight by relying on injected services for authentication, networking, diagnostics, and persistence.

## Application shell

- Entry lives under `JamfDashboardApp/App`, which boots `JamfFrameworkContainer` and registers bundled modules.
- `JamfModule` contract: `id`, `title`, `subtitle`, `iconSystemName`, and `makeRootView(context:)`.
- `ModuleContext` provides shared services to every module:
  - `JamfAPIGateway` for authenticated requests and 401 retry behavior
  - `JamfAuthenticationService` for API client and username/password flows with token caching/invalidations
  - `JamfCredentialsStore` for Keychain-backed credential persistence and signature change tracking
  - `DiagnosticsCenter` for in-memory diagnostics, persistent NDJSON error log, and JSON export

## Module packages

- Managed by `ModulePackageManager` and persisted via `ModulePackageStore`; duplicate package IDs are rejected and bundled defaults are restored on bootstrap.
- Manifest fields (JSON):
  - `package_id` (string, required)
  - `module_type` (`computer-search`, `mobile-device-search`, `support-technician`, `prestage-director`)
  - `package_version` (string, defaults to `1.0.0`)
  - Optional: `module_display_name`, `module_subtitle`, `icon_system_name`
- Templates: `ModulePackageTemplates/`.
- Default bundled packages:
  - `com.jamftool.modules.computer-search`
  - `com.jamftool.modules.mobile-device-search`
  - `com.jamftool.modules.support-technician`
  - `com.jamftool.modules.prestage-director`

## Request and diagnostics flow

1. A module builds intent and calls `JamfAPIGateway`.
2. The gateway asks `JamfAuthenticationService` for a valid token; invalidation triggers re-authentication.
3. Responses are normalized to framework errors; 401 triggers one retry after token invalidation.
4. Failures are recorded in `DiagnosticsCenter` (memory) and the persistent NDJSON log; users can export diagnostics from Settings.

## Security and platform

- macOS target uses App Sandbox and Hardened Runtime.
- Entitlements: `JamfDashboardApp/JamfDashboardApp.entitlements`.
- Build settings are configured in `Jamf Dashboard.xcodeproj/project.pbxproj`.
- Scanner integration is centralized in `Framework/Scanning/CodeScannerSheet.swift` to handle permissions and unavailable states.
